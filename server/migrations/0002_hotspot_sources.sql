-- Hotspots can also come from the city's collision records (`just server-import-collisions`), not just from
-- drivers' hard brakes. Those are shown without driver votes and keep how many crashes were reported there.
ALTER TABLE hotspots
    ADD COLUMN source text NOT NULL DEFAULT 'drivers' CHECK (source IN ('drivers', 'city_collisions')),
    ADD COLUMN reported_crashes integer CHECK (reported_crashes IS NULL OR reported_crashes > 0);
CREATE INDEX hotspots_source_idx ON hotspots (source);
