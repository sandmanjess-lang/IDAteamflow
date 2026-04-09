-- =============================================
-- TeamFlow Supabase Schema
-- Run this in Supabase Dashboard > SQL Editor
-- =============================================

-- 1. Profiles table (linked to Supabase Auth)
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  username TEXT UNIQUE NOT NULL,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  color TEXT NOT NULL DEFAULT '#60a5fa',
  target_h NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Clients
CREATE TABLE clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  contact TEXT,
  share_token TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Job Bags
CREATE TABLE job_bags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID REFERENCES clients(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  members JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ DEFAULT now(),
  created_by UUID REFERENCES profiles(id),
  share_token TEXT UNIQUE,
  show_time_to_client BOOLEAN DEFAULT false,
  po_number TEXT,
  estimate TEXT,
  invoice TEXT
);

-- 4. Tasks
CREATE TABLE tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('high', 'medium', 'low')),
  status TEXT NOT NULL DEFAULT 'todo' CHECK (status IN ('todo', 'inprogress', 'done')),
  assignees JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ DEFAULT now(),
  due_date DATE,
  created_by UUID REFERENCES profiles(id),
  job_bag_id UUID REFERENCES job_bags(id) ON DELETE SET NULL,
  billable_h NUMERIC,
  is_reminder BOOLEAN DEFAULT false
);

-- 5. Time Logs
CREATE TABLE time_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id UUID REFERENCES tasks(id) ON DELETE CASCADE,
  job_bag_id UUID REFERENCES job_bags(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  hours NUMERIC NOT NULL,
  billable_h NUMERIC,
  date DATE NOT NULL,
  notes TEXT
);

-- 6. Chat Messages (covers both team chat and job bag chats)
CREATE TABLE chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  channel TEXT NOT NULL,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  text TEXT,
  files JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_chat_channel ON chat_messages(channel, created_at);

-- 7. Notifications
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  task_id UUID,
  task_title TEXT,
  assigner_name TEXT,
  jb_name TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  read BOOLEAN DEFAULT false
);
CREATE INDEX idx_notif_target ON notifications(target_user_id, created_at DESC);

-- 8. Job Bag Files
CREATE TABLE job_bag_files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_bag_id UUID REFERENCES job_bags(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type TEXT,
  size INTEGER,
  url TEXT NOT NULL,
  storage_path TEXT,
  uploaded_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- =============================================
-- Row Level Security Policies
-- =============================================

-- Profiles
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "profiles_select_auth" ON profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "profiles_select_anon" ON profiles FOR SELECT TO anon USING (true);
CREATE POLICY "profiles_insert" ON profiles FOR INSERT TO authenticated WITH CHECK (
  id = auth.uid() OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "profiles_update" ON profiles FOR UPDATE TO authenticated USING (
  id = auth.uid() OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "profiles_delete" ON profiles FOR DELETE TO authenticated USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
);

-- Clients
ALTER TABLE clients ENABLE ROW LEVEL SECURITY;
CREATE POLICY "clients_auth_all" ON clients FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "clients_anon_read" ON clients FOR SELECT TO anon USING (share_token IS NOT NULL);

-- Job Bags
ALTER TABLE job_bags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "job_bags_auth_all" ON job_bags FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "job_bags_anon_read" ON job_bags FOR SELECT TO anon USING (share_token IS NOT NULL);

-- Tasks
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tasks_auth_all" ON tasks FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "tasks_anon_read" ON tasks FOR SELECT TO anon USING (
  job_bag_id IN (SELECT id FROM job_bags WHERE share_token IS NOT NULL)
);

-- Time Logs
ALTER TABLE time_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "time_logs_auth_all" ON time_logs FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "time_logs_anon_read" ON time_logs FOR SELECT TO anon USING (
  job_bag_id IN (SELECT id FROM job_bags WHERE share_token IS NOT NULL AND show_time_to_client = true)
);

-- Chat Messages
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "chat_auth_all" ON chat_messages FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Notifications
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notif_auth_all" ON notifications FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Job Bag Files
ALTER TABLE job_bag_files ENABLE ROW LEVEL SECURITY;
CREATE POLICY "jb_files_auth_all" ON job_bag_files FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "jb_files_anon_read" ON job_bag_files FOR SELECT TO anon USING (
  job_bag_id IN (SELECT id FROM job_bags WHERE share_token IS NOT NULL)
);

-- =============================================
-- Enable Realtime on tables that need it
-- =============================================
ALTER PUBLICATION supabase_realtime ADD TABLE chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE time_logs;

-- =============================================
-- Auto-create profile on signup trigger
-- =============================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, name, username, role, color)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'role', 'member'),
    COALESCE(NEW.raw_user_meta_data->>'color', '#60a5fa')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =============================================
-- Storage bucket for file uploads
-- =============================================
INSERT INTO storage.buckets (id, name, public) VALUES ('uploads', 'uploads', true);

CREATE POLICY "uploads_auth_insert" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'uploads');
CREATE POLICY "uploads_public_read" ON storage.objects FOR SELECT TO anon USING (bucket_id = 'uploads');
CREATE POLICY "uploads_auth_read" ON storage.objects FOR SELECT TO authenticated USING (bucket_id = 'uploads');
CREATE POLICY "uploads_auth_delete" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'uploads');
