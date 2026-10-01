"""Generate a synthetic trade dataset with injected reconciliation breaks and settlement fails."""
import random, sqlite3, datetime as dt

random.seed(42)
N = 2000
START, END = dt.date(2026, 7, 1), dt.date(2026, 9, 30)
REF_DATE = END  # "today" for ageing / pending logic

INSTRUMENTS = {
    'Equity':     ['VOD.L', 'HSBA.L', 'BP.L', 'AZN.L', 'ULVR.L', 'SHEL.L'],
    'Bond':       ['UKT 4.25% 2032', 'UKT 3.75% 2038', 'BUND 2.5% 2034', 'UST 4% 2030'],
    'FX':         ['GBPUSD', 'EURGBP', 'USDJPY', 'EURUSD'],
    'Derivative': ['FTSE100 FUT', 'GBPUSD FWD', 'IRS 5Y SONIA', 'EQ OPTION AZN'],
}
BASE_PRICE = {'Equity': 800, 'Bond': 98, 'FX': 1.2, 'Derivative': 50}
SETTLE_DAYS = {'Equity': 2, 'Bond': 2, 'FX': 2, 'Derivative': 1}
COUNTERPARTIES = ['Alpha Securities', 'Brightwater Capital', 'Corvus Markets', 'Delta Prime', 'Eastgate Bank']
# Some counterparties are deliberately worse than others so the analysis has a story to find
FAIL_PROB = {'Alpha Securities': 0.015, 'Brightwater Capital': 0.02, 'Corvus Markets': 0.07,
             'Delta Prime': 0.02, 'Eastgate Bank': 0.035}

def add_bdays(d, n):
    while n > 0:
        d += dt.timedelta(days=1)
        if d.weekday() < 5:
            n -= 1
    return d

def rand_bday():
    while True:
        d = START + dt.timedelta(days=random.randint(0, (END - START).days))
        if d.weekday() < 5:
            return d

con = sqlite3.connect('trades.db')
with open('schema.sql') as f:
    con.executescript(f.read())

for tid in range(1, N + 1):
    ac = random.choices(list(INSTRUMENTS), weights=[40, 20, 25, 15])[0]
    inst = random.choice(INSTRUMENTS[ac])
    side = random.choice(['BUY', 'SELL'])
    qty = random.choice([100, 500, 1000, 5000, 10000, 50000])
    price = round(BASE_PRICE[ac] * random.uniform(0.9, 1.1), 4)
    cp = random.choice(COUNTERPARTIES)
    td = rand_bday()
    exp = add_bdays(td, SETTLE_DAYS[ac])
    con.execute('INSERT INTO trades VALUES (?,?,?,?,?,?,?,?,?,?)',
                (tid, td, ac, inst, side, qty, price, round(qty * price, 2), cp, exp))

    # Counterparty confirmation, with injected breaks (~5%) and missing confirms (~1.5%)
    r = random.random()
    if r < 0.015:
        pass  # confirmation never received
    else:
        c_qty, c_price, c_settle = qty, price, exp
        if r < 0.025:   c_price = round(price * random.uniform(1.002, 1.01), 4)   # price break
        elif r < 0.04:  c_qty = int(qty * random.choice([0.5, 0.9, 1.1]))         # quantity break
        elif r < 0.065: c_settle = add_bdays(exp, 1)                              # date break
        con.execute('INSERT INTO confirmations VALUES (?,?,?,?)', (tid, c_qty, c_price, c_settle))

    # Settlement outcome
    if exp > REF_DATE:
        con.execute('INSERT INTO settlements VALUES (?,?,?)', (tid, 'PENDING', None))
    elif random.random() < FAIL_PROB[cp]:
        con.execute('INSERT INTO settlements VALUES (?,?,?)', (tid, 'FAILED', None))
    else:
        con.execute('INSERT INTO settlements VALUES (?,?,?)', (tid, 'SETTLED', exp))

con.commit()
print('Rows -> trades:', con.execute('SELECT COUNT(*) FROM trades').fetchone()[0],
      '| confirmations:', con.execute('SELECT COUNT(*) FROM confirmations').fetchone()[0],
      '| settlements:', con.execute('SELECT COUNT(*) FROM settlements').fetchone()[0])
con.close()
