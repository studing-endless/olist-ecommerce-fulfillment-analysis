USE olist_ecommerce;
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
