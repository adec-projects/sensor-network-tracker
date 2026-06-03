-- Persistent free-text "Notes / Details" on sensors and communities, plus
-- a community "network availability" field (Wi-Fi / cell networks on site).
-- These stay visible on the profile pages so important info (lock combos,
-- access notes, available networks) doesn't get lost in history.

ALTER TABLE sensors     ADD COLUMN IF NOT EXISTS details text DEFAULT '';
ALTER TABLE communities ADD COLUMN IF NOT EXISTS details text DEFAULT '';
ALTER TABLE communities ADD COLUMN IF NOT EXISTS network_availability text DEFAULT '';
