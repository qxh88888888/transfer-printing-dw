-- ============================================================================
-- 03_ads_transform.sql  ——  DWS/ADS 汇总层
-- 作用：产出分析宽表与指标汇总表（等价于原 SQLite 的宽表 + 各项指标查询）
-- 说明：指标口径与原项目完全一致，可直接与 Power BI / Python 结果对照
-- ============================================================================

USE transfer_printing_dw;

-- ---------------------------------------------------------------------------
-- 1. 订单-机台-班组 分析宽表（核心表）
--    指标：次品率 / 返工率 / 机台效率 / 单位成本
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ads_wide_order_machine;
CREATE TABLE ads_wide_order_machine
STORED AS ORC
AS
SELECT
    p.order_id,
    p.machine_id,
    p.team,
    p.output_sqm,
    p.run_hours,
    p.avg_temp,
    p.avg_speed,
    p.avg_pressure,
    p.rated_speed,
    p.rated_power,
    q.inspect_sqm,
    q.defect_sqm,
    q.color_defect_sqm,
    q.register_defect_sqm,
    q.rework_cnt,
    q.inspect_cnt,
    -- 次品率 = 缺陷面积 / 检验面积
    ROUND(q.defect_sqm / q.inspect_sqm, 4)                                                 AS defect_rate,
    -- 返工率 = 返工次数 / 检验次数
    ROUND(q.rework_cnt / q.inspect_cnt, 4)                                                 AS rework_rate,
    -- 机台效率 = 实际速度 / 额定速度
    ROUND((p.output_sqm / p.run_hours) / p.rated_speed, 4)                                 AS machine_efficiency,
    -- 单位成本 = (材料 + 人工 + 能耗 + 返工) / 产出面积
    ROUND((15.0 * p.output_sqm
         + 80.0 * p.run_hours
         + 0.8  * p.rated_power * p.run_hours
         + 8.0  * q.defect_sqm) / p.output_sqm, 2)                                         AS unit_cost,
    o.customer,
    o.pattern,
    o.quantity_sqm,
    o.order_date,
    o.promise_date,
    o.actual_date,
    o.delay_days,
    o.on_time_flag,
    o.is_improved
FROM (
    SELECT order_id, machine_id, team,
           SUM(roll_sqm)      AS output_sqm,
           SUM(run_hours)     AS run_hours,
           AVG(avg_temp)      AS avg_temp,
           AVG(avg_speed)     AS avg_speed,
           AVG(avg_pressure)  AS avg_pressure,
           AVG(rated_speed)   AS rated_speed,
           AVG(rated_power)   AS rated_power
    FROM dwd_prod_clean
    GROUP BY order_id, machine_id, team
) p
LEFT JOIN (
    SELECT order_id,
           SUM(inspect_sqm)                                              AS inspect_sqm,
           SUM(defect_sqm)                                               AS defect_sqm,
           SUM(CASE WHEN defect_type='色差'     THEN defect_sqm ELSE 0 END) AS color_defect_sqm,
           SUM(CASE WHEN defect_type='套印不准' THEN defect_sqm ELSE 0 END) AS register_defect_sqm,
           SUM(rework_flag)                                              AS rework_cnt,
           COUNT(*)                                                      AS inspect_cnt
    FROM dwd_qual_clean
    GROUP BY order_id
) q ON p.order_id = q.order_id
LEFT JOIN dwd_orders_clean o ON p.order_id = o.order_id;

-- ---------------------------------------------------------------------------
-- 2. 缺陷类型帕累托
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ads_defect_pareto;
CREATE TABLE ads_defect_pareto
STORED AS ORC
AS
SELECT
    defect_type,
    ROUND(SUM(defect_sqm), 2)                              AS defect_sqm,
    ROUND(SUM(defect_sqm) / SUM(SUM(defect_sqm)) OVER (), 4) AS share
FROM dwd_qual_clean
GROUP BY defect_type;

-- ---------------------------------------------------------------------------
-- 3. 机台维度汇总
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ads_machine_summary;
CREATE TABLE ads_machine_summary
STORED AS ORC
AS
SELECT
    machine_id,
    COUNT(*)                        AS records,
    ROUND(AVG(defect_rate), 4)      AS defect_rate,
    ROUND(AVG(rework_rate), 4)      AS rework_rate,
    ROUND(AVG(avg_temp), 1)         AS avg_temp,
    ROUND(AVG(avg_speed), 1)        AS avg_speed,
    ROUND(AVG(machine_efficiency),4) AS machine_efficiency,
    ROUND(AVG(unit_cost), 2)        AS unit_cost
FROM ads_wide_order_machine
GROUP BY machine_id;

-- ---------------------------------------------------------------------------
-- 4. 改善前后对比（工艺改善效果评估）
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ads_improve_compare;
CREATE TABLE ads_improve_compare
STORED AS ORC
AS
SELECT
    CASE WHEN is_improved THEN '改善后' ELSE '改善前' END AS period,
    COUNT(*)                                             AS records,
    ROUND(AVG(defect_rate), 4)                           AS avg_defect_rate,
    ROUND(AVG(rework_rate), 4)                           AS avg_rework_rate,
    ROUND(AVG(on_time_flag), 4)                          AS on_time_rate,
    ROUND(AVG(CASE WHEN delay_days > 0 THEN delay_days END), 2) AS avg_delay_days,
    ROUND(AVG(machine_efficiency), 4)                    AS avg_machine_efficiency,
    ROUND(AVG(unit_cost), 2)                             AS avg_unit_cost
FROM ads_wide_order_machine
GROUP BY is_improved;

-- ---------------------------------------------------------------------------
-- 5. 月度趋势（次品率 / 交期达成率）
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ads_monthly_trend;
CREATE TABLE ads_monthly_trend
STORED AS ORC
AS
SELECT
    SUBSTR(CAST(order_date AS STRING), 1, 7) AS month,
    COUNT(*)                                 AS records,
    ROUND(AVG(defect_rate), 4)               AS defect_rate,
    ROUND(AVG(on_time_flag), 4)              AS on_time_rate
FROM ads_wide_order_machine
GROUP BY SUBSTR(CAST(order_date AS STRING), 1, 7);
