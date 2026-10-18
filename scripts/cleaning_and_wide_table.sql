-- 1) 订单表去重 + 关键字段非空
DROP TABLE IF EXISTS orders_clean;
CREATE TABLE orders_clean AS
SELECT DISTINCT
    order_id, customer, pattern, quantity_sqm,
    order_date, promise_date, actual_date, delay_days, on_time_flag, is_improved
FROM orders
WHERE order_id IS NOT NULL
  AND quantity_sqm > 0
  AND promise_date >= order_date;

-- 2) 生产明细：去掉产量<=0、运行时长<=0、速度异常的记录
DROP TABLE IF EXISTS prod_clean;
CREATE TABLE prod_clean AS
SELECT *
FROM prod_record
WHERE roll_sqm > 0
  AND run_hours > 0
  AND avg_speed BETWEEN 5 AND 40
  AND avg_temp BETWEEN 160 AND 260;

-- 3) 质检明细：去掉检验面积<=0、缺陷面积>检验面积的异常
DROP TABLE IF EXISTS qual_clean;
CREATE TABLE qual_clean AS
SELECT *
FROM quality_inspect
WHERE inspect_sqm > 0
  AND defect_sqm >= 0
  AND defect_sqm <= inspect_sqm;
  
  DROP TABLE IF EXISTS wide_order_machine;
CREATE TABLE wide_order_machine AS
WITH prod_agg AS (
    SELECT order_id, machine_id, team,
           SUM(roll_sqm) AS output_sqm,
           SUM(run_hours) AS run_hours,
           AVG(avg_temp) AS avg_temp,
           AVG(avg_speed) AS avg_speed,
           AVG(avg_pressure) AS avg_pressure,
           AVG(rated_speed) AS rated_speed,
           AVG(rated_power) AS rated_power
    FROM prod_clean
    GROUP BY order_id, machine_id, team
),
qual_agg AS (
    SELECT order_id,
           SUM(inspect_sqm) AS inspect_sqm,
           SUM(defect_sqm) AS defect_sqm,
           SUM(CASE WHEN defect_type='色差' THEN defect_sqm ELSE 0 END) AS color_defect_sqm,
           SUM(CASE WHEN defect_type='套印不准' THEN defect_sqm ELSE 0 END) AS register_defect_sqm,
           SUM(rework_flag) AS rework_cnt,
           COUNT(*) AS inspect_cnt
    FROM qual_clean
    GROUP BY order_id
)
SELECT
    p.order_id, p.machine_id, p.team,
    p.output_sqm, p.run_hours,
    p.avg_temp, p.avg_speed, p.avg_pressure, p.rated_speed, p.rated_power,
    q.inspect_sqm, q.defect_sqm, q.color_defect_sqm, q.register_defect_sqm,
    q.rework_cnt, q.inspect_cnt,
    ROUND(q.defect_sqm * 1.0 / NULLIF(q.inspect_sqm,0), 4) AS defect_rate,
    ROUND(q.rework_cnt * 1.0 / NULLIF(q.inspect_cnt,0), 4) AS rework_rate,
    -- 机台效率 = 实际速度 / 额定速度
    ROUND((p.output_sqm / NULLIF(p.run_hours,0)) / NULLIF(p.rated_speed,0), 4) AS machine_efficiency,
    -- 单位成本 = (材料 + 人工 + 能耗 + 返工) / 产出面积
    ROUND((
        15.0 * p.output_sqm
        + 80.0 * p.run_hours
        + 0.8 * p.rated_power * p.run_hours
        + 8.0 * q.defect_sqm
    ) / NULLIF(p.output_sqm,0), 2) AS unit_cost,
    o.customer, o.pattern, o.quantity_sqm,
    o.order_date, o.promise_date, o.actual_date, o.delay_days, o.on_time_flag,
    o.is_improved
FROM prod_agg p
LEFT JOIN qual_agg q ON p.order_id = q.order_id
LEFT JOIN orders_clean o ON p.order_id = o.order_id;

SELECT
    CASE WHEN is_improved THEN '改善后' ELSE '改善前' END AS period,
    COUNT(*) AS records,
    ROUND(AVG(defect_rate), 4) AS avg_defect_rate,
    ROUND(AVG(rework_rate), 4) AS avg_rework_rate,
    ROUND(AVG(on_time_flag), 4) AS on_time_rate,
    ROUND(AVG(CASE WHEN delay_days > 0 THEN delay_days END), 2) AS avg_delay_days,
    ROUND(AVG(machine_efficiency), 4) AS avg_machine_efficiency,
    ROUND(AVG(unit_cost), 2) AS avg_unit_cost
FROM wide_order_machine
GROUP BY is_improved;

-- 缺陷类型帕累托
SELECT defect_type,
       SUM(defect_sqm) AS defect_sqm,
       ROUND(SUM(defect_sqm) * 1.0 / SUM(SUM(defect_sqm)) OVER (), 4) AS share
FROM qual_clean
GROUP BY defect_type
ORDER BY defect_sqm DESC;

-- 机台维度
SELECT machine_id,
       COUNT(*) AS records,
       ROUND(AVG(defect_rate), 4) AS defect_rate,
       ROUND(AVG(rework_rate), 4) AS rework_rate,
       ROUND(AVG(avg_temp), 1) AS avg_temp,
       ROUND(AVG(avg_speed), 1) AS avg_speed,
       ROUND(AVG(machine_efficiency), 4) AS machine_efficiency,
       ROUND(AVG(unit_cost), 2) AS unit_cost
FROM wide_order_machine
GROUP BY machine_id
ORDER BY defect_rate DESC;

-- 班组、花型、客户同理，把 GROUP BY 换掉即可