-- ============================================================================
-- 01_ods_ddl.sql  ——  ODS 贴源层（外部表）
-- 作用：把 HDFS 上的原始 CSV 直接映射成 Hive 表，不做任何加工
-- 特点：全部字段用 STRING 存储，保留原始形态，出问题可回溯到源头
-- 依赖：HDFS 路径 /transfer_printing_dw/ods/<表名>/<表名>.csv（已上传）
-- ============================================================================

CREATE DATABASE IF NOT EXISTS transfer_printing_dw
COMMENT '转移印花生产分析数据仓库'
LOCATION '/transfer_printing_dw/warehouse';

USE transfer_printing_dw;

-- ---------------------------------------------------------------------------
-- 1. 订单表
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ods_orders;
CREATE EXTERNAL TABLE ods_orders (
    order_id     STRING COMMENT '订单号',
    customer     STRING COMMENT '客户',
    pattern      STRING COMMENT '花型',
    quantity_sqm STRING COMMENT '下单面积(㎡)',
    order_date   STRING COMMENT '下单日期',
    is_improved  STRING COMMENT '是否改善后(True/False)',
    promise_days STRING COMMENT '承诺交期天数',
    promise_date STRING COMMENT '承诺交付日',
    actual_date  STRING COMMENT '实际交付日',
    delay_days   STRING COMMENT '延误天数(负数=提前)',
    on_time_flag STRING COMMENT '准时标志(1/0)'
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/transfer_printing_dw/ods/orders'
TBLPROPERTIES ('skip.header.line.count'='1');

-- ---------------------------------------------------------------------------
-- 2. 生产明细表（按卷）
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ods_prod_record;
CREATE EXTERNAL TABLE ods_prod_record (
    order_id     STRING COMMENT '订单号',
    roll_id      STRING COMMENT '卷号',
    machine_id   STRING COMMENT '机台号',
    team         STRING COMMENT '班组',
    roll_sqm     STRING COMMENT '本卷生产面积(㎡)',
    run_hours    STRING COMMENT '运行时长(小时)',
    rated_speed  STRING COMMENT '额定速度(m/min)',
    rated_power  STRING COMMENT '额定功率(kW)',
    avg_temp     STRING COMMENT '平均温度(℃)',
    avg_speed    STRING COMMENT '平均速度(m/min)',
    avg_pressure STRING COMMENT '平均压力(MPa)',
    is_improved  STRING COMMENT '是否改善后'
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/transfer_printing_dw/ods/prod_record'
TBLPROPERTIES ('skip.header.line.count'='1');

-- ---------------------------------------------------------------------------
-- 3. 质检明细表
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ods_quality_inspect;
CREATE EXTERNAL TABLE ods_quality_inspect (
    order_id     STRING COMMENT '订单号',
    roll_id      STRING COMMENT '卷号',
    machine_id   STRING COMMENT '机台号',
    inspect_sqm  STRING COMMENT '检验面积(㎡)',
    defect_sqm   STRING COMMENT '缺陷面积(㎡)',
    defect_type  STRING COMMENT '缺陷类型',
    rework_flag  STRING COMMENT '返工标志(1/0)',
    is_improved  STRING COMMENT '是否改善后'
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/transfer_printing_dw/ods/quality_inspect'
TBLPROPERTIES ('skip.header.line.count'='1');

-- ---------------------------------------------------------------------------
-- 4. 排产计划表
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ods_production_plan;
CREATE EXTERNAL TABLE ods_production_plan (
    order_id      STRING COMMENT '订单号',
    machine_id    STRING COMMENT '机台号',
    planned_start STRING COMMENT '计划开工日',
    planned_end   STRING COMMENT '计划完工日'
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/transfer_printing_dw/ods/production_plan'
TBLPROPERTIES ('skip.header.line.count'='1');

-- ---------------------------------------------------------------------------
-- 5. 维度表：机台 / 客户 / 花型
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ods_dim_machine;
CREATE EXTERNAL TABLE ods_dim_machine (
    machine_id  STRING,
    rated_speed STRING,
    rated_power STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/transfer_printing_dw/ods/dim_machine'
TBLPROPERTIES ('skip.header.line.count'='1');

DROP TABLE IF EXISTS ods_dim_customer;
CREATE EXTERNAL TABLE ods_dim_customer (
    customer STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/transfer_printing_dw/ods/dim_customer'
TBLPROPERTIES ('skip.header.line.count'='1');

DROP TABLE IF EXISTS ods_dim_pattern;
CREATE EXTERNAL TABLE ods_dim_pattern (
    pattern STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/transfer_printing_dw/ods/dim_pattern'
TBLPROPERTIES ('skip.header.line.count'='1');
