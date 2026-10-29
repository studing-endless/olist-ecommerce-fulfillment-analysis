from project_paths import TABLES, FIGURES

import pandas as pd

# 1. 读取两份数据
shortlist = pd.read_csv(
    TABLES / "seller_investigation_shortlist.csv"
)
handoff = pd.read_csv(
    TABLES / "seller_handoff_profile.csv"
)

# 2. 核验导出的交运数据是否完整
print("交运样本订单数：", handoff["order_count"].sum())
print("交运超期订单数：", handoff["late_handoff_orders"].sum())
print("最终延迟订单数：", handoff["late_delivery_orders"].sum())

assert handoff["seller_id"].is_unique
assert handoff["order_count"].sum() == 95029
assert handoff["late_handoff_orders"].sum() == 8655
assert handoff["late_delivery_orders"].sum() == 6518
assert handoff["ontime_handoff_late_delivery"].sum() == 4706

# 3. 将9名候选卖家与交运数据关联
result = shortlist.merge(
    handoff,
    on="seller_id",
    how="left",
    validate="one_to_one",
    suffixes=("_overall", "_handoff")
)

assert result["late_handoff_rate_pct"].notna().all()

# 4. 计算最终延迟订单中按时交运的比例
result["ontime_handoff_share_pct"] = (
    result["ontime_handoff_late_delivery"]
    / result["late_delivery_orders"] * 100
).round(2)

# 5. 查看9名卖家的交运表现
columns = [
    "seller_id",
    "late_rate_pct",
    "bad_review_rate_pct",
    "late_handoff_rate_pct",
    "late_delivery_orders",
    "ontime_handoff_late_delivery",
    "ontime_handoff_share_pct"
]

print("\n9名候选卖家的交运诊断：")
print(result[columns].to_string(index=False))



# 1. 读取卖家交易金额数据
amount = pd.read_csv(
    TABLES / "seller_issue_amount.csv"
)

# 2. 核对数据
assert amount["seller_id"].is_unique
assert amount["order_count"].sum() == 95195
assert amount["issue_orders"].sum() == 14165
assert round(amount["issue_amount"].sum(), 2) == 2564540.84

print("\n交易金额数据核验通过！")

# 3. 与之前的9名候选卖家合并
final = result.merge(
    amount[["seller_id", "total_amount", "issue_amount"]],
    on="seller_id",
    how="left",
    validate="one_to_one"
)

assert len(final) == 9
assert final["issue_amount"].notna().all()

# 4. 查看最终分析结果
columns = [
    "seller_id",
    "order_count_overall",
    "issue_orders",
    "issue_rate_pct",
    "late_handoff_rate_pct",
    "bad_review_rate_pct",
    "issue_amount"
]

print("\n最终9名卖家运营调查表：")
print(final[columns].to_string(index=False))

# 5. 保存最终结果
final[columns].to_csv(
    TABLES / "seller_final_investigation_profile.csv",
    index=False,
    encoding="utf-8-sig"
)

print("\n最终卖家分析表已保存！")
