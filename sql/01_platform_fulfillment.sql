USE olist_ecommerce;
-- Olist 电商订单履约风险分析
-- 第一部分：平台履约现状

USE olist_ecommerce;

-- 1.1 订单状态分布
SELECT
    order_status,
    COUNT(*) AS order_count,
    ROUND(
        COUNT(*) * 100.0 /
        (SELECT COUNT(*) FROM olist_orders),
        2
    ) AS order_pct
FROM olist_orders
GROUP BY order_status
ORDER BY order_count DESC;


-- 标记为 delivered 的订单，是否都有实际收货时间？其他状态的订单是否也可能存在收货时间？
-- 1.2 不同订单状态的配送日期完整性

SELECT
    order_status,
    COUNT(*) AS total_orders,

    SUM(order_delivered_customer_date IS NOT NULL)
        AS orders_with_delivery_date,

    SUM(order_delivered_customer_date IS NULL)
        AS orders_without_delivery_date,

    SUM(order_estimated_delivery_date IS NULL)
        AS orders_without_estimated_date

FROM olist_orders
GROUP BY order_status
ORDER BY total_orders DESC;

-- 检查那 14 笔特殊订单

-- 1.3 检查订单状态与实际收货时间不一致的记录

SELECT
    order_id,
    order_status,
    order_purchase_timestamp,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
FROM olist_orders
WHERE
    (order_status = 'delivered'
     AND order_delivered_customer_date IS NULL)
    OR
    (order_status = 'canceled'
     AND order_delivered_customer_date IS NOT NULL)
ORDER BY order_status, order_purchase_timestamp;



-- 1.4 已交付订单的时间逻辑检查

SELECT
    COUNT(*) AS valid_date_candidates,

    SUM(
        order_delivered_customer_date
        < order_purchase_timestamp
    ) AS delivery_before_purchase,

    SUM(
        order_delivered_carrier_date IS NOT NULL
        AND order_delivered_customer_date
            < order_delivered_carrier_date
    ) AS delivery_before_carrier,

    SUM(
        DATE(order_estimated_delivery_date)
        < DATE(order_purchase_timestamp)
    ) AS estimate_before_purchase

FROM olist_orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;
  
-- 1.5 平台整体配送时长与延迟交付率
-- 业务问题：客户平均等待多久？多少订单延迟交付？
SELECT
	-- 有效已交付的订单数
	COUNT(*) AS delivered_orders,
    -- TIMESTAMPDIFF()：计算实际配送时长
    ROUND(
		AVG(
			TIMESTAMPDIFF(
				SECOND,
				order_purchase_timestamp,
				order_delivered_customer_date
			) / 86400.0
        ),
        2
	) AS avg_delivery_days,
    
    SUM(
		CASE
            WHEN DATE(order_delivered_customer_date)
                 > DATE(order_estimated_delivery_date)
            THEN 1
            ELSE 0
        END
	) AS late_orders,
    
    ROUND(
		100.0 * AVG(
			CASE
				WHEN DATE(order_delivered_customer_date)
					> DATE(order_estimated_delivery_date)
				THEN 1
				ELSE 0
			END
        ),
        2
	) AS late_delivery_rate
    
FROM olist_orders
WHERE order_status = "delivered"
	AND order_purchase_timestamp IS NOT NULL
    AND order_delivered_customer_date IS NOT NULL
    AND order_estimated_delivery_date IS NOT NULL
    AND order_delivered_customer_date >= order_purchase_timestamp;
    
    
 -- 1.6 配送时长分布分析
-- 目的：不同等待时长的订单有多少？延迟率有何差异？   
-- CTE（公用表表达式）
WITH delivery_data AS (
	-- 第一步：为每笔有效订单计算配送时长和延迟标记
	SELECT
		order_id,
        TIMESTAMPDIFF(
            SECOND,
            order_purchase_timestamp,
            order_delivered_customer_date
        ) / 86400.0 AS delivery_days,
        
        CASE
            WHEN DATE(order_delivered_customer_date)
                 > DATE(order_estimated_delivery_date)
            THEN 1
            ELSE 0
        END AS is_late 
	FROM olist_orders
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
      AND order_delivered_customer_date >= order_purchase_timestamp
)	
-- 第二步：按配送时长分组统计		

