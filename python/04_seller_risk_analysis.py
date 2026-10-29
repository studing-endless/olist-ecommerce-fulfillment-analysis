from project_paths import TABLES, FIGURES

import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path

# ===================================
# 1. 读取数据
# ===================================

df = pd.read_csv(TABLES / "seller_profile.csv")

print("卖家画像数据形状：", df.shape)
print("重复卖家数：", df["seller_id"].duplicated().sum())
print("\n各字段缺失值：")
print(df.isna().sum())

# ===================================
# 2. 核对SQL统计结果
# ===================================

checks = {
    "order_count": 95195,
    "late_orders": 6521,
    "reviewed_orders": 94051,
    "bad_review_orders": 11597
}

assert len(df) == 2948
assert df["seller_id"].is_unique

for column, expected in checks.items():
    actual = df[column].sum()
    assert actual == expected, f"{column} 核验失败：{actual}"

assert (
    df["late_bad_orders"] + df["ontime_bad_orders"]
    == df["bad_review_orders"]
).all()

print("\n数据核验通过！")

# ===================================
# 3. 筛选具有一定规模的卖家
# ===================================
# 从卖家画像中筛选出订单数至少100笔的卖家。
focus = df[
    (df["order_count"] >= 100)
    & (df["reviewed_orders"] > 0)
].copy()

print("\n参与四象限分析的卖家数：", len(focus))
print(
    "这些卖家覆盖的订单比例：",
    f"{focus['order_count'].sum() / df['order_count'].sum():.2%}"
)

# ===================================
# 4. 按延迟率和差评率划分四象限
# ===================================

focus["risk_group"] = "Both below"

focus.loc[
    (focus["late_rate_pct"] > 6.85)
    & (focus["bad_review_rate_pct"] > 12.33),
    "risk_group"
] = "Both above"

focus.loc[
    (focus["late_rate_pct"] > 6.85)
    & (focus["bad_review_rate_pct"] <= 12.33),
    "risk_group"
] = "Delay above"
#把延迟率大于6.85%的卖家，在 risk_group 列中标记为 High Delay。
#loc[行条件, 列名] 就是根据条件选择行和列。
focus.loc[
    (focus["late_rate_pct"] <= 6.85)
    & (focus["bad_review_rate_pct"] > 12.33),
    "risk_group"
] = "Review above"

# ===================================
# 5. 汇总不同类型卖家的问题规模
# ===================================

summary = focus.groupby("risk_group").agg(
    seller_count=("seller_id", "size"),
    order_count=("order_count", "sum"),
    late_orders=("late_orders", "sum"),
    bad_reviews=("bad_review_orders", "sum")
)

print("\n四象限卖家分布：")
#完整打印所有行和列
print(summary.to_string())

# ===================================
# 6. 绘制四象限散点图
# ===================================

fig, ax = plt.subplots(figsize=(10, 7))

for group, data in focus.groupby("risk_group"):
    ax.scatter(
        data["late_rate_pct"],
        data["bad_review_rate_pct"],
        s=data["order_count"] / 15 + 15,
        alpha=0.65,
        label=f"{group} (n={len(data)})"
    )

ax.axvline(6.85, linestyle="--", color="gray")
ax.axhline(12.33, linestyle="--", color="gray")

ax.set_xlabel("Seller Late Delivery Rate (%)")
ax.set_ylabel("Seller Bad Review Rate (%)")
ax.set_title(f"Single-seller Fulfillment (orders >= 100; n={len(focus)} sellers)")

ax.legend()
ax.grid(alpha=0.2)

plt.tight_layout()

# ===================================
# 7. 保存图片
# ===================================

output_dir = FIGURES
output_dir.mkdir(parents=True, exist_ok=True)

plt.savefig(
    output_dir / "seller_risk_quadrants.png",
    dpi=300,
    bbox_inches="tight"
)

plt.close(fig)

# ===================================
# 8. 查看双指标偏高的候选卖家
# ===================================

candidates = focus[
    focus["risk_group"] == "Both above"
].sort_values(
    ["late_orders", "bad_review_orders"],
    ascending=False
)

