"""Export three seller aggregates; run after SQL 03 has created the view."""
import os
from getpass import getpass
import pandas as pd
import pymysql
from project_paths import ROOT, TABLES

user = os.environ.get("OLIST_DB_USER") or input("MySQL user: ").strip()
password = os.environ.get("OLIST_DB_PASSWORD") or getpass("MySQL password: ")
conn = pymysql.connect(host=os.environ.get("OLIST_DB_HOST", "127.0.0.1"),
    port=int(os.environ.get("OLIST_DB_PORT", "3306")), user=user, password=password,
    database=os.environ.get("OLIST_DB_NAME", "olist_ecommerce"), charset="utf8mb4")
try:
    for name in ["seller_profile", "seller_handoff_profile", "seller_issue_amount"]:
        query = (ROOT / "sql" / ("export_" + name + ".sql")).read_text(encoding="utf8")
        query = query.split(";", 1)[1].strip().rstrip(";")
        with conn.cursor() as cursor:
            cursor.execute(query)
            df = pd.DataFrame(cursor.fetchall(), columns=[c[0] for c in cursor.description])
        df.to_csv(TABLES / (name + ".csv"), index=False, encoding="utf-8-sig")
        print(name, len(df))
finally:
    conn.close()
