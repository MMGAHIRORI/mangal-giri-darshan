-- CRITICAL SECURITY FIXES MIGRATION
-- This migration addresses the major security vulnerabilities identified

-- 1. Create security definer functions to safely check user roles and avoid recursive RLS
CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS TEXT AS $$
  SELECT role FROM public.user_profiles WHERE user_id = auth.uid();
$$ LANGUAGE SQL SECURITY DEFINER STABLE SET search_path = public;

CREATE OR REPLACE FUNCTION public.is_admin_user()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles 
    WHERE user_id = auth.uid() 
    AND role IN ('admin', 'super_admin')
  );
$$ LANGUAGE SQL SECURITY DEFINER STABLE SET search_path = public;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles 
    WHERE user_id = auth.uid() 
    AND role = 'super_admin'
  );
$$ LANGUAGE SQL SECURITY DEFINER STABLE SET search_path = public;

CREATE OR REPLACE FUNCTION public.can_manage_content()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles 
    WHERE user_id = auth.uid() 
    AND role IN ('admin', 'super_admin', 'operator')
    AND is_disabled = false
  );
$$ LANGUAGE SQL SECURITY DEFINER STABLE SET search_path = public;

-- 2. Fix EVENTS table RLS policies - CRITICAL SECURITY FIX
DROP POLICY IF EXISTS "Authenticated users can view events" ON public.events;
DROP POLICY IF EXISTS "Authenticated users can insert events" ON public.events;
DROP POLICY IF EXISTS "Authenticated users can update events" ON public.events;
DROP POLICY IF EXISTS "Authenticated users can delete events" ON public.events;

-- Allow public read access for events (this is intentional for a public website)
-- Keep "Public can view events" policy as it exists

-- Only admins can manage events
CREATE POLICY "Admins can insert events" 
ON public.events 
FOR INSERT 
TO authenticated
WITH CHECK (public.can_manage_content());

CREATE POLICY "Admins can update events" 
ON public.events 
FOR UPDATE 
TO authenticated
USING (public.can_manage_content());

CREATE POLICY "Admins can delete events" 
ON public.events 
FOR DELETE 
TO authenticated
USING (public.can_manage_content());

-- 3. Fix GALLERY_PHOTOS table RLS policies - CRITICAL SECURITY FIX
DROP POLICY IF EXISTS "Authenticated users can view gallery photos" ON public.gallery_photos;
DROP POLICY IF EXISTS "Authenticated users can insert gallery photos" ON public.gallery_photos;
DROP POLICY IF EXISTS "Authenticated users can update gallery photos" ON public.gallery_photos;
DROP POLICY IF EXISTS "Authenticated users can delete gallery photos" ON public.gallery_photos;

-- Allow public read access for gallery (this is intentional for a public website)
-- Keep "Public can view gallery photos" policy as it exists

-- Only admins can manage gallery
CREATE POLICY "Admins can insert gallery photos" 
ON public.gallery_photos 
FOR INSERT 
TO authenticated
WITH CHECK (public.can_manage_content());

CREATE POLICY "Admins can update gallery photos" 
ON public.gallery_photos 
FOR UPDATE 
TO authenticated
USING (public.can_manage_content());

CREATE POLICY "Admins can delete gallery photos" 
ON public.gallery_photos 
FOR DELETE 
TO authenticated
USING (public.can_manage_content());

-- 4. Fix LIVE_STREAM_SETTINGS table RLS policies - CRITICAL SECURITY FIX
DROP POLICY IF EXISTS "Authenticated users can view live stream settings" ON public.live_stream_settings;
DROP POLICY IF EXISTS "Authenticated users can insert live stream settings" ON public.live_stream_settings;
DROP POLICY IF EXISTS "Authenticated users can update live stream settings" ON public.live_stream_settings;
DROP POLICY IF EXISTS "Authenticated users can delete live stream settings" ON public.live_stream_settings;

-- Allow public read access for live stream settings (needed for public viewing)
-- Keep "Public can view live stream settings" policy as it exists

-- Only admins can manage live stream settings
CREATE POLICY "Admins can insert live stream settings" 
ON public.live_stream_settings 
FOR INSERT 
TO authenticated
WITH CHECK (public.can_manage_content());

CREATE POLICY "Admins can update live stream settings" 
ON public.live_stream_settings 
FOR UPDATE 
TO authenticated
USING (public.can_manage_content());

CREATE POLICY "Admins can delete live stream settings" 
ON public.live_stream_settings 
FOR DELETE 
TO authenticated
USING (public.can_manage_content());

-- 5. Add RLS policies to USERS table - CRITICAL SECURITY FIX
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own record" 
ON public.users 
FOR SELECT 
TO authenticated
USING (auth.uid() = id);

CREATE POLICY "Super admins can view all users" 
ON public.users 
FOR SELECT 
TO authenticated
USING (public.is_super_admin());

CREATE POLICY "Super admins can manage users" 
ON public.users 
FOR ALL 
TO authenticated
USING (public.is_super_admin());

-- 6. Enhance USER_PROFILES RLS policies for admin management
CREATE POLICY "Admins can view all profiles" 
ON public.user_profiles 
FOR SELECT 
TO authenticated
USING (
  auth.uid() = user_id OR  -- Users can see their own profile
  public.is_admin_user()   -- Admins can see all profiles
);

CREATE POLICY "Super admins can manage all profiles" 
ON public.user_profiles 
FOR UPDATE 
TO authenticated
USING (
  auth.uid() = user_id OR  -- Users can update their own profile
  public.is_super_admin()  -- Super admins can update any profile
);

-- 7. Secure ADMIN_USERS table 
CREATE POLICY "Super admins can manage admin users" 
ON public.admin_users 
FOR ALL 
TO authenticated
USING (public.is_super_admin());

-- 8. Add audit logging for security events
CREATE TABLE IF NOT EXISTS public.security_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  action TEXT NOT NULL,
  table_name TEXT,
  record_id TEXT,
  old_values JSONB,
  new_values JSONB,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.security_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only super admins can view audit logs" 
ON public.security_audit_log 
FOR SELECT 
TO authenticated
USING (public.is_super_admin());

-- 9. Create function to log security events
CREATE OR REPLACE FUNCTION public.log_security_event(
  p_action TEXT,
  p_table_name TEXT DEFAULT NULL,
  p_record_id TEXT DEFAULT NULL,
  p_old_values JSONB DEFAULT NULL,
  p_new_values JSONB DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  INSERT INTO public.security_audit_log (
    user_id, action, table_name, record_id, old_values, new_values
  ) VALUES (
    auth.uid(), p_action, p_table_name, p_record_id, p_old_values, p_new_values
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 10. Fix user_id data type consistency
-- The user_id column should be UUID to match auth.users
ALTER TABLE public.user_profiles ALTER COLUMN user_id TYPE UUID USING user_id::UUID;