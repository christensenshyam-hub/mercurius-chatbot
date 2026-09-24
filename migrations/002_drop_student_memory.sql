-- migrations/002_drop_student_memory.sql
-- Retire the cross-session "student memory" store.
--
-- Applied by `node scripts/migrate.mjs`, which records it in schema_migrations
-- so it runs exactly once per database. Safe to re-run by hand: IF EXISTS
-- makes a second pass a no-op. The table's index (idx_memory_session) is
-- dropped with it on both drivers.
--
-- WHY: student_memory held free-text facts extracted from a (possibly
-- minor's) conversations and replayed them into later prompts. The feature is
-- being removed; its rows are personal data with no remaining reader, so the
-- table goes rather than lingering.
--
-- ⚠️ db.initSchema must stop CREATE-ing this table in the same change that
-- removes the memory helpers — otherwise the next boot silently recreates it
-- (empty) and this migration, already recorded as applied, never runs again.

DROP TABLE IF EXISTS student_memory;
