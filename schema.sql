CREATE EXTENSION IF NOT EXISTS citext;


CREATE TABLE parties (
    party_id    BIGSERIAL PRIMARY KEY,
    email       CITEXT NOT NULL UNIQUE,
    party_type  TEXT NOT NULL CHECK (party_type IN ('vendor', 'client')),
    name        TEXT NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION verify_corporate_email()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.email NOT ILIKE '%@corporate.com' THEN
        NEW.is_verified := FALSE;
    ELSE
        NEW.is_verified := TRUE;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_verify_corporate_email
BEFORE INSERT OR UPDATE OF email ON parties
FOR EACH ROW EXECUTE FUNCTION verify_corporate_email();


CREATE TABLE assets (
    asset_id     BIGSERIAL PRIMARY KEY,
    vendor_id    BIGINT NOT NULL REFERENCES parties(party_id) ON DELETE RESTRICT,
    category     TEXT NOT NULL,
    sub_category TEXT,
    unit_price   NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
    condition    TEXT NOT NULL CHECK (condition IN ('new', 'used', 'refurbished')),
    zone         TEXT NOT NULL,
    qty_on_hand  INT NOT NULL DEFAULT 0 CHECK (qty_on_hand >= 0),
    version      BIGINT NOT NULL DEFAULT 0,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
) WITH (fillfactor = 70);

CREATE OR REPLACE FUNCTION enforce_vendor_party()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM parties
        WHERE party_id = NEW.vendor_id
          AND party_type = 'vendor'
    ) THEN
        RAISE EXCEPTION 'vendor_id % does not belong to a vendor party', NEW.vendor_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_enforce_vendor_party
BEFORE INSERT OR UPDATE OF vendor_id ON assets
FOR EACH ROW EXECUTE FUNCTION enforce_vendor_party();

CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_assets_updated_at
BEFORE UPDATE ON assets
FOR EACH ROW EXECUTE FUNCTION touch_updated_at();


CREATE TABLE txns (
    txn_id               BIGSERIAL PRIMARY KEY,
    buyer_id             BIGINT NOT NULL REFERENCES parties(party_id) ON DELETE RESTRICT,
    vendor_id            BIGINT NOT NULL REFERENCES parties(party_id) ON DELETE RESTRICT,
    asset_id             BIGINT NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    qty                  INT NOT NULL CHECK (qty > 0),
    unit_price_snapshot  NUMERIC(12, 2) NOT NULL,
    status               TEXT NOT NULL CHECK (status IN ('pending', 'confirmed', 'cancelled')),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_at         TIMESTAMPTZ
);

CREATE OR REPLACE FUNCTION enforce_buyer_party()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM parties
        WHERE party_id = NEW.buyer_id
          AND party_type = 'client'
    ) THEN
        RAISE EXCEPTION 'buyer_id % does not belong to a client party', NEW.buyer_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_enforce_buyer_party
BEFORE INSERT OR UPDATE OF buyer_id ON txns
FOR EACH ROW EXECUTE FUNCTION enforce_buyer_party();
