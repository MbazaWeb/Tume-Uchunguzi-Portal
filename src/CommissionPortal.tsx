import {FormEvent,useEffect,useRef,useState} from 'react';
import {createPortal} from 'react-dom';
import {Link,useSearchParams} from 'react-router';
import {ArrowRight,CheckCircle2,Eye,EyeOff,ExternalLink,FileText,LockKeyhole,MapPin,Moon,ShieldCheck,Sun,Upload,Users} from 'lucide-react';
import {Upload as TusUpload} from 'tus-js-client';
import {supabase,supabasePublishableKey,supabaseUrl} from './lib/supabase';
import {useLanguage} from './lib/language';
import './commission.css';

const commissionUrl='https://www.tume.uchunguzi.go.tz/';
const evidenceTypes=['application/pdf','image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime'];
const maxFileBytes=50*1024*1024;

export function AccountAccessPage(){
  const {t}=useLanguage();
  const [searchParams,setSearchParams]=useSearchParams();
  const [mode,setMode]=useState<'login'|'signup'>(()=>searchParams.get('mode')==='signup'?'signup':'login');
  const [session,setSession]=useState<any>(undefined);
  const [busy,setBusy]=useState(false);
  const [message,setMessage]=useState('');
  const [showPassword,setShowPassword]=useState(false);
  const [headerActions,setHeaderActions]=useState<HTMLElement|null>(null);
  const [theme,setTheme]=useState<'light'|'dark'>(()=>{
    const saved=localStorage.getItem('tume-theme');
    if(saved==='light'||saved==='dark')return saved;
    return window.matchMedia?.('(prefers-color-scheme: dark)').matches?'dark':'light';
  });
  useEffect(()=>{
    setHeaderActions(document.querySelector<HTMLElement>('.navActions'));
    const observer=new MutationObserver(()=>setTheme(document.documentElement.dataset.theme==='dark'?'dark':'light'));
    observer.observe(document.documentElement,{attributes:true,attributeFilter:['data-theme']});
    return()=>observer.disconnect();
  },[]);
  useEffect(()=>{setMode(searchParams.get('mode')==='signup'?'signup':'login')},[searchParams]);
  useEffect(()=>{supabase.auth.getSession().then(({data})=>setSession(data.session));const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,next)=>setSession(next));return()=>subscription.unsubscribe()},[]);
  function toggleTheme(){
    const next=theme==='dark'?'light':'dark';
    setTheme(next);localStorage.setItem('tume-theme',next);document.documentElement.dataset.theme=next;document.documentElement.style.colorScheme=next;
  }
  function changeMode(next:'login'|'signup'){
    setMode(next);setMessage('');setShowPassword(false);setSearchParams(next==='signup'?{mode:'signup'}:{mode:'login'});
  }
  async function submitAuth(e:FormEvent<HTMLFormElement>){
    e.preventDefault();setBusy(true);setMessage('');
    const form=new FormData(e.currentTarget),email=String(form.get('email')||'').trim().toLowerCase(),password=String(form.get('password')||'');
    if(mode==='signup'){
      const display_name=String(form.get('name')||'').trim(),mobile=String(form.get('mobile')||'').trim();
      const {data,error}=await supabase.auth.signUp({email,password,options:{data:{display_name,mobile,account_type:'individual'},emailRedirectTo:window.location.origin+'/account'}});
      if(error)setMessage(error.message);
      else setMessage(data.session?t('Akaunti imeundwa na umeingia moja kwa moja.','Your account is ready and you are signed in.'):t('Akaunti imeundwa. Angalia barua pepe yako ikiwa uthibitisho unahitajika.','Your account has been created. Check your email if confirmation is required.'));
    }else{
      const {error}=await supabase.auth.signInWithPassword({email,password});
      if(error)setMessage(error.message==='Invalid login credentials'?t('Barua pepe au nenosiri si sahihi.','Email or password is incorrect.'):error.message);
      else setMessage(t('Umeingia kikamilifu.','You are signed in.'));
    }
    setBusy(false);
  }
  return <>
    {headerActions&&createPortal(<button type="button" className="ghost themeHeader" onClick={toggleTheme} aria-label={theme==='dark'?t('Badili kwenda mwanga','Switch to light theme'):t('Badili kwenda giza','Switch to dark theme')} title={theme==='dark'?t('Mwanga','Light'):t('Giza','Dark')}>{theme==='dark'?<Sun size={16}/>:<Moon size={16}/>}<span>{theme==='dark'?t('Mwanga','Light'):t('Giza','Dark')}</span></button>,headerActions)}
    {session===undefined?<section className="section page accountAuthLoading"><h1 className="pageTitle">{t('Inapakia...','Loading...')}</h1></section>:session?.user?<section className="section page"><span className="kicker">{t('AKAUNTI YA TUME','COMMISSION ACCOUNT')}</span><h1 className="pageTitle">{t('Akaunti yako','Your account')}</h1><p className="lead">{session.user.email}</p><div className="authShell"><div className="authIntro"><ShieldCheck/><h2>{t('Akaunti ya Tume ya Uchunguzi','Commission of Inquiry account')}</h2><p>{t('Tumia akaunti hii kuwasilisha taarifa na kufuatilia taarifa zako.','Use this account to submit information and track your submissions.')}</p></div><div className="authForm"><Link className="primary linkBtn" to="/toa-taarifa">{t('Wasilisha taarifa','Submit information')} <ArrowRight size={17}/></Link><Link className="secondary linkBtn" to="/taarifa-zangu">{t('Taarifa zangu','My submissions')} <ArrowRight size={17}/></Link><button type="button" className="authSwitch" onClick={async()=>{await supabase.auth.signOut();setSession(null);setMessage(t('Umetoka kwenye akaunti.','You have signed out.'))}}>{t('Toka kwenye akaunti','Sign out')}</button>{message&&<div className="authMessage" role="status">{message}</div>}</div></div></section>:<section className="section page"><span className="kicker">{t('UTAMBULISHO','ACCOUNT ACCESS')}</span><h1 className="pageTitle">{mode==='login'?t('Ingia','Login'):t('Jisajili','Sign up')}</h1><div className="authShell"><div className="authIntro"><div className="authOfficialLogo"><img src="https://www.tume.uchunguzi.go.tz/site/images/emblem.webp" alt={t('Nembo ya Tume ya Uchunguzi','Commission emblem')}/><div><strong>{t('TUME YA UCHUNGUZI','COMMISSION OF INQUIRY')}</strong><span>{t('PORTALI YA WANANCHI','CITIZEN PORTAL')}</span></div></div><ShieldCheck/><h2>{t('Akaunti ya Tume','Commission account')}</h2><p>{t('Ingia au jisajili ili kuwasilisha taarifa kwa Tume na kufuatilia hatua zake kwa faragha.','Sign in or create an account to submit information to the Commission and privately track its progress.')}</p></div><form className="authForm" onSubmit={submitAuth}>{mode==='signup'&&<><label>{t('Jina la kuonyesha','Display name')}<input name="name" required autoComplete="name"/></label><label>{t('Namba ya simu','Phone number')}<input name="mobile" type="tel" required autoComplete="tel" placeholder="07XXXXXXXX"/></label></>}<label>{t('Barua pepe','Email address')}<input name="email" type="email" required autoComplete="email"/></label><label>{t('Nenosiri','Password')}<div className="passwordField"><input name="password" type={showPassword?'text':'password'} required minLength={6} autoComplete={mode==='login'?'current-password':'new-password'}/><button type="button" className="passwordToggle" onClick={()=>setShowPassword(value=>!value)} aria-label={showPassword?t('Ficha nenosiri','Hide password'):t('Onyesha nenosiri','Show password')}>{showPassword?<EyeOff size={16}/>:<Eye size={16}/>}<span>{showPassword?t('Ficha','Hide'):t('Onyesha','Show')}</span></button></div></label>{message&&<div className="authMessage" role="status">{message}</div>}<button className="primary" disabled={busy}>{busy?(mode==='login'?t('Inaingia...','Signing in...'):t('Inatengeneza akaunti...','Creating account...')):mode==='login'?t('Ingia','Sign in'):t('Tengeneza akaunti','Create account')}</button><button type="button" className="authSwitch" onClick={()=>changeMode(mode==='login'?'signup':'login')}>{mode==='login'?t('Huna akaunti? Jisajili','New here? Create an account'):t('Tayari una akaunti? Ingia','Already have an account? Sign in')}</button></form></div></section>}
  </>;
}

declare global {
  interface Window {
    turnstile?: {
      render:(container:HTMLElement,options:Record<string,unknown>)=>string;
      remove:(widgetId:string)=>void;
    };
  }
}

export function CommissionHomePage(){
  const [isAdmin,setIsAdmin]=useState(false);
  const [signedIn,setSignedIn]=useState(false);
  useEffect(()=>{let live=true;async function sync(session:any){setSignedIn(Boolean(session?.user));if(!session?.user){setIsAdmin(false);return}const {data:profile}=await supabase.from('profiles').select('role').eq('id',session.user.id).maybeSingle();if(live)setIsAdmin(profile?.role==='admin')}supabase.auth.getSession().then(({data})=>sync(data.session));const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,session)=>sync(session));return()=>{live=false;subscription.unsubscribe()}},[]);
  const commissioners=['Jaji Shaban Ally Lila, Mwenyekiti','Justice Petrus Tileinge Damaseb','Awadh Mohamed Bawazir','Aishiel Nelson Sumari','Barishaki Bonny Cheborion','Gad John Mjemmas'];
  return <div className="commissionHome" style={{background:'#fff'}}>
    <section className="commissionHero">
      <div className="commissionHeroCopy">
        <span className="commissionEyebrow"><ShieldCheck size={15}/> Jamhuri ya Muungano wa Tanzania</span>
        <h1>Tume ya Uchunguzi</h1>
        <p className="commissionMandate">Kuchunguza wahusika na ukiukwaji wa sheria wakati na baada ya Uchaguzi Mkuu Oktoba 2025.</p>
        <p className="commissionIntro">Portal hii ni njia ya wananchi kushiriki katika uchunguzi kwa kuwasilisha maelezo, nyaraka na ushahidi unaohusiana na matukio yanayochunguzwa.</p>
        <div className="commissionActions">
          <Link className="primary linkBtn" to="/toa-taarifa">Wasilisha taarifa <ArrowRight size={17}/></Link>
          <a className="secondary linkBtn" href={commissionUrl} target="_blank" rel="noreferrer">Tovuti rasmi ya Tume <ExternalLink size={15}/></a>
        </div>
        <div className="commissionContactLine"><a href="mailto:barua@tume.uchunguzi.go.tz">barua@tume.uchunguzi.go.tz</a><a href="tel:+255737305449">+255 737 305449</a></div>
      </div>
      <aside className="commissionHeroAside">
        <div className="commissionSeal"><img src="https://www.tume.uchunguzi.go.tz/site/images/emblem.webp" alt="Nembo ya Tume ya Uchunguzi"/></div>
        <span>UCHUNGUZI · OKTOBA 2025</span>
        <h2>Sauti na ushahidi wako ni muhimu.</h2>
        <p>Ingia au jisajili ili kuwasilisha maelezo kwa siri na kufuatilia hatua za taarifa zako.</p>
        <Link to={signedIn?'/toa-taarifa':'/account?mode=signup'}>{signedIn?'Wasilisha taarifa':'Jisajili kuanza'} <ArrowRight size={16}/></Link>
      </aside>
    </section>

    <section className="commissionSection commissionMembers">
      <div className="commissionSectionHeading"><span className="kicker">AKAUNTI YA MWANANCHI</span><h2>{signedIn?'Endelea na taarifa zako':'Ingia au jisajili kushiriki'}</h2><p>{signedIn?'Wasilisha taarifa mpya au kagua hali ya taarifa ulizowasilisha kwa Tume.':'Akaunti yako itakuwezesha kuwasilisha taarifa na kufuatilia hatua zake kwa faragha.'}</p></div>
      <div className="commissionActions">{signedIn?<><Link className="primary linkBtn" to="/toa-taarifa">Wasilisha taarifa <ArrowRight size={17}/></Link><Link className="secondary linkBtn" to="/taarifa-zangu">Taarifa zangu <ArrowRight size={17}/></Link></>:<><Link className="primary linkBtn" to="/account?mode=signup">Jisajili <ArrowRight size={17}/></Link><Link className="secondary linkBtn" to="/account?mode=login">Ingia kwenye akaunti <ArrowRight size={17}/></Link></>}</div>
    </section>

    <section className="commissionSection commissionHow">
      <div className="commissionSectionHeading"><span className="kicker">USHIRIKI WA WANANCHI</span><h2>Unachoweza kuwasilisha</h2><p>Taarifa zinazohusiana na matukio yanayochunguzwa na Tume.</p></div>
      <div className="commissionInfoGrid">
        <article><FileText/><h3>Simulizi na maelezo</h3><p>Eleza ulichokiona, ulichosikia au unachokijua. Taja mahali, tarehe na muktadha kadiri unavyoweza.</p></article>
        <article><Upload/><h3>Nyaraka na ushahidi</h3><p>Ambatisha nyaraka za PDF, picha au video zinazohusiana na maelezo yako.</p></article>
        <article><LockKeyhole/><h3>Uwasilishaji wa siri</h3><p>Jina na mawasiliano ni hiari. Taarifa na viambatisho vinaonekana kwa wasimamizi walioidhinishwa pekee.</p></article>
      </div>
    </section>

    <section className="commissionSection commissionProcess">
      <div><span className="kicker">JINSI YA KUSHIRIKI</span><h2>Hatua tatu rahisi</h2></div>
      <ol><li><b>01</b><span><strong>Andika taarifa</strong><small>Eleza tukio, eneo na tarehe.</small></span></li><li><b>02</b><span><strong>Ambatisha ushahidi</strong><small>PDF, picha au video hadi MB 50 kwa faili.</small></span></li><li><b>03</b><span><strong>Wasilisha kwa Tume</strong><small>Utapokea namba ya kumbukumbu baada ya kukamilisha.</small></span></li></ol>
      <div className="commissionPrivacy"><LockKeyhole size={19}/><p><b>Faragha ya taarifa</b><br/>Usiweke taarifa za siri au za watu wengine ambazo si muhimu kwa uchunguzi. Taarifa za uwasilishaji hazitaonekana hadharani; zitapitiwa na wasimamizi wa Tume.</p></div>
    </section>

    <section className="commissionSection commissionMembers">
      <div className="commissionSectionHeading"><span className="kicker">KAMISHNA</span><h2>Uongozi wa Tume</h2></div>
      <div className="commissionPeople">{commissioners.map((name,index)=><div key={name}><Users size={16}/><span>{name}</span>{index===0&&<small>Mwenyekiti wa Tume</small>}</div>)}</div>
      <a className="commissionOfficialLink" href={commissionUrl+'administration/management-team'} target="_blank" rel="noreferrer">Tazama taarifa rasmi za makamishna <ExternalLink size={14}/></a>
    </section>

    <section className="commissionFooterBand"><div><MapPin size={18}/><span>P.O. Box 471, Dar es Salaam, Tanzania</span></div><div><a href="mailto:barua@tume.uchunguzi.go.tz">barua@tume.uchunguzi.go.tz</a><a href="tel:+255737305449">+255 737 305449</a></div><a href={commissionUrl} target="_blank" rel="noreferrer">Chanzo rasmi: tume.uchunguzi.go.tz <ExternalLink size={14}/></a>{isAdmin&&<Link to="/admin/inquiries">Kagua taarifa zilizowasilishwa <ArrowRight size={14}/></Link>}</section>
  </div>;
}

export function InquirySubmissionPage(){
  const [user,setUser]=useState<any>(undefined);
  const siteKey=import.meta.env.VITE_TURNSTILE_SITE_KEY||'';
  const widgetHost=useRef<HTMLDivElement>(null);
  const widgetId=useRef('');
  const [captchaToken,setCaptchaToken]=useState('');
  const [files,setFiles]=useState<File[]>([]);
  const [busy,setBusy]=useState(false);
  const [message,setMessage]=useState('');
  const [reference,setReference]=useState('');

  useEffect(()=>{supabase.auth.getUser().then(({data})=>setUser(data.user||null));const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,session)=>setUser(session?.user||null));return()=>subscription.unsubscribe()},[]);

  useEffect(()=>{
    if(!siteKey||!widgetHost.current)return;
    const existing=document.querySelector<HTMLScriptElement>('script[data-inquiry-turnstile]');
    const script=existing||document.createElement('script');
    const render=()=>{
      if(!widgetHost.current||!window.turnstile||widgetId.current)return;
      widgetId.current=window.turnstile.render(widgetHost.current,{sitekey:siteKey,callback:(token:string)=>setCaptchaToken(token),'expired-callback':()=>setCaptchaToken(''),'error-callback':()=>setCaptchaToken('')});
    };
    if(!existing){script.src='https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';script.async=true;script.defer=true;script.dataset.inquiryTurnstile='true';script.addEventListener('load',render);document.head.appendChild(script)}else if(window.turnstile)render();else script.addEventListener('load',render);
    return()=>{script.removeEventListener('load',render);if(widgetId.current&&window.turnstile){window.turnstile.remove(widgetId.current);widgetId.current=''}};
  },[siteKey]);

  function selectFiles(list:FileList|null){
    const selected=Array.from(list||[]);
    if(selected.length>5){setMessage('Unaweza kuchagua hadi faili 5.');return}
    if(selected.some(file=>!evidenceTypes.includes(file.type)||file.size>maxFileBytes)){setMessage('Tumia PDF, JPG, PNG, WebP, MP4, WebM au MOV. Kila faili liwe chini ya MB 50.');return}
    setMessage('');setFiles(selected);
  }

  async function submit(e:FormEvent<HTMLFormElement>){
    e.preventDefault();
    if(!user){setMessage('Ingia kwenye akaunti yako ili kuwasilisha taarifa.');return}
    if(!captchaToken){setMessage('Thibitisha kuwa wewe si roboti kabla ya kuwasilisha.');return}
    const form=e.currentTarget;
    const data=new FormData(form);
    if(String(data.get('website')||'').trim())return;
    setBusy(true);setMessage('');
    const report={fullName:String(data.get('fullName')||'').trim(),contact:String(data.get('contact')||'').trim(),incidentDate:String(data.get('incidentDate')||''),region:String(data.get('region')||'').trim(),district:String(data.get('district')||'').trim(),location:String(data.get('location')||'').trim(),description:String(data.get('description')||'').trim()};
    const {data:created,error:createError}=await supabase.functions.invoke('inquiry-intake',{body:{action:'create',turnstileToken:captchaToken,website:'',report,attachments:files.map(file=>({name:file.name,size:file.size,type:file.type}))}});
    if(createError||!created?.id||!Array.isArray(created.uploads)){setMessage('Imeshindikana kuanza uwasilishaji. Jaribu tena au wasiliana na Tume kupitia barua pepe rasmi.');setBusy(false);return}
    const storageBase=new URL(supabaseUrl);
    storageBase.hostname=storageBase.hostname.replace('.supabase.co','.storage.supabase.co');
    for(let index=0;index<files.length;index++){
      const file=files[index],upload=created.uploads[index];
      try{
        await new Promise<void>((resolve,reject)=>{
          const tusUpload=new TusUpload(file,{endpoint:new URL('/storage/v1/upload/resumable',storageBase).toString(),headers:{apikey:supabasePublishableKey,'x-signature':upload.token},metadata:{bucketName:'inquiry-evidence',objectName:upload.path,contentType:file.type,cacheControl:'3600'},chunkSize:6*1024*1024,retryDelays:[0,3000,5000,10000,20000],uploadDataDuringCreation:true,removeFingerprintOnSuccess:true,onError:reject,onSuccess:()=>resolve()});
          tusUpload.start();
        });
      }catch{setMessage('Faili halikupakiwa kikamilifu. Tafadhali jaribu tena au wasiliana na Tume.');setBusy(false);return}
    }
    const {data:finalized,error:finalizeError}=await supabase.functions.invoke('inquiry-intake',{body:{action:'finalize',id:created.id}});
    if(finalizeError||!finalized?.referenceCode){setMessage('Taarifa zimepokelewa lakini uthibitisho haujakamilika. Tafadhali wasiliana na Tume ukitumia namba '+created.referenceCode+'.');setBusy(false);return}
    setReference(finalized.referenceCode);setFiles([]);setCaptchaToken('');form.reset();setBusy(false);
  }

  if(user===undefined)return <section className="section page inquiryPage"><h1 className="pageTitle">Inathibitisha akaunti...</h1></section>;
  if(!user)return <section className="section page inquiryPage"><span className="kicker">AKAUNTI INAHITAJIKA</span><h1 className="pageTitle">Ingia ili kuwasilisha taarifa</h1><p className="lead">Taarifa utakazowasilisha zitaunganishwa na akaunti yako, ili uweze kufuatilia hatua zake baadaye.</p><div className="commissionActions"><Link className="primary linkBtn" to="/account?mode=login">Ingia <ArrowRight size={17}/></Link><Link className="secondary linkBtn" to="/account?mode=signup">Jisajili <ArrowRight size={17}/></Link></div></section>;
  return <section className="section page inquiryPage">
    <span className="kicker">USHIRIKI WA WANANCHI</span><h1 className="pageTitle">Wasilisha taarifa kwa Tume</h1>
    <p className="lead">Toa maelezo kuhusu tukio linalohusiana na uchunguzi. Taarifa itaunganishwa na akaunti yako ili uweze kuifuatilia.</p>
    {reference?<div className="inquirySuccess"><CheckCircle2/><div><span>TAARIFA IMEWASILISHWA</span><h2>{reference}</h2><p>Hifadhi namba hii kwa marejeo. Uwasilishaji wako hautaonekana hadharani kwenye portal.</p><Link to="/">Rudi mwanzo</Link></div></div>:<form className="inquiryForm" onSubmit={submit}>
      <div className="inquiryFormIntro"><LockKeyhole size={19}/><p><b>Uwasilishaji wa siri</b><br/>Maelezo na faili zako hazitaonyeshwa hadharani. Wasimamizi wa Tume walioidhinishwa pekee ndio wanaoweza kuzikagua.</p></div>
      <label>Maelezo ya tukio<textarea name="description" required minLength={50} maxLength={10000} placeholder="Eleza kilichotokea, ulichokiona au unachokijua. Jumuisha tarehe na eneo kadiri iwezekanavyo."/></label>
      <div className="inquiryFormTwo"><label>Tarehe ya tukio<input name="incidentDate" type="date" required max={new Date().toISOString().slice(0,10)}/></label><label>Mkoa<input name="region" required maxLength={100} placeholder="Mfano: Dar es Salaam"/></label></div>
      <div className="inquiryFormTwo"><label>Wilaya<input name="district" maxLength={100}/></label><label>Eneo au mahali<input name="location" maxLength={500} placeholder="Mtaa, kituo au alama ya eneo"/></label></div>
      <details className="inquiryOptional"><summary>Taarifa zako (hiari)</summary><div className="inquiryFormTwo"><label>Jina<input name="fullName" maxLength={160} autoComplete="name"/></label><label>Simu au barua pepe<input name="contact" maxLength={160} autoComplete="email"/></label></div><small>Ukiacha mawasiliano, Tume haitaweza kukuuliza maswali ya ufafanuzi.</small></details>
      <label className="inquiryFilePicker"><span><Upload size={18}/><b>Ambatisha ushahidi</b><small>PDF, picha au video. Hadi faili 5, MB 50 kila moja.</small></span><input type="file" accept=".pdf,.jpg,.jpeg,.png,.webp,.mp4,.webm,.mov,application/pdf,image/jpeg,image/png,image/webp,video/mp4,video/webm,video/quicktime" multiple onChange={e=>selectFiles(e.target.files)}/></label>
      {files.length>0&&<ul className="inquiryFileList">{files.map(file=><li key={file.name+file.lastModified}>{file.name}<small>{(file.size/1024/1024).toFixed(1)} MB</small></li>)}</ul>}
      <label className="inquiryHoneypot" aria-hidden="true">Website<input name="website" tabIndex={-1} autoComplete="off"/></label>
      {siteKey?<div className="inquiryCaptcha" ref={widgetHost}/>:<div className="inquirySetupNotice">Uwasilishaji wa mtandaoni utawezeshwa baada ya kusanidi ulinzi wa faragha wa portal.</div>}
      {message&&<div className="authMessage" role="alert">{message}</div>}
      <button className="primary inquirySubmit" disabled={busy||!siteKey||!captchaToken}>{busy?'Inatuma taarifa...':'Wasilisha taarifa kwa siri'} <ArrowRight size={17}/></button>
      <small className="inquiryDisclaimer">Kwa taarifa rasmi kuhusu Tume, tembelea <a href={commissionUrl} target="_blank" rel="noreferrer">tume.uchunguzi.go.tz</a> au piga +255 737 305449.</small>
    </form>}
  </section>;
}

