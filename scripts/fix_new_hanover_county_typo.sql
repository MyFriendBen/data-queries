-- MFB-984: Fix "NewHanover County" typo in screener_screen.county.
-- Production has 1 row from before the April 2025 launch with the missing space.
-- Run once against the benefits-api production DB. Expected: UPDATE 1.

BEGIN;

UPDATE screener_screen
SET county = 'New Hanover County'
WHERE county = 'NewHanover County';

COMMIT;
