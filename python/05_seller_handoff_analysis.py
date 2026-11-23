from project_paths import TABLES, FIGURES

import pandas as pd
from analysis_checks import reference_enabled, require
from reference_checks import verify_handoff, verify_amount

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
for column in ["late_handoff_orders", "late_delivery_orders", "ontime_handoff_late_delivery"]:
    require(handoff[column].notna().all() and handoff[column].between(0, handoff.order_count).all(), "交运计数超出分母")
require((handoff.ontime_handoff_late_delivery <= handoff.late_delivery_orders).all(), "交运交叉计数不一致")
if reference_enabled():
    verify_handoff(handoff)

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
require(amount.issue_orders.between(0, amount.order_count).all(), "问题订单数超出分母")
require(amount.issue_amount.between(0, amount.total_amount).all(), "问题金额超出总额")

print("\n交易金额数据核验通过！")

# 3. 与之前的9名候选卖家合并
final = result.merge(
    amount[["seller_id", "total_amount", "issue_amount"]],
    on="seller_id",
    how="left",
    validate="one_to_one"
)

require(len(final) == len(shortlist), "合并改变了短名单人数")
if reference_enabled():
    verify_amount(amount, final)
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