export function InquiryTrackingPage(){
  const {t}=useLanguage();
  const [user,setUser]=useState<any>(undefined);
  const [rows,setRows]=useState<any[]>([]);
  const [loading,setLoading]=useState(true);
  const [message,setMessage]=useState('');
  const [expandedRow,setExpandedRow]=useState<string|null>(null);
  const [followups,setFollowups]=useState<Record<string,any[]>>({});
  const [draftFollowup,setDraftFollowup]=useState<Record<string,string>>({});
  const [extraFiles,setExtraFiles]=useState<Record<string,File|null>>({});
  const [submittingFollowup,setSubmittingFollowup]=useState<string>('');
  useEffect(()=>{let live=true;(async()=>{const {data:{user:currentUser}}=await supabase.auth.getUser();if(!live)return;setUser(currentUser||null);if(!currentUser){setLoading(false);return}const {data,error}=await supabase.from('inquiry_submissions').select('id,reference_code,incident_date,region,district,location,description,attachments,status,review_note,created_at,reviewed_at').eq('user_id',currentUser.id).neq('status','uploading').order('created_at',{ascending:false}).limit(100);if(!live)return;if(error)setMessage(t('Imeshindikana kupakia taarifa zako. Jaribu tena baadaye.','Could not load your reports. Try again later.'));else setRows(data||[]);setLoading(false)})();return()=>{live=false}},[]);
  async function openEvidence(path:string){const {data,error}=await supabase.storage.from('inquiry-evidence').createSignedUrl(path,120);if(error||!data?.signedUrl)setMessage(t('Imeshindikana kufungua kiambatisho.','Could not open attachment.'));else window.open(data.signedUrl,'_blank','noopener,noreferrer')}
  async function toggleExpand(rowId:string){
    if(expandedRow===rowId){setExpandedRow(null);return}
    setExpandedRow(rowId);
    if(!followups[rowId]){const {data,error}=await supabase.from('inquiry_followups').select('id,sender_role,body,attachment_path,attachment_name,attachment_size,created_at').eq('submission_id',rowId).order('created_at',{ascending:true}).limit(200);if(!error&&data)setFollowups(prev=>({...prev,[rowId]:data||[]}));}
  }
  async function sendFollowup(rowId:string){
    const body=(draftFollowup[rowId]||'').trim();
    const file=extraFiles[rowId]||null;
    if(!body&&!file){setMessage(t('Andika ujumbe au chagua faili kabla ya kutuma.','Write a message or pick a file before sending.'));return}
    setSubmittingFollowup(rowId);
    let attachmentPath:string|null=null,attachmentName:string|null=null,attachmentSize:number|null=null;
    if(file){
      const {data:{user}}=await supabase.auth.getUser();
      if(!user){setMessage(t('Ingia ili kuongeza ushahidi.','Sign in to add evidence.'));setSubmittingFollowup('');return}
      attachmentPath=`${user.id}/${rowId}/${crypto.randomUUID()}.${file.name.split('.').pop()||'bin'}`;
      attachmentName=file.name;attachmentSize=file.size;
      const {error:uploadError}=await supabase.storage.from('inquiry-evidence').upload(attachmentPath,file,{upsert:false});
      if(uploadError){setMessage(t('Faili halikupakiwa. Jaribu tena.','File could not be uploaded. Try again.'));setSubmittingFollowup('');return}
    }
    const {data:followup,error}=await supabase.from('inquiry_followups').insert({submission_id:rowId,sender_role:'citizen',body,attachment_path:attachmentPath,attachment_name:attachmentName,attachment_size:attachmentSize}).select('id,sender_role,body,attachment_path,attachment_name,attachment_size,created_at').single();
    if(error){setMessage(t('Ujumbe haujahifadhiwa. Jaribu tena.','Message could not be saved. Try again.'));setSubmittingFollowup('');return}
    setFollowups(prev=>({...prev,[rowId]:[...(prev[rowId]||[]),followup]}));
    setDraftFollowup(prev=>({...prev,[rowId]:''}));
    setExtraFiles(prev=>({...prev,[rowId]:null}));
    setMessage(t('Ujumbe umewasilishwa kwa Tume.','Message sent to the Commission.'));
    setSubmittingFollowup('');
  }
  if(user===undefined||loading)return <section className="section page inquiryInbox"><h1 className="pageTitle">{t('Inapakia taarifa zako...','Loading your reports...')}</h1></section>;
  if(!user)return <section className="section page inquiryInbox"><span className="kicker">{t('AKAUNTI INAHITAJIKA','ACCOUNT REQUIRED')}</span><h1 className="pageTitle">{t('Ingia kufuatilia taarifa zako','Sign in to track your reports')}</h1><p className="lead">{t('Tumia akaunti uliyotumia wakati wa kuwasilisha taarifa.','Use the same account you used when submitting reports.')}</p><Link className="primary linkBtn" to="/account?mode=login">{t('Ingia','Sign in')} <ArrowRight size={17}/></Link></section>;
  const statusLabels:Record<string,string>={submitted:t('Imepokelewa','Received'),reviewing:t('Inakaguliwa','Under review'),closed:t('Imekamilika','Closed')};
  return <section className="section page inquiryInbox"><span className="kicker">{t('AKAUNTI YANGU','MY ACCOUNT')}</span><h1 className="pageTitle">{t('Taarifa zangu','My submissions')}</h1><p className="lead">{t('Hali na marejeo ya taarifa ulizowasilisha kwa Tume. Unaweza kufuatilia, kuongeza ushahidi zaidi, na kuwasiliana moja kwa moja na mkaguzi.','Status and reference for reports you have submitted to the Commission. You can track, add more evidence, and message the reviewer directly.')}</p>{message&&<div className="authMessage" role="alert">{message}</div>}{rows.map(row=>{
    const isOpen=expandedRow===row.id;
    const messages=followups[row.id]||[];
    return <article className={`inquiryCase ${isOpen?'expanded':''}`} key={row.id}>
      <header><div><span>{row.reference_code}</span><h2>{new Date(row.incident_date+'T00:00:00').toLocaleDateString('sw-TZ')} · {row.region}{row.district?', '+row.district:''}</h2></div><strong className={'inquiryStatus '+row.status}>{statusLabels[row.status]||row.status}</strong></header>
      {row.location&&<small>{row.location}</small>}
      <p>{row.description}</p>
      <small>{t('Iliwasilishwa','Submitted')}: {new Date(row.created_at).toLocaleString('sw-TZ')}</small>
      {row.review_note&&<div className="inquiryFormIntro"><p><b>{t('Ujumbe kutoka kwa mkaguzi','Message from the reviewer')}</b><br/>{row.review_note}</p></div>}
      {(row.attachments||[]).map((file:any)=><button className="inquiryEvidenceLink" key={file.path} onClick={()=>openEvidence(file.path)}>{file.name} · {(file.size/1024/1024).toFixed(1)} MB</button>)}
      <button type="button" className="followUpToggleBtn" onClick={()=>toggleExpand(row.id)}>{isOpen?t('Funga mazungumzo','Close conversation'):t('Fuatilia na uongeze ushahidi','Follow up & add more evidence')}</button>
      {isOpen&&<div className="followUpThread">
        <h3>{t('Mazungumzo na Tume','Conversation with the Commission')}</h3>
        {messages.length===0&&<p className="followUpEmpty">{t('Bado hakuna majadiliano. Anza kuongeza ujumbe au ushahidi wa ziada.','No messages yet. Start by adding a message or additional evidence.')}</p>}
        {messages.map(msg=><div key={msg.id} className={`followUpMessage ${msg.sender_role}`}>
          <small>{msg.sender_role==='citizen'?t('Wewe','You'):'Tume'} · {new Date(msg.created_at).toLocaleString('sw-TZ')}</small>
          <p>{msg.body}</p>
          {msg.attachment_path&&<button className="inquiryEvidenceLink" onClick={()=>openEvidence(msg.attachment_path)}>{msg.attachment_name} · {((msg.attachment_size||0)/1024/1024).toFixed(1)} MB</button>}
        </div>)}
        <div className="followUpComposer">
          <textarea value={draftFollowup[row.id]||''} onChange={e=>setDraftFollowup(prev=>({...prev,[row.id]:e.target.value}))} placeholder={t('Andika ujumbe wako kwa Tume hapa...','Type your message to the Commission here...')} maxLength={5000} />
          <label className="followUpFilePicker"><Upload size={16}/> <span>{extraFiles[row.id]?extraFiles[row.id]!.name:t('Ongeza faili la ushahidi wa ziada (hiari)','Attach additional evidence (optional)')}</span><input type="file" onChange={e=>setExtraFiles(prev=>({...prev,[row.id]:e.target.files?.[0]||null}))} /></label>
          <button type="button" className="primary followUpSendBtn" disabled={submittingFollowup===row.id} onClick={()=>sendFollowup(row.id)}>{submittingFollowup===row.id?t('Inatuma...','Sending...'):t('Wasilisha ujumbe','Send message')}</button>
        </div>
      </div>}
    </article>;
  })}{!rows.length&&!message&&<div className="empty"><FileText/><p>{t('Bado hujawasilisha taarifa.','You have not submitted any reports yet.')}</p><Link className="primary linkBtn" to="/toa-taarifa">{t('Wasilisha taarifa','Submit a report')} <ArrowRight size={17}/></Link></div>}<Link className="secondary linkBtn" to="/toa-taarifa">{t('Wasilisha taarifa nyingine','Submit another report')} <ArrowRight size={17}/></Link></section>;
}

