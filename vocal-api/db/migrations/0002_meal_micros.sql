-- 0002: optional micronutrient columns on meals.
--
-- Additive only — no rename, no drop. Existing rows leave these NULL,
-- which the iOS / Flutter client treats as "unknown".
--
-- iron_mg and vitamin_c_mg are REAL because a single decimal place is
-- the natural precision for those (e.g. 4.5 mg iron, 12.3 mg vit C).
-- Everything else is INTEGER mg/g.

ALTER TABLE meals ADD COLUMN sodium_mg     INTEGER;
ALTER TABLE meals ADD COLUMN fiber_g       INTEGER;
ALTER TABLE meals ADD COLUMN sugar_g       INTEGER;
ALTER TABLE meals ADD COLUMN calcium_mg    INTEGER;
ALTER TABLE meals ADD COLUMN iron_mg       REAL;
ALTER TABLE meals ADD COLUMN vitamin_c_mg  REAL;
ALTER TABLE meals ADD COLUMN potassium_mg  INTEGER;
