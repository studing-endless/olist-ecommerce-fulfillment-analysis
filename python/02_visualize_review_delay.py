from project_paths import TABLES, FIGURES
import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path

# ==============================
# 1. 读取数据
# ==============================

df = pd.read_csv(TABLES / "order_review_analysis.csv")

print("数据形状（行数、列数）：", df.shape)
print("\n前3行数据：")
print(df.head(3).to_string(index=False))


# ==============================
# 2. 数据质量检查
# ==============================

print("\n重复订单数：", df["order_id"].duplicated().sum())

print("\n各字段缺失值数量：")
print(df.isna().sum())


# ==============================
# 3. 延迟与准时订单的差评率
# ==============================
## 按照 is_late 分组：
## agg()——一次计算多个统计指标
## 指定统计字段is_bad_review
result = df.groupby("is_late")["is_bad_review"].agg(
    order_count="size", #统计每组订单数量
    bad_orders="sum",  #求和，得到差评订单数
    bad_rate="mean"  #求平均值，得到差评率
)

print("\n延迟与准时订单的差评情况：")
print(result)


# ==============================
# 4. 按配送超期程度分组
# ==============================

labels = [
    "On time / Early",
    "1-3 days late",
    "4-7 days late",
    "8+ days late"
]
#pd.cut()——按照数值区间分组
#把配送超期天数转换为一个新的分类字段。
#给 DataFrame 新增一列。
df["delay_group"] = pd.cut(
    df["delay_days"],
    bins=[float("-inf"), 0, 3, 7, float("inf")],
    labels=labels
)

summary = df.groupby("delay_group", observed=True)["is_bad_review"].agg(
    order_count="size",
    bad_orders="sum",
    bad_rate="mean"
).reset_index()

summary["bad_rate_pct"] = summary["bad_rate"] * 100

print("\n不同延迟程度的差评情况：")
print(summary.to_string(index=False))


# ==============================
# 5. 绘制差评率柱状图
# ==============================

fig, ax = plt.subplots(figsize=(10, 6))

bars = ax.bar(
    summary["delay_group"].astype(str),
    summary["bad_rate_pct"]
)

for bar, rate, n in zip(
    bars,
    summary["bad_rate_pct"],
    summary["order_count"]
):
    ax.text(
        bar.get_x() + bar.get_width() / 2,
        bar.get_height() + 2,
        f"{rate:.2f}%\n(n={n:,})",
        ha="center"
    )

ax.set_title("Delivery Delay and Customer Bad Reviews (n=95,299)")
ax.set_xlabel("Delivery Delay Group")
ax.set_ylabel("Bad Review Rate (%)")
ax.set_ylim(0, 100)
ax.grid(axis="y", alpha=0.2)
ax.set_axisbelow(True)

plt.tight_layout()


# ==============================
# 6. 保存并显示图表
# ==============================

output_dir = FIGURES
output_dir.mkdir(parents=True, exist_ok=True)

plt.savefig(
    output_dir / "review_rate_by_delay.png",
    dpi=300,
    bbox_inches="tight"
)

plt.close(fig)

print("\n图表保存成功：outputs/figures/review_rate_by_delay.png")