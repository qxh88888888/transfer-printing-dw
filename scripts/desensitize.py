"""
desensitize.py —— 生成脱敏后的样本数据（上传 GitHub 用）

做法：
  1. 从原始 CSV 中随机抽取 N 个订单（固定随机种子，结果可复现）
  2. 只保留这些订单关联的订单 / 生产 / 质检 / 排产数据，保证子集内部可关联
  3. 对客户、花型、班组等字段做代码化替换（客户甲 -> CUST_001）
  4. 输出到 data/sample/，不写入全量原始数据

用法：
  python scripts/desensitize.py --src "原始CSV所在目录" --out data/sample --orders 500
"""
import argparse
import os

import pandas as pd

# ---------------------------------------------------------------------------
# 脱敏映射表：把可读的业务名称替换成中性代码
# ---------------------------------------------------------------------------
CUSTOMER_MAP = {c: f'CUST_{i:03d}' for i, c in enumerate(['客户甲', '客户乙', '客户丙',
                                                          '客户丁', '客户戊', '客户己'], start=1)}
PATTERN_MAP = {p: f'PAT_{i:03d}' for i, p in enumerate(['花型A', '花型B', '花型C',
                                                         '花型D', '花型E'], start=1)}
TEAM_MAP = {'A班': 'TEAM_A', 'B班': 'TEAM_B', 'C班': 'TEAM_C'}

# 单表最大行数，防止样本过大
MAX_ROWS_PER_TABLE = 20000


def mask(df, column, mapping):
    """按映射表替换某列的取值，未在映射中的保持原样"""
    if column in df.columns:
        df[column] = df[column].replace(mapping)
    return df


def main():
    parser = argparse.ArgumentParser(description='生成脱敏样本数据')
    parser.add_argument('--src', required=True, help='原始 CSV 所在目录')
    parser.add_argument('--out', default='data/sample', help='输出目录')
    parser.add_argument('--orders', type=int, default=500, help='抽取的订单数')
    parser.add_argument('--seed', type=int, default=42, help='随机种子')
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)

    def read(name):
        return pd.read_csv(os.path.join(args.src, f'{name}.csv'))

    orders = read('orders')

    # ---- 1. 抽取订单，得到本次样本的订单号集合 ----
    n = min(args.orders, len(orders))
    sample_orders = orders.sample(n=n, random_state=args.seed)
    keep_ids = set(sample_orders['order_id'])

    orders = sample_orders.copy()

    # ---- 2. 其余明细表按订单号过滤，保证子集内部可关联 ----
    tables = {'orders': orders, 'production_plan': read('production_plan'),
              'prod_record': read('prod_record'), 'quality_inspect': read('quality_inspect')}

    for name in ['production_plan', 'prod_record', 'quality_inspect']:
        df = tables[name]
        df = df[df['order_id'].isin(keep_ids)].copy()
        if len(df) > MAX_ROWS_PER_TABLE:
            df = df.sample(n=MAX_ROWS_PER_TABLE, random_state=args.seed)
        tables[name] = df

    # 维度表数据量很小，整体保留
    tables['dim_machine'] = read('dim_machine')
    tables['dim_customer'] = read('dim_customer')
    tables['dim_pattern'] = read('dim_pattern')

    # ---- 3. 字段脱敏 ----
    for name, df in tables.items():
        df = mask(df, 'customer', CUSTOMER_MAP)
        df = mask(df, 'pattern', PATTERN_MAP)
        df = mask(df, 'team', TEAM_MAP)
        tables[name] = df

    tables['dim_customer'] = pd.DataFrame({'customer': list(CUSTOMER_MAP.values())})
    tables['dim_pattern'] = pd.DataFrame({'pattern': list(PATTERN_MAP.values())})

    # ---- 4. 输出（utf-8 无 BOM，方便直接入库）----
    for name, df in tables.items():
        path = os.path.join(args.out, f'{name}.csv')
        df.to_csv(path, index=False, encoding='utf-8')
        print(f'{name:20s} -> {len(df):>7d} 行  {path}')


if __name__ == '__main__':
    main()
