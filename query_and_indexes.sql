SELECT
    asset_id,
    category,
    sub_category,
    unit_price,
    condition,
    zone,
    qty_on_hand,
    updated_at
FROM assets
WHERE category    = 'Heavy Machinery'
  AND zone        = 'Warehouse Zone A'
  AND qty_on_hand > 0
ORDER BY updated_at DESC, unit_price ASC
LIMIT 50;


CREATE INDEX idx_assets_dashboard
    ON assets (updated_at DESC, unit_price ASC)
    WHERE category    = 'Heavy Machinery'
      AND zone        = 'Warehouse Zone A'
      AND qty_on_hand > 0
    INCLUDE (asset_id, sub_category, condition, qty_on_hand);


CREATE INDEX idx_assets_category_zone
    ON assets (category, zone, updated_at DESC, unit_price ASC)
    WHERE qty_on_hand > 0;
