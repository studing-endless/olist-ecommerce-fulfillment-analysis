-- 仅在全新专用数据库执行一次；已有同名数据库时 CREATE DATABASE 会报错，请立即停止。
-- 将 data/raw/ 替换为下载目录（正斜杠）；原始 CSV 不入库版本控制。
-- 支持 MySQL 8+，客户端遇错必须停止，不要使用 --force。
-- 创建 Olist 项目数据库
CREATE DATABASE olist_ecommerce
DEFAULT CHARACTER SET utf8mb4
DEFAULT COLLATE utf8mb4_unicode_ci;

USE olist_ecommerce;

SELECT DATABASE() AS current_database;



CREATE TABLE olist_orders (
    order_id VARCHAR(32),
    customer_id VARCHAR(32),
    order_status VARCHAR(32),
    order_purchase_timestamp DATETIME,
    order_approved_at DATETIME,
    order_delivered_carrier_date DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME
);



-- 管理员需提前启用 local_infile；客户端连接也需显式允许 LOCAL。

-- 清空表的内容



LOAD DATA LOCAL INFILE
'data/raw/olist_orders_dataset.csv'
INTO TABLE olist_orders
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    order_id,
    customer_id,
    order_status,
    @purchase,
    @approved,
    @carrier,
    @delivered,
    @estimated
)
SET
    order_purchase_timestamp = NULLIF(@purchase, ''),
    order_approved_at = NULLIF(@approved, ''),
    order_delivered_carrier_date = NULLIF(@carrier, ''),
    order_delivered_customer_date = NULLIF(@delivered, ''),
    order_estimated_delivery_date =
        NULLIF(TRIM(TRAILING '\r' FROM @estimated), '');
        
-- 验证订单表
SELECT
	COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_orders,
    SUM(order_id IS NULL) AS null_order_ids,
    SUM(order_purchase_timestamp IS NULL) AS null_purchase_dates,
    MIN(order_purchase_timestamp) AS earliest_order,
    MAX(order_purchase_timestamp) AS latest_order
FROM olist_orders;




-- ========================================
-- 一、建表（原始层）
-- ========================================

