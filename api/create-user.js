const { createClient } = require('@supabase/supabase-js');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceRoleKey) {
    return res.status(500).json({ error: 'SUPABASE_SERVICE_ROLE_KEY not configured' });
  }

  const supabaseUrl = 'https://pwhrtvfzeoahqpdjyssg.supabase.co';
  const sbAdmin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  });

  try {
    const { email, password, name, role, color, targetH, username } = req.body;

    if (!email || !password || !name) {
      return res.status(400).json({ error: 'email, password, and name are required' });
    }

    // Create auth user
    const { data: authData, error: authError } = await sbAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });

    if (authError) {
      return res.status(400).json({ error: authError.message });
    }

    // Create profile
    const { data: profile, error: profError } = await sbAdmin.from('profiles').insert({
      id: authData.user.id,
      name,
      username: username || email.split('@')[0],
      role: role || 'member',
      color: color || '#60a5fa',
      target_h: targetH || 0,
    }).select().single();

    if (profError) {
      // Try to clean up the auth user if profile creation fails
      await sbAdmin.auth.admin.deleteUser(authData.user.id);
      return res.status(400).json({ error: profError.message });
    }

    return res.status(200).json({ success: true, userId: authData.user.id, profile });
  } catch (err) {
    console.error('create-user error:', err);
    return res.status(500).json({ error: err.message || 'Internal server error' });
  }
};
