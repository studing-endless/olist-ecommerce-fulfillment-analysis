"""Check the exact Git index before committing or pushing; never stages files."""
from pathlib import Path
import ast
import csv
import io
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SAFE_CSV = {
    'seller_strategy_comparison.csv', 'seller_strategy_audit.csv',
    'seller_strategy_overlap.csv',
    '01_order_status_distribution.csv', '02_state_delivery_summary.csv',
    'review_summary.csv', 'delay_group_summary.csv', 'handoff_summary.csv',
    'seller_shortlist_public.csv', 'platform_summary.csv',
    'regional_period_summary.csv', 'regional_stage_summary.csv',
    'ontime_order_structure.csv', 'two_item_review_summary.csv',
}
files = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode('utf8').split('\0')
files = [x for x in files if x]
assert files, 'Git index is empty; review files and stage first.'
issues = []
for name in files:
    p = ROOT / name
    content = subprocess.check_output(['git', 'show', ':' + name], cwd=ROOT)
    parts = Path(name).parts
    if any(x in parts for x in ['data', 'tables', '.vscode', '.venv', '__pycache__', 'report_media']):
        issues.append((name, 'private directory'))
    if p.suffix.lower() not in {'.py', '.sql', '.md', '.txt', '.png', '.csv'} and name != '.gitignore':
        issues.append((name, 'unexpected file type'))
    if len(content) > 2_000_000:
        issues.append((name, 'file exceeds 2 MB review threshold'))
    if p.suffix == '.csv':
        if p.parent != ROOT/'outputs' or p.name not in SAFE_CSV:
            issues.append((name, 'unapproved CSV'))
        fields = next(csv.reader(io.StringIO(content.decode('utf-8-sig'))))
        if set(fields) & {'order_id','customer_id','customer_unique_id','seller_id','review_comment_message'}:
            issues.append((name, 'record identifier or raw comment'))
    if p.suffix in {'.py','.sql','.md','.txt'} or name == '.gitignore':
        text=content.decode('utf-8-sig')
        patterns=[r'gh[pousr]_[A-Za-z0-9]{20,}',r'github_pat_[A-Za-z0-9_]{20,}',
                  r'AKIA[0-9A-Z]{16}',r'-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----',
                  r'(?i)[A-Z]:[\\/](?:Users|data_analysis|桌面)[\\/]',
                  r'(?i)(?:mysql|postgres(?:ql)?)://[^\s]+:[^\s]+@']
        for pattern in patterns:
            if re.search(pattern,text): issues.append((name,'secret or local path pattern'))
        if p.suffix == '.md':
            for link in re.findall(r'\]\(([^)]+)\)',text):
                if '://' not in link and not link.startswith('#') and not (p.parent/link.split('#')[0]).exists():
                    issues.append((name,'broken relative link: '+link))
        if p.suffix == '.py':
            tree=ast.parse(text,filename=name)
            for node in ast.walk(tree):
                if isinstance(node,ast.Assign) and isinstance(node.value,ast.Constant) and isinstance(node.value.value,str) and node.value.value:
                    if any(isinstance(x,ast.Name) and re.search(r'password|passwd|token|secret',x.id,re.I) for x in node.targets):
                        issues.append((name,'literal credential assignment'))
assert not issues, str(issues)
print(f'PASS: {len(files)} indexed files; approved aggregates only; Python syntax and Markdown links checked.')
print('Pattern scans are limited; review the staged diff and exact index before publication.')
