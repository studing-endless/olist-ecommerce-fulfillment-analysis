USE olist_ecommerce;

-- ==============================================
-- 3.1 订单评价覆盖情况
-- 目的：确定订单级差评分析的数据处理规则
-- ==============================================
WITH review_summary AS (
	-- 第一步：将评价表汇总到每订单一行
	SELECT
		order_id,
        COUNT(*) AS review_count,
        MIN(review_score) AS min_score,
        MAX(review_score) AS max_score
	FROM olist_order_reviews
    GROUP BY order_id
)
-- 第二步：检查有效配送订单的评价情况
SELECT
	COUNT(*) AS total_orders,
    -- 没有评价的订单
	SUM(
		CASE WHEN r.order_id IS NULL
			THEN 1 ELSE 0 END
	) AS no_review_orders,
    
    -- 只有一条评价的订单
	SUM(
		CASE WHEN r.review_count = 1
			THEN 1 ELSE 0 END
	) AS single_review_orders,
    
    -- 有多条评价的订单
	SUM(
		CASE WHEN r.review_count > 1
			THEN 1 ELSE 0 END
	) AS multi_review_orders,
    
    -- 同一订单存在不同评分的订单数
	SUM(
		CASE WHEN r.min_score <> r.max_score
			THEN 1 ELSE 0 END
	) AS conflicting_score_orders
FROM olist_orders AS o
LEFT JOIN review_summary AS r
	ON o.order_id = r.order_id
-- 与前面配送分析保持相同样本口径
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date
      >= o.order_purchase_timestamp;
      
      
-- ============================================
-- 3.3 配送延迟与客户差评率对比
-- 主分析：仅使用有一条有效评价的订单
-- ============================================
-- MAX() 在这里是为了配合 GROUP BY 取得组内唯一的评分，并不是我们决定采用“最高分”作为订单评分。
WITH single_review AS (
	SELECT
		order_id,
        MAX(review_score) AS review_score
	FROM olist_order_reviews
    GROUP BY order_id
    -- 它只保留恰好有一条评价记录的订单。
    HAVING COUNT(*) = 1
		AND COUNT(review_score) = 1
)
SELECT
	 -- 按订单是否延迟分组
     CASE 
		WHEN DATE(o.order_delivered_customer_date)
             > DATE(o.order_estimated_delivery_date)
		THEN 'late'
        ELSE 'on_time'
	END AS delivery_status,
    
    -- 有效评价订单数
    COUNT(*) AS reviewed_orders,
    
    -- 差评订单数（1-2分)
    SUM(
		CASE
			WHEN r.review_score <= 2 THEN 1
            ELSE 0
		END
     ) AS bad_review_orders,
     
     -- 差评率
	ROUND(
		100.0 * AVG(
			CASE
				WHEN r.review_score <= 2 THEN 1 
                ELSE 0
			END
		),
        2
	) AS bad_review_rate_pct
FROM olist_orders AS o
JOIN single_review AS r
	ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date
      >= o.order_purchase_timestamp
-- 先按照指定条件把订单分成不同的组，再分别计算每组的数量、均值和比例。      
GROUP BY delivery_status
ORDER BY delivery_status


-- ============================================
-- 3.4 不同超期程度的客户差评率
-- 业务问题：超期越严重，差评率是否越高？
-- ============================================
;
WITH single_review AS (
	-- 每订单只保留一条有效评价
    SELECT 
		order_id,
        MAX(review_score) AS review_score
	FROM olist_order_reviews
    GROUP BY order_id
    -- 只有一条记录，而且评分不为空
    HAVING COUNT(*) = 1
		AND COUNT(review_score) = 1
),

review_data AS (
	SELECT
		o.order_id,
        r.review_score,
        
        -- 实际收货日期相对承诺日期的差值
        DATEDIFF(
            o.order_delivered_customer_date,
            o.order_estimated_delivery_date
        ) AS delay_days
	FROM olist_orders AS o
    JOIN single_review AS r
		ON o.order_id = r.order_id
	WHERE o.order_status = 'delivered'
		AND o.order_purchase_timestamp IS NOT NULL
		AND o.order_delivered_customer_date IS NOT NULL
		AND o.order_estimated_delivery_date IS NOT NULL
		AND o.order_delivered_customer_date
          >= o.order_purchase_timestamp
),