SELECT 
	CASE 
		WHEN delivery_days < 7 THEN "01_不足7天"
        WHEN delivery_days < 14 THEN "02_7至不足14天"
        WHEN delivery_days < 21 THEN "03_14至不足21天"
        WHEN delivery_days < 30 THEN "04_21至不足30天"
        ELSE "05_30天及以上"
	END AS delivery_group,
    
    COUNT(*) AS order_count,
    ROUND(AVG(delivery_days),2) AS avg_days,
    SUM(is_late) AS late_orders,
    ROUND(AVG(is_late) * 100, 2) AS late_rate_pct
    
FROM delivery_data
GROUP BY delivery_group
ORDER BY delivery_group;


-- 1.7 配送时长的中位数、P90和P95
WITH delivery_data AS (
	SELECT
        TIMESTAMPDIFF(
            SECOND,
            order_purchase_timestamp,
            order_delivered_customer_date
        ) / 86400.0 AS delivery_days
    FROM olist_orders
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
      AND order_delivered_customer_date >= order_purchase_timestamp
      AND order_estimated_delivery_date IS NOT NULL
),

ranked_data AS (
	SELECT
		delivery_days,
        
        -- 按配送时长从短到长排序并编号
        ROW_NUMBER() OVER (
			ORDER BY delivery_days
		) AS rn,
        
        -- 计算样本总量
        COUNT(*) OVER () AS n
	FROM delivery_data
)

SELECT
	COUNT(*) AS total_orders,
    ROUND(AVG(delivery_days), 2) AS avg_days,
    -- 中位数：奇数样本取中间值，偶数取中间两个值的均值
    ROUND(AVG(
		CASE
			WHEN rn IN (
				FLOOR((n + 1) / 2),
				FLOOR((n + 2) / 2)
			)
			THEN delivery_days
		END
	),2) AS median_days,
    
	-- P90：最接近90%累计位置的观测值
    ROUND(MAX(
		CASE
			WHEN rn = CEIL(n * 0.90)
			THEN delivery_days
		END
	), 2) AS p90_days,
    
    -- P95：最接近95%累计位置的观测值
    ROUND(MAX(
        CASE
            WHEN rn = CEIL(n * 0.95)
            THEN delivery_days
        END
    ), 2) AS p95_days
FROM ranked_data;

 -- 1.8 承诺配送周期与延迟严重程度
 WITH delivery_data AS (
	SELECT
		order_id,
        
        -- 下单日期到承诺交付日期的天数
		DATEDIFF(
			order_estimated_delivery_date,
            order_purchase_timestamp
		) AS promised_days,
        
        -- 实际收货日期对承诺日期的差值
        DATEDIFF(
			order_delivered_customer_date,
            order_estimated_delivery_date
		) AS delay_days
        
	FROM olist_orders
	WHERE order_status = 'delivered'
      AND order_purchase_timestamp IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
      AND order_delivered_customer_date >= order_purchase_timestamp
)

SELECT 
	-- 有效已交付订单数
    COUNT(*) AS total_orders,
    
    -- 平均承诺配送周期
    ROUND(AVG(promised_days), 2) AS avg_promised_days,
    
    -- 延迟订单平均超期天数
    ROUND(
		AVG(
			CASE
				WHEN delay_days > 0 THEN delay_days
			END
		), 2
	) AS avg_late_days,
    
    -- 延迟1至3天
    SUM(
		CASE WHEN delay_days BETWEEN 1 AND 3
			THEN 1 ELSE 0 END
	) AS late_1_3_days,
    
    -- 延迟4至7天
    SUM(
		CASE WHEN delay_days BETWEEN 4 AND 7
			THEN 1 ELSE 0 END
	) AS late_4_7_days,
    
    SUM(
		CASE WHEN delay_days >= 8
			THEN 1 ELSE 0 END
	) AS late_8_plus_days
    
FROM delivery_data;


