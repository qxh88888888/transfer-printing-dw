import pandas as pd, numpy as np
import matplotlib.pyplot as plt
import matplotlib
matplotlib.rcParams['font.sans-serif'] = ['SimHei']  # 中文显示
matplotlib.rcParams['axes.unicode_minus'] = False

# ---------- 3.1 读取并补做清洗校验（体现Pandas清洗） ----------
df = pd.read_csv('wide_order_machine.csv')
qual = pd.read_csv('qual_clean.csv')

print('清洗前宽表行数:', len(df))
# 缺失值检查
missing = df.isna().sum()
print('缺失值:\n', missing[missing > 0])
# 重复值
dup = df.duplicated(subset=['order_id','machine_id','team']).sum()
print('重复行:', dup)
df = df.drop_duplicates(subset=['order_id','machine_id','team'])
# 异常值：次品率>1或<0、机台效率>1.2
df = df[(df['defect_rate'].between(0,1)) & (df['machine_efficiency'].between(0,1.2))]
print('清洗后宽表行数:', len(df))

# ---------- 3.2 NumPy 计算关键指标 ----------
df['defect_rate_np'] = np.where(df['inspect_sqm']>0, df['defect_sqm']/df['inspect_sqm'], np.nan)
df['delay_days_np'] = np.where(df['actual_date'].notna(), df['delay_days'], np.nan)

# ---------- 3.3 改善前后对比 ----------
summary = df.groupby('is_improved').agg(
    defect_rate=('defect_rate','mean'),
    rework_rate=('rework_rate','mean'),
    on_time_rate=('on_time_flag','mean'),
    avg_delay=('delay_days', lambda x: x[x>0].mean()),
    machine_efficiency=('machine_efficiency','mean'),
    unit_cost=('unit_cost','mean'),
).round(4)
print(summary)

# ---------- 3.4 次品率月度趋势 ----------
df['order_date'] = pd.to_datetime(df['order_date'])
df['month'] = df['order_date'].dt.to_period('M').astype(str)
monthly = df.groupby('month').agg(defect_rate=('defect_rate','mean'),
                                  on_time_rate=('on_time_flag','mean')).reset_index()

fig, ax1 = plt.subplots(figsize=(10,4))
ax1.plot(monthly['month'], monthly['defect_rate'], 'o-', color='#C44E52', label='次品率')
ax1.set_ylabel('次品率')
ax2 = ax1.twinx()
ax2.plot(monthly['month'], monthly['on_time_rate'], 's--', color='#4C72B0', label='交期达成率')
ax2.set_ylabel('交期达成率')
plt.title('次品率与交期达成率月度趋势（2026.02为改善分界）')
plt.xticks(rotation=45)
plt.tight_layout()
plt.savefig('monthly_trend.png', dpi=150)
plt.show()

# ---------- 3.5 相关性：次品率 vs 温度/速度 ----------
corr = df[['defect_rate','avg_temp','avg_speed','avg_pressure','machine_efficiency']].corr()
print('相关性:\n', corr.round(3))

# ---------- 3.6 机台异常定位：散点图 ----------
m = df.groupby('machine_id').agg(
    defect_rate=('defect_rate','mean'),
    avg_temp=('avg_temp','mean'),
    avg_speed=('avg_speed','mean'),
    efficiency=('machine_efficiency','mean'),
    unit_cost=('unit_cost','mean'),
).reset_index()

fig, ax = plt.subplots(figsize=(8,5))
sc = ax.scatter(m['avg_temp'], m['defect_rate'], s=m['unit_cost']*20,
                c=m['avg_speed'], cmap='coolwarm', alpha=0.8, edgecolors='k')
for _, r in m.iterrows():
    ax.annotate(r['machine_id'], (r['avg_temp'], r['defect_rate']), fontsize=9)
plt.colorbar(sc, label='平均速度')
ax.set_xlabel('平均温度(℃)')
ax.set_ylabel('平均次品率')
plt.title('机台温度-次品率散点（气泡大小=单位成本，颜色=速度）')
plt.tight_layout()
plt.savefig('machine_scatter.png', dpi=150)
plt.show()

# ---------- 3.7 缺陷帕累托 ----------
pareto = qual.groupby('defect_type')['defect_sqm'].sum().sort_values(ascending=False).reset_index()
pareto['cum_share'] = pareto['defect_sqm'].cumsum() / pareto['defect_sqm'].sum()

fig, ax1 = plt.subplots(figsize=(8,4))
ax1.bar(pareto['defect_type'], pareto['defect_sqm'], color='#4C72B0', alpha=0.8)
ax1.set_ylabel('缺陷面积')
ax2 = ax1.twinx()
ax2.plot(pareto['defect_type'], pareto['cum_share'], 'o-', color='#C44E52')
ax2.set_ylabel('累计占比')
ax2.axhline(0.8, linestyle='--', color='gray')
plt.title('缺陷类型帕累托图')
plt.tight_layout()
plt.savefig('defect_pareto.png', dpi=150)
plt.show()