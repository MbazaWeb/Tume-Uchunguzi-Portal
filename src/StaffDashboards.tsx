import {useEffect,useState} from 'react';
import {Link} from 'react-router';
import {
  ArrowRight, BarChart3, CheckCircle2, Clock, FileText,
  PieChart, ShieldCheck, TrendingUp, UserCheck, Users, XCircle,
} from 'lucide-react';
import {supabase} from './lib/supabase';
import {useLanguage} from './lib/language';

// ==========================================================
// Shared: StatCard
// ==========================================================
function StatCard({label, value, icon: Icon, color}:{label:string; value:number|string; icon:any; color:string}){
  return <article className="statCard" style={{borderLeftColor:color}}>
    <div className="statCardIcon" style={{background:`${color}20`, color}}>
      <Icon size={22}/>
    </div>
    <div className="statCardBody">
      <strong>{value}</strong>
      <span>{label}</span>
    </div>
  </article>;
}

// ==========================================================
// Shared: MiniBarChart
// ==========================================================
function MiniBarChart({data, color}:{data:{label:string; value:number}[]; color:string}){
  const max = Math.max(...data.map(d=>d.value), 1);
  return <div className="miniBarChart">
    {data.map(d => <div key={d.label} className="miniBar">
      <div className="miniBarTrack">
        <div className="miniBarFill" style={{width:`${(d.value/max)*100}%`, background:color}}/>
      </div>
      <div className="miniBarLabel">
        <span>{d.label}</span>
        <b>{d.value}</b>
      </div>
    </div>)}
  </div>;
}

// ==========================================================
// Shared: PieChart (simple CSS)
// ==========================================================
function SimplePie({data}:{data:{label:string; value:number; color:string}[]}){
  const total = data.reduce((s, d) => s + d.value, 0) || 1;
  let cumulative = 0;
  const segments = data.map(d => {
    const start = (cumulative / total) * 360;
    cumulative += d.value;
    const end = (cumulative / total) * 360;
    return `${d.color} ${start}deg ${end}deg`;
  }).join(', ');
  
  return <div className="pieWrap">
    <div className="pie" style={{background:`conic-gradient(${segments})`}}>
      <div className="pieInner">
        <strong>{total}</strong>
        <span>Total</span>
      </div>
    </div>
    <div className="pieLegend">
      {data.map(d => <div key={d.label} className="pieLegendItem">
        <span className="pieDot" style={{background:d.color}}/>
        <span>{d.label}</span>
        <b>{d.value}</b>
      </div>)}
    </div>
  </div>;
}

// ==========================================================
// ADMIN DASHBOARD
// ==========================================================
export function AdminDashboard(){
  const {t}=useLanguage();
  const [loading,setLoading]=useState(true);
  const [stats,setStats]=useState({
    users:0, admins:0, reviewers:0, committees:0, citizens:0,
    submissions:0, submitted:0, reviewing:0, closed:0,
    assignments:0, assigned:0, in_review:0, reviewed:0,
    decisions:0, approve:0, reject:0, pendingDecision:0,
  });
  const [recentSubmissions,setRecentSubmissions]=useState<any[]>([]);
  const [byRegion,setByRegion]=useState<{label:string;value:number}[]>([]);

  useEffect(()=>{
    async function load(){
      // Users
      const {data:profiles} = await supabase.from('profiles').select('id, role');
      const p = profiles || [];
      
      // Submissions
      const {data:subs} = await supabase.from('inquiry_submissions').select('id, status, region, created_at').neq('status','uploading');
      const s = subs || [];
      
      // Assignments
      const {data:assigns} = await supabase.from('inquiry_assignments').select('id, status');
      const a = assigns || [];
      
      // Decisions
      const {data:decisions} = await supabase.from('inquiry_decisions').select('id, decision');
      const d = decisions || [];

      setStats({
        users: p.length,
        admins: p.filter(x=>x.role==='admin').length,
        reviewers: p.filter(x=>x.role==='reviewer').length,
        committees: p.filter(x=>x.role==='committee').length,
        citizens: p.filter(x=>x.role==='citizen').length,
        submissions: s.length,
        submitted: s.filter(x=>x.status==='submitted').length,
        reviewing: s.filter(x=>x.status==='reviewing').length,
        closed: s.filter(x=>x.status==='closed').length,
        assignments: a.length,
        assigned: a.filter(x=>x.status==='assigned').length,
        in_review: a.filter(x=>x.status==='in_review').length,
        reviewed: a.filter(x=>x.status==='reviewed').length,
        decisions: d.length,
        approve: d.filter(x=>x.decision==='approve').length,
        reject: d.filter(x=>x.decision==='reject').length,
        pendingDecision: s.length - d.length,
      });

      // Recent submissions
      const {data:recent} = await supabase
        .from('inquiry_submissions')
        .select('id, reference_code, title, region, status, created_at, anonymous_flag')
        .neq('status','uploading')
        .order('created_at',{ascending:false})
        .limit(5);
      setRecentSubmissions(recent || []);

      // By region
      const regionCount: Record<string, number> = {};
      s.forEach(x => { regionCount[x.region] = (regionCount[x.region] || 0) + 1; });
      const regions = Object.entries(regionCount)
        .sort((a,b)=>b[1]-a[1])
        .slice(0, 5)
        .map(([label,value])=>({label,value}));
      setByRegion(regions);

      setLoading(false);
    }
    load();
  },[]);

  if(loading) return <section className="section page"><h1 className="pageTitle">{t('Inapakia...','Loading...')}</h1></section>;

  const submissionsPie = [
    {label:t('Imepokelewa','Submitted'), value:stats.submitted, color:'#087ea4'},
    {label:t('Inakaguliwa','Reviewing'), value:stats.reviewing, color:'#f59e0b'},
    {label:t('Imefungwa','Closed'), value:stats.closed, color:'#10b981'},
  ];

  const decisionsPie = [
    {label:t('Kubali','Approve'), value:stats.approve, color:'#10b981'},
    {label:t('Kataa','Reject'), value:stats.reject, color:'#ef4444'},
    {label:t('Zinasubiri','Pending'), value:stats.pendingDecision, color:'#94a3b8'},
  ];

  return <section className="section page">
    <span className="kicker">{t('USIMAMIZI','ADMIN DASHBOARD')}</span>
    <h1 className="pageTitle">{t('Dashibodi ya Msimamizi','Administrator Dashboard')}</h1>
    <p className="lead">{t('Muhtasari wa shughuli zote kwenye portal.','Overview of all portal activity.')}</p>

    {/* Submissions summary */}
    <h2 className="dashboardSubhead">{t('Taarifa','Submissions')}</h2>
    <div className="statGrid">
      <StatCard label={t('Jumla','Total')} value={stats.submissions} icon={FileText} color="#087ea4"/>
      <StatCard label={t('Zilizopokelewa','Submitted')} value={stats.submitted} icon={Clock} color="#087ea4"/>
      <StatCard label={t('Zinakaguliwa','Reviewing')} value={stats.reviewing} icon={UserCheck} color="#087ea4"/>
      <StatCard label={t('Zilizofungwa','Closed')} value={stats.closed} icon={CheckCircle2} color="#087ea4"/>
    </div>

    {/* Users summary */}
    <h2 className="dashboardSubhead">{t('Watumiaji','Users')}</h2>
    <div className="statGrid">
      <StatCard label={t('Jumla','Total')} value={stats.users} icon={Users} color="#087ea4"/>
      <StatCard label="Admin" value={stats.admins} icon={ShieldCheck} color="#087ea4"/>
      <StatCard label={t('Wakaguzi','Reviewers')} value={stats.reviewers} icon={UserCheck} color="#087ea4"/>
      <StatCard label={t('Kamati','Committee')} value={stats.committees} icon={Users} color="#087ea4"/>
      <StatCard label={t('Wananchi','Citizens')} value={stats.citizens} icon={Users} color="#087ea4"/>
    </div>

    {/* Assignments + Decisions */}
    <h2 className="dashboardSubhead">{t('Kazi & Maamuzi','Work & Decisions')}</h2>
    <div className="statGrid">
      <StatCard label={t('Zilizopewa','Assigned')} value={stats.assigned} icon={FileText} color="#087ea4"/>
      <StatCard label={t('Zinakaguliwa','In Review')} value={stats.in_review} icon={Clock} color="#087ea4"/>
      <StatCard label={t('Zilizokaguliwa','Reviewed')} value={stats.reviewed} icon={CheckCircle2} color="#087ea4"/>
      <StatCard label={t('Maamuzi','Decisions')} value={stats.decisions} icon={TrendingUp} color="#087ea4"/>
    </div>

    {/* Charts */}
    <h2 className="dashboardSubhead">{t('Mchanganuo','Breakdown')}</h2>
    <div className="chartGrid">
      <article className="chartCard">
        <h3><PieChart size={18}/> {t('Taarifa kwa hali','Submissions by status')}</h3>
        <SimplePie data={submissionsPie}/>
      </article>
      <article className="chartCard">
        <h3><PieChart size={18}/> {t('Maamuzi','Decisions')}</h3>
        <SimplePie data={decisionsPie}/>
      </article>
      <article className="chartCard">
        <h3><BarChart3 size={18}/> {t('Mikoa 5 yenye taarifa nyingi','Top 5 regions')}</h3>
        {byRegion.length ? <MiniBarChart data={byRegion} color="#087ea4"/> : <p className="muted">{t('Hakuna data.','No data.')}</p>}
      </article>
    </div>

    {/* Recent submissions */}
    <h2 className="dashboardSubhead">{t('Taarifa za hivi karibuni','Recent submissions')}</h2>
    <div className="staffCardList">
      {recentSubmissions.map(s => <Link key={s.id} to="/admin" className="staffCard">
        <div>
          <strong>{s.reference_code}</strong>
          <span>{s.title || t('Bila kichwa','Untitled')}</span>
          <small>{s.region} Ã‚Â· {new Date(s.created_at).toLocaleDateString()}</small>
        </div>
        <span className={`statusBadge ${s.status}`}>{s.status}</span>
        <ArrowRight size={16}/>
      </Link>)}
      {!recentSubmissions.length && <p className="muted">{t('Hakuna taarifa.','No submissions.')}</p>}
    </div>

    {/* Quick links */}
    <h2 className="dashboardSubhead">{t('Viungo vya haraka','Quick links')}</h2>
    <div className="quickLinks">
      <Link to="/admin/users" className="quickLink"><Users size={18}/> {t('Watumiaji','Manage Users')}</Link>
      <Link to="/admin" className="quickLink"><FileText size={18}/> {t('Taarifa','View Submissions')}</Link>
      <Link to="/workflow" className="quickLink"><UserCheck size={18}/> {t('Kazi','Workflow')}</Link>
      <Link to="/committee" className="quickLink"><CheckCircle2 size={18}/> {t('Kamati','Committee')}</Link>
    </div>
  </section>;
}

// ==========================================================
// REVIEWER DASHBOARD
// ==========================================================
export function WorkflowDashboard(){
  const {t}=useLanguage();
  const [loading,setLoading]=useState(true);
  const [stats,setStats]=useState({total:0, assigned:0, in_review:0, reviewed:0, urgent:0});
  const [assignments,setAssignments]=useState<any[]>([]);

  useEffect(()=>{
    async function load(){
      const {data:{user}} = await supabase.auth.getUser();
      if(!user){setLoading(false);return}

      const {data:rows} = await supabase
        .from('inquiry_assignments')
        .select('id, status, assigned_at, submission:inquiry_submissions(id, reference_code, title, region, status)')
        .eq('reviewer_id', user.id)
        .order('assigned_at',{ascending:false});

      const a = rows || [];
      const now = Date.now();
      const urgent = a.filter(x => x.status==='assigned' && (now - new Date(x.assigned_at).getTime()) > 3*24*60*60*1000).length;

      setStats({
        total: a.length,
        assigned: a.filter(x=>x.status==='assigned').length,
        in_review: a.filter(x=>x.status==='in_review').length,
        reviewed: a.filter(x=>x.status==='reviewed').length,
        urgent,
      });
      setAssignments(a);
      setLoading(false);
    }
    load();
  },[]);

  if(loading) return <section className="section page"><h1 className="pageTitle">{t('Inapakia...','Loading...')}</h1></section>;

  const progressPie = [
    {label:t('Zinasubiri','Assigned'), value:stats.assigned, color:'#3b82f6'},
    {label:t('Zinakaguliwa','In Review'), value:stats.in_review, color:'#f59e0b'},
    {label:t('Zilizokaguliwa','Reviewed'), value:stats.reviewed, color:'#10b981'},
  ];

  return <section className="section page">
    <span className="kicker">{t('UKAGUZI','REVIEWER DASHBOARD')}</span>
    <h1 className="pageTitle">{t('Dashibodi ya Mkaguzi','Reviewer Dashboard')}</h1>
    <p className="lead">{t('Muhtasari wa kazi zako za ukaguzi.','Overview of your review work.')}</p>

    <h2 className="dashboardSubhead">{t('Kazi zangu','My work')}</h2>
    <div className="statGrid">
      <StatCard label={t('Jumla','Total')} value={stats.total} icon={FileText} color="#087ea4"/>
      <StatCard label={t('Zinasubiri','Assigned')} value={stats.assigned} icon={Clock} color="#087ea4"/>
      <StatCard label={t('Zinakaguliwa','In Review')} value={stats.in_review} icon={UserCheck} color="#087ea4"/>
      <StatCard label={t('Zilizokaguliwa','Reviewed')} value={stats.reviewed} icon={CheckCircle2} color="#087ea4"/>
      <StatCard label={t('Zinahitaji haraka','Urgent')} value={stats.urgent} icon={XCircle} color="#087ea4"/>
    </div>

    <h2 className="dashboardSubhead">{t('Mchanganuo','Breakdown')}</h2>
    <div className="chartGrid">
      <article className="chartCard">
        <h3><PieChart size={18}/> {t('Maendeleo yangu','My progress')}</h3>
        <SimplePie data={progressPie}/>
      </article>
    </div>

    <h2 className="dashboardSubhead">{t('Kazi zangu','My assignments')}</h2>
    <div className="staffCardList">
      {assignments.map(a => <Link key={a.id} to="/workflow" className="staffCard">
        <div>
          <strong>{a.submission?.reference_code}</strong>
          <span>{a.submission?.title || t('Bila kichwa','Untitled')}</span>
          <small>{a.submission?.region} Ã‚Â· {new Date(a.assigned_at).toLocaleDateString()}</small>
        </div>
        <span className={`statusBadge ${a.status}`}>{a.status}</span>
        <ArrowRight size={16}/>
      </Link>)}
      {!assignments.length && <p className="muted">{t('Hakuna kazi zilizopewa bado.','No assignments yet.')}</p>}
    </div>

    <div className="quickLinks">
      <Link to="/workflow" className="quickLink"><FileText size={18}/> {t('Ona kazi zote','View all assignments')}</Link>
    </div>
  </section>;
}

// ==========================================================
// COMMITTEE DASHBOARD
// ==========================================================
export function CommitteeDashboard(){
  const {t}=useLanguage();
  const [loading,setLoading]=useState(true);
  const [stats,setStats]=useState({total:0, voted:0, pending:0, approve:0, reject:0});
  const [submissions,setSubmissions]=useState<any[]>([]);
  const [byRegion,setByRegion]=useState<{label:string;value:number}[]>([]);

  useEffect(()=>{
    async function load(){
      const {data:{user}} = await supabase.auth.getUser();
      if(!user){setLoading(false);return}

      const {data:subs} = await supabase
        .from('inquiry_submissions')
        .select('id, reference_code, title, region, status, created_at, anonymous_flag')
        .in('status',['submitted','reviewing'])
        .order('created_at',{ascending:false});
      const s = subs || [];

      const {data:myVotes} = await supabase
        .from('inquiry_decisions')
        .select('id, submission_id, decision')
        .eq('committee_id', user.id);
      const v = myVotes || [];

      const votedIds = new Set(v.map(x=>x.submission_id));
      const pending = s.filter(x=>!votedIds.has(x.id));

      setStats({
        total: s.length,
        voted: v.length,
        pending: pending.length,
        approve: v.filter(x=>x.decision==='approve').length,
        reject: v.filter(x=>x.decision==='reject').length,
      });
      setSubmissions(pending.slice(0,5));

      const regionCount: Record<string, number> = {};
      s.forEach(x => { regionCount[x.region] = (regionCount[x.region] || 0) + 1; });
      const regions = Object.entries(regionCount)
        .sort((a,b)=>b[1]-a[1])
        .slice(0, 5)
        .map(([label,value])=>({label,value}));
      setByRegion(regions);

      setLoading(false);
    }
    load();
  },[]);

  if(loading) return <section className="section page"><h1 className="pageTitle">{t('Inapakia...','Loading...')}</h1></section>;

  const votesPie = [
    {label:t('Kubali','Approve'), value:stats.approve, color:'#10b981'},
    {label:t('Kataa','Reject'), value:stats.reject, color:'#ef4444'},
    {label:t('Zinasubiri','Pending'), value:stats.pending, color:'#94a3b8'},
  ];

  return <section className="section page">
    <span className="kicker">{t('KAMATI','COMMITTEE DASHBOARD')}</span>
    <h1 className="pageTitle">{t('Dashibodi ya Kamati','Committee Dashboard')}</h1>
    <p className="lead">{t('Muhtasari wa kura na maamuzi.','Overview of votes and decisions.')}</p>

    <h2 className="dashboardSubhead">{t('Kura zangu','My votes')}</h2>
    <div className="statGrid">
      <StatCard label={t('Taarifa zote','Total submissions')} value={stats.total} icon={FileText} color="#087ea4"/>
      <StatCard label={t('Zilizopigiwa kura','Voted')} value={stats.voted} icon={CheckCircle2} color="#087ea4"/>
      <StatCard label={t('Zinasubiri kura','Pending')} value={stats.pending} icon={Clock} color="#087ea4"/>
      <StatCard label={t('Kubali','Approve')} value={stats.approve} icon={CheckCircle2} color="#087ea4"/>
      <StatCard label={t('Kataa','Reject')} value={stats.reject} icon={XCircle} color="#087ea4"/>
    </div>

    <h2 className="dashboardSubhead">{t('Mchanganuo','Breakdown')}</h2>
    <div className="chartGrid">
      <article className="chartCard">
        <h3><PieChart size={18}/> {t('Kura zangu','My votes')}</h3>
        <SimplePie data={votesPie}/>
      </article>
      <article className="chartCard">
        <h3><BarChart3 size={18}/> {t('Mikoa 5 yenye taarifa nyingi','Top 5 regions')}</h3>
        {byRegion.length ? <MiniBarChart data={byRegion} color="#087ea4"/> : <p className="muted">{t('Hakuna data.','No data.')}</p>}
      </article>
    </div>

    <h2 className="dashboardSubhead">{t('Taarifa zinazohitaji kura yako','Submissions needing your vote')}</h2>
    <div className="staffCardList">
      {submissions.map(s => <Link key={s.id} to="/committee" className="staffCard">
        <div>
          <strong>{s.reference_code}</strong>
          <span>{s.title || t('Bila kichwa','Untitled')}</span>
          <small>{s.region} Ã‚Â· {new Date(s.created_at).toLocaleDateString()}</small>
        </div>
        <ArrowRight size={16}/>
      </Link>)}
      {!submissions.length && <p className="muted">{t('Hakuna taarifa zinazohitaji kura yako.','No submissions waiting for your vote.')}</p>}
    </div>

    <div className="quickLinks">
      <Link to="/committee" className="quickLink"><CheckCircle2 size={18}/> {t('Piga kura','Vote now')}</Link>
    </div>
  </section>;
}