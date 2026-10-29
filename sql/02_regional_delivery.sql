USE olist_ecommerce;

-- ==================================================
-- 2.1 各州订单履约情况
-- 目的：比较各州订单规模、配送时长和延迟交付率
-- ==================================================

WITH regional_orders AS (

	-- 第一步：将每笔订单与客户所在州关联
    SELECT
		o.order_id,
        c.customer_state,
        
	-- 计算实际配送时长（天）
    TIMESTAMPDIFF(
		SECOND,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date
	) / 86400.0 AS delivery_days,
    
     -- 计算承诺配送周期（自然日）
    DATEDIFF(
		o.order_estimated_delivery_date,
        o.order_purchase_timestamp
	) AS promised_days,
    
    -- 判断订单是否延迟
    CASE 
		WHEN DATE(o.order_delivered_customer_date)
			> DATE(o.order_estimated_delivery_date)
		THEN 1
        ELSE 0
	END AS is_late
    
    
FROM olist_orders AS o
JOIN olist_customers AS c
	ON o.customer_id = c.customer_id
    
  -- 保持与之前整体履约分析相同的样本口径
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
      AND o.order_delivered_customer_date
          >= o.order_purchase_timestamp
)


-- 第二步：按客户所在州汇总
SELECT
	customer_state AS state,
    COUNT(*) AS total_orders,
    ROUND(AVG(delivery_days), 2) AS avg_delivery_days,
    ROUND(AVG(promised_days), 2) AS avg_promised_days,
    SUM(is_late) AS late_orders,
    ROUND(100.0 * AVG(is_late), 2) AS late_rate_pct
    
FROM regional_orders
GROUP BY customer_state

-- 先按延迟订单数量排序，观察问题规模
ORDER BY late_orders DESC;


-- ==================================================
-- 2.2 SP与RJ月度延迟率对比
-- 目的：检查RJ的高延迟率是否具有时间持续性
-- ==================================================

SELECT
	-- 下单月份
    DATE_FORMAT(
		o.order_purchase_timestamp,
        '%Y-%m'
	) AS order_month,
    
    -- 客户所在州
    c.customer_state AS state,
    
    -- 有效已交付订单数
    COUNT(*) AS total_orders,
    
    -- 延迟订单数
    SUM(
        CASE
            WHEN DATE(o.order_delivered_customer_date)
                 > DATE(o.order_estimated_delivery_date)
            THEN 1
            ELSE 0
        END
    ) AS late_orders,
    
    -- 月度延迟率
    ROUND(
		100.0 * AVG(
			CASE 
				WHEN DATE(o.order_delivered_customer_date)
					> DATE(o.order_estimated_delivery_date)
				THEN 1
                ELSE 0
			END
		),
        2
	) AS late_rate_pct
    
    
FROM olist_orders AS o
JOIN olist_customers AS c
	ON o.customer_id = c.customer_id

WHERE c.customer_state IN ('SP', 'RJ')
	AND o.order_status = "delivered"
    AND o.order_purchase_timestamp IS NOT NULL
    AND o.order_delivered_customer_date IS NOT NULL
    AND o.order_estimated_delivery_date IS NOT NULL
    AND o.order_delivered_customer_date
		>= o.order_purchase_timestamp
        
GROUP BY order_month,state
ORDER BY order_month,state
-- 因为 MySQL 允许 GROUP BY 和 ORDER BY 使用 SELECT 中定义的列别名。

-- 2.3 RJ与SP不同时间段的履约表现
;
with delivery_data AS (
	SELECT
		c.customer_state AS state,
        
        -- 根据观察到的月度变化划分时期
        CASE
			WHEN o.order_purchase_timestamp < '2017-11-01'
				THEN '01_前期'
			WHEN o.order_purchase_timestamp < '2018-04-01'
				THEN '02_高延迟期'
			ELSE '03_后期'
		END AS period,
        
       -- 实际配送时长（天）
       TIMESTAMPDIFF(
			SECOND,
            o.order_purchase_timestamp,
            o.order_delivered_customer_date
        ) / 86400.0 AS delivery_days,
        
		-- 承诺配送周期（自然日）
        DATEDIFF(
			o.order_estimated_delivery_Date,
            o.order_purchase_timestamp
		) AS promised_days,
        
         -- 超期天数（正数代表延迟）
        DATEDIFF(
            o.order_delivered_customer_date,
            o.order_estimated_delivery_date
        ) AS delay_days
        
FROM olist_orders AS o
JOIN olist_customers AS c
	ON o.customer_id = c.customer_id
    
WHERE c.customer_state IN ('RJ', 'SP')
	-- 只分析2017年9月至2018年6月
      AND o.order_purchase_timestamp >= '2017-09-01'
      AND o.order_purchase_timestamp < '2018-07-01'
      -- 保持与此前一致的有效订单口径
      AND o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
      AND o.order_delivered_customer_date
          >= o.order_purchase_timestamp
)


SELECT 
	period,
    state,
    COUNT(*) AS total_orders,
    ROUND(AVG(delivery_days),2) AS avg_delivery_days,
    ROUND(AVG(promised_days),2) AS avg_promised_days,
    SUM(delay_days > 0 ) AS late_orders,
    ROUND(AVG(delay_days > 0) * 100, 2)
		AS late_rate_pct
FROM delivery_data
GROUP BY period, state
ORDER BY period, state;

-- 2.4 RJ与SP不同时期的配送阶段耗时
-- 目的：判断配送耗时增加主要表现在哪个阶段
-- 为了保证计算合理，我们排除缺失承运方时间和时间顺序不正确的记录。
WITH delivery_data AS (
	SELECT
    c.customer_state AS state,
    
    CASE
		WHEN o.order_purchase_timestamp < '2017-11-01'
			THEN '01_前期'
		WHEN o.order_purchase_timestamp < '2018-04-01'
			THEN '02_高延迟期'
		ELSE '03_后期'
	END AS period,
        
	    -- 阶段1：下单到交付承运方
        TIMESTAMPDIFF(
            SECOND,
            o.order_purchase_timestamp,
            o.order_delivered_carrier_date
        ) / 86400.0 AS pre_carrier_days,
        
        
        -- 阶段2：交付承运方到客户收货
        TIMESTAMPDIFF(
            SECOND,
            o.order_delivered_carrier_date,
            o.order_delivered_customer_date
        ) / 86400.0 AS transit_days
        
	FROM olist_orders AS o

    JOIN olist_customers AS c
        ON o.customer_id = c.customer_id

    WHERE c.customer_state IN ('RJ', 'SP')
     -- 分析时期：2017年9月至2018年6月
      AND o.order_purchase_timestamp >= '2017-09-01'
      AND o.order_purchase_timestamp < '2018-07-01'

      AND o.order_status = 'delivered'
      -- 确保三个时间节点存在
      AND o.order_purchase_timestamp IS NOT NULL
      AND o.order_delivered_carrier_date IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
      -- 确保时间先后顺序合理
      AND o.order_delivered_carrier_date
          >= o.order_purchase_timestamp

      AND o.order_delivered_customer_date
          >= o.order_delivered_carrier_date
)

SELECT
	period,
    state,
    COUNT(*) AS total_orders,
    
    -- 阶段1平均耗时
    ROUND(AVG(pre_carrier_days), 2) AS avg_pre_carrier_days,
    
    -- 阶段2平均耗时
    ROUND(AVG(transit_days), 2) AS avg_transit_days,
    
    
     -- 总平均配送时长
     ROUND(
		AVG(pre_carrier_days + transit_days),
        2
	) AS avg_total_days
FROM delivery_data
GROUP BY period, state
ORDER BY period, state;

-- 2.5 RJ和SP高延迟期的卖家数量结构
-- 目的：确认后续发货地区分析能否保持订单粒度

WITH seller_count AS (
	SELECT
		order_id,
        -- 统计每笔订单涉及多少个不同卖家
        COUNT(DISTINCT seller_id) AS seller_count
        
	FROM olist_order_items
    GROUP BY order_id
)

SELECT 
	c.customer_state AS state,
    COUNT(*) AS total_orders,
    
    -- 只有一个不同卖家的订单
    SUM(s.seller_count = 1) AS single_seler_orders,
    
    -- 涉及多个卖家的订单
	SUM(s.seller_count > 1) AS muti_seller_orders,
    
    
    -- 没有找到订单商品记录
	SUM(s.order_id IS NULL) AS order_without_items
    
FROM olist_orders AS o
JOIN olist_customers AS c
	ON o.customer_id = c.customer_id
LEFT JOIN seller_count AS s
	ON o.order_id = s.order_id
WHERE c.customer_state IN ('RJ','SP')
	AND o.order_purchase_timestamp >= '2017-11-01'
    AND o.order_purchase_timestamp < '2018-04-01'
    AND o.order_status = 'delivered'
    AND o.order_delivered_carrier_date IS NOT NULL
	AND o.order_delivered_customer_date IS NOT NULL
	AND o.order_delivered_carrier_date >= o.order_purchase_timestamp
	AND o.order_delivered_customer_date >= o.order_delivered_carrier_date
GROUP BY c.customer_state;
  

-- 需要关联四张表，但仍然保持一笔订单对应一行。
-- olist_sellers 的 seller_id 是否唯一：
SELECT
	COUNT(*) AS seller_rows,
    COUNT(DISTINCT seller_id) AS unique_sellers,
    SUM(seller_id IS NULL) AS missing_seller_ids
FROM olist_sellers;
-- 2.6 不同时期的同州与异州卖家订单比较

WITH single_seller AS (
	-- 每个订单只保留一个不同卖家的订单
    SELECT 
		order_id,
        MIN(seller_id) AS seller_id
	FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
		AND COUNT(seller_id) = COUNT(*)
),


delivery_data AS (
	SELECT
		c.customer_state AS state,
        CASE
			WHEN o.order_purchase_timestamp < '2017-11-01'
				THEN '01_前期'
			WHEN o.order_purchase_timestamp < '2018-04-01'
				THEN '02_高延迟期'
			ELSE '03_后期'
		END AS period,
	
    -- 卖家与客户是否属于同一个州
    CASE
		WHEN s.seller_state IS NULL THEN '未知'
        WHEN s.seller_state = c.customer_state THEN '同州'
        ELSE '异州'
	END AS seller_region_type,
    
    
    -- 交付承运方后耗时
        TIMESTAMPDIFF(
            SECOND,
            o.order_delivered_carrier_date,
            o.order_delivered_customer_date
        ) / 86400.0 AS transit_days,
        
     -- 是否延迟交付
    CASE
		WHEN DATE(o.order_delivered_customer_date)
			> DATE(o.order_estimated_delivery_date)
		THEN 1 ELSE 0
	END AS is_late
        
	FROM olist_orders AS o
    JOIN olist_customers AS c
		ON o.customer_id = c.customer_id
	JOIN single_seller AS ss
		ON o.order_id = ss.order_id
	LEFT JOIN olist_sellers AS s
		ON ss.seller_id = s.seller_id
        
    WHERE c.customer_state IN ('RJ', 'SP')
      AND o.order_purchase_timestamp >= '2017-09-01'
      AND o.order_purchase_timestamp < '2018-07-01'
      AND o.order_status = 'delivered'
      AND o.order_delivered_carrier_date IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
      AND o.order_delivered_carrier_date >= o.order_purchase_timestamp
      AND o.order_delivered_customer_date >= o.order_delivered_carrier_date
)

SELECT 
	period,
    state,
    seller_region_type,
    COUNT(*) AS total_orders,
    ROUND(AVG(transit_days), 2) AS avg_transit_days,
    SUM(is_late) AS late_orders,
    ROUND(AVG(is_late) * 100, 2) AS late_rate_pct
    
FROM delivery_data
GROUP BY period, state, seller_region_type
ORDER BY period, state, seller_region_type;




-- ============================================
-- 2.7 RJ高延迟期：卖家来源州分析
-- 目的：识别不同卖家来源州的订单规模和配送表现
-- ============================================

WITH single_seller AS (

    SELECT
        order_id,
        MIN(seller_id) AS seller_id

    FROM olist_order_items
    GROUP BY order_id

    HAVING COUNT(DISTINCT seller_id) = 1
       AND COUNT(seller_id) = COUNT(*)
)

SELECT
    -- 卖家所在州
    COALESCE(s.seller_state, 'UNKNOWN') AS seller_state,

    -- 订单数
    COUNT(*) AS total_orders,

    -- 交付承运方后的平均耗时
    ROUND(
        AVG(
            TIMESTAMPDIFF(
                SECOND,
                o.order_delivered_carrier_date,
                o.order_delivered_customer_date
            ) / 86400.0
        ),
        2
    ) AS avg_transit_days,

    -- 延迟订单数
    SUM(
        DATE(o.order_delivered_customer_date)
        > DATE(o.order_estimated_delivery_date)
    ) AS late_orders,

    -- 延迟率
    ROUND(
        100.0 * AVG(
            DATE(o.order_delivered_customer_date)
            > DATE(o.order_estimated_delivery_date)
        ),
        2
    ) AS late_rate_pct

FROM olist_orders AS o

JOIN olist_customers AS c
    ON o.customer_id = c.customer_id

JOIN single_seller AS ss
    ON o.order_id = ss.order_id

LEFT JOIN olist_sellers AS s
    ON ss.seller_id = s.seller_id

WHERE c.customer_state = 'RJ'

  -- 只分析高延迟期
  AND o.order_purchase_timestamp >= '2017-11-01'
  AND o.order_purchase_timestamp < '2018-04-01'

  AND o.order_status = 'delivered'
  AND o.order_delivered_carrier_date IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL

  -- 保持时间逻辑一致
  AND o.order_delivered_carrier_date
      >= o.order_purchase_timestamp
  AND o.order_delivered_customer_date
      >= o.order_delivered_carrier_date

GROUP BY COALESCE(s.seller_state, 'UNKNOWN')

ORDER BY total_orders DESC;