grouped_data AS (
	-- 按实际超期程度分类
    SELECT 
		review_score,
        CASE 
			WHEN delay_days <= 0 THEN '01_准时或提前'
            WHEN delay_days <= 3 THEN '02_延迟1-3天'
            WHEN delay_days <= 7 THEN '03_延迟4-7天'
            ELSE '04_延迟8天及以上'
		END AS delay_group
	FROM review_data
)

SELECT
	delay_group,
    
    -- 当前组的有效评价订单数
    COUNT(*) AS reviewed_orders,
    
    -- 当前组差评订单数
    SUM(
		CASE
			WHEN review_score <= 2 THEN 1
            ELSE 0 
		END
	) AS bad_review_orders,
    
    -- 当前组差评率
    
	ROUND(
        100.0 * AVG(
            CASE
                WHEN review_score <= 2 THEN 1
                ELSE 0
            END
        ),
        2
    ) AS bad_review_rate_pct
FROM grouped_data
GROUP BY delay_group
ORDER BY delay_group;


-- ==================================================
-- 3.5 多评价订单处理规则的敏感性分析
-- 目的：检查差评率结论是否依赖订单评分处理方式
-- ==================================================
WITH review_summary AS (
	-- 每笔订单汇总为一行
    SELECT 
		order_id,
		COUNT(*) AS review_count,
		COUNT(review_score) AS valid_score_count,
		MIN(review_score) AS min_score,
		MAX(review_score) AS max_Score
	FROM olist_order_reviews
    GROUP BY order_id
),

review_data AS (
	SELECT
		o.order_id,
		CASE
            WHEN DATE(o.order_delivered_customer_date)
                 > DATE(o.order_estimated_delivery_date)
            THEN 'late'
            ELSE 'on_time'
        END AS delivery_status, 
        r.review_count,
        r.min_score,
        r.max_score
	FROM olist_orders AS o
    JOIN review_summary AS r
		ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
      AND o.order_delivered_customer_date >= o.order_purchase_timestamp
      
      -- 要求本次使用的评分记录均有效
      AND r.valid_score_count = r.review_count
)

SELECT
	delivery_status,
    COUNT(*) AS reviewed_orders,
    SUM(review_count > 1) AS muti_review_orders,
    
    -- 任意一条评分为1-2分，即视为差评
    ROUND(
		100.0 * AVG(min_score <= 2),
        2
	) AS any_bad_rate_pct,
    
    -- 所有评分均为1-2分，才视为差评
    ROUND(
		100.0 * AVG(max_score <= 2),
        2
	) AS all_bad_rate_pct
FROM review_data
GROUP BY delivery_status
ORDER BY delivery_status;

-- 3.6 建立订单级履约与评价分析视图
-- 每行对应一笔有单条有效评价的已交付订单
-- VIEW 叫作视图。 理解成一张保存了查询逻辑的虚拟表：


CREATE OR REPLACE VIEW v_order_review_analysis AS 
SELECT
	o.order_id,
    c.customer_unique_id,
    c.customer_state,
    DATE_FORMAT(
		o.order_purchase_timestamp,'%Y-%m'
	) AS order_month,
    
    -- 实际配送时长
    TIMESTAMPDIFF(
		SECOND,
		o.order_purchase_timestamp,
        o.order_delivered_customer_date
    ) / 86400.0 AS delivery_days,
	-- 相对承诺日期的差值
    DATEDIFF(
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    ) AS delay_days,
    
    -- 是否延迟
    CASE 
		WHEN DATE(o.order_delivered_customer_date)
			> DATE(o.order_estimated_delivery_date)
		THEN 1 ELSE 0
	END AS is_late,
    
    r.review_score,
    
    -- 是否差评
    CASE
		WHEN r.review_score <= 2
        THEN 1 ELSE 0
	END AS is_bad_review
    
FROM olist_orders AS o
JOIN olist_customers AS c
	ON o.customer_id = c.customer_id
JOIN(
	SELECT
		order_id,
        MAX(review_score) AS review_score
	FROM olist_order_reviews
    GROUP BY order_id
    HAVING COUNT(*) = 1
		AND COUNT(review_score) = 1
) AS r
	ON o.order_id = r.order_id
    
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date
      >= o.order_purchase_timestamp;


SELECT
	-- 订单记录数
	COUNT(*) AS total_orders,
    
    -- 不同订单ID数量
    COUNT(DISTINCT order_id) AS unique_orders,
    SUM(is_late) AS late_orders,
    SUM(is_bad_review) AS bad_review_orders,
    -- 评分缺失数
	SUM(review_score IS NULL) AS missing_scores
    
FROM v_order_review_analysis;



