import pandas as pd, sqlite3
conn = sqlite3.connect('transfer_printing.db')
for f, t in [('orders.csv','orders'), ('prod_record.csv','prod_record'),
             ('quality_inspect.csv','quality_inspect'), ('production_plan.csv','production_plan'),
             ('dim_machine.csv','dim_machine'), ('dim_customer.csv','dim_customer'),
             ('dim_pattern.csv','dim_pattern')]:
    pd.read_csv(f).to_sql(t, conn, if_exists='replace', index=False)
conn.close()
print('导入完成')
