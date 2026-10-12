import {useEffect,useState} from 'react';
import {useNavigate} from 'react-router';
import {supabase} from './lib/supabase';
import {useLanguage} from './lib/language';
import Dashboard from './Dashboard';

// ==========================================================
// RoleBasedDashboard — entry point kwa /dashboard
// Redirects staff to their dashboards; shows citizen dashboard kwa citizen.
// ==========================================================
export default function RoleBasedDashboard(){
  const navigate = useNavigate();
  const {t} = useLanguage();
  const [checking, setChecking] = useState(true);
  const [role, setRole] = useState<string | null>(null);

  useEffect(() => {
    async function check(){
      const {data:{user}} = await supabase.auth.getUser();
      if(!user){
        // Hajalogin — citizen dashboard ina-handle redirect
        setChecking(false);
        return;
      }
      const {data:profile} = await supabase
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

      const userRole = profile?.role || 'citizen';
      setRole(userRole);

      // Redirect staff kwa dashboards zao
      if(userRole === 'admin'){
        navigate('/admin', {replace:true});
        return;
      }
      if(userRole === 'reviewer'){
        navigate('/workflow', {replace:true});
        return;
      }
      if(userRole === 'committee'){
        navigate('/committee', {replace:true});
        return;
      }

      // Citizen — endelea kuonyesha citizen dashboard
      setChecking(false);
    }
    check();
  }, [navigate]);

  if(checking){
    return <section className="section page">
      <h1 className="pageTitle">{t('Inapakia...','Loading...')}</h1>
    </section>;
  }

  // Citizen dashboard (au kama hajalogin, Dashboard ina-handle)
  return <Dashboard/>;
}