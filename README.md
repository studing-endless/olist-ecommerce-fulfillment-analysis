# Olist 电商订单履约风险诊断与客户体验分析

Olist 帮助巴西商家接入线上销售渠道。消费者下单后，卖家备货并交给物流合作伙伴配送。一笔订单可能包含多个卖家的商品，而系统记录的准时签收只反映订单状态。消费者是否按承诺日期收到商品、是否收齐，以及体验如何，需要结合不同记录判断。

项目使用 Olist 2016—2018 年巴西电商公开历史数据，回答三个业务问题。

- 哪些地区和时期的配送问题更集中，耗时增加主要发生在哪个环节？
- 超过承诺日期与差评有什么关系，准时订单还暴露了哪些体验问题？
- 当调查资源有限时，哪些卖家值得优先核查，应从哪里查起？

[完整业务分析报告](docs/analysis_journey.md)串起原始分析的判断过程。[卖家策略比较](docs/seller_decision_case.md)是后续扩展，比较相同调查名额下四种筛选方式的取舍。

## 主要发现

- **配送问题有明确的排查范围。** 有效已交付订单的延迟率为 **6.77%**，延迟大多集中在等待较久的订单。SP 的延迟订单最多，RJ 的延迟率更高。RJ 高延迟期主要是交运后变慢，其中 SP 来源订单值得优先核查。
- **晚到与差评相关，准时也可能收到低分。** 延迟订单差评率为 **62.36%**，准时订单为 **9.25%**。考虑地区和月份后，关联仍存在。准时的两件商品订单中，双卖家组差评率更高，两组评论都出现少件线索，实际原因仍需查证。
- **卖家名单要配合调查目标使用。** 完整历史筛出 **9 名候选**。交运记录可以区分应先查备货交接，还是先查后续配送。问题订单金额用于衡量涉及的交易规模。
- **相同调查名额下，简单排序也值得比较。** 在后续历史时间切分中，订单量排序覆盖的问题订单最多，问题占比排序所覆盖订单的问题率最高。原组合规则没有胜出。这一回顾性比较无法验证前瞻预测表现或实际改善效果。

## 图表与结果入口

| 想进一步了解 | 资料 |
| --- | --- |
| 延迟集中在哪些地区和阶段 | [各州延迟率](figures/state_delivery.png)、[SP 与 RJ 配送阶段](figures/regional_stages.png) |
| 超期程度和客户评价 | [超期天数与差评率](figures/review_rate_by_delay.png) |
| 卖家如何入选、分别应该查什么 | [卖家四象限](figures/seller_risk_quadrants.png)、[交运诊断](figures/handoff_diagnosis.png) |
| 相同名额下四种筛选方式的取舍 | [完整业务决策报告与样本审计](docs/seller_decision_case.md)、[策略结果 CSV](outputs/seller_strategy_comparison.csv)、[策略对比图](figures/seller_strategy_comparison.png) |

各模块的样本、分母、图表解读和调查建议见[完整业务分析报告](docs/analysis_journey.md)。指标定义和样本筛选见[方法与指标](docs/methodology.md)。

数据来自 [Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)，原始数据许可为 CC BY-NC-SA 4.0。技术栈为 MySQL 8+ 和 Python，依赖见运行说明。

## 如何运行

环境建议：Python 3.9+、MySQL 8+。在仓库根目录运行：

```powershell
python -m pip install -r requirements.txt
# 先下载九份原始 CSV，并按 docs/data_setup.md 在全新数据库执行 SQL 00—05。
python python/01_export_order_review.py
python python/00_export_seller_tables.py
python python/02_visualize_review_delay.py
python python/03_review_statistics.py
python python/04_seller_risk_analysis.py
python python/05_seller_handoff_analysis.py
python python/06_plot_public_summaries.py
```

连接数据库时交互输入用户名和密码，或自行设置 `OLIST_DB_*` 环境变量。原始 CSV 自行从 Kaggle 下载；`data/` 和 `outputs/tables/` 均不入库。已有公开汇总表可直接用于最后一步绘图。完整顺序、SQL 导入路径配置及导出依赖见[数据准备](docs/data_setup.md)。

原项目发布核验中已复跑 Python 评价图、统计模型、卖家筛选、交运合并，并对照原始 CSV 和已有结果核验关键数字；**未实际运行 MySQL 导入、SQL 分析脚本及数据库导出步骤**。SQL 完成静态检查与已识别执行错误修复，不能等同于数据库端执行成功。详情见[核验记录](docs/validation.md)和[报告核验对照](docs/report_reconciliation.md)。

## 文件导航

| 目录 | 内容 |
| --- | --- |
| `sql/` | 数据导入、平台/地区/评价/卖家/交运与金额分析、三份导出查询 |
| `python/` | MySQL 导出、可视化、统计模型、卖家筛选及交运合并 |
| `figures/` | 原有五张分析图与一张卖家策略比较图 |
| `outputs/` | 经检查的订单或卖家汇总成果，含展示编号候选表 |
| `docs/` | 指标口径、复现说明、审计与安全检查、报告结果对照 |

仓库不包含原始 CSV、订单级导出、客户信息、评论原文、个人配置或内部 Word 报告。数据与衍生汇总来源及许可说明见 [DATA_LICENSE.md](DATA_LICENSE.md)。
