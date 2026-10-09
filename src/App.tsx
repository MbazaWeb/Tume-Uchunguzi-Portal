import {useEffect,useState} from 'react';
import {NavLink,Outlet,useLocation} from 'react-router';
import {Menu,X,ShieldCheck} from 'lucide-react';
import {supabase} from './lib/supabase';
import {AppLanguage,LanguageContext} from './lib/language';
import './lib/authVisibility';

const nav=[['/','Tume','Commission'],['/toa-taarifa','Wasilisha Taarifa','Submit Information'],['/taarifa-zangu','Taarifa Zangu','My Submissions']];
export default function App(){
  const location=useLocation();
  const [session,setSession]=useState<any>(null);
  const [userRole,setUserRole]=useState<string|null>(null);
  const [mobileOpen,setMobileOpen]=useState(false);
  const [language,setLanguageState]=useState<AppLanguage>(()=>localStorage.getItem('tume-language')==='en'?'en':'sw');
  const [theme,setTheme]=useState<'light'|'dark'>(()=>{const saved=localStorage.getItem('tume-theme');return saved==='light'||saved==='dark'?saved:'light'});
  const setLanguage=(v:AppLanguage)=>{setLanguageState(v);localStorage.setItem('tume-language',v);document.documentElement.lang=v};
  const t=<T,>(sw:T,en:T):T=>language==='sw'?sw:en;
  const isAdminArea=location.pathname==='/admin'||location.pathname.startsWith('/admin/');
  useEffect(()=>{
    async function syncAuth(next:any){
      setSession(next);
      if(!next?.user){setUserRole(null);return}
      const {data}=await supabase.from('profiles').select('role').eq('id',next.user.id).maybeSingle();
      setUserRole(data?.role||null);
    }
    supabase.auth.getSession().then(({data})=>syncAuth(data.session));
    const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,next)=>syncAuth(next));
    return()=>subscription.unsubscribe();
  },[]);
  useEffect(()=>{document.documentElement.lang=language},[language]);
  useEffect(()=>{document.documentElement.dataset.theme=theme;document.documentElement.style.colorScheme=theme;localStorage.setItem('tume-theme',theme)},[theme]);
  useEffect(()=>setMobileOpen(false),[location.pathname]);
  async function logout(){await supabase.auth.signOut();setSession(null);setUserRole(null)}
  return <LanguageContext.Provider value={{language,setLanguage,t}}>
    <div className={'app '+(isAdminArea?'staffApp':'')}>
      <header className={'nav '+(isAdminArea?'adminNav':'')}>
        <NavLink to="/" className="brand"><div className="mark officialMark"><ShieldCheck size={24}/></div><div><strong>TUME YA UCHUNGUZI</strong><span>{t('PORTALI YA TAARIFA ZA UCHUNGUZI','INQUIRY REPORTING PORTAL')}</span></div></NavLink>
        <nav>{nav.map(([to,sw,en])=><NavLink key={to} to={to} end={to==='/'}>{t(sw,en)}</NavLink>)}</nav>
        <div className="navActions">
          <button className="ghost languageSwitch headerLanguage" onClick={()=>setLanguage(language==='sw'?'en':'sw')}><b>{language.toUpperCase()}</b> / {language==='sw'?'EN':'SW'}</button>
          {userRole==='admin'&&<NavLink className="headerAdminLink" to="/admin">{t('Admin','Admin')}</NavLink>}
          <NavLink className="headerAccountLink" to="/account">{session?.user?t('Akaunti','Account'):t('Ingia','Sign in')}</NavLink>
          <button className="mobileMenuBtn" onClick={()=>setMobileOpen(v=>!v)} aria-label={t('Fungua menyu','Open menu')}>{mobileOpen?<X size={21}/>:<Menu size={21}/>}</button>
        </div>
      </header>
      {mobileOpen&&<div className="menuBackdrop" onClick={()=>setMobileOpen(false)}><div className="mobileNav" onClick={e=>e.stopPropagation()}><nav>{nav.map(([to,sw,en])=><NavLink key={to} to={to} end={to==='/'}>{t(sw,en)}</NavLink>)}</nav>{userRole==='admin'&&<NavLink to="/admin">{t('Admin','Admin')}</NavLink>}{session?.user&&<button className="menuLogout" onClick={logout}>{t('Toka','Sign out')}</button>}</div></div>}
      <main><Outlet/></main>
      <footer className="siteFooter"><div className="footerBrand"><strong>TUME YA UCHUNGUZI</strong><p>{t('Portal ya kupokea na kufuatilia taarifa zinazohusiana na uchunguzi wa matukio ya Oktoba 2025.','Portal for receiving and tracking information related to the inquiry into events of October 2025.')}</p><span>Development by <b>PlayGO Tanzania</b></span></div><div className="footerLinks"><b>{t('Viungo Muhimu','Useful Links')}</b><NavLink to="/toa-taarifa">{t('Wasilisha Taarifa','Submit Information')}</NavLink><NavLink to="/taarifa-zangu">{t('Taarifa Zangu','My Submissions')}</NavLink><a href="https://www.tume.uchunguzi.go.tz/" target="_blank" rel="noreferrer">{t('Tovuti rasmi ya Tume','Official Commission website')}</a></div><div className="footerLinks"><b>{t('Akaunti','Account')}</b><NavLink to="/account">{t('Ingia / Akaunti','Sign in / Account')}</NavLink></div><p className="legal">{t('Taarifa zako zinapaswa kushughulikiwa kwa usiri na watumishi walioidhinishwa pekee.','Your reports must be handled confidentially and only by authorized personnel.')}</p></footer>
    </div>
  </LanguageContext.Provider>
}
