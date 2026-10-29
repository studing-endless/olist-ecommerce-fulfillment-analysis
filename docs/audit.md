# 项目审计与整理说明

原项目共34个文件，约136 MB。原文件均只读；独立副本中整理代码与文档，未迁移、覆盖或删除原文件。

## 脚本与依赖映射

| 原文件 | 发布文件 | 输入、用途与输出 |
| --- | --- | --- |
| olist_import_remaining_8_tables.sql | sql/00_import_data.sql | 实际包含九张表的建表与导入；原名与内容不一致，发布版据实命名 |
| 平台订单履约现状分析.sql | sql/01_platform_fulfillment.sql | 订单质量、状态、耗时分布、延迟与阶段分析 |
| 02_regional_delivery.sql | sql/02_regional_delivery.sql | 订单+客户+订单项+卖家；州、月、时期、阶段与卖家来源 |
| 03_review_analysis.sql | sql/03_review_analysis.sql | 订单+评价+客户；评价覆盖、敏感性、订单级分析视图 |
| outputs/04_seller_risk_analysis.sql | sql/04_seller_risk_analysis.sql | 订单+订单项+评价/视图；全体卖家画像及探索 |
| outputs/extra materials.sql | sql/05_handoff_and_amount.sql | 交运诊断、准时订单商品结构、评论探索、问题订单金额 |
| outputs/补充实验.sql | sql/exploratory/06_supplementary_checks.sql | 与05部分重复的早期质量与结构检查，保留但不要求重复执行 |
| 01_export_order_review.py | python/01_export_order_review.py | 读取MySQL评价视图，核验并输出本地订单级CSV |
| 02_visualize_review_delay.py | python/02_visualize_review_delay.py | 订单级CSV→按超期程度差评率图 |
| 03_review_statistics（无扩展名） | python/03_review_statistics.py | 订单级CSV→RD、RR、95%CI及州/月调整GLM |
| 04_seller_risk_analysis.py | python/04_seller_risk_analysis.py | 卖家画像CSV→四象限、55名候选、9人短名单及门槛敏感性 |
| 05_seller_handoff_analysis.py | python/05_seller_handoff_analysis.py | 短名单+交运+金额表→最终9人调查表 |

新增 `project_paths.py` 统一输出定位；新增 `00_export_seller_tables.py` 和三份 `export_*.sql` 填补原流程中手工另存卖家查询结果的缺口，查询来自原SQL而非另造分析。新增06从公开汇总绘图、07检查实际Git索引。

## 原有输出的处理

- 原outputs根目录两份状态/州汇总审核后保留；同名order_review_analysis.csv仅是5列核验计数，未与tables中的订单级同名文件混用。
- 原订单明细9 MB仅用于本地核验，不发布。完整卖家画像、交运和金额表仅用于工作验证；公开候选表删除原始ID并使用展示编号。
- 原2张图对应的真实Python分析被保留并复跑，增加样本口径标题；另外3张图来自报告已完成分析的审核汇总，不引入新结论。Word及原截图均不发布。
- .vscode/settings.json仅有本地编辑器环境偏好，完全排除。原脚本密码通过getpass输入，未发现硬编码数据库密码；未将任何交互凭据写入发布文件。

## 修复范围

地区SQL修复 `peroid/period` 不一致；各分析SQL共补齐7处相邻语句间缺失分号，并为末尾语句补分号。评价SQL删除仅用于排障的 `USER()/CURRENT_USER()/@@port` 查询。指定单个卖家的探索条件参数化为 `@focus_seller_id`。

导入脚本原来同时存在“只导入8张表”的旧说明、订单表清空、部分表重复追加、全局开关及单表排序规则变更。发布版按九张表命名，限定全新数据库首次运行，移除清表和全局/单表配置变更，统一继承数据库排序规则；保留原CSV字段映射和导入后行数核对。

Python保留原始样本断言、分组区间、筛选阈值、去重公式与回归设定；仅处理路径、扩展名、密码输入/连接兼容及无界面绘图。原环境SQLAlchemy为1.0，不能满足原脚本URL API；发布导出改用现有PyMySQL，不修改SELECT内容。

关于报告中不同样本、计划与已完成结果的区分，见 report_reconciliation.md。发布文件逐项清单见 release_manifest.md。