CREATE TABLE IF NOT EXISTS `olist_customers` (
    `customer_id` VARCHAR(32),
    `customer_unique_id` VARCHAR(32),
    `customer_zip_code_prefix` VARCHAR(5),
    `customer_city` VARCHAR(255),
    `customer_state` VARCHAR(10)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `olist_order_items` (
    `order_id` VARCHAR(32),
    `order_item_id` INT,
    `product_id` VARCHAR(32),
    `seller_id` VARCHAR(32),
    `shipping_limit_date` DATETIME,
    `price` DECIMAL(12,2),
    `freight_value` DECIMAL(12,2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `olist_order_payments` (
    `order_id` VARCHAR(32),
    `payment_sequential` INT,
    `payment_type` VARCHAR(50),
    `payment_installments` INT,
    `payment_value` DECIMAL(12,2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `olist_order_reviews` (
    `review_id` VARCHAR(32),
    `order_id` VARCHAR(32),
    `review_score` TINYINT,
    `review_comment_title` VARCHAR(255),
    `review_comment_message` TEXT,
    `review_creation_date` DATETIME,
    `review_answer_timestamp` DATETIME
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `olist_products` (
    `product_id` VARCHAR(32),
    `product_category_name` VARCHAR(255),
    `product_name_lenght` INT,
    `product_description_lenght` INT,
    `product_photos_qty` INT,
    `product_weight_g` DECIMAL(12,2),
    `product_length_cm` DECIMAL(12,2),
    `product_height_cm` DECIMAL(12,2),
    `product_width_cm` DECIMAL(12,2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `olist_sellers` (
    `seller_id` VARCHAR(32),
    `seller_zip_code_prefix` VARCHAR(5),
    `seller_city` VARCHAR(255),
    `seller_state` VARCHAR(10)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `product_category_name_translation` (
    `product_category_name` VARCHAR(255),
    `product_category_name_english` VARCHAR(255)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `olist_geolocation` (
    `geolocation_zip_code_prefix` VARCHAR(5),
    `geolocation_lat` DOUBLE,
    `geolocation_lng` DOUBLE,
    `geolocation_city` VARCHAR(255),
    `geolocation_state` VARCHAR(10)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ========================================
-- 二、导入（逐表重置后写入；不是追加）
-- 执行中 geolocation ~100万行，耗时可能明显长于其他表。
-- ========================================

-- [1/8] olist_customers ← olist_customers_dataset.csv
LOAD DATA LOCAL INFILE 'data/raw/olist_customers_dataset.csv'
INTO TABLE `olist_customers`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    @last
)
SET
    customer_state = TRIM(TRAILING '\r' FROM @last);
SHOW COUNT(*) WARNINGS;

-- [2/8] olist_order_items ← olist_order_items_dataset.csv
LOAD DATA LOCAL INFILE 'data/raw/olist_order_items_dataset.csv'
INTO TABLE `olist_order_items`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    order_id,
    order_item_id,
    product_id,
    seller_id,
    @shipping_limit,
    @price,
    @last
)
SET
    shipping_limit_date = NULLIF(@shipping_limit, ''),
    price = NULLIF(@price, ''),
    freight_value = NULLIF(TRIM(TRAILING '\r' FROM @last), '');
SHOW COUNT(*) WARNINGS;

-- [3/8] olist_order_payments ← olist_order_payments_dataset.csv
LOAD DATA LOCAL INFILE 'data/raw/olist_order_payments_dataset.csv'
INTO TABLE `olist_order_payments`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    @last
)
SET
    payment_value = NULLIF(TRIM(TRAILING '\r' FROM @last), '');
SHOW COUNT(*) WARNINGS;

-- [4/8] olist_order_reviews ← olist_order_reviews_dataset.csv


LOAD DATA LOCAL INFILE
'data/raw/olist_order_reviews_dataset.csv'
INTO TABLE olist_order_reviews
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    review_id,
    order_id,
    review_score,
    @title,
    @message,
    @created,
    @answered
)
SET
    review_comment_title = NULLIF(@title, ''),
    review_comment_message = NULLIF(@message, ''),
    review_creation_date = NULLIF(@created, ''),
    review_answer_timestamp =
        NULLIF(TRIM(TRAILING '\r' FROM @answered), '');

SHOW COUNT(*) WARNINGS;

-- [5/8] olist_products ← olist_products_dataset.csv

LOAD DATA LOCAL INFILE 'data/raw/olist_products_dataset.csv'
INTO TABLE `olist_products`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    product_id,
    @category,
    @name_len,
    @description_len,
    @photos,
    @weight,
    @length,
    @height,
    @last
)
SET
    product_category_name = NULLIF(@category, ''),
    product_name_lenght = NULLIF(@name_len, ''),
    product_description_lenght = NULLIF(@description_len, ''),
    product_photos_qty = NULLIF(@photos, ''),
    product_weight_g = NULLIF(@weight, ''),
    product_length_cm = NULLIF(@length, ''),
    product_height_cm = NULLIF(@height, ''),
    product_width_cm = NULLIF(TRIM(TRAILING '\r' FROM @last), '');
SHOW COUNT(*) WARNINGS;

-- [6/8] olist_sellers ← olist_sellers_dataset.csv

LOAD DATA LOCAL INFILE 'data/raw/olist_sellers_dataset.csv'
INTO TABLE `olist_sellers`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    @last
)
SET
    seller_state = TRIM(TRAILING '\r' FROM @last);
SHOW COUNT(*) WARNINGS;

-- [7/8] product_category_name_translation ← product_category_name_translation.csv

LOAD DATA LOCAL INFILE 'data/raw/product_category_name_translation.csv'
INTO TABLE `product_category_name_translation`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    product_category_name,
    @last
)
SET
    product_category_name_english = TRIM(TRAILING '\r' FROM @last);
SHOW COUNT(*) WARNINGS;

-- [8/8] olist_geolocation ← olist_geolocation_dataset.csv

LOAD DATA LOCAL INFILE 'data/raw/olist_geolocation_dataset.csv'
INTO TABLE `olist_geolocation`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    geolocation_city,
    @last
)
SET
    geolocation_state = TRIM(TRAILING '\r' FROM @last);
SHOW COUNT(*) WARNINGS;

-- ========================================
-- 三、所有文件执行成功后：记录数对照
-- 只验证行数；不是完整数据质量审计。
-- ========================================
SELECT 'olist_orders' AS table_name, COUNT(*) AS actual_rows, 99441 AS reference_rows FROM olist_orders
UNION ALL SELECT 'olist_customers', COUNT(*), 99441 FROM `olist_customers`
UNION ALL SELECT 'olist_order_items', COUNT(*), 112650 FROM `olist_order_items`
UNION ALL SELECT 'olist_order_payments', COUNT(*), 103886 FROM `olist_order_payments`
UNION ALL SELECT 'olist_order_reviews', COUNT(*), 99224 FROM `olist_order_reviews`
UNION ALL SELECT 'olist_products', COUNT(*), 32951 FROM `olist_products`
UNION ALL SELECT 'olist_sellers', COUNT(*), 3095 FROM `olist_sellers`
UNION ALL SELECT 'product_category_name_translation', COUNT(*), 71 FROM `product_category_name_translation`
UNION ALL SELECT 'olist_geolocation', COUNT(*), 1000163 FROM `olist_geolocation`;

-- 两张容易踩坑的表：检查业务键，不直接创建主键。
SELECT COUNT(*) AS item_rows, COUNT(DISTINCT order_id, order_item_id) AS unique_order_items FROM olist_order_items;
SELECT COUNT(*) AS review_rows, COUNT(DISTINCT review_id) AS unique_review_ids, COUNT(DISTINCT order_id) AS reviewed_orders FROM olist_order_reviews;

-- 若 WARNINGS 非零，不要忽略；单独重跑那张表并立即查看 SHOW WARNINGS LIMIT 20。
-- 注意：本脚本只负责原始层，后续需要另做键唯一性、缺失、日期逻辑、关联完整性验证。

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT review_id, order_id) AS unique_pairs
FROM olist_order_reviews;


