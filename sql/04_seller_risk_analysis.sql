USE olist_ecommerce;
-- 统计每笔订单涉及的卖家数量
SELECT
	seller_count,
    COUNT(*) order_count
FROM(
	SELECT
		order_id,
		COUNT(DISTINCT seller_id) AS seller_count
	FROM olist_order_items
	GROUP BY order_id
) t

GROUP BY seller_count
ORDER BY seller_count;


-- 检查有效已交付订单涉及的卖家数量
SELECT
	COALESCE(i.seller_count, 0) AS seller_count,
    COUNT(*) AS order_count
FROM olist_orders o
LEFT JOIN (
	SELECT
		order_id,
        COUNT(DISTINCT seller_id) AS seller_count
	FROM olist_order_items
    GROUP BY order_id
) i
	ON o.order_id = i.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
GROUP BY COALESCE(i.seller_count, 0)
ORDER BY seller_count;

-- 统计每个卖家参与的有效已支付订单数

SELECT	
	i.seller_id,
    COUNT(DISTINCT o.order_id) AS order_count
    
FROM olist_orders AS o
JOIN olist_order_items AS i
	ON o.order_id = i.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
  
GROUP BY i.seller_id
ORDER BY order_count DESC

LIMIT 20;

-- 第一步：计算每个卖家的订单数
WITH seller_orders AS (
	SELECT
		i.seller_id,
        COUNT(DISTINCT o.order_id) AS order_count
    
    FROM olist_orders AS o
    JOIN olist_order_items AS i
		ON o.order_id = i.order_id
	WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
      AND o.order_delivered_customer_date >= o.order_purchase_timestamp   
	GROUP BY i.seller_id
)

-- 第二步：按照订单数量给卖家分组
SELECT
	CASE
		WHEN order_count < 10 THEN '01. 1-9'
        WHEN order_count < 30 THEN '02. 10-29'
        WHEN order_count < 100 THEN '03. 30-99'
        WHEN order_count < 300 THEN '04. 100-299'
        ELSE '05. 300+'
	END AS order_group,
    COUNT(*) AS seller_count
FROM seller_orders
GROUP BY order_group
ORDER BY order_group;


-- 第一步：找出只涉及一个卖家的订单
WITH single_seller_orders AS (
	SELECT
		order_id,
        MIN(seller_id) AS seller_id
	FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
)

-- 第二步：统计各卖家的订单量与延迟情况
SELECT
	s.seller_id,
    COUNT(*) AS order_count,
    SUM(
		CASE
			WHEN DATE(o.order_delivered_customer_date)
				 > DATE(o.order_estimated_delivery_date)
			THEN 1
            ELSE 0
		END
	) AS late_orders,
    ROUND(
        AVG(
            CASE
                WHEN DATE(o.order_delivered_customer_date)
                   > DATE(o.order_estimated_delivery_date)
                THEN 1
                ELSE 0
            END
        ) * 100, 2
    ) AS late_rate_pct
    
FROM olist_orders AS o
JOIN single_seller_orders AS s
	ON o.order_id = s.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
 
 GROUP BY s.seller_id
 ORDER BY late_orders DESC
 LIMIT 20;

-- 在订单量达到一定规模的卖家中，谁的延迟率最高？
-- 第一步：找出只涉及一个卖家的订单
WITH single_seller_orders AS (
	SELECT
		order_id,
        MIN(seller_id) AS seller_id
	FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
)

-- 第二步：统计各卖家的订单量与延迟情况
SELECT
	s.seller_id,
    COUNT(*) AS order_count,
    SUM(
		CASE
			WHEN DATE(o.order_delivered_customer_date)
				 > DATE(o.order_estimated_delivery_date)
			THEN 1
            ELSE 0
		END
	) AS late_orders,
    ROUND(
        AVG(
            CASE
                WHEN DATE(o.order_delivered_customer_date)
                   > DATE(o.order_estimated_delivery_date)
                THEN 1
                ELSE 0
            END
        ) * 100, 2
    ) AS late_rate_pct
    
FROM olist_orders AS o
JOIN single_seller_orders AS s
	ON o.order_id = s.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
 
 GROUP BY s.seller_id
 HAVING COUNT(*) >= 100
 ORDER BY late_rate_pct DESC,late_orders DESC
 LIMIT 20;
 
 -- 分析该卖家的订单流向哪些地区
 -- 1.找到单卖家订单
 WITH single_seller_orders AS (
    SELECT
        order_id,
        MIN(seller_id) AS seller_id
    FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
)
-- 2. 分析指定卖家的收货地区与延迟情况
SELECT
    c.customer_state,

    COUNT(*) AS order_count,

    SUM(
        CASE
            WHEN DATE(o.order_delivered_customer_date)
               > DATE(o.order_estimated_delivery_date)
            THEN 1
            ELSE 0
        END
    ) AS late_orders,

    ROUND(
        AVG(
            CASE
                WHEN DATE(o.order_delivered_customer_date)
                   > DATE(o.order_estimated_delivery_date)
                THEN 1
                ELSE 0
            END
        ) * 100, 2
    ) AS late_rate_pct

FROM olist_orders AS o

JOIN single_seller_orders AS s
    ON o.order_id = s.order_id

JOIN olist_customers AS c
    ON o.customer_id = c.customer_id

WHERE o.order_status = 'delivered'
   AND o.order_purchase_timestamp IS NOT NULL
   AND o.order_delivered_customer_date IS NOT NULL
   AND o.order_estimated_delivery_date IS NOT NULL
   AND o.order_delivered_customer_date >= o.order_purchase_timestamp
-- 只研究这个卖家
	AND s.seller_id = @focus_seller_id
GROUP BY c.customer_state
ORDER BY late_orders DESC;


-- 看卖家每个月的订单量、延迟订单数和延迟率 
-- 1. 找出单卖家订单
WITH single_seller_orders AS (
	SELECT
		order_id,
        MIN(seller_id) AS seller_id
	FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
)

-- 2. 统计指定卖家每个月的履约情况
SELECT
	DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*) AS order_count,
    SUM(
        CASE
            WHEN DATE(o.order_delivered_customer_date)
               > DATE(o.order_estimated_delivery_date)
            THEN 1
            ELSE 0
        END
    ) AS late_orders,
    
    ROUND(
        AVG(
            CASE
                WHEN DATE(o.order_delivered_customer_date)
                   > DATE(o.order_estimated_delivery_date)
                THEN 1
                ELSE 0
            END
        ) * 100, 2
    ) AS late_rate_pct
    
FROM olist_orders AS o
JOIN single_seller_orders AS s
	ON o.order_id = s.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp

  AND s.seller_id = @focus_seller_id
  
  GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
  ORDER BY order_month;
  
  
WITH single_seller AS (
	SELECT
		order_id,
		MIN(seller_id) AS seller_id
	FROM olist_order_items
	GROUP BY order_id
	HAVING COUNT(DISTINCT seller_id) = 1
)

SELECT 
	COUNT(*) AS reviewed_single_seller_orders,
    COUNT(DISTINCT r.order_id) AS unique_orders,
    COUNT(DISTINCT s.seller_id) AS seller_count
    
FROM v_order_review_analysis AS r
JOIN single_seller AS s
	ON r.order_id = s.order_id;
    
    
-- 构建卖家履约与客户评价画像了。
-- 第一步：每笔订单只保留一个卖家
WITH single_seller AS (
	SELECT
		order_id,
        MIN(seller_id) AS seller_id
	FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
),
-- 第二步：每笔订单只保留一条有效评价
single_review AS (
	SELECT
		order_id,
        MAX(review_score) AS review_score
	FROM olist_order_reviews
    GROUP BY order_id
    HAVING COUNT(*) = 1
		AND COUNT(review_score) = 1
)


-- 第二步：计算卖家履约与评价指标

