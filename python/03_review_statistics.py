from project_paths import TABLES, FIGURES

import pandas as pd
import numpy as np
import statsmodels.api as sm
import statsmodels.formula.api as smf
from statsmodels.stats.proportion import confint_proportions_2indep

# 1. 读取订单明细
df = pd.read_csv(TABLES / "order_review_analysis.csv")

assert len(df) == 95299
assert df["order_id"].is_unique

required = [
    "is_late", "is_bad_review", "customer_state",
    "order_month", "customer_unique_id"
]
assert df[required].notna().all().all(), "模型所需字段存在缺失值"

# 2. 按是否延迟统计订单数和差评数
summary = df.groupby("is_late")["is_bad_review"].agg(
    total="size",
    bad="sum"
)
#取行索引为1、列名为 total 的那个数。
n1 = int(summary.loc[1, "total"]) 
a = int(summary.loc[1, "bad"])
n0 = int(summary.loc[0, "total"])
c = int(summary.loc[0, "bad"])

assert (n1, a, n0, c) == (6353, 3962, 88946, 8227)

p1 = a / n1  #延迟订单差评数 ÷ 延迟订单总数。
p0 = c / n0  #准时订单差评数 ÷ 准时订单总数

# 3. 风险差和风险比
rd = p1 - p0
rr = p1 / p0

# 4. 计算95%置信区间
rd_ci = confint_proportions_2indep(
    a, n1, c, n0, compare="diff", method="newcomb"
)

rr_ci = confint_proportions_2indep(
    a, n1, c, n0, compare="ratio", method="log"
)

print("========== 未调整的统计结果 ==========")
print(f"延迟订单差评率：{p1:.2%}")
print(f"准时订单差评率：{p0:.2%}")
print(f"风险差 RD：{rd*100:.2f} 个百分点")
print(f"RD 95%CI：[{rd_ci[0]*100:.2f}, {rd_ci[1]*100:.2f}]")
print(f"风险比 RR：{rr:.2f}")
print(f"RR 95%CI：[{rr_ci[0]:.2f}, {rr_ci[1]:.2f}]")

# 5. Logistic回归：调整地区与月份
#因为各地区的配送条件、不同月份的订单环境可能不同。如果仅比较所有延迟与准时订单，结果中可能混有这些因素带来的差异。
#因变量：是否差评  
# 主要解释变量：是否配送延迟
#控制变量：客户所在州
#控制变量：下单月份


model = smf.glm(
    formula=(
        "is_bad_review ~ is_late "
        "+ C(customer_state) + C(order_month)"
    ),
    data=df,
    family=sm.families.Binomial()
)

# 同一客户可能对应多笔订单，按客户聚类计算标准误
result = model.fit(
    cov_type="cluster",
    cov_kwds={"groups": df["customer_unique_id"]}
)

if not result.converged:
    raise RuntimeError("模型未收敛，不能使用当前回归结果")

# 6. 提取延迟变量的回归结果
coef = result.params["is_late"]
ci = result.conf_int().loc["is_late"]
p_value = result.pvalues["is_late"]

adjusted_or = np.exp(coef)
or_low = np.exp(ci.iloc[0])
or_high = np.exp(ci.iloc[1])

print("\n========== 调整后的Logistic回归 ==========")
print(f"模型样本量：{int(result.nobs)}")
print("已调整：客户所在州、下单月份")
print(f"延迟订单调整后 OR：{adjusted_or:.2f}")
print(f"OR 95%CI：[{or_low:.2f}, {or_high:.2f}]")
print(f"P值：{p_value:.4g}")
