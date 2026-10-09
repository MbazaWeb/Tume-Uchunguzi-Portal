import {createClient} from '@supabase/supabase-js';

export const supabaseUrl=import.meta.env.VITE_SUPABASE_URL||'https://xckqpkymphvhxgxyolpz.supabase.co';
export const supabasePublishableKey=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY||'sb_publishable_R3zZMxZL76iEAYAkhxzhVA_XK7S3iEU';

export const supabase=createClient(supabaseUrl,supabasePublishableKey,{
  auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}
});
