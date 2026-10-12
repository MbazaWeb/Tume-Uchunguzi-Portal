import {FormEvent,useEffect,useState} from 'react';
import {Link} from 'react-router';
import {
  ArrowRight, CheckCircle2, FileText, LockKeyhole,
  ShieldCheck, UserCheck, Users, XCircle,
} from 'lucide-react';
import {supabase} from './lib/supabase';
import {useLanguage} from './lib/language';

// ==========================================================
// Types
// ==========================================================
type Profile = {
  id: string;
  email: string;
  display_name: string;
  role: 'citizen' | 'admin' | 'reviewer' | 'committee';
  created_at: string;
};

type Submission = {
  id: string;
  reference_code: string;
  title: string;
  description: string;
  status: string;
  created_at: string;
  anonymous_flag: boolean;
  incident_date: string;
  region: string;
  district: string;
  short_title_category: string;
};

type Assignment = {
  id: string;
  submission_id: string;
  reviewer_id: string;
  status: 'assigned' | 'in_review' | 'reviewed' | 'returned';
  notes: string;
  assigned_at: string;
};

type Decision = {
  id: string;
  submission_id: string;
  committee_id: string;
  decision: 'approve' | 'reject' | 'request_more_info' | 'escalate';
  rationale: string;
  created_at: string;
};

// ==========================================================
// Shared: Role badge
// ==========================================================
function RoleBadge({role}:{role:string}){
  const colors: Record<string,string> = {
    admin: 'bg-red-100 text-red-800 border-red-200',
    reviewer: 'bg-blue-100 text-blue-800 border-blue-200',
    committee: 'bg-purple-100 text-purple-800 border-purple-200',
    citizen: 'bg-gray-100 text-gray-800 border-gray-200',
  };
  return <span className={`inline-flex items-center px-2 py-1 text-xs font-semibold rounded-full border ${colors[role] || colors.citizen}`}>{role}</span>;
}

// ==========================================================
// PAGE 1: AdminUsersPage — manage users and their roles
// ==========================================================
export function AdminUsersPage(){
  const {t}=useLanguage();
  const [authorized,setAuthorized]=useState<boolean|null>(null);
  const [users,setUsers]=useState<Profile[]>([]);
  const [busy,setBusy]=useState<string>('');
  const [message,setMessage]=useState('');
  const [search,setSearch]=useState('');

  async function load(){
    const {data:{user}}=await supabase.auth.getUser();
    if(!user){setAuthorized(false);return}
    const {data:me}=await supabase.from('profiles').select('role').eq('id',user.id).maybeSingle();
    if(me?.role!=='admin'){setAuthorized(false);return}
    setAuthorized(true);

    const {data,error} = await supabase
      .from('profiles')
      .select('id, display_name, role, created_at')
      .order('created_at',{ascending:false})
      .limit(500);

    if(error){setMessage(error.message);return}

    // Get emails from auth.users via a view or fallback (email not in profiles)
    // For now, we show display_name and role. Email requires admin API.
    const enriched = (data||[]).map(p=>({...p, email: ''}));
    setUsers(enriched as Profile[]);
  }

  useEffect(()=>{load()},[]);

  async function changeRole(userId:string, newRole:Profile['role']){
    setBusy(userId); setMessage('');
    const {error} = await supabase
      .from('profiles')
      .update({role: newRole})
      .eq('id', userId);
    if(error){
      setMessage(`Error: ${error.message}`);
    } else {
      setMessage(t('Role imebadilishwa.','Role updated.'));
      await load();
    }
    setBusy('');
  }

  if(authorized===null) return <section className="section page"><h1 className="pageTitle">{t('Inapakia...','Loading...')}</h1></section>;
  if(!authorized) return <section className="section page"><h1 className="pageTitle">{t('Ufikiaji umezuiwa','Access restricted')}</h1><p className="lead">{t('Ukurasa huu ni wa wasimamizi wa Tume.','This page is for Commission administrators.')}</p><Link to="/">Rudi mwanzo</Link></section>;

  const filtered = users.filter(u =>
    !search ||
    u.display_name?.toLowerCase().includes(search.toLowerCase()) ||
    u.id.toLowerCase().includes(search.toLowerCase())
  );

  return <section className="section page">
    <span className="kicker">{t('USIMAMIZI WA WATUMIAJI','USER MANAGEMENT')}</span>
    <h1 className="pageTitle">{t('Watumiaji','Users')}</h1>
    <p className="lead">{t('Badilisha role za watumiaji ili kuwapa ufikiaji wa Tume.','Change user roles to grant Commission access.')}</p>

    {message && <div className="authMessage" role="status">{message}</div>}

    <div className="wizardTwo" style={{marginTop:'2rem'}}>
      <label>{t('Tafuta','Search')}
        <input
          type="text"
          placeholder={t('Jina au ID','Name or ID')}
          value={search}
          onChange={e=>setSearch(e.target.value)}
        />
      </label>
      <div style={{display:'flex',alignItems:'flex-end'}}>
        <span style={{fontSize:'0.9rem',color:'#666'}}>
          {filtered.length} {t('watumiaji','users')}
        </span>
      </div>
    </div>

    <div style={{marginTop:'2rem'}}>
      {filtered.map(user=>(
        <article key={user.id} className="inquiryCase" style={{display:'grid',gap:'1rem',gridTemplateColumns:'1fr auto'}}>
          <div>
            <strong style={{display:'block',marginBottom:'0.25rem'}}>
              {user.display_name || t('Bila jina','No name')}
            </strong>
            <small style={{color:'#666',display:'block',marginBottom:'0.5rem'}}>
              ID: {user.id.slice(0,8)}...
            </small>
            <RoleBadge role={user.role} />
          </div>
          <div style={{display:'flex',flexDirection:'column',gap:'0.5rem',minWidth:'160px'}}>
            <label style={{fontSize:'0.8rem',color:'#666'}}>
              {t('Badilisha role','Change role')}
              <select
                value={user.role}
                disabled={busy===user.id}
                onChange={e=>changeRole(user.id, e.target.value as Profile['role'])}
              >
                <option value="citizen">citizen</option>
                <option value="reviewer">reviewer</option>
                <option value="committee">committee</option>
                <option value="admin">admin</option>
              </select>
            </label>
          </div>
        </article>
      ))}
      {!filtered.length && <div className="empty"><FileText/><p>{t('Hakuna watumiaji wanaolingana na utafutaji.','No users match your search.')}</p></div>}
    </div>
  </section>;
}

// ==========================================================
// PAGE 2: WorkflowPage — reviewer dashboard
// ==========================================================
export function WorkflowPage(){
  const {t}=useLanguage();
  const [authorized,setAuthorized]=useState<boolean|null>(null);
  const [assignments,setAssignments]=useState<(Assignment & {submission: Submission})[]>([]);
  const [loading,setLoading]=useState(true);
  const [message,setMessage]=useState('');
  const [busy,setBusy]=useState('');

  async function load(){
    const {data:{user}}=await supabase.auth.getUser();
    if(!user){setAuthorized(false);setLoading(false);return}
    const {data:me}=await supabase.from('profiles').select('role').eq('id',user.id).maybeSingle();
    if(!['reviewer','admin'].includes(me?.role)){
      setAuthorized(false);setLoading(false);return;
    }
    setAuthorized(true);

    const {data:rows,error} = await supabase
      .from('inquiry_assignments')
      .select('id, submission_id, reviewer_id, status, notes, assigned_at, submission:inquiry_submissions(id, reference_code, title, description, status, created_at, anonymous_flag, incident_date, region, district, short_title_category)')
      .eq('reviewer_id', user.id)
      .order('assigned_at', {ascending:false})
      .limit(100);

    if(error){setMessage(error.message);setLoading(false);return}
    setAssignments((rows||[]) as any);
    setLoading(false);
  }

  useEffect(()=>{load()},[]);

  async function updateStatus(assignmentId:string, newStatus:Assignment['status']){
    setBusy(assignmentId); setMessage('');
    const {error} = await supabase
      .from('inquiry_assignments')
      .update({status:newStatus})
      .eq('id', assignmentId);
    if(error) setMessage(error.message);
    else { setMessage(t('Hali imesasishwa.','Status updated.')); await load(); }
    setBusy('');
  }

  if(loading) return <section className="section page"><h1 className="pageTitle">{t('Inapakia...','Loading...')}</h1></section>;
  if(!authorized) return <section className="section page"><h1 className="pageTitle">{t('Ufikiaji umezuiwa','Access restricted')}</h1><p className="lead">{t('Ukurasa huu ni wa wakaguzi wa Tume.','This page is for Commission reviewers.')}</p><Link to="/">Rudi mwanzo</Link></section>;

  return <section className="section page">
    <span className="kicker">{t('UKAGUZI','REVIEW WORKFLOW')}</span>
    <h1 className="pageTitle">{t('Kazi zangu','My assignments')}</h1>
    <p className="lead">{t('Taarifa zilizopewa kwako kwa ukaguzi.','Submissions assigned to you for review.')}</p>

    {message && <div className="authMessage" role="status">{message}</div>}

    {!assignments.length && <div className="empty"><FileText/><p>{t('Hakuna kazi zilizopewa bado.','No assignments yet.')}</p></div>}

    {assignments.map(a => <article key={a.id} className="inquiryCase">
      <header>
        <div>
          <span>{a.submission.reference_code}</span>
          <h2>{a.submission.short_title_category || a.submission.title}</h2>
        </div>
        <RoleBadge role={a.status} />
      </header>
      <p>{a.submission.description}</p>
      <small>
        {a.submission.incident_date} · {a.submission.region}
        {a.submission.district ? ', ' + a.submission.district : ''}
        {a.submission.anonymous_flag ? ' · ' + t('Bila jina','Anonymous') : ''}
      </small>
      <div style={{display:'flex',gap:'0.5rem',marginTop:'1rem',flexWrap:'wrap'}}>
        <button
          type="button"
          className="primary"
          disabled={busy===a.id || a.status==='in_review'}
          onClick={()=>updateStatus(a.id,'in_review')}
        >
          {t('Anza ukaguzi','Start review')}
        </button>
        <button
          type="button"
          className="secondary"
          disabled={busy===a.id || a.status==='reviewed'}
          onClick={()=>updateStatus(a.id,'reviewed')}
        >
          {t('Maliza ukaguzi','Mark reviewed')}
        </button>
      </div>
    </article>)}
  </section>;
}

// ==========================================================
// PAGE 3: CommitteePage — committee members vote
// ==========================================================
export function CommitteePage(){
  const {t}=useLanguage();
  const [authorized,setAuthorized]=useState<boolean|null>(null);
  const [submissions,setSubmissions]=useState<Submission[]>([]);
  const [decisions,setDecisions]=useState<Record<string, Decision>>({});
  const [drafts,setDrafts] = useState<Record<string, {decision: Decision['decision']; rationale: string}>>({});
  const [loading,setLoading]=useState(true);
  const [busy,setBusy]=useState('');
  const [message,setMessage]=useState('');

  async function load(){
    const {data:{user}}=await supabase.auth.getUser();
    if(!user){setAuthorized(false);setLoading(false);return}
    const {data:me}=await supabase.from('profiles').select('role').eq('id',user.id).maybeSingle();
    if(!['committee','admin'].includes(me?.role)){
      setAuthorized(false);setLoading(false);return;
    }
    setAuthorized(true);

    // Load submissions that have been reviewed (assignments status = 'reviewed')
    const {data:rows,error} = await supabase
      .from('inquiry_submissions')
      .select('id, reference_code, title, description, status, created_at, anonymous_flag, incident_date, region, district, short_title_category')
      .neq('status','uploading')
      .in('status', ['submitted','reviewing'])
      .order('created_at',{ascending:false})
      .limit(100);

    if(error){setMessage(error.message);setLoading(false);return}
    setSubmissions((rows||[]) as Submission[]);

    // Load my decisions
    const {data:mine} = await supabase
      .from('inquiry_decisions')
      .select('id, submission_id, committee_id, decision, rationale, created_at')
      .eq('committee_id', user.id);

    const map: Record<string, Decision> = {};
    (mine||[]).forEach(d => { map[d.submission_id] = d as Decision; });
    setDecisions(map);
    setLoading(false);
  }

  useEffect(()=>{load()},[]);

  function setDraft(submissionId:string, patch: Partial<{decision: Decision['decision']; rationale: string}>){
    setDrafts(prev => ({
      ...prev,
      [submissionId]: {
        decision: patch.decision ?? prev[submissionId]?.decision ?? 'approve',
        rationale: patch.rationale ?? prev[submissionId]?.rationale ?? '',
      }
    }));
  }

  async function submitDecision(submissionId:string){
    const draft = drafts[submissionId] || {decision:'approve' as const, rationale:''};
    setBusy(submissionId); setMessage('');
    const {data:{user}} = await supabase.auth.getUser();
    if(!user){setBusy('');return}

    const {error} = await supabase
      .from('inquiry_decisions')
      .upsert({
        submission_id: submissionId,
        committee_id: user.id,
        decision: draft.decision,
        rationale: draft.rationale,
      }, { onConflict: 'submission_id,committee_id' });

    if(error) setMessage(error.message);
    else { setMessage(t('Uamuzi umewekwa.','Decision recorded.')); await load(); }
    setBusy('');
  }

  if(loading) return <section className="section page"><h1 className="pageTitle">{t('Inapakia...','Loading...')}</h1></section>;
  if(!authorized) return <section className="section page"><h1 className="pageTitle">{t('Ufikiaji umezuiwa','Access restricted')}</h1><p className="lead">{t('Ukurasa huu ni wa wajumbe wa Tume.','This page is for Commission committee members.')}</p><Link to="/">Rudi mwanzo</Link></section>;

  return <section className="section page">
    <span className="kicker">{t('KAMATI','COMMITTEE')}</span>
    <h1 className="pageTitle">{t('Kupiga kura','Vote on submissions')}</h1>
    <p className="lead">{t('Toa uamuzi wako kwa taarifa zilizokaguliwa.','Record your decision on reviewed submissions.')}</p>

    {message && <div className="authMessage" role="status">{message}</div>}

    {!submissions.length && <div className="empty"><FileText/><p>{t('Hakuna taarifa zilizoandaliwa.','No submissions ready for review.')}</p></div>}

    {submissions.map(s => {
      const myDecision = decisions[s.id];
      const draft = drafts[s.id] || {decision:'approve' as const, rationale:''};
      return <article key={s.id} className="inquiryCase">
        <header>
          <div>
            <span>{s.reference_code}</span>
            <h2>{s.short_title_category || s.title}</h2>
          </div>
          {myDecision ? <RoleBadge role={`voted: ${myDecision.decision}`} /> : <RoleBadge role="pending" />}
        </header>
        <p>{s.description}</p>
        <small>
          {s.incident_date} · {s.region}
          {s.district ? ', ' + s.district : ''}
          {s.anonymous_flag ? ' · ' + t('Bila jina','Anonymous') : ''}
        </small>

        {myDecision ? (
          <div style={{marginTop:'1rem',padding:'1rem',background:'#f5f5f5',borderRadius:'0.5rem'}}>
            <strong>{t('Uamuzi wako','Your decision')}: {myDecision.decision}</strong>
            {myDecision.rationale && <p style={{marginTop:'0.5rem',fontStyle:'italic'}}>{myDecision.rationale}</p>}
          </div>
        ) : (
          <div style={{display:'grid',gap:'0.75rem',marginTop:'1rem'}}>
            <label>{t('Uamuzi','Decision')}
              <select value={draft.decision} onChange={e=>setDraft(s.id, {decision: e.target.value as Decision['decision']})}>
                <option value="approve">{t('Kubali','Approve')}</option>
                <option value="reject">{t('Kataa','Reject')}</option>
                <option value="request_more_info">{t('Omba maelezo zaidi','Request more info')}</option>
                <option value="escalate">{t('Pandisha','Escalate')}</option>
              </select>
            </label>
            <label>{t('Sababu','Rationale')}
              <textarea
                value={draft.rationale}
                maxLength={5000}
                onChange={e=>setDraft(s.id, {rationale: e.target.value})}
                placeholder={t('Eleza uamuzi wako...','Explain your decision...')}
              />
            </label>
            <button
              type="button"
              className="primary"
              disabled={busy===s.id}
              onClick={()=>submitDecision(s.id)}
            >
              {busy===s.id ? t('Inatuma...','Submitting...') : t('Tuma uamuzi','Submit decision')}
            </button>
          </div>
        )}
      </article>;
    })}
  </section>;
}