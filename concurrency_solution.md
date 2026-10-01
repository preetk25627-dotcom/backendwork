# Concurrency Solution

## The Problem

Two procurement managers click "Confirm Order" at the exact same millisecond. Both sessions read `qty_on_hand = 1` for the same asset. Without any protection, both would think the stock is available and we'd end up overselling.

## The Strategy

We combine **pessimistic row-level locking** (`SELECT … FOR UPDATE SKIP LOCKED`) with an **optimistic version check** on the same short transaction. Only the single contested row gets locked — the rest of the inventory stays completely unaffected.

`SKIP LOCKED` is the key detail here. The moment Session A locks the row, Session B's `SELECT … FOR UPDATE SKIP LOCKED` returns zero rows instantly instead of sitting in a queue. Session B gets an "out of stock" response in milliseconds rather than waiting for Session A to finish.

The `version` column acts as a second safety net. Even if two sessions somehow slip through to the `UPDATE`, only the one whose version still matches the database will succeed. The other hits `NOT FOUND` and rolls back cleanly.

## Implementation

```sql
CREATE OR REPLACE PROCEDURE place_order(
    p_asset_id  BIGINT,
    p_buyer_id  BIGINT,
    p_vendor_id BIGINT,
    p_qty       INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_version    BIGINT;
    v_price      NUMERIC(12,2);
    v_rows       INT;
BEGIN
    SELECT version, unit_price
    INTO   v_version, v_price
    FROM   assets
    WHERE  asset_id    = p_asset_id
      AND  qty_on_hand >= p_qty
    FOR UPDATE SKIP LOCKED;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'asset_unavailable'
            USING HINT = 'Item is out of stock or already being processed';
    END IF;

    UPDATE assets
    SET    qty_on_hand = qty_on_hand - p_qty,
           version     = version + 1
    WHERE  asset_id    = p_asset_id
      AND  version     = v_version;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        RAISE EXCEPTION 'concurrent_modification'
            USING HINT = 'Another transaction updated this asset simultaneously';
    END IF;

    INSERT INTO txns (
        buyer_id,
        vendor_id,
        asset_id,
        qty,
        unit_price_snapshot,
        status,
        confirmed_at
    ) VALUES (
        p_buyer_id,
        p_vendor_id,
        p_asset_id,
        p_qty,
        v_price,
        'confirmed',
        now()
    );
END;
$$;
```

## How to Call It

```sql
CALL place_order(
    p_asset_id  => 42,
    p_buyer_id  => 7,
    p_vendor_id => 3,
    p_qty       => 1
);
```

The application layer catches `asset_unavailable` and shows "Sorry, this item just sold out" to the losing manager. No retry loop needed on the application side.

## Why This Works at Scale

| Concern | How it's handled |
|---|---|
| Only one winner per asset | `FOR UPDATE` ensures mutual exclusion at the row level |
| No queue buildup | `SKIP LOCKED` makes losers fail fast — no waiting |
| No lost updates on retry | `version` check catches any stale read that slips through |
| Rest of inventory unaffected | Lock scope is a single row, not a table or page |
| Transaction duration | Typically 2–5 ms — lock is held for the minimum possible time |
