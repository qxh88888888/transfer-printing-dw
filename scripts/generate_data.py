import numpy as np
import pandas as pd
from datetime import datetime, timedelta

np.random.seed(42)

# ================= 参数 =================
N_ORDERS = 6000                 # 6000单 × 约20卷 ≈ 30万行
START = datetime(2025, 7, 1)
END = datetime(2026, 7, 1)
IMPROVE_DATE = datetime(2026, 2, 1)   # 改善分界点
DAYS = (END - START).days

MACHINES = {
    'M01': {'rated_speed': 18, 'rated_power': 45},
    'M02': {'rated_speed': 18, 'rated_power': 45},
    'M03': {'rated_speed': 16, 'rated_power': 50},  # 温度易波动
    'M04': {'rated_speed': 20, 'rated_power': 42},
    'M05': {'rated_speed': 22, 'rated_power': 48},  # 速度偏快
    'M06': {'rated_speed': 18, 'rated_power': 45},
}
TEAMS = ['A班', 'B班', 'C班']
DEFECT_TYPES = ['色差', '套印不准', '发虚', '水波纹', '其他']
CUSTOMERS = ['客户甲', '客户乙', '客户丙', '客户丁', '客户戊', '客户己']
PATTERNS = ['花型A', '花型B', '花型C', '花型D', '花型E']

# ================= 1. 订单表 =================
order_ids = [f'ORD{str(i).zfill(6)}' for i in range(1, N_ORDERS + 1)]
order_dates = [START + timedelta(days=np.random.randint(0, DAYS)) for _ in range(N_ORDERS)]

orders = pd.DataFrame({
    'order_id': order_ids,
    'customer': np.random.choice(CUSTOMERS, N_ORDERS),
    'pattern': np.random.choice(PATTERNS, N_ORDERS),
    'quantity_sqm': np.random.randint(150, 2500, N_ORDERS),
    'order_date': order_dates,
})
orders['is_improved'] = orders['order_date'] >= IMPROVE_DATE
orders['promise_days'] = np.where(orders['is_improved'],
                                  np.random.randint(12, 26, N_ORDERS),
                                  np.random.randint(15, 31, N_ORDERS))
orders['promise_date'] = orders['order_date'] + pd.to_timedelta(orders['promise_days'], unit='D')

# 实际交付：改善前延期更多，改善后延期更少
delay_choices = [-5, -3, -2, -1, 0, 1, 2, 3, 5, 7, 10, 14]

# 改善前：准时82%，延期18%，平均延误约3.1天
p_before = [0.03, 0.10, 0.15, 0.20, 0.34,
            0.05, 0.05, 0.04, 0.02, 0.01, 0.005, 0.005]

# 改善后：准时90%，延期10%，平均延误约1.8天
p_after = [0.05, 0.10, 0.15, 0.20, 0.40,
           0.05, 0.03, 0.015, 0.004, 0.001, 0, 0]
delay = np.where(orders['is_improved'],
                 np.random.choice(delay_choices, N_ORDERS, p=p_after),
                 np.random.choice(delay_choices, N_ORDERS, p=p_before))
orders['actual_date'] = orders['promise_date'] + pd.to_timedelta(delay, unit='D')
orders['delay_days'] = delay
orders['on_time_flag'] = (delay <= 0).astype(int)

# ================= 2. 生产明细表（按卷） =================
prod_rows = []
for _, o in orders.iterrows():
    n_rolls = int(np.clip(np.random.normal(20, 5), 5, 45))
    roll_sqm = o['quantity_sqm'] / n_rolls
    machine = np.random.choice(list(MACHINES.keys()))
    team = np.random.choice(TEAMS)
    rated_speed = MACHINES[machine]['rated_speed']
    rated_power = MACHINES[machine]['rated_power']

    for r in range(n_rolls):
        if machine == 'M03':
            temp = np.random.normal(215, 12); speed = np.random.normal(16, 3)
        elif machine == 'M05':
            temp = np.random.normal(200, 8);  speed = np.random.normal(22, 4)
        else:
            temp = np.random.normal(205, 6);  speed = np.random.normal(15, 2)

        # 改善后：温度/速度向标准值收敛
        if o['is_improved']:
            temp = 205 + (temp - 205) * 0.6
            speed = 15 + (speed - 15) * 0.6

        run_hours = roll_sqm / max(speed, 1)
        prod_rows.append({
            'order_id': o['order_id'],
            'roll_id': f"{o['order_id']}-R{r+1:02d}",
            'machine_id': machine,
            'team': team,
            'roll_sqm': round(roll_sqm, 2),
            'run_hours': round(run_hours, 2),
            'rated_speed': rated_speed,
            'rated_power': rated_power,
            'avg_temp': round(temp, 1),
            'avg_speed': round(speed, 1),
            'avg_pressure': round(np.random.normal(2.8, 0.3), 2),
            'is_improved': o['is_improved'],
        })
prod = pd.DataFrame(prod_rows)

# ================= 3. 质检明细表 =================
qual_rows = []
for _, p in prod.iterrows():
    n_inspect = np.random.choice([1, 2], p=[0.6, 0.4])
    inspect_sqm = p['roll_sqm'] / n_inspect
    base = 0.048 if p['is_improved'] else 0.065
    temp_effect = abs(p['avg_temp'] - 205) * 0.0012
    speed_effect = abs(p['avg_speed'] - 15) * 0.0025
    defect_rate = min(0.20, max(0.01, base + temp_effect + speed_effect + np.random.normal(0, 0.008)))
    defect_sqm = round(inspect_sqm * defect_rate, 2)

    rework_prob = 0.021 if p['is_improved'] else 0.032
    qual_rows.append({
        'order_id': p['order_id'],
        'roll_id': p['roll_id'],
        'machine_id': p['machine_id'],
        'inspect_sqm': round(inspect_sqm, 2),
        'defect_sqm': defect_sqm,
        'defect_type': np.random.choice(DEFECT_TYPES, p=[0.40, 0.25, 0.15, 0.10, 0.10]),
        'rework_flag': 1 if np.random.random() < rework_prob else 0,
        'is_improved': p['is_improved'],
    })
qual = pd.DataFrame(qual_rows)

# ================= 4. 排产计划表 =================
plan_rows = []
for _, o in orders.iterrows():
    for _ in range(np.random.randint(1, 4)):
        plan_rows.append({
            'order_id': o['order_id'],
            'machine_id': np.random.choice(list(MACHINES.keys())),
            'planned_start': o['order_date'] + timedelta(days=np.random.randint(0, 5)),
        })
plan = pd.DataFrame(plan_rows)
plan['planned_end'] = plan['planned_start'] + pd.to_timedelta(np.random.randint(3, 10, len(plan)), unit='D')

# ================= 5. 维度表 =================
dim_machine = pd.DataFrame([
    {'machine_id': k, 'rated_speed': v['rated_speed'], 'rated_power': v['rated_power']}
    for k, v in MACHINES.items()
])
dim_customer = pd.DataFrame({'customer': CUSTOMERS})
dim_pattern = pd.DataFrame({'pattern': PATTERNS})

# ================= 输出 =================
print('订单表:', orders.shape)
print('生产明细:', prod.shape)
print('质检明细:', qual.shape)
print('排产表:', plan.shape)
print('合计行数:', len(orders) + len(prod) + len(qual) + len(plan) + len(dim_machine) + len(dim_customer) + len(dim_pattern))

orders.to_csv('orders.csv', index=False, encoding='utf-8-sig')
prod.to_csv('prod_record.csv', index=False, encoding='utf-8-sig')
qual.to_csv('quality_inspect.csv', index=False, encoding='utf-8-sig')
plan.to_csv('production_plan.csv', index=False, encoding='utf-8-sig')
dim_machine.to_csv('dim_machine.csv', index=False, encoding='utf-8-sig')
dim_customer.to_csv('dim_customer.csv', index=False, encoding='utf-8-sig')
dim_pattern.to_csv('dim_pattern.csv', index=False, encoding='utf-8-sig')
print('CSV已导出，可直接导入 Power BI')