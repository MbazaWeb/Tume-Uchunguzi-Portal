import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.VITE_TUME_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error('Missing VITE_TUME_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const DEMO = {
  email: 'demo@tume.local',
  password: 'DemoTume2026!',
  email_confirm: true,
  user_metadata: {
    role: 'demo',
    full_name: 'Demo User',
    is_demo: true,
  },
};

const { data, error } = await admin.auth.admin.createUser(DEMO);

if (error) {
  console.error('Failed:', error.message);
  process.exit(1);
}

console.log('Demo user created:');
console.log('  Email:   ', DEMO.email);
console.log('  Password:', DEMO.password);
console.log('  ID:      ', data.user.id);