# 发布文件清单

此清单对应本地待发布内容。用户确认公开操作之前，不创建公开仓库、不改变远端可见性、不推送。

最终45个文件：10份SQL、9份Python、5张PNG、11份经过审核的CSV汇总、6份docs文档，以及README、依赖说明、数据许可说明和.gitignore共4份根目录文件。

安全排除：九份原始CSV、订单/客户级明细、原始卖家ID映射、评论原文、内部Word及其截图、个人环境配置、虚拟环境、缓存和凭据。CSV仅按明确白名单收录，目录outputs/tables整体忽略。检查了常见Token/私钥/连接串、硬编码密码、本机绝对路径、意外文件类型与大文件。

本次对原项目34个文件进行了SHA-256和大小前后对比，文件集合与内容均一致；内部Word哈希亦未改变。

下表是清单生成时其余44个文件的工作区字节数和SHA-256；本清单不计算自身哈希。Git本地关闭自动换行转换，正式提交前检查索引和文件一致。总大小另加本文档，约1MB。

| 文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| `.gitignore` | 784 | `11da7be73ad221836ad2988497c44e42868bd8d4e374b37841a8d11fe591bf9c` |
| `DATA_LICENSE.md` | 928 | `218921833c67a33ca1dd99333c79354e30008adbdc47e90a13296a3a9886796e` |
| `README.md` | 9,750 | `95fe5d38e922e38b70e5fa1528a56e8db19e92742eb78ba76d4e82ae519446ff` |
| `docs/audit.md` | 4,011 | `9782a15aa8d5055c1b1373d7c5c13c3cb3f636f758b154975a7022ccf1a8b19e` |
| `docs/data_setup.md` | 5,232 | `bca89e26bd1beffb6ea7b6c6bb59147366747b0f1ab112c7c225ce7ecb36fa95` |
| `docs/methodology.md` | 4,884 | `0df5b052d52d037025aa76289aef80d16655b54f8aacdcffcda277b4c505e54a` |
| `docs/report_reconciliation.md` | 3,632 | `316028fc5582b93ce6e37df76271b8746180f42ad123de77c80f659246d8302d` |
| `docs/validation.md` | 3,672 | `477cfd83578617afc9195bddf3ddd4918c2036d6c77ed8894b5c19055033d589` |
| `figures/handoff_diagnosis.png` | 67,615 | `eb49763722d3533e8fdbca1f1a2b551bfb1436fcc65075c46600dcf91b961b98` |
| `figures/regional_stages.png` | 82,514 | `3c53654f9a8666c38bf0a871fc6f8682d722b3a0da47554c52f781b47c8df1b8` |
| `figures/review_rate_by_delay.png` | 152,822 | `a233702da6b921e2da60d2ec7c61b56aab0ef0bfa0dcd4a8a124019e876bbf10` |
| `figures/seller_risk_quadrants.png` | 388,696 | `792d24153f56fe4be151948c4cfe3f5b1ceb7c73185c51b08b462cab3bcbe4d7` |
| `figures/state_delivery.png` | 85,301 | `ccee9e7adf7c7c9ec3e54f29a69d7506bc2237911263ec0a84cd67b373349701` |
| `outputs/01_order_status_distribution.csv` | 183 | `1ede6319dd1bc86c28c2fc0e201d1d3844e6473c4ae5578c8174f1d3752bcc6a` |
| `outputs/02_state_delivery_summary.csv` | 843 | `7e1334c42697c3ae221b46f77cff2654c16afe74ae66818d90a925af181050b3` |
| `outputs/delay_group_summary.csv` | 173 | `02935f54eed254c6cdda6e8ea201ede6d901b16c6e3ada413c8318a6f531904d` |
| `outputs/handoff_summary.csv` | 139 | `43d6d5c1d01057b320b3a098cf2748651c56599335553fe148a0d4c66b14de4a` |
| `outputs/ontime_order_structure.csv` | 172 | `74f8814674c44bf98d654f691840d29c8582d50afc893c4286349695ebdc140f` |
| `outputs/platform_summary.csv` | 142 | `57c015c0bee3a415bece3463b479fd7071adc9acce9e4d31e7a63c223d9ba485` |
| `outputs/regional_period_summary.csv` | 331 | `fb6a6efd2c068a28a442f9b8540b134ef74831fbb990d8e31aee96fb46c44e31` |
| `outputs/regional_stage_summary.csv` | 243 | `5347fc0cff6df40afc5b7c9fb4e556b4145b4f51caa85b320e85f7e1eb7b9b21` |
| `outputs/review_summary.csv` | 83 | `88e1bd994bce2c36a6d7617568296a47847e7528ac9c2079fbb630f1eaa6ee8c` |
| `outputs/seller_shortlist_public.csv` | 548 | `b787d4e50eef8c264c046faa5b65955094d0958a7be27e17c2de349111b35bb3` |
| `outputs/two_item_review_summary.csv` | 84 | `7b156701909d7eb02c89e2d49015879b0ad62412e0cf38d8ba8f27e4e9e80d6d` |
| `python/00_export_seller_tables.py` | 1,142 | `c187b0e1df1299756cf8530154c8f5350b8b6f84dece532558138e641194fd4c` |
| `python/01_export_order_review.py` | 2,617 | `7b3020b83745b34cc34943d2e0b866056070979164e16390ec875c893985ae53` |
| `python/02_visualize_review_delay.py` | 3,018 | `d3920b2115b3906d4132b05706e7909773b1c769d5e69d9ab74d93c41d47071e` |
| `python/03_review_statistics.py` | 3,047 | `1dbd83d5c6f832422a415d0d3f91c126d1dae28b027af1cb0f61a9d0262e5e15` |
| `python/04_seller_risk_analysis.py` | 7,830 | `f990988aa9da00579066179b8bec04551d0c63a79a47684b194bcbd545b79de0` |
| `python/05_seller_handoff_analysis.py` | 2,704 | `c1f121781ee4f6c6098858359b0c693d7b629626189d65228cd203c28df4d378` |
| `python/06_plot_public_summaries.py` | 2,741 | `12994dc906c7f93badc0f769668e42c5806ddec2f7794580f2d4c29277b9dd55` |
| `python/07_check_publication.py` | 3,268 | `1aedeb08b47319a90789fc0ca345b45ba4470fee3b7426890fcd9a096c718564` |
| `python/project_paths.py` | 406 | `2138cef6c95e1ab2649d2a30d0e42e5029ce0e7fd38cdb210c1429424b79cfa8` |
| `requirements.txt` | 94 | `c342bd0c402ae0b0b16f24e23b78719f04cb366a1b9655bd460721c9bc457506` |
| `sql/00_import_data.sql` | 10,791 | `d450a6bb46fe54dcb1de58a51d2c0d13e2c828b6b98ea00aabbd473797f9b01f` |
| `sql/01_platform_fulfillment.sql` | 11,919 | `79a4847552f7246ffc8d7b6b4fbbe2540d6230b9f053cf6fef8507e4ec08d7f6` |
| `sql/02_regional_delivery.sql` | 13,454 | `5c8afa0188335901a4bf9ece7258b7f10617c241a5f6a14f131957cc3ce250c7` |
| `sql/03_review_analysis.sql` | 8,978 | `291cd9ad14a07b73b2b2d4158eeb0ae214460e5cfd39ac30b4a02aae9439b017` |
| `sql/04_seller_risk_analysis.sql` | 16,884 | `b9b1d6338d9d6a3ba9199e5c77088a062f1960b8c7fc0dc0b1000a17ad246135` |
| `sql/05_handoff_and_amount.sql` | 20,223 | `4c32b5db4071bd5fc2d43bf3e698dbb7f92cc3637201eaaa50c3688f511f5f42` |
| `sql/exploratory/06_supplementary_checks.sql` | 9,405 | `13a7db9c1c26b73828f3db93c9b7f068330674ce213b2c1ab0795ec14f2c9e31` |
| `sql/export_seller_handoff_profile.sql` | 1,826 | `6122bdb362032c7bbf974b523de3ec4479f63169536786cbbecb9977296c0aaf` |
| `sql/export_seller_issue_amount.sql` | 1,773 | `c7687d0a9c5316d64627ef7284de830e76d071e51e2a9cb0c4e13c86caece8bc` |
| `sql/export_seller_profile.sql` | 2,619 | `c128837135f766394cc5ae57dc47e48ce65b8691597cb04d33694e2ee101c087` |
