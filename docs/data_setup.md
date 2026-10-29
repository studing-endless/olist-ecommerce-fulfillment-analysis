# 数据准备与运行顺序

## 下载与环境

从 [Kaggle 数据页](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)自行下载并解压九份 CSV 到本地 `data/raw/`。数据源许可 CC BY-NC-SA 4.0；本仓库不分发原始文件。

需要 MySQL 8+（CTE、窗口函数）、Python 3.9+。在根目录运行 `python -m pip install -r requirements.txt`。已验证的分析库版本见 validation.md；依赖范围不等于每一组合都经过测试。

## MySQL 导入

使用**全新专用数据库**。打开 `sql/00_import_data.sql`，将全部 `data/raw/` 替换为自己机器的完整下载目录，路径使用正斜杠。`LOAD DATA LOCAL INFILE` 的文件路径由客户端解析，相对路径工作目录因客户端不同可能不同。

脚本创建 `olist_ecommerce` 数据库；已有同名库时应停止，换一个全新数据库名并同步替换所有 SQL 的 `USE` 与 Python 的 `OLIST_DB_NAME`。不要在已有业务库中继续执行，不使用客户端 `--force` 选项。脚本不含 TRUNCATE 或 DROP。原始导入脚本的本机路径、清表、全局开关及末尾单表排序规则变更已在发布版移除；所有表在同一数据库默认排序规则下创建。

`LOCAL INFILE` 需要管理员事先允许服务器端 local_infile，客户端也须启用。发布脚本不自动更改全局服务器设置。逐表导入后立即核查警告，尤其评价 CSV 的多行文本、双引号及行尾处理；有警告先解决，不继续分析。此导入流程本次未连接 MySQL 实测。

| 表 | 本地核验原始行数 |
| --- | ---: |
| olist_orders | 99,441 |
| olist_customers | 99,441 |
| olist_order_items | 112,650 |
| olist_order_payments | 103,886 |
| olist_order_reviews | 99,224 |
| olist_products | 32,951 |
| olist_sellers | 3,095 |
| product_category_name_translation | 71 |
| olist_geolocation | 1,000,163 |

行数不能替代键唯一性与质量检查。`review_id` 单独不是唯一键；地理表邮编前缀也不是唯一键，不可直接无聚合关联订单。当前主分析未关联地理表。

## SQL 顺序

1. `00_import_data.sql`：建库建表与数据导入，核对行数。
2. `01_platform_fulfillment.sql`：状态、缺失、时间逻辑、配送分布和阶段检查。
3. `02_regional_delivery.sql`：州、月份、时期、配送阶段及卖家来源。
4. `03_review_analysis.sql`：评价覆盖、差评对比和规则敏感性；创建 `v_order_review_analysis`。
5. `04_seller_risk_analysis.sql`：探索及全部卖家画像查询，依赖上一步视图。
6. `05_handoff_and_amount.sql`：交运、准时订单商品结构、评论探查及交易金额查询。

`sql/exploratory/06_supplementary_checks.sql` 保留早期交运与商品结构检查，部分与 05 重复，不是生成主结果的额外必跑步骤。SQL 中的随机评论探查只用于本地查看，不保存或公开评论。

`04` 中单个卖家的探索查询使用 `@focus_seller_id`。如要运行该两段查询，先在本地设置 `SET @focus_seller_id='自行选择的公开数据卖家ID';`，其余全体卖家查询不受影响。

## Python 连接与导出

数据库导出脚本交互询问用户名，密码通过 `getpass` 输入。也可设置 `OLIST_DB_USER`、`OLIST_DB_PASSWORD`、`OLIST_DB_HOST`、`OLIST_DB_PORT`、`OLIST_DB_NAME`。默认主机为本地、端口 3306、库名为 olist_ecommerce；没有默认密码。不要将凭据写进代码、命令历史或提交文件。

先运行 `python python/01_export_order_review.py`，读取评价视图，输出 `outputs/tables/order_review_analysis.csv`（95,299 行；断言与本地数据版本一致）。

然后运行 `python python/00_export_seller_tables.py`，依次执行三份 `sql/export_*.sql` 中的完整查询，输出：

| 私有中间表 | 查询来源 | 后续使用 |
| --- | --- | --- |
| seller_profile.csv | 04 最后一条全部卖家画像查询 | Python 04 |
| seller_handoff_profile.csv | 05 按卖家汇总交运查询 | Python 05 |
| seller_issue_amount.csv | 05 最后一条问题金额查询 | Python 05 |

三份导出查询保留原有逻辑，不需要手工在 SQL 结果界面逐表另存。PyMySQL 游标执行查询并生成 DataFrame，避免旧 SQLAlchemy 版本的 URL API 兼容问题；数据库连接步骤尚未运行验证。

之后按 README 的 Python 02、03、04、05 顺序执行。04 生成候选与短名单，05 依赖短名单并生成最终调查表。Python 03 不依赖 04/05。01 与 00 导出脚本彼此无依赖，但两者都在 SQL 03 之后运行。

`OLIST_TABLES_DIR` 可指定自己的本地中间表目录，`OLIST_FIGURES_DIR` 可指定图表目录；默认路径相对代码文件定位，不依赖终端工作目录。`outputs/tables/` 整体被 Git 忽略。

只展示已有结果时可直接运行 `python python/06_plot_public_summaries.py`，从仓库中的公开汇总表生成州、时期阶段和交运三张图。评价图和四象限图由 02、04 用自行准备的本地中间表生成。公开汇总表是本次核验时的固定结果，重跑 SQL 并不会自动替换这些经人工审核的发布文件。
