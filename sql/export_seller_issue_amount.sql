USE olist_ecommerce;
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
