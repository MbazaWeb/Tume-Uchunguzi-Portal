import {createClient} from '@supabase/supabase-js';

// This application must use its own Tume Uchunguzi Supabase project.
// Configure VITE_TUME_SUPABASE_URL and VITE_TUME_SUPABASE_PUBLISHABLE_KEY in Vercel.
// Never fall back to the Katiba Yetu project or commit private credentials.
const supabaseUrl=import.meta.env.VITE_TUME_SUPABASE_URL||'https://tume-supabase-not-configured.invalid';
const supabasePublishableKey=import.meta.env.VITE_TUME_SUPABASE_PUBLISHABLE_KEY||'tume-public-key-not-configured';

export const supabase=createClient(supabaseUrl,supabasePublishableKey,{
  auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}
});