SELECT
	s.seller_id,
    
    -- 履约指标
	COUNT(*) AS order_count,
    SUM(
		CASE
			WHEN DATE(o.order_delivered_customer_date)
				> DATE(o.order_estimated_delivery_date)
			THEN 1 ELSE 0
		END
	) AS late_orders,
    ROUND(
        AVG(
            CASE
                WHEN DATE(o.order_delivered_customer_date)
                   > DATE(o.order_estimated_delivery_date)
                THEN 1 ELSE 0
            END
        ) * 100, 2
    ) AS late_rate_pct,
    
    COUNT(r.order_id) AS reviewed_orders,
    SUM(
		CASE
			WHEN r.review_score <= 2 THEN 1
            ELSE 0 
		END
	) AS bad_review_orders,
    
    ROUND(
		100.0 * SUM(
			CASE
				WHEN r.review_score <= 2 THEN 1
				ELSE 0 
			END
		) / NULLIF(COUNT(r.order_id), 0 ),
		2
	) AS bad_review_rate_pct
FROM olist_orders AS o

JOIN single_seller AS s
	ON o.order_id = s.order_id
LEFT JOIN single_review AS r
	ON o.order_id = r.order_id

WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
GROUP BY s.seller_id
HAVING COUNT(*) >= 100
ORDER BY bad_review_orders DESC
LIMIT 20;

-- 计算全体单卖家订单的基准指标

WITH single_seller AS (
	SELECT
		order_id,
        MIN(seller_id) AS seller_id
	FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
),
-- 第二步：每笔订单只保留一条有效评价
single_review AS (
	SELECT
		order_id,
        MAX(review_score) AS review_score
	FROM olist_order_reviews
    GROUP BY order_id
    HAVING COUNT(*) = 1
		AND COUNT(review_score) = 1
)

SELECT
	COUNT(*) AS order_count,
	SUM(
        DATE(o.order_delivered_customer_date)
        > DATE(o.order_estimated_delivery_date)
    ) AS late_orders,
    ROUND(
        AVG(
            DATE(o.order_delivered_customer_date)
            > DATE(o.order_estimated_delivery_date)
        ) * 100, 2
    ) AS late_rate_pct,
    
    COUNT(r.order_id) AS reviewed_orders,
    SUM(r.review_score <= 2) AS bad_review_orders,
     ROUND(
        AVG(r.review_score <= 2) * 100, 2
    ) AS bad_review_rate_pct
    FROM olist_orders AS o

JOIN single_seller AS s
    ON o.order_id = s.order_id

LEFT JOIN single_review AS r
    ON o.order_id = r.order_id

WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp



;
WITH single_seller AS (
	SELECT
		order_id,
        MIN(seller_id) AS seller_id
	FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
),
-- 第二步：每笔订单只保留一条有效评价
single_review AS (
	SELECT
		order_id,
        MAX(review_score) AS review_score
	FROM olist_order_reviews
    GROUP BY order_id
    HAVING COUNT(*) = 1
		AND COUNT(review_score) = 1
)


-- 第二步：计算卖家履约与评价指标

SELECT
	s.seller_id,
    
    -- 履约指标
	COUNT(*) AS order_count,
    SUM(
		CASE
			WHEN DATE(o.order_delivered_customer_date)
				> DATE(o.order_estimated_delivery_date)
			THEN 1 ELSE 0
		END
	) AS late_orders,
    ROUND(
        AVG(
            CASE
                WHEN DATE(o.order_delivered_customer_date)
                   > DATE(o.order_estimated_delivery_date)
                THEN 1 ELSE 0
            END
        ) * 100, 2
    ) AS late_rate_pct,
    
    COUNT(r.order_id) AS reviewed_orders,
    -- 有效评价中的延迟订单数
    SUM(
		CASE
			WHEN r.order_id IS NOT NULL
            AND DATE(o.order_delivered_customer_date)
				> DATE(o.order_estimated_delivery_date)
			THEN 1
            ELSE 0
		END
	) AS reviewed_late_orders,
    SUM(
		CASE
			WHEN r.review_score <= 2 THEN 1
            ELSE 0 
		END
	) AS bad_review_orders,
    
    ROUND(
		100.0 * SUM(
			CASE
				WHEN r.review_score <= 2 THEN 1
				ELSE 0 
			END
		) / NULLIF(COUNT(r.order_id), 0 ),
		2
	) AS bad_review_rate_pct,
    
    
    -- 延迟订单中，同时发生差评的订单数
    SUM(
		CASE
			WHEN DATE(o.order_delivered_customer_date)
				> DATE(o.order_estimated_delivery_date)
                AND r.review_score <= 2
			THEN 1
            ELSE 0
		END
	) AS late_bad_orders,
    
-- 准时订单中，发生差评的订单数
	SUM(
		CASE
			 WHEN DATE(o.order_delivered_customer_date)
				 <= DATE(o.order_estimated_delivery_date)
				 AND r.review_score <= 2
			 THEN 1
             ELSE 0
		END
	) AS ontime_bad_orders
    

FROM olist_orders AS o

JOIN single_seller AS s
	ON o.order_id = s.order_id
LEFT JOIN single_review AS r
	ON o.order_id = r.order_id

WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
GROUP BY s.seller_id
-- 双高卖家
-- 先只研究至少100笔有效订单的卖家。
HAVING COUNT(*) >= 100
	AND late_rate_pct > 6.85
    AND bad_review_rate_pct > 12.33
-- 优先查看涉及延迟订单较多的卖家。
ORDER BY late_orders DESC
LIMIT 20;

-- 建立全部卖家的基础画像”。
WITH single_seller AS (
	SELECT
		order_id,
        MIN(seller_id) AS seller_id
	FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
),
-- 第二步：每笔订单只保留一条有效评价
single_review AS (
	SELECT
		order_id,
        MAX(review_score) AS review_score
	FROM olist_order_reviews
    GROUP BY order_id
    HAVING COUNT(*) = 1
		AND COUNT(review_score) = 1
)


-- 第二步：计算卖家履约与评价指标

SELECT
	s.seller_id,
    
    -- 履约指标
	COUNT(*) AS order_count,
    SUM(
		CASE
			WHEN DATE(o.order_delivered_customer_date)
				> DATE(o.order_estimated_delivery_date)
			THEN 1 ELSE 0
		END
	) AS late_orders,
    ROUND(
        AVG(
            CASE
                WHEN DATE(o.order_delivered_customer_date)
                   > DATE(o.order_estimated_delivery_date)
                THEN 1 ELSE 0
            END
        ) * 100, 2
    ) AS late_rate_pct,
    
    COUNT(r.order_id) AS reviewed_orders,
    -- 有效评价中的延迟订单数
    SUM(
		CASE
			WHEN r.order_id IS NOT NULL
            AND DATE(o.order_delivered_customer_date)
				> DATE(o.order_estimated_delivery_date)
			THEN 1
            ELSE 0
		END
	) AS reviewed_late_orders,
    SUM(
		CASE
			WHEN r.review_score <= 2 THEN 1
            ELSE 0 
		END
	) AS bad_review_orders,
    
    ROUND(
		100.0 * SUM(
			CASE
				WHEN r.review_score <= 2 THEN 1
				ELSE 0 
			END
		) / NULLIF(COUNT(r.order_id), 0 ),
		2
	) AS bad_review_rate_pct,
    
    
    -- 延迟订单中，同时发生差评的订单数
    SUM(
		CASE
			WHEN DATE(o.order_delivered_customer_date)
				> DATE(o.order_estimated_delivery_date)
                AND r.review_score <= 2
			THEN 1
            ELSE 0
		END
	) AS late_bad_orders,
    
-- 准时订单中，发生差评的订单数
	SUM(
		CASE
			 WHEN DATE(o.order_delivered_customer_date)
				 <= DATE(o.order_estimated_delivery_date)
				 AND r.review_score <= 2
			 THEN 1
             ELSE 0
		END
	) AS ontime_bad_orders
    

FROM olist_orders AS o

JOIN single_seller AS s
	ON o.order_id = s.order_id
LEFT JOIN single_review AS r
	ON o.order_id = r.order_id

WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
GROUP BY s.seller_id
ORDER BY late_orders DESC;
