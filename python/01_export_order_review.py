
from pathlib import Path
from getpass import getpass

import pandas as pd


import os
import pymysql
from project_paths import TABLES


# ==========================================
# 1. 配置项目路径
# ==========================================


output_dir = TABLES

output_file = output_dir / "order_review_analysis.csv"


# ==========================================
# 2. 连接 MySQL 数据库
# ==========================================

db_user = os.environ.get("OLIST_DB_USER") or input("MySQL user: ").strip()
db_password = os.environ.get("OLIST_DB_PASSWORD") or getpass("MySQL password: ")
db_options = dict(host=os.environ.get("OLIST_DB_HOST", "127.0.0.1"),
                  port=int(os.environ.get("OLIST_DB_PORT", "3306")),
                  user=db_user, password=db_password,
                  database=os.environ.get("OLIST_DB_NAME", "olist_ecommerce"),
                  charset="utf8mb4")


# ==========================================
# 3. 读取订单级分析视图
# ==========================================

sql = """
SELECT
    order_id,
    customer_unique_id,
    customer_state,
    order_month,
    delivery_days,
    delay_days,
    is_late,
    review_score,
    is_bad_review
FROM v_order_review_analysis
"""

try:
    conn = pymysql.connect(**db_options)
    with conn.cursor() as cursor:
        cursor.execute(sql)
        df = pd.DataFrame(cursor.fetchall(), columns=[c[0] for c in cursor.description])
finally:
    if "conn" in globals():
        conn.close()


# ==========================================
# 4. 核验读取的数据
# ==========================================

total_orders = len(df)
unique_orders = df["order_id"].nunique()
late_orders = int(df["is_late"].sum())
bad_review_orders = int(df["is_bad_review"].sum())
missing_scores = int(df["review_score"].isna().sum())

print("\n数据核验结果：")
print("总订单数：", total_orders)
print("唯一订单数：", unique_orders)
print("延迟订单数：", late_orders)
print("差评订单数：", bad_review_orders)
print("缺失评分数：", missing_scores)

# 与此前SQL结果核对
assert total_orders == 95299
assert unique_orders == 95299
assert late_orders == 6353
assert bad_review_orders == 12189
assert missing_scores == 0


# ==========================================
# 5. 导出分析数据
# ==========================================

df.to_csv(
    output_file,
    index=False,
    encoding="utf-8-sig"
)

print("\n数据导出成功！")
print("保存位置：", output_file)
