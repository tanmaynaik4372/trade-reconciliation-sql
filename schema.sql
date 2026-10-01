-- Trade reconciliation & settlement monitoring (synthetic data)
DROP TABLE IF EXISTS trades;
DROP TABLE IF EXISTS confirmations;
DROP TABLE IF EXISTS settlements;

-- Internal booking: what we captured in the front office system
CREATE TABLE trades (
    trade_id        INTEGER PRIMARY KEY,
    trade_date      DATE    NOT NULL,
    asset_class     TEXT    NOT NULL CHECK (asset_class IN ('Equity','Bond','FX','Derivative')),
    instrument      TEXT    NOT NULL,
    side            TEXT    NOT NULL CHECK (side IN ('BUY','SELL')),
    quantity        INTEGER NOT NULL,
    price           REAL    NOT NULL,
    notional        REAL    NOT NULL,
    counterparty    TEXT    NOT NULL,
    expected_settle DATE    NOT NULL
);

-- Counterparty's view of the same trade (middle office matching)
CREATE TABLE confirmations (
    trade_id        INTEGER PRIMARY KEY REFERENCES trades(trade_id),
    quantity        INTEGER NOT NULL,
    price           REAL    NOT NULL,
    settle_date     DATE    NOT NULL
);

-- Back office settlement outcome
CREATE TABLE settlements (
    trade_id        INTEGER PRIMARY KEY REFERENCES trades(trade_id),
    status          TEXT NOT NULL CHECK (status IN ('SETTLED','FAILED','PENDING')),
    actual_settle   DATE
);
