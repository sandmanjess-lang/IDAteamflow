-- =============================================
-- Notifications: add support for multiple notification kinds
-- Run this ONCE in Supabase Dashboard > SQL Editor
-- Safe to re-run (uses IF NOT EXISTS)
-- =============================================

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS kind TEXT DEFAULT 'task_assigned';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS channel TEXT;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS body TEXT;

-- Backfill any rows that pre-date the column
UPDATE notifications SET kind='task_assigned' WHERE kind IS NULL;
