USE olist_ecommerce;
-- 统计这笔订单有几条商品明细。
-- 检查同一订单中是否存在多个交运截止时间
SELECT
	order_id,
    COUNT(*) AS item_count,
    -- 统计存在多少个不同的非空截止时间
    COUNT(DISTINCT shipping_limit_date) AS deadline_count
FROM olist_order_items
GROUP BY order_id
HAVING deadline_count > 1
LIMIT 20


-- 检查单卖家订单中有多少存在多个截止时间
;
WITH item_check AS (
	SELECT
		order_id,
        COUNT(DISTINCT seller_id) AS seller_count,
        COUNT(DISTINCT shipping_limit_date) AS deadline_count,
        SUM(shipping_limit_date IS NULL) AS missing_deadline
	FROM olist_order_items
    GROUP BY order_id
)

SELECT
	COUNT(*) AS total_orders,
    
    SUM(
		i.deadline_count = 1 AND i.missing_deadline = 0
	) AS single_deadline_orders,
    
    SUM(
		i.deadline_count > 1 AND i.missing_deadline = 0
	) AS multiple_deadline_orders,
    
    SUM(
		i.missing_deadline > 0
	) AS missing_deadline_orders,
    
    SUM(
		o.order_delivered_carrier_date IS NULL
	) AS missing_carrier_orders
FROM olist_orders AS o
JOIN item_check AS i
	ON o.order_id = i.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp

  AND i.seller_count = 1;    
  
  
-- 第一步：整理单卖家订单的交运截止时间
WITH single_seller AS (
	SELECT
		order_id,
        MIN(shipping_limit_date) AS shipping_deadline
	FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
)
-- 第二步：分析交运超期与最终送达延迟的关系
SELECT
	COUNT(*) AS valid_orders,
    
    -- 交运超期订单数
	SUM(
		o.order_delivered_carrier_date > s.shipping_deadline
	) AS late_handoff_orders,
    
    -- 交运超期率
	ROUND(
		AVG(o.order_delivered_carrier_date > s.shipping_deadline
        ) * 100, 2
	) AS late_handoff_rate_pct,
	-- 最终延迟送达订单数
    SUM(
        DATE(o.order_delivered_customer_date)
        > DATE(o.order_estimated_delivery_date)
    ) AS late_delivery_orders,
    -- 交运超期，且最终延迟
    SUM(
		o.order_delivered_carrier_date > s.shipping_deadline
        AND DATE(o.order_delivered_customer_date)
            > DATE(o.order_estimated_delivery_date)
	) AS late_handoff_late_delivery,
    
    -- 按时交运，但最终延迟
    SUM(
        o.order_delivered_carrier_date <= s.shipping_deadline
        AND DATE(o.order_delivered_customer_date)
            > DATE(o.order_estimated_delivery_date)
    ) AS ontime_handoff_late_delivery
FROM olist_orders AS o
JOIN single_seller AS s
	ON o.order_id = s.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
 -- 本次新增：确保承运方时间有效且顺序合理
  AND o.order_delivered_carrier_date IS NOT NULL
  AND o.order_delivered_carrier_date >= o.order_purchase_timestamp
  AND o.order_delivered_carrier_Date <= o.order_delivered_customer_date;
  
  
  
 
  -- 1. 每笔单卖家订单保留一个卖家和交运截止时间
  WITH single_seller AS (
  SELECT
	order_id,
    MIN(seller_id) AS seller_id,
    MIN(shipping_limit_date) AS shipping_deadline
	FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id)= 1
)
-- 2. 统计每个卖家的交运与最终送达情况
SELECT 
	s.seller_id,
    COUNT(*) AS order_count,
	-- 交运超期订单数
    SUM(
        o.order_delivered_carrier_date > s.shipping_deadline
    ) AS late_handoff_orders,
    
    -- 交运超期率
    ROUND(
        AVG(o.order_delivered_carrier_date > s.shipping_deadline)
        * 100, 2
    ) AS late_handoff_rate_pct,
    
    -- 最终延迟订单数
    SUM(
        DATE(o.order_delivered_customer_date)
        > DATE(o.order_estimated_delivery_date)
    ) AS late_delivery_orders,
    
     -- 按时交运但最终延迟的订单数
    SUM(
        o.order_delivered_carrier_date <= s.shipping_deadline
        AND DATE(o.order_delivered_customer_date)
            > DATE(o.order_estimated_delivery_date)
    ) AS ontime_handoff_late_delivery
    