print("\n双指标偏高的前10名卖家：")
print(
    candidates[
        [
            "seller_id",
            "order_count",
            "late_orders",
            "late_rate_pct",
            "bad_review_orders",
            "bad_review_rate_pct"
        ]
    ].head(10).to_string(index=False)
)


# 计算每个卖家涉及的问题订单数，避免重复计数
focus["issue_orders"] = (
    focus["late_orders"]
    + focus["bad_review_orders"]
    - focus["late_bad_orders"]
)

# 计算问题订单占比
focus["issue_rate_pct"] = (
    focus["issue_orders"] / focus["order_count"] * 100
).round(2)




# 筛选双指标偏高的卖家，按问题订单数降序排列
priority = focus[
    focus["risk_group"] == "Both above"
].sort_values("issue_orders", ascending=False)



print("\n卖家运营优先调查候选名单：")
print(
    priority[
        ["seller_id", "order_count",
         "late_rate_pct", "bad_review_rate_pct",
         "issue_orders", "issue_rate_pct"]
    ].head(10).to_string(index=False)
)


# 保存卖家运营调查候选名单
priority.to_csv(
    TABLES / "seller_investigation_candidates.csv",
    index=False,
    encoding="utf-8-sig"
)

print("已保存候选卖家数量：", len(priority))


# 1. 问题订单数量最多的5名卖家
volume_top = priority.nlargest(5, "issue_orders")

# 2. 问题订单占比最高的5名卖家
rate_top = priority.nlargest(5, "issue_rate_pct")

# 3. 合并两份名单，去掉重复卖家
shortlist = pd.concat([volume_top, rate_top])

shortlist = shortlist.drop_duplicates(subset="seller_id")

# 4. 按问题订单数量排序
shortlist = shortlist.sort_values(
    "issue_orders", ascending=False
)

columns = [
    "seller_id",
    "order_count",
    "late_rate_pct",
    "bad_review_rate_pct",
    "issue_orders",
    "issue_rate_pct"
]

print("\n运营优先调查短名单：")
print(shortlist[columns].to_string(index=False))

# 5. 保存结果
shortlist[columns].to_csv(
    TABLES / "seller_investigation_shortlist.csv",
    index=False,
    encoding="utf-8-sig"
)



# ======================================
# 卖家筛查稳健性检查
# ======================================

# 计算全部卖家的问题订单数和占比
df["issue_orders"] = (
    df["late_orders"]
    + df["bad_review_orders"]
    - df["late_bad_orders"]
)

df["issue_rate_pct"] = (
    df["issue_orders"] / df["order_count"] * 100
)

results = {}

# 分别测试50、100、150笔订单门槛
for min_orders in [50, 100, 150]:

    # 第一步：筛选双指标偏高的卖家
    candidates = df[
        (df["order_count"] >= min_orders)
        & (df["late_rate_pct"] > 6.85)
        & (df["bad_review_rate_pct"] > 12.33)
    ].copy()

    # 第二步：分别取问题数量前5名和问题比例前5名
    volume_top = candidates.nlargest(5, "issue_orders")
    rate_top = candidates.nlargest(5, "issue_rate_pct")

    # 第三步：合并去重
    shortlist = pd.concat([volume_top, rate_top])
    shortlist = shortlist.drop_duplicates(subset="seller_id")

    results[min_orders] = {
        "candidates": len(candidates),
        "ids": set(shortlist["seller_id"])
    }

# 第四步：与原先100笔方案比较
baseline = results[100]["ids"]

print("\n===== 不同订单门槛的敏感性分析 =====")

for min_orders in [50, 100, 150]:
    current = results[min_orders]["ids"]

    print(f"\n最低订单数：{min_orders}")
    print("双指标偏高卖家数：", results[min_orders]["candidates"])
    print("调查短名单人数：", len(current))
    print("与原方案重合人数：", len(current & baseline))
    print("相比原方案新增：", len(current - baseline))
    print("相比原方案退出：", len(baseline - current))