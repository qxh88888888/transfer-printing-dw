-- ============================================================================
-- 02_dwd_transform.sql  ——  DWD 明细层
-- 作用：清洗 + 类型转换（等价于原来 SQLite 里的 cleaning_and_wide_table.sql 前半段）
-- 清洗规则：
--   订单：去重、剔除数量<=0、承诺交期早于下单日的异常
--   生产：剔除面积/时长<=0、速度或温度明显异常的记录
--   质检：剔除检验面积<=0、缺陷面积>检验面积的异常
-- ============================================================================

USE transfer_printing_dw;

-- ---------------------------------------------------------------------------
-- 1. 订单明细（清洗后）
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS dwd_orders_clean;
CREATE TABLE dwd_orders_clean
STORED AS ORC
AS
SELECT DISTINCT
    order_id,
    customer,
    pattern,
    CAST(quantity_sqm AS INT)                                   AS quantity_sqm,
    CAST(order_date   AS DATE)                                  AS order_date,
    CASE WHEN LOWER(TRIM(is_improved))='true' THEN TRUE ELSE FALSE END AS is_improved,
    CAST(promise_days AS INT)                                   AS promise_days,
    CAST(promise_date AS DATE)                                  AS promise_date,
    CAST(actual_date  AS DATE)                                  AS actual_date,
    CAST(delay_days   AS INT)                                   AS delay_days,
    CAST(on_time_flag AS INT)                                   AS on_time_flag
FROM ods_orders
WHERE order_id IS NOT NULL
  AND TRIM(order_id) <> ''
  AND CAST(quantity_sqm AS INT) > 0
  AND CAST(promise_date AS DATE) >= CAST(order_date AS DATE);

-- ---------------------------------------------------------------------------
-- 2. 生产明细（清洗后）
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS dwd_prod_clean;
CREATE TABLE dwd_prod_clean
STORED AS ORC
AS
SELECT
    order_id,
    roll_id,
    machine_id,
    team,
    CAST(roll_sqm     AS DOUBLE) AS roll_sqm,
    CAST(run_hours    AS DOUBLE) AS run_hours,
    CAST(rated_speed  AS INT)    AS rated_speed,
    CAST(rated_power  AS INT)    AS rated_power,
    CAST(avg_temp     AS DOUBLE) AS avg_temp,
    CAST(avg_speed    AS DOUBLE) AS avg_speed,
    CAST(avg_pressure AS DOUBLE) AS avg_pressure,
    CASE WHEN LOWER(TRIM(is_improved))='true' THEN TRUE ELSE FALSE END AS is_improved
FROM ods_prod_record
WHERE CAST(roll_sqm  AS DOUBLE) > 0
  AND CAST(run_hours AS DOUBLE) > 0
  AND CAST(avg_speed AS DOUBLE) BETWEEN 5 AND 40
  AND CAST(avg_temp  AS DOUBLE) BETWEEN 160 AND 260;

-- ---------------------------------------------------------------------------
-- 3. 质检明细（清洗后）
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS dwd_qual_clean;
CREATE TABLE dwd_qual_clean
STORED AS ORC
AS
SELECT
    order_id,
    roll_id,
    machine_id,
    CAST(inspect_sqm AS DOUBLE) AS inspect_sqm,
    CAST(defect_sqm  AS DOUBLE) AS defect_sqm,
    defect_type,
    CAST(rework_flag AS INT)    AS rework_flag,
    CASE WHEN LOWER(TRIM(is_improved))='true' THEN TRUE ELSE FALSE END AS is_improved
FROM ods_quality_inspect
WHERE CAST(inspect_sqm AS DOUBLE) > 0
  AND CAST(defect_sqm  AS DOUBLE) >= 0
  AND CAST(defect_sqm  AS DOUBLE) <= CAST(inspect_sqm AS DOUBLE);

-- ---------------------------------------------------------------------------
-- 4. 维度表
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_machine;
CREATE TABLE dim_machine
STORED AS ORC
AS
SELECT
    machine_id,
    CAST(rated_speed AS INT) AS rated_speed,
    CAST(rated_power AS INT) AS rated_power
FROM ods_dim_machine;

DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer
STORED AS ORC
AS
SELECT DISTINCT customer FROM ods_dim_customer;

DROP TABLE IF EXISTS dim_pattern;
CREATE TABLE dim_pattern
STORED AS ORC
AS
SELECT DISTINCT pattern FROM ods_dim_pattern;
