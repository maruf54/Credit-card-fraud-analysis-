-- =====================================================================
-- Credit Card Fraud: Pattern Analysis (PostgreSQL)
-- Run in database: fraud
-- Lines starting with \copy must run in SQL Shell (psql), not pgAdmin.
-- =====================================================================

-- ---------- 1. Table + import ----------
CREATE TABLE transactions (
  time NUMERIC,
  v1 NUMERIC, v2 NUMERIC, v3 NUMERIC, v4 NUMERIC, v5 NUMERIC, v6 NUMERIC, v7 NUMERIC,
  v8 NUMERIC, v9 NUMERIC, v10 NUMERIC, v11 NUMERIC, v12 NUMERIC, v13 NUMERIC, v14 NUMERIC,
  v15 NUMERIC, v16 NUMERIC, v17 NUMERIC, v18 NUMERIC, v19 NUMERIC, v20 NUMERIC, v21 NUMERIC,
  v22 NUMERIC, v23 NUMERIC, v24 NUMERIC, v25 NUMERIC, v26 NUMERIC, v27 NUMERIC, v28 NUMERIC,
  amount NUMERIC,
  class INT
);

-- psql only (change the path to where your file is):
-- \copy transactions FROM 'C:/path/to/creditcard.csv' WITH (FORMAT csv, HEADER true);

-- row id, used later to join model scores back
ALTER TABLE transactions ADD COLUMN txn_id BIGSERIAL PRIMARY KEY;


-- ---------- 2.1 Class balance ----------
SELECT class,
       COUNT(*) AS txns,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 3) AS pct
FROM transactions
GROUP BY class;


-- ---------- 2.2 Amount stats by class ----------
SELECT class,
       COUNT(*) AS txns,
       ROUND(MIN(amount), 2) AS min_amt,
       ROUND(AVG(amount), 2) AS avg_amt,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount)::numeric, 2) AS median_amt,
       ROUND(MAX(amount), 2) AS max_amt
FROM transactions
GROUP BY class;


-- ---------- 2.3 Fraud rate by (relative) hour ----------
SELECT (FLOOR(time / 3600)::int % 24) AS hour,
       COUNT(*) AS txns,
       SUM(class) AS frauds,
       ROUND(100.0 * SUM(class) / COUNT(*), 3) AS fraud_rate_pct
FROM transactions
GROUP BY 1
ORDER BY fraud_rate_pct DESC;


-- ---------- 2.4 Duplicate rows ----------
SELECT COUNT(*) AS duplicate_groups, SUM(n - 1) AS extra_rows
FROM (
  SELECT time, amount, v1, v2, v3, v4, class, COUNT(*) AS n
  FROM transactions
  GROUP BY time, amount, v1, v2, v3, v4, class
  HAVING COUNT(*) > 1
) d;


-- ---------- 4. Model scores from Colab ----------
DROP TABLE IF EXISTS txn_risk_scores;
CREATE TABLE txn_risk_scores (txn_id BIGINT, fraud_probability NUMERIC);

-- Option A (pgAdmin Query Tool): put the file in C:\Users\Public first
-- COPY txn_risk_scores FROM 'C:/Users/Public/txn_risk_scores.csv' WITH (FORMAT csv, HEADER true);
-- Option B (psql):
-- \copy txn_risk_scores FROM 'C:/path/to/txn_risk_scores.csv' WITH (FORMAT csv, HEADER true);

-- sanity check: both tables should have rows and txn_id ranges should overlap
SELECT 'transactions' AS tbl, COUNT(*) AS total_rows, MIN(txn_id) AS min_id, MAX(txn_id) AS max_id FROM transactions
UNION ALL
SELECT 'txn_risk_scores', COUNT(*), MIN(txn_id), MAX(txn_id) FROM txn_risk_scores;


-- ---------- 4.1 Highest-risk transactions ----------
SELECT t.txn_id, t.amount, s.fraud_probability, t.class AS actual_fraud
FROM txn_risk_scores s
JOIN transactions t ON t.txn_id = s.txn_id
ORDER BY s.fraud_probability DESC
LIMIT 20;


-- ---------- 4.2 Confusion matrix at threshold 0.5 ----------
SELECT CASE WHEN s.fraud_probability >= 0.5 THEN 'Flagged' ELSE 'Passed' END AS model_decision,
       SUM(CASE WHEN t.class = 1 THEN 1 ELSE 0 END) AS real_fraud,
       SUM(CASE WHEN t.class = 0 THEN 1 ELSE 0 END) AS normal
FROM txn_risk_scores s
JOIN transactions t ON t.txn_id = s.txn_id
GROUP BY 1;


-- ---------- 4.3 Review queue for analysts ----------
CREATE OR REPLACE VIEW v_review_queue AS
SELECT t.txn_id, t.amount, s.fraud_probability,
       CASE WHEN s.fraud_probability >= 0.8 THEN 'HIGH'
            WHEN s.fraud_probability >= 0.5 THEN 'MEDIUM' END AS risk_level
FROM txn_risk_scores s
JOIN transactions t ON t.txn_id = s.txn_id
WHERE s.fraud_probability >= 0.5;

SELECT risk_level, COUNT(*) AS txns, ROUND(SUM(amount), 2) AS amount_at_risk
FROM v_review_queue
GROUP BY risk_level;