-- ==================================================
-- 1.9 配送阶段耗时分析
-- 业务问题：准时和延迟订单的两个配送阶段有何差异？

WITH delivery_data AS (
	SELECT 
		order_id,
        -- 标记订单是否延迟
        CASE
			WHEN DATE(order_delivered_customer_date)
				> DATE(order_estimated_delivery_date)
			THEN 'late'
            ELSE 'on_time'
		END AS delivery_status,
        -- 阶段1：下单到交付承运方
        TIMESTAMPDIFF(
			SECOND,
            order_purchase_timestamp,
            order_delivered_carrier_date
		) / 86400.0 AS pre_carrier_days,
        
        
        -- 阶段2：交付承运方到客户收货
        TIMESTAMPDIFF(
			SECOND,
            order_delivered_carrier_date,
            order_delivered_customer_date
		) / 86400.0 AS transit_days
        
	FROM olist_orders
		WHERE order_status = 'delivered'
		  AND order_purchase_timestamp IS NOT NULL
		  AND order_delivered_carrier_date IS NOT NULL
		  AND order_delivered_customer_date IS NOT NULL
		  AND order_estimated_delivery_date IS NOT NULL

		  -- 排除时间顺序不合理的记录
		  AND order_delivered_carrier_date
			  >= order_purchase_timestamp

		  AND order_delivered_customer_date
			  >= order_delivered_carrier_date
)
    
SELECT
	delivery_status,
    -- 当前分组的订单数、
    COUNT(*) AS order_count,
    
     -- 阶段1平均耗时
     ROUND(AVG(pre_carrier_days), 2)
		AS avg_pre_carrier_days,
        
	 -- 阶段2平均耗时
     ROUND(AVG(transit_days), 2)
		AS avg_transit_days,
        
	-- 两阶段合计的平均配送时长
    ROUND(
		AVG(pre_carrier_days + transit_Days),
        2
	) AS avg_total_days
    
FROM delivery_data
GROUP BY delivery_status
ORDER BY delivery_status;


-- ==================================================
-- 1.10 配送阶段分析的样本损失检查
-- 目的：确认189笔订单为什么未进入阶段分析
-- ==================================================
WITH base_orders AS (
	 -- 与之前96,470笔有效已交付订单保持同一口径
     SELECT *
    FROM olist_orders
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
      AND order_delivered_customer_date >= order_purchase_timestamp
)

SELECT
	-- 原始候选样本数
    COUNT(*) AS base_orders,
    
    -- 缺少交付承运方时间
    SUM(
		order_delivered_carrier_date IS NULL
	) AS missing_carrier_date,
    
    -- 交付承运方时间早于下单时间
    SUM(
		order_delivered_carrier_date
			< order_purchase_timestamp
	) AS carrier_before_purchase,
    
    -- 客户收货时间早于交付承运方时间
    SUM(
        order_delivered_customer_date
            < order_delivered_carrier_date
    ) AS delivery_before_carrier,
    
     -- 最终可用于两个阶段比较的订单数
     SUM(
        CASE
            WHEN order_delivered_carrier_date IS NOT NULL
             AND order_delivered_carrier_date
                 >= order_purchase_timestamp
             AND order_delivered_customer_date
                 >= order_delivered_carrier_date
            THEN 1
            ELSE 0
        END
    ) AS valid_stage_orders
FROM base_orders;

-- ============================================
-- 1.11 订单表与客户表的关联检查
-- 目的：确认JOIN不会造成订单数量重复
-- ============================================

-- ============================================
-- 1.11 订单表与客户表的关联检查
-- 目的：确认JOIN不会造成订单数量重复
-- ============================================

SELECT
    COUNT(*) AS joined_rows,
    COUNT(DISTINCT o.order_id) AS unique_orders,
    SUM(c.customer_id IS NULL) AS unmatched_orders,
    SUM(c.customer_state IS NULL) AS missing_states
FROM olist_orders AS o
LEFT JOIN olist_customers AS c
    ON o.customer_id = c.customer_id;


-- JOIN 后一定要关注数据粒度有没有变化。;
