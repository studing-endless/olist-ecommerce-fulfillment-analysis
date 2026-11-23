"""Run the existing SQL in order against an explicitly named dedicated database."""
import argparse
from getpass import getpass
from pathlib import Path
import os
import re
import pymysql
import sqlparse

ROOT = Path(__file__).resolve().parents[1]


def statements(path, database, raw_dir=None):
    text = path.read_text(encoding='utf8')
    text = re.sub(r'\bolist_ecommerce\b', database, text)
    if raw_dir is not None:
        directory = str(raw_dir.resolve()).replace('\\', '/')
        if "'" in directory:
            raise ValueError('CSV directory cannot contain a single quote')
        text = text.replace('data/raw/', directory.rstrip('/') + '/')
    return [sqlparse.format(s, strip_comments=True).strip()
            for s in sqlparse.split(text) if sqlparse.format(s, strip_comments=True).strip().strip(';')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True)
    parser.add_argument('--initialize', action='store_true', help='Create a NEW database and import nine CSVs once')
    parser.add_argument('--raw-dir', type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*', args.database):
        parser.error('Use a simple dedicated database name')
    if args.initialize and (args.raw_dir is None or not args.raw_dir.is_dir()):
        parser.error('--initialize requires an existing --raw-dir')
    if args.initialize:
        template = (ROOT/'sql/00_import_data.sql').read_text(encoding='utf8')
        filenames = re.findall(r"'data/raw/([^']+)'", template)
        if len(filenames) != 9 or any(not (args.raw_dir/name).is_file() for name in filenames):
            parser.error('All nine original CSV files must exist before creating the database')
    user = os.environ.get('OLIST_DB_USER') or input('MySQL user: ').strip()
    password = os.environ.get('OLIST_DB_PASSWORD') or getpass('MySQL password: ')
    conn = pymysql.connect(host=os.environ.get('OLIST_DB_HOST', '127.0.0.1'),
        port=int(os.environ.get('OLIST_DB_PORT', '3306')), user=user, password=password,
        charset='utf8mb4', local_infile=args.initialize, autocommit=True)
    try:
        with conn.cursor() as cursor:
            cursor.execute('SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME=%s', (args.database,))
            exists = cursor.fetchone() is not None
            if args.initialize == exists:
                raise ValueError('Initialization requires an absent database; analysis requires an existing dedicated database')
            files = [ROOT/'sql/00_import_data.sql'] if args.initialize else sorted((ROOT/'sql').glob('0[1-5]_*.sql'))
            for path in files:
                count = 0
                for statement in statements(path, args.database, args.raw_dir):
                    cursor.execute(statement)
                    # Check warnings immediately, before another statement resets them.
                    if cursor._result.warning_count:
                        raise RuntimeError(f'{path.name} statement {count+1} produced SQL warnings; stop and inspect locally')
                    if cursor.description:
                        cursor.fetchall()  # Never print order IDs or comment text.
                    count += 1
                print(f'PASS {path.name}: {count} statements')
    finally:
        conn.close()


if __name__ == '__main__':
    main()