export function InquiryInboxPage(){
  const {t}=useLanguage();
  const [authorized,setAuthorized]=useState<boolean|null>(null);
  const [rows,setRows]=useState<any[]>([]);
  const [message,setMessage]=useState('');
  const [busy,setBusy]=useState('');
  const [staffDrafts,setStaffDrafts]=useState<Record<string,string>>({});
  const [staffFollowups,setStaffFollowups]=useState<Record<string,any[]>>({});
  const [expandedRow,setExpandedRow]=useState<string|null>(null);
  const [sending,setSending]=useState<string>('');
  async function load(){
    const {data:{user}}=await supabase.auth.getUser();
    if(!user){setAuthorized(false);return}
    const {data:profile}=await supabase.from('profiles').select('role').eq('id',user.id).maybeSingle();
    if(profile?.role!=='admin'){setAuthorized(false);return}
    setAuthorized(true);
    const {data,error}=await supabase.from('inquiry_submissions').select('id,reference_code,full_name,contact,incident_date,region,district,location,description,attachments,status,review_note,created_at,anonymous_flag,street_village,short_title_category,people_involved').neq('status','uploading').order('created_at',{ascending:false}).limit(100);
    if(error)setMessage(error.message);else setRows(data||[]);
  }
  useEffect(()=>{load()},[]);
  async function review(row:any,status:'reviewing'|'closed'){
    setBusy(row.id);const {error}=await supabase.from('inquiry_submissions').update({status,review_note:row.editNote||row.review_note||'',reviewed_by:(await supabase.auth.getUser()).data.user?.id||null,reviewed_at:new Date().toISOString()}).eq('id',row.id);
    if(error)setMessage(error.message);else{setMessage(t('Mapitio yamehifadhiwa.','Review saved.'));await load()}setBusy('');
  }
  async function openEvidence(path:string){
    const {data,error}=await supabase.storage.from('inquiry-evidence').createSignedUrl(path,120);
    if(error||!data?.signedUrl)setMessage(t('Imeshindikana kufungua kiambatisho.','Could not open attachment.'));else window.open(data.signedUrl,'_blank','noopener,noreferrer');
  }
  async function toggleExpand(rowId:string){
    if(expandedRow===rowId){setExpandedRow(null);return}
    setExpandedRow(rowId);
    if(!staffFollowups[rowId]){const {data,error}=await supabase.from('inquiry_followups').select('id,sender_role,body,attachment_path,attachment_name,attachment_size,created_at').eq('submission_id',rowId).order('created_at',{ascending:true}).limit(200);if(!error&&data)setStaffFollowups(prev=>({...prev,[rowId]:data||[]}));}
  }
  async function sendStaffReply(rowId:string){
    const body=(staffDrafts[rowId]||'').trim();
    if(!body){setMessage(t('Andika ujumbe kabla ya kutuma.','Write a message before sending.'));return}
    setSending(rowId);
    const {data:followup,error}=await supabase.from('inquiry_followups').insert({submission_id:rowId,sender_role:'staff',body}).select('id,sender_role,body,attachment_path,attachment_name,attachment_size,created_at').single();
    if(error){setMessage(t('Ujumbe haujahifadhiwa.','Message could not be saved.'));setSending('');return}
    setStaffFollowups(prev=>({...prev,[rowId]:[...(prev[rowId]||[]),followup]}));
    setStaffDrafts(prev=>({...prev,[rowId]:''}));
    setMessage(t('Ujumbe umetumwa kwa mwananchi.','Reply sent to the citizen.'));
    setSending('');
  }
  if(authorized===null)return <section className="section page"><h1 className="pageTitle">{t('Inapakia taarifa...','Loading reports...')}</h1></section>;
  if(!authorized)return <section className="section page"><h1 className="pageTitle">{t('Ufikiaji umezuiwa','Access restricted')}</h1><p className="lead">{t('Ukurasa huu ni wa wasimamizi wa Tume walioidhinishwa.','This page is for authorized Commission administrators only.')}</p><Link to="/account">{t('Ingia kwenye akaunti','Sign in')}</Link></section>;
  return <section className="section page inquiryInbox"><span className="kicker">{t('USIMAMIZI WA TUME','COMMISSION ADMIN')}</span><h1 className="pageTitle">{t('Taarifa za wananchi','Citizen submissions')}</h1><p className="lead">{t('Taarifa na viambatisho vya siri. Usishiriki nje ya mchakato ulioidhinishwa.','Reports and attachments are confidential. Do not share outside the authorized process.')}</p>{message&&<div className="authMessage">{message}</div>}{rows.map(row=>{
    const isOpen=expandedRow===row.id;
    const messages=staffFollowups[row.id]||[];
    const people=row.people_involved?String(row.people_involved).split(';').filter(Boolean):[];
    return <article className={`inquiryCase ${isOpen?'expanded':''}`} key={row.id}>
      <header><div><span>{row.reference_code}</span><h2>{row.incident_date} · {row.region}{row.district?', '+row.district:''}{row.street_village?', '+row.street_village:''}</h2></div><select aria-label={'Hali ya '+row.reference_code} value={row.status} onChange={e=>review(row,e.target.value as 'reviewing'|'closed')} disabled={busy===row.id}><option value="submitted">{t('Imepokelewa','Received')}</option><option value="reviewing">{t('Inakaguliwa','Under review')}</option><option value="closed">{t('Imefungwa','Closed')}</option></select></header>
      {row.short_title_category&&<small>{t('Kichwa:','Title:')} {row.short_title_category}</small>}
      <p>{row.description}</p>
      {row.anonymous_flag&&<small className="anonFlag">{t('Taarifa bila akaunti (haiwezi kufuatiliwa)','Anonymous submission (cannot be tracked)')}</small>}
      {(row.full_name||row.contact)&&<small>{[row.full_name,row.contact].filter(Boolean).join(' · ')}</small>}
      {row.location&&<small>{row.location}</small>}
      {people.length>0&&<small>{t('Watu waliohusika','People involved')}: {people.join('; ')}</small>}
      {(row.attachments||[]).map((file:any)=><button className="inquiryEvidenceLink" key={file.path} onClick={()=>openEvidence(file.path)}>{file.name} · {(file.size/1024/1024).toFixed(1)} MB</button>)}
      <textarea aria-label={t('Dokezo la mapitio','Internal review note')} defaultValue={row.review_note||''} onChange={e=>row.editNote=e.target.value} placeholder={t('Dokezo la ndani','Internal note')}/>
      <button className="secondary" disabled={busy===row.id} onClick={()=>review(row,row.status==='closed'?'closed':'reviewing')}>{t('Hifadhi dokezo','Save note')}</button>
      <button type="button" className="followUpToggleBtn" onClick={()=>toggleExpand(row.id)}>{isOpen?t('Funga mazungumzo','Close conversation'):t('Mazungumzo na mwananchi','Citizen conversation')}</button>
      {isOpen&&<div className="followUpThread">
        <h3>{t('Mazungumzo na mwananchi','Conversation with citizen')}</h3>
        {messages.length===0&&<p className="followUpEmpty">{t('Bado hakuna majadiliano.','No messages yet.')}</p>}
        {messages.map(msg=><div key={msg.id} className={`followUpMessage ${msg.sender_role}`}>
          <small>{msg.sender_role==='staff'?t('Tume','Commission'):'Mwananchi'} · {new Date(msg.created_at).toLocaleString('sw-TZ')}</small>
          <p>{msg.body}</p>
          {msg.attachment_path&&<button className="inquiryEvidenceLink" onClick={()=>openEvidence(msg.attachment_path)}>{msg.attachment_name} · {((msg.attachment_size||0)/1024/1024).toFixed(1)} MB</button>}
        </div>)}
        <div className="followUpComposer">
          <textarea value={staffDrafts[row.id]||''} onChange={e=>setStaffDrafts(prev=>({...prev,[row.id]:e.target.value}))} placeholder={t('Andika jibu kwa mwananchi hapa...','Type your reply to the citizen here...')} maxLength={5000} />
          <button type="button" className="primary followUpSendBtn" disabled={sending===row.id} onClick={()=>sendStaffReply(row.id)}>{sending===row.id?t('Inatuma...','Sending...'):t('Tuma jibu','Send reply')}</button>
        </div>
      </div>}
    </article>;
  })}{!rows.length&&!message&&<p>{t('Hakuna taarifa zilizowasilishwa.','No submissions yet.')}</p>}</section>;
}