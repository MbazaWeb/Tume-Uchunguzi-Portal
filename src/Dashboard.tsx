import {useEffect,useState} from 'react';
import {Link,useNavigate} from 'react-router';
import {ArrowRight,FileText,ShieldCheck} from 'lucide-react';
import {supabase} from './lib/supabase';
import {useLanguage} from './lib/language';

export default function Dashboard(){
  const navigate=useNavigate();
  const {t}=useLanguage();
  const [loading,setLoading]=useState(true);
  const [user,setUser]=useState<any>(null);
  const [displayName,setDisplayName]=useState<string>('');

  useEffect(()=>{
    supabase.auth.getUser().then(async ({data})=>{
      if(!data.user){navigate('/account?mode=login',{replace:true});return}
      setUser(data.user);

      // 1) Jaribu display_name kutoka auth metadata (inawekwa wakati wa signup)
      let name = data.user.user_metadata?.display_name || '';

      // 2) Kama haipo, jaribu profiles table
      if(!name){
        const {data:profile} = await supabase
          .from('profiles')
          .select('display_name,full_name')
          .eq('id',data.user.id)
          .maybeSingle();
        name = profile?.display_name || profile?.full_name || '';
      }

      // 3) Fallback: sehemu ya mwanzo ya email (kabla ya @)
      if(!name) name = (data.user.email || '').split('@')[0];

      setDisplayName(name);
      setLoading(false);
    });
  },[navigate]);

  if(loading)return <section className="section page"><h1 className="pageTitle">{t('Inapakia...','Loading...')}</h1></section>;

  return <section className="section page">
    <span className="kicker">{t('DASHBOARD YAKO','YOUR DASHBOARD')}</span>
    <h1 className="pageTitle">{t('Karibu','Welcome')}, {displayName}</h1>
    <p className="lead">{t('Chagua hatua inayofuata.','Choose your next action.')}</p>
    <div className="commissionInfoGrid" style={{marginTop:'2rem'}}>
      <article>
        <FileText/>
        <h3>{t('Wasilisha taarifa','Submit information')}</h3>
        <p>{t('Wasilisha taarifa mpya kwa Tume.','Submit a new report to the Commission.')}</p>
        <Link className="primary linkBtn" to="/toa-taarifa">{t('Anza','Start')} <ArrowRight size={16}/></Link>
      </article>
      <article>
        <ShieldCheck/>
        <h3>{t('Taarifa zangu','My submissions')}</h3>
        <p>{t('Fuatilia hali ya taarifa ulizowasilisha.','Track the status of your submissions.')}</p>
        <Link className="primary linkBtn" to="/taarifa-zangu">{t('Ona','View')} <ArrowRight size={16}/></Link>
      </article>
    </div>
    <button className="secondary linkBtn" style={{marginTop:'2rem'}} onClick={async()=>{await supabase.auth.signOut();navigate('/',{replace:true})}}>
      {t('Toka','Sign out')}
    </button>
  </section>;
}