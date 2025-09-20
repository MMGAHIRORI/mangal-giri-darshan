import { supabase } from "./client";

export interface CreatedAdminUserResult {
  userId: string;
  email: string;
}

export const createAdminUser = async (
  email: string,
  password: string,
  role: 'admin' | 'user' | 'operator' = 'admin',
  permissions?: {
    can_manage_events?: boolean;
    can_manage_gallery?: boolean;
    can_manage_livestream?: boolean;
    can_edit_profile?: boolean;
    can_manage_users?: boolean;
  }
): Promise<CreatedAdminUserResult> => {
  if (!email || !password) {
    throw new Error("Email and password are required");
  }

  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      emailRedirectTo: `${window.location.origin}/admin-login`,
    },
  });

  if (error) {
    throw new Error(error.message);
  }

  if (!data.user) {
    throw new Error("User sign up failed");
  }

  // Set default permissions based on role
  const defaultPermissions = {
    can_read: true,
    can_write: role === 'admin',
    can_manage_events: role === 'admin',
    can_manage_gallery: role === 'admin',
    can_manage_livestream: role === 'admin',
    can_edit_profile: role === 'admin',
    can_manage_users: role === 'admin', // Admins can manage users by default
    is_disabled: false,
    is_main_admin: false, // New users are never main admin
    admin_created: false
  };

  // Override with custom permissions if provided
  const finalPermissions = permissions ? { ...defaultPermissions, ...permissions } : defaultPermissions;

  // Create or update user profile using upsert for better reliability
  console.log('Creating/updating user profile...');
  const { error: upsertError } = await supabase
    .from('user_profiles')
    .upsert({
      user_id: data.user.id,
      email: email,
      name: email.split('@')[0], // Use email prefix as default name
      role,
      ...finalPermissions
    }, {
      onConflict: 'user_id'
    });
  
  if (upsertError) {
    throw new Error(`Failed to create/update user profile: ${upsertError.message}`);
  }

  // Add to admin_users table for admin and operator roles
  if (role === 'admin' || role === 'operator') {
    const { error: adminError } = await supabase
      .from("admin_users")
      .upsert({ 
        user_id: data.user.id, 
        email, 
        role 
      }, {
        onConflict: 'user_id'
      });
    if (adminError) {
      // Ignore soft-fail for legacy table to avoid blocking flow
      console.warn('admin_users insert failed', adminError);
    }
  }

  return { userId: data.user.id, email };
};

export const sendPasswordReset = async (email: string): Promise<void> => {
  if (!email) throw new Error("Email is required");

  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${window.location.origin}/admin-login`,
  });

  if (error) {
    throw new Error(error.message);
  }
};


