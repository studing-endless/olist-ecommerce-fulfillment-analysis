# 数据准备与运行顺序

## 环境与输入

建议使用稳定正式版Python 3.10或3.11及MySQL 8。实际验证版本与执行范围见[质量修复报告](quality_review.md)，早期3.9.0rc2环境的验证范围见报告中的[历史核验](quality_review.md#历史核验与原报告证据)。在仓库根目录使用PowerShell运行。

```powershell
py -3.10 -m venv .venv
.venv/Scripts/python.exe -m pip install -r requirements-verified.txt
.venv/Scripts/python.exe -m pip check
```

`requirements.txt`保留兼容范围，`requirements-verified.txt`记录本次Windows/Python 3.10实际安装版本及间接依赖，不代表所有操作系统都经过测试。安装完成后可激活环境，以下命令均使用该虚拟环境的 `python`。

```powershell
. .venv/Scripts/Activate.ps1
```

已有原始数据可直接指定路径。从[Kaggle数据页](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)获取九份CSV时遵守CC BY-NC-SA 4.0。原始文件不进入Git。`review_id`单独不是唯一键，地理表邮编前缀也不是唯一键，当前主分析不关联地理表。

| 表 | 已核验原始行数 |
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

## 建库与SQL

只在获得授权的全新专用测试数据库执行。服务器端需事先允许 `local_infile`，初始化入口仅对当前客户端启用LOCAL，不更改服务器全局配置。禁止对现有业务库运行，也不要使用客户端 `--force`。Windows的MySQL服务端数据目录建议用纯英文路径，运行前核对实例端口与目录。

```powershell
$env:OLIST_DB_HOST = '127.0.0.1'
$env:OLIST_DB_PORT = '34067' # 改成专用实例实际端口
$env:OLIST_DB_NAME = 'olist_quality_local' # 必须为尚不存在的新库
$env:OLIST_DB_USER = Read-Host '专用实例用户名'
python python/09_run_sql.py --database $env:OLIST_DB_NAME --initialize --raw-dir '自行准备的CSV目录'
python python/09_run_sql.py --database $env:OLIST_DB_NAME
```

密码由getpass交互读取，不写入命令历史。自动化环境可由私有运行器在进程内注入 `OLIST_DB_PASSWORD`，使用后清理环境变量。连接信息、密码和调试输出不提交。

09按现有SQL执行，初始化检测同名库存在时立即拒绝。随后依次执行01平台、02地区、03评价并建立视图、04卖家、05交运及金额。结果仅消费不打印订单ID或评论，逐语句遇错或警告停止。初始化中途失败时保留库用于排查，下一次使用新的授权空库，勿向已导入表追加。

也可使用MySQL客户端执行原SQL。先将00的CSV目录改成完整正斜杠路径，并把所有SQL中的库名统一到授权新库。`LOAD DATA LOCAL INFILE`的文件路径由客户端解析。不得在原CSV上改写转义或换行。导入后检查行数、警告、评价组合键及商品明细键。04的单卖家探索依赖本地设置 `@focus_seller_id`，未设置时该探索返回空，不影响全体画像。补充06有与05重复的早期查询，不属于必跑主流程。

## 导出与原分析

```powershell
# 普通运行检查结构与数值有效性。复现固定公开版本时另启用基准核验。
$env:OLIST_VERIFY_REFERENCE = '1'
$env:OLIST_FIGURES_DIR = 'outputs/local_figures'
python python/01_export_order_review.py
python python/00_export_seller_tables.py
python python/02_visualize_review_delay.py
python python/03_review_statistics.py
python python/04_seller_risk_analysis.py
python python/05_seller_handoff_analysis.py
python python/06_plot_public_summaries.py
Remove-Item Env:OLIST_VERIFY_REFERENCE
```

01读取SQL03的视图，00执行三份卖家导出查询，两者相互独立但均在SQL03之后运行。04需要seller_profile，05需要04短名单、seller_handoff_profile及seller_issue_amount。中间表默认写入被忽略的 `outputs/tables/`，可用 `OLIST_TABLES_DIR`改到私有工作目录。02—05日志可能含原始卖家ID，仅在本地保留。06读取现有公开汇总再绘三图，不更新公开汇总文件。上面指定的本地图目录避免覆盖已审核图表。

常规分析可不设 `OLIST_VERIFY_REFERENCE`。该变量为1时额外检查固定数据版本的样本、分组、统计量、候选人数与金额。新数据版本未通过固定基准不等于通用结构无效，应先排查版本和口径。

## 时间切分策略与测试

```powershell
python python/08_seller_strategy_comparison.py --raw-dir '自行准备的CSV目录' --output-dir outputs/local_strategy --figure outputs/local_figures/seller_strategy_comparison.png
python -m unittest discover -s tests -v
```

08只读订单、商品、评价必要字段，写三份匿名汇总与一张图。与原完整历史9名候选分开解释，详见[卖家决策报告](seller_decision_case.md)。图表与汇总可在本地输出目录查看。

默认测试包含输入检查、短名单并集与既有时间边界/泄漏测试。真实MySQL合成测试另需显式设置 `OLIST_TEST_DB_NAME`，库名前缀为 `olist_quality_`，端口固定34067，沿用当前进程的专用测试凭据。它们只创建连接内临时表，关闭连接自动释放；未配置时显示跳过，不称为通过。

```powershell
$env:OLIST_TEST_DB_NAME = $env:OLIST_DB_NAME
python -m unittest discover -s tests -v
Remove-Item Env:OLIST_TEST_DB_NAME
```

发布前在人工审阅的文件暂存后执行 `python python/07_check_publication.py`。原始CSV、Word、真实ID映射、订单明细、数据库目录、虚拟环境和日志均排除。
