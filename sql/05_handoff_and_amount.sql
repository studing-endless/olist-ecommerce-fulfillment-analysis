USE olist_ecommerce;
-- 同一笔订单中的不同商品，是否可能有不同的交运截止时间？
-- 检查同一订单中是否存在多个交运截止时间
SELECT
    order_id,
    COUNT(*) AS item_count,
    COUNT(DISTINCT shipping_limit_date) AS deadline_count
FROM olist_order_items
GROUP BY order_id
HAVING deadline_count > 1
LIMIT 20;



-- 检查单卖家订单中有多少存在多个截止时间
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
        AVG(
            o.order_delivered_carrier_date > s.shipping_deadline
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
  AND o.order_delivered_carrier_date <= o.order_delivered_customer_date;
  
  
  
  -- 1. 每笔单卖家订单保留一个卖家和交运截止时间
WITH single_seller AS (
    SELECT
        order_id,
        MIN(seller_id) AS seller_id,
        MIN(shipping_limit_date) AS shipping_deadline
    FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
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


-- 先检查差评文本能不能用
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

-- 先查看准时订单的真实差评内容
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

  -- 只查看低分且有文字的评价
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

-- 2. 每笔订单保留一条有效评价
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

  -- 只研究准时或提前送达的订单
  AND DATE(o.order_delivered_customer_date)
      <= DATE(o.order_estimated_delivery_date)

GROUP BY item_group

ORDER BY item_group;






-- 只研究恰好有2件商品的订单，比较1个卖家与2个卖家的差评率。
-- 1. 统计每笔订单的商品数和卖家数
WITH item_count AS (
    SELECT
        order_id,
        COUNT(*) AS item_num,
        COUNT(DISTINCT seller_id) AS seller_num
    FROM olist_order_items
    GROUP BY order_id
),

-- 2. 每笔订单保留一条有效评价
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
	i.seller_num AS seller_count,

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

  -- 只研究准时或提前送达的订单
  AND DATE(o.order_delivered_customer_date)
      <= DATE(o.order_estimated_delivery_date)
  -- 只保留恰好有2条商品明细的订单。
  AND i.item_num = 2
  

GROUP BY  i.seller_num

ORDER BY  i.seller_num;

-- 应该回到客户评价内容，看看多卖家订单的差评主要在抱怨什么。
-- 直接查看恰好2件商品、2个卖家、准时送达且收到差评的订单评论。
WITH two_seller_orders AS (
	SELECT order_id
    FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(*)  = 2
		AND COUNT(DISTINCT seller_id) = 2
),

-- 2. 每笔订单保留一条有效评价
single_review AS (
	SELECT 
		order_id,
        MAX(review_score) AS review_score,
        MAX(review_comment_message) AS review_comment_message
	FROM olist_order_reviews
    GROUP BY order_id
    HAVING COUNT(*) = 1
		AND COUNT(review_score) = 1
)

-- 3. 随机查看20条准时订单的低分文字评价
SELECT
	o.order_id,
    r.review_score,
    r.review_comment_message
FROM olist_orders AS o
JOIN two_seller_orders AS i
	ON o.order_id = i.order_id
JOIN single_review AS r
	ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp

  AND DATE(o.order_delivered_customer_date)
      <= DATE(o.order_estimated_delivery_date)
      
  AND r.review_score <= 2
  AND r.review_comment_message IS NOT NULL
  AND TRIM(r.review_comment_message) <>''
-- 随机排列符合条件的记录
ORDER BY RAND()
LIMIT 20;


-- 1. 每笔订单的商品数、卖家数
WITH item_info AS (
	SELECT 
		order_id,
        COUNT(*) AS item_num,
        COUNT(DISTINCT seller_id) AS seller_num
	FROM olist_order_items
    GROUP BY order_id
),

-- 2. 每笔订单只保留一条有效评价
single_review AS (
	SELECT 
		order_id,
        MAX(review_score) AS review_score,
        MAX(review_answer_timestamp) AS review_time,
        MAX(review_comment_message) AS review_comment_message
	FROM olist_order_reviews
    GROUP BY order_id
    HAVING COUNT(*) = 1
		AND COUNT(review_score) = 1
)

-- 3. 比较低分评价发生在系统签收前还是签收后
SELECT 
	i.seller_num AS seller_count,
    COUNT(*) AS bad_orders,
    SUM(
		r.review_comment_message IS NOT NULL
		AND TRIM(r.review_comment_message) <> ''
	) AS with_comment,
    SUM(
		r.review_time < o.order_delivered_customer_date
	) AS review_before_delivery,
    
     SUM(
        r.review_time >= o.order_delivered_customer_date
     ) AS review_after_delivery,
     
     SUM(
		r.review_time IS NULL
	) AS missing_review_time
    
FROM olist_orders AS o
JOIN item_info AS i
	ON o.order_id = i.order_id
JOIN single_review AS r
	ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp

  AND DATE(o.order_delivered_customer_date)
      <= DATE(o.order_estimated_delivery_date)

  AND i.item_num = 2
  AND r.review_score <= 2
  
GROUP BY i.seller_num
ORDER BY i.seller_num;

-- 只补充单卖家组的评论样本
WITH two_item_orders AS (
	SELECT order_id
    FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(*)  = 2
		AND COUNT(DISTINCT seller_id) = 1
),

-- 2. 每笔订单保留一条有效评价
single_review AS (
	SELECT 
		order_id,
        MAX(review_score) AS review_score,
        MAX(review_comment_message) AS review_comment_message
	FROM olist_order_reviews
    GROUP BY order_id
    HAVING COUNT(*) = 1
		AND COUNT(review_score) = 1
)

-- 3. 随机查看20条准时订单的低分文字评价
SELECT
	o.order_id,
    r.review_score,
    r.review_comment_message
FROM olist_orders AS o
JOIN two_item_orders AS i
	ON o.order_id = i.order_id
JOIN single_review AS r
	ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp

  AND DATE(o.order_delivered_customer_date)
      <= DATE(o.order_estimated_delivery_date)
      
  AND r.review_score <= 2
  AND r.review_comment_message IS NOT NULL
  AND TRIM(r.review_comment_message) <>''
-- 随机排列符合条件的记录
ORDER BY RAND()
LIMIT 20;

-- ：问题订单涉及的交易金额与运费分析。
-- 第一步：将商品明细汇总到订单级
WITH order_amount AS (
	SELECT 
		order_id,
        COUNT(DISTINCT seller_id) AS seller_count,
        SUM(price) AS goods_amount,
        SUM(freight_value) AS freight_amount
	FROM olist_order_items
    GROUP BY order_id
)

-- 第二步：计算有效单卖家订单的交易金额
SELECT
	COUNT(*) AS order_count,
    ROUND(SUM(a.goods_amount), 2) AS total_goods_amount,
    ROUND(SUM(a.freight_amount), 2) AS total_freight_amount,
    ROUND(
		SUM(a.goods_amount + a.freight_amount), 2
	) AS total_amount,
    ROUND(
		AVG(a.goods_amount + a.freight_amount), 2
	) AS avg_order_amount
FROM olist_orders AS o
JOIN order_amount AS a
	ON o.order_id = a.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
  
  AND a.seller_count = 1
  
  
 -- 1. 商品明细汇总到订单级，只保留单卖家订单
 ;
WITH order_amount AS (
	SELECT
		order_id,
        SUM(price) AS goods_amount,
        SUM(freight_value) AS freight_amount
	FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
),

-- 2. 每笔订单只保留一条有效评价
single_review AS (
	SELECT
		order_id,
        MAX(review_score) AS review_score
	FROM olist_order_reviews
    GROUP BY order_id
    HAVING COUNT(*) = 1
		AND COUNT(review_score) = 1
),

-- 3. 判断每笔订单是否存在可观察问题
order_data AS (
	SELECT
		o.order_id,
        a.goods_amount,
        a.freight_amount,
        
		CASE
			WHEN DATE(o.order_delivered_customer_date)
					 > DATE(o.order_estimated_delivery_date)
				  OR r.review_score <= 2
			THEN 1
			ELSE 0
		END AS is_issue
	FROM olist_orders AS o
    JOIN order_amount AS a
		ON o.order_id = a.order_id
	LEFT JOIN single_review AS r
		ON o.order_id = r.order_id
	
 WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
)

-- 4. 汇总问题订单涉及的交易金额
SELECT
	COUNT(*) AS order_count,
    SUM(is_issue) AS issue_orders,
    ROUND(
		AVG(is_issue) * 100 , 2
	) AS issue_rate_pct,
    
    ROUND(
		SUM(CASE WHEN is_issue = 1
			THEN goods_amount ELSE 0 END), 2
	) AS issue_goods_amount,
    
    ROUND(
		SUM(CASE WHEN is_issue = 1
			THEN freight_amount ELSE 0 END), 2
	) AS issue_freight_amount,
    
   ROUND(
        SUM(CASE WHEN is_issue = 1
            THEN goods_amount + freight_amount ELSE 0 END), 2
    ) AS issue_total_amount
    
FROM order_data;




-- 1. 商品明细汇总到订单级，只保留单卖家订单
 WITH order_amount AS (
	SELECT
		order_id,
        MIN(seller_id) AS seller_id,
        SUM(price) AS goods_amount,
        SUM(freight_value) AS freight_amount
	FROM olist_order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
),

-- 2. 每笔订单只保留一条有效评价
single_review AS (
	SELECT
		order_id,
        MAX(review_score) AS review_score
	FROM olist_order_reviews
    GROUP BY order_id
    HAVING COUNT(*) = 1
		AND COUNT(review_score) = 1
),

-- 3. 判断每笔订单是否存在可观察问题
order_data AS (
	SELECT
		o.order_id,
        a.goods_amount,
        a.freight_amount,
        a.seller_id,
		CASE
			WHEN DATE(o.order_delivered_customer_date)
					 > DATE(o.order_estimated_delivery_date)
				  OR r.review_score <= 2
			THEN 1
			ELSE 0
		END AS is_issue
	FROM olist_orders AS o
    JOIN order_amount AS a
		ON o.order_id = a.order_id
	LEFT JOIN single_review AS r
		ON o.order_id = r.order_id
	
 WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
)

-- 4. 汇总问题订单涉及的交易金额
SELECT
	seller_id,
	COUNT(*) AS order_count,
    SUM(is_issue) AS issue_orders,
    ROUND(
		SUM(goods_amount + freight_amount), 2
	) AS total_amount,
    
    
   ROUND(
        SUM(CASE 
				WHEN is_issue = 1
				THEN goods_amount + freight_amount 
				ELSE 0 
			END), 2
    ) AS issue_amount
    
FROM order_data
GROUP BY seller_id
ORDER BY issue_amount DESC;