-- ============================================================
-- EXTENSIONS
-- Run this FIRST, before 01_schema.sql
-- ============================================================
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";
create extension if not exists "pg_net";
-- pg_stat_statements and supabase_vault are enabled by default on new
-- Supabase projects; if not, enable them from Database > Extensions.
