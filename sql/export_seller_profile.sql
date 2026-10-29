USE olist_ecommerce;
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