FROM olist_orders AS o
JOIN single_seller AS s
    ON o.order_id = s.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp

  AND o.order_delivered_carrier_date IS NOT NULL
  AND o.order_delivered_carrier_date >= o.order_purchase_timestamp
  AND o.order_delivered_carrier_date <= o.order_delivered_customer_date
GROUP BY s.seller_id
ORDER BY ontime_handoff_late_delivery DESC



-- 检查原始评价表中的文本可用性，
;
SELECT
    review_score,
    COUNT(*) AS review_count,

    SUM(
        review_comment_message IS NOT NULL
        AND TRIM(review_comment_message) <> ''
    ) AS with_comment,

    ROUND(
        AVG(
            review_comment_message IS NOT NULL
            AND TRIM(review_comment_message) <> ''
        ) * 100, 2
    ) AS comment_rate_pct

FROM olist_order_reviews
WHERE review_score IN (1, 2)
GROUP BY review_score
ORDER BY review_score;

-- 查看准时订单的真实差评内容
SELECT
	r.review_score,
    r.review_comment_message,
    r.review_answer_timestamp,
    o.order_delivered_customer_date
    
FROM olist_orders AS o
JOIN olist_order_reviews AS r
	ON o.order_id = r.order_id
    
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
  -- 最终按承诺日期送达
  AND DATE(o.order_delivered_customer_date)
      <= DATE(o.order_estimated_delivery_date)
-- 只看低分且有文字的评价
   AND r.review_score IN (1, 2)
   AND r.review_comment_message IS NOT NULL
   AND TRIM(r.review_comment_message) <> ''

LIMIT 15;


-- 在配送准时的订单中，购买多件商品的订单，差评率是否比只购买一件商品的订单更高？
-- 第一步：统计每笔订单包含多少件商品
WITH item_count AS (
	SELECT
		order_id,
        COUNT(*) AS item_num
	FROM olist_order_items
    GROUP BY order_id
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

-- 第三步：比较准时订单的差评率
SELECT
	CASE
		WHEN i.item_num = 1 THEN '单商品订单'
        ELSE '多商品订单'
	END AS item_group,
    
    COUNT(*) AS order_count,
    SUM(r.review_score <= 2) AS bad_orders,
    ROUND(
        AVG(r.review_score <= 2) * 100, 2
    ) AS bad_rate_pct
    
    FROM olist_orders AS o
    JOIN item_count AS i
		ON o.order_id = i.order_id
	JOIN single_review AS r
		ON o.order_id = r.order_id
	WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
    -- 本次只研究准时或提前送达的订单
  AND DATE(o.order_delivered_customer_date)
      <= DATE(o.order_estimated_delivery_date)

GROUP BY item_group;
		
        




-- 1. 统计每笔订单的商品数和卖家数
WITH item_count AS (
	SELECT
		order_id,
        COUNT(*) AS item_num,
        COUNT(DISTINCT seller_id) AS seller_num
	FROM olist_order_items
    GROUP BY order_id
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

-- 3. 比较三种订单结构的差评率
SELECT
	CASE
		WHEN i.item_num = 1 THEN '01. 单商品单卖家'
        WHEN i.seller_num = 1 THEN '02. 多商品单卖家'
        ELSE '03. 多商品多卖家'
	END AS item_group,
    
    COUNT(*) AS order_count,
    SUM(r.review_score <= 2) AS bad_orders,
    ROUND(
        AVG(r.review_score <= 2) * 100, 2
    ) AS bad_rate_pct
    
FROM olist_orders AS o
JOIN item_count AS i
	ON o.order_id = i.order_id
JOIN single_review AS r
	ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
    -- 本次只研究准时或提前送达的订单
  AND DATE(o.order_delivered_customer_date)
      <= DATE(o.order_estimated_delivery_date)

GROUP BY item_group
ORDER BY item_group;

