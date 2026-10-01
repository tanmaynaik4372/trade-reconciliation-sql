-- ============================================================
-- 1. Trades with no counterparty confirmation (unconfirmed)
-- ============================================================
SELECT t.trade_id, t.trade_date, t.asset_class, t.counterparty, t.notional
FROM trades t
LEFT JOIN confirmations c ON c.trade_id = t.trade_id
WHERE c.trade_id IS NULL
ORDER BY t.notional DESC;

-- ============================================================
-- 2. Reconciliation breaks: classify each mismatch
-- ============================================================
SELECT t.trade_id, t.asset_class, t.counterparty,
       CASE
         WHEN t.price <> c.price               THEN 'PRICE'
         WHEN t.quantity <> c.quantity         THEN 'QUANTITY'
         WHEN t.expected_settle <> c.settle_date THEN 'SETTLE DATE'
       END AS break_type,
       t.notional
FROM trades t
JOIN confirmations c ON c.trade_id = t.trade_id
WHERE t.price <> c.price
   OR t.quantity <> c.quantity
   OR t.expected_settle <> c.settle_date;

-- ============================================================
-- 3. Break rate by asset class (breaks + unconfirmed / total trades)
-- ============================================================
WITH flagged AS (
  SELECT t.trade_id, t.asset_class,
         CASE WHEN c.trade_id IS NULL
                OR t.price <> c.price
                OR t.quantity <> c.quantity
                OR t.expected_settle <> c.settle_date
              THEN 1 ELSE 0 END AS is_break
  FROM trades t
  LEFT JOIN confirmations c ON c.trade_id = t.trade_id
)
SELECT asset_class,
       COUNT(*)                                   AS trades,
       SUM(is_break)                              AS breaks,
       ROUND(100.0 * SUM(is_break) / COUNT(*), 2) AS break_rate_pct
FROM flagged
GROUP BY asset_class
ORDER BY break_rate_pct DESC;

-- ============================================================
-- 4. Settlement fail rate by counterparty (settled + failed only)
-- ============================================================
SELECT t.counterparty,
       COUNT(*)                                                    AS due_trades,
       SUM(CASE WHEN s.status = 'FAILED' THEN 1 ELSE 0 END)        AS fails,
       ROUND(100.0 * SUM(CASE WHEN s.status = 'FAILED' THEN 1 ELSE 0 END) / COUNT(*), 2) AS fail_rate_pct,
       ROUND(SUM(CASE WHEN s.status = 'FAILED' THEN t.notional ELSE 0 END), 0) AS failed_notional
FROM trades t
JOIN settlements s ON s.trade_id = t.trade_id
WHERE s.status IN ('SETTLED','FAILED')
GROUP BY t.counterparty
ORDER BY fail_rate_pct DESC;

-- ============================================================
-- 5. Ageing of failed trades (days past expected settlement, as at 30 Sep 2026)
-- ============================================================
SELECT t.trade_id, t.counterparty, t.asset_class, t.notional,
       CAST(julianday('2026-09-30') - julianday(t.expected_settle) AS INTEGER) AS days_overdue,
       CASE
         WHEN julianday('2026-09-30') - julianday(t.expected_settle) <= 5  THEN '0-5 days'
         WHEN julianday('2026-09-30') - julianday(t.expected_settle) <= 30 THEN '6-30 days'
         ELSE '30+ days'
       END AS age_bucket
FROM trades t
JOIN settlements s ON s.trade_id = t.trade_id
WHERE s.status = 'FAILED'
ORDER BY days_overdue DESC;

-- ============================================================
-- 6. Rank counterparties by fail rate within each asset class (window function)
-- ============================================================
WITH stats AS (
  SELECT t.asset_class, t.counterparty,
         COUNT(*) AS due_trades,
         SUM(CASE WHEN s.status = 'FAILED' THEN 1 ELSE 0 END) AS fails
  FROM trades t
  JOIN settlements s ON s.trade_id = t.trade_id
  WHERE s.status IN ('SETTLED','FAILED')
  GROUP BY t.asset_class, t.counterparty
)
SELECT asset_class, counterparty, due_trades, fails,
       ROUND(100.0 * fails / due_trades, 2) AS fail_rate_pct,
       RANK() OVER (PARTITION BY asset_class ORDER BY 1.0 * fails / due_trades DESC) AS risk_rank
FROM stats
ORDER BY asset_class, risk_rank;
