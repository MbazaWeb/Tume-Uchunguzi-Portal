export type VerificationStatus='verified'|'pending'|'unavailable';

export interface SourceInfo {
  documentId:string;
  sourceLocator:string;
  verificationStatus:VerificationStatus;
}

export interface ConstitutionArticle {
  sura:string;
  ibara:number|string;
  jina:string;
  maudhui:string;
  vifungu:string[];
  sehemu?:string;
  chanzo:SourceInfo;
}

export interface ConstitutionExplanation {
  plainLanguage?:string;
  meaning?:string;
  keyPoints?:string[];
  legalTerms?:Array<{term:string;meaning:string}>;
  examples?:Array<{title?:string;scenario?:string;analysis?:string}|string>;
  history?:{summary?:string;notes?:string[];sourceUrl?:string}|string;
  expertPerspectives?:Array<{label?:string;focus?:string;view?:string}|string>;
  debateQuestion?:string;
  disclaimer?:string;
}

export interface ConstitutionChapter {
  sura?:string;
  chapter?:string;
  jina:string;
  documentId:string;
  chapterNumber:number;
  ibara:string[];
  sehemu:string[];
}

export interface ConstitutionSource {
  id:string;
  title:string;
  family:'official'|'draft';
  jurisdiction:'tanzania'|'zanzibar';
  language?:'sw'|'en';
  basePath:string;
  year:string;
  edition:string;
}

export const constitutionSources:ConstitutionSource[]=[
  {id:'doc-union-1977',title:'Katiba ya Jamhuri ya Muungano wa Tanzania',family:'official',jurisdiction:'tanzania',language:'sw',basePath:'/katiba/Katiba/Tanzania',year:'1977',edition:'Toleo la 2000'},
  {id:'doc-zanzibar-1984',title:'Katiba ya Zanzibar',family:'official',jurisdiction:'zanzibar',language:'sw',basePath:'/katiba/Katiba/Zanzibar',year:'1984',edition:'Toleo la 2020'},
  {id:'doc-rasimu-tanzania-2014',title:'Rasimu ya Katiba ya Tanzania',family:'draft',jurisdiction:'tanzania',language:'sw',basePath:'/katiba/Rasimu za Katiba/Tanzania',year:'2014',edition:'Rasimu / Toleo la 2014'}
];

const manifestCache:{promise?:Promise<string[]>}={};

async function loadManifestPaths(){
  if(!manifestCache.promise) manifestCache.promise=fetch('/katiba/snapshot.csv').then(async r=>{
    if(!r.ok) throw new Error('Katiba path manifest haijapatikana.');
    const text=(await r.text()).replace(/^\uFEFF/,'');
    return text.split(/\r?\n/).slice(1).map(line=>{
      const match=line.match(/^"((?:[^"]|"")*)"/);
      return match?match[1].replace(/""/g,'"').replace(/\\/g,'/').replace(/^\//,''):'';
    }).filter(Boolean);
  });
  return manifestCache.promise;
}

function sourceManifestPrefix(source:ConstitutionSource){
  return source.basePath.replace(/^\/katiba\//,'').replace(/\/$/,'')+'/';
}

async function chapterManifest(source:ConstitutionSource){
  const paths=await loadManifestPaths();
  const prefix=sourceManifestPrefix(source);
  const names=new Set<string>();
  for(const path of paths){
    if(!path.startsWith(prefix)||!path.toLowerCase().endsWith('.json')) continue;
    const rest=path.slice(prefix.length),parts=rest.split('/');
    if(parts.length>=2&&parts[0]) names.add(parts[0]);
  }
  return [...names];
}

const jsonCache=new Map<string,Promise<unknown>>();

async function fetchJson<T>(url:string):Promise<T>{
  let request=jsonCache.get(url);
  if(!request){
    request=fetch(encodeURI(url)).then(async r=>{
      if(!r.ok) throw new Error('Faili ya Katiba haijapatikana: '+url);
      const text=await r.text();
      return JSON.parse(text.charCodeAt(0)===0xFEFF?text.slice(1):text);
    });
    jsonCache.set(url,request);
  }
  return request as Promise<T>;
}

export function normalizeArticleText(article:Pick<ConstitutionArticle,'maudhui'|'vifungu'>){const summary=String(article.maudhui||'').trim(),clauses=(article.vifungu||[]).map(x=>String(x||'').trim()).filter(Boolean);if(!clauses.length)return summary;if(!summary)return clauses.join('\n');const compact=(s:string)=>s.replace(/\s+/g,' ').trim();const normalizedSummary=compact(summary),normalizedClauses=compact(clauses.join(' '));if(normalizedSummary===normalizedClauses||clauses.every(x=>normalizedSummary.includes(compact(x))))return clauses.join('\n');return [summary,...clauses.filter(x=>!normalizedSummary.includes(compact(x)))].filter(Boolean).join('\n')}

export function getSource(documentId:string){
  return constitutionSources.find(s=>s.id===documentId);
}

export async function loadChapters(documentId:string){
  const source=getSource(documentId);
  if(!source) return [];
  const chapters:ConstitutionChapter[]=[];
  let names:string[]=[];
  try{names=await chapterManifest(source)}catch{return chapters}
  for(const name of names){
    try{
      const chapter=await fetchJson<ConstitutionChapter>(`${source.basePath}/${name}/${name}.json`);
      if(chapter.documentId===documentId) chapters.push(chapter);
    }catch{}
  }
  return chapters.sort((a,b)=>(a.chapterNumber??Number.MAX_SAFE_INTEGER)-(b.chapterNumber??Number.MAX_SAFE_INTEGER)||String((a as any).sura||(a as any).chapter||'').localeCompare(String((b as any).sura||(b as any).chapter||''),'sw'));
}

export async function loadArticle(documentId:string,chapterName:string,fileName:string){
  const source=getSource(documentId);
  if(!source) return undefined;
  try{
    return await fetchJson<ConstitutionArticle>(`${source.basePath}/${chapterName}/${fileName}`);
  }catch{
    return undefined;
  }
}

export async function loadArticleByNumber(documentId:string,articleNumber:string){
  const normalizedArticleNumber=decodeURIComponent(articleNumber).replace(/^(?:Ibara|Article)\s+/i,'').replace(/\.json$/i,'');
  const chapters=await loadChapters(documentId);
  for(const chapter of chapters){
    const file=chapter.ibara.find(name=>name.replace(/^(?:Ibara|Article)\s+/i,'').replace(/\.json$/i,'')===normalizedArticleNumber);
    if(file){
      const chapterName=(chapter as any).sura||(chapter as any).chapter;
      const article=await loadArticle(documentId,chapterName,file);
      if(article) return {article,chapter,fileName:file};
    }
  }
  return undefined;
}

export async function loadConstitutionExplanation(documentId:string,articleNumber:string|number){
  const source=getSource(documentId);if(!source)return undefined;
  const number=String(articleNumber).replace(/^(?:Ibara|Article)\s+/i,'').replace(/\.json$/i,'');
  const candidates=[
    source.basePath+'/Explanations/Ibara '+number+'.json',
    source.basePath+'/Explanations/Article '+number+'.json',
    source.basePath+'/explanations/Ibara '+number+'.json',
    source.basePath+'/explanations/Article '+number+'.json'
  ];
  for(const url of candidates){try{return await fetchJson<ConstitutionExplanation>(url)}catch{}}
  return undefined;
}

export async function loadAllArticles(documentId:string){
  const chapters=await loadChapters(documentId);
  const rows:ConstitutionArticle[]=[];
  for(const chapter of chapters){
    const chapterName=chapter.sura||chapter.chapter;
    if(!chapterName) continue;
    const loaded=await Promise.all(chapter.ibara.map(file=>loadArticle(documentId,chapterName,file)));
    rows.push(...loaded.filter((x):x is ConstitutionArticle=>Boolean(x)));
  }
  return rows;
}

export async function searchConstitution(query:string,documentId?:string){
  const q=query.trim().toLocaleLowerCase('sw');
  if(!q) return [];
  const tokens=q.split(/\s+/).filter(Boolean);
  const sources=documentId?constitutionSources.filter(s=>s.id===documentId):constitutionSources;
  const groups=await Promise.all(sources.map(async source=>{
    const articles=await loadAllArticles(source.id);
    return articles.map(article=>{
      const number=String(article.ibara).toLocaleLowerCase('sw'),title=(article.jina||'').toLocaleLowerCase('sw'),chapter=(article.sura||'').toLocaleLowerCase('sw'),part=(article.sehemu||'').toLocaleLowerCase('sw'),body=normalizeArticleText(article).toLocaleLowerCase('sw');
      const searchable=[number,title,chapter,part,body].join(' ');
      if(!tokens.every(token=>searchable.includes(token))) return null;
      let score=0;
      if(number===q||('ibara '+number)===q)score+=1000;
      if(title===q)score+=800;
      if(title.startsWith(q))score+=500;
      if(title.includes(q))score+=300;
      if(chapter.includes(q)||part.includes(q))score+=150;
      if(body.includes(q))score+=80;
      for(const token of tokens){if(number===token)score+=180;if(title.includes(token))score+=60;if(body.includes(token))score+=10}
      return {source,article,score};
    }).filter((x):x is {source:ConstitutionSource;article:ConstitutionArticle;score:number}=>Boolean(x));
  }));
  return groups.flat().sort((a,b)=>b.score-a.score||String(a.article.ibara).localeCompare(String(b.article.ibara),undefined,{numeric:true}));
}

export interface ConstitutionScheduleSearchResult {source:ConstitutionSource;schedule:ConstitutionSchedule;score:number;excerpt:string}
export async function searchSchedules(query:string,documentId?:string):Promise<ConstitutionScheduleSearchResult[]>{const q=query.trim().toLocaleLowerCase('en');if(!q)return[];const tokens=q.split(/\s+/).filter(Boolean);const sources=(documentId?constitutionSources.filter(s=>s.id===documentId):constitutionSources).filter(s=>s.language==='en');const groups=await Promise.all(sources.map(async source=>(await loadSchedules(source.id)).map(schedule=>{const body=[schedule.schedule,schedule.title||'',schedule.referredToIn||'',...(schedule.items||[]).map(x=>[x.number,x.reference||'',x.text].join(' ')),...(schedule.lists||[]).flatMap(x=>[x.name,x.referredToIn||'',x.description||'',...x.items.map(i=>[i.number||'',i.reference||'',i.text].join(' '))])].join(' ');const searchable=body.toLocaleLowerCase('en');if(!tokens.every(token=>searchable.includes(token)))return null;let score=80;if(schedule.schedule.toLocaleLowerCase('en').includes(q))score+=500;if((schedule.title||'').toLocaleLowerCase('en').includes(q))score+=350;const at=searchable.indexOf(q),start=Math.max(0,at>=0?at-70:0);return {source,schedule,score,excerpt:body.slice(start,start+260)};}).filter((x):x is ConstitutionScheduleSearchResult=>Boolean(x))));return groups.flat().sort((a,b)=>b.score-a.score)}

export interface SourceIntegrityIssue {sourceId:string;chapter?:string;file?:string;kind:'missing_chapter_index'|'missing_article'|'unreferenced_article'|'invalid_json'|'invalid_schedule'|'unverified_schedule';message:string}
export interface SourceIntegrityReport {manifestFiles:number;jsonFiles:number;chapterIndexes:number;articleFiles:number;referencedArticles:number;scheduleFiles:number;verifiedSchedules:number;issues:SourceIntegrityIssue[]}

export async function checkSourceIntegrity():Promise<SourceIntegrityReport>{
  const paths=await loadManifestPaths(),jsonPaths=paths.filter(p=>p.toLowerCase().endsWith('.json'));
  const issues:SourceIntegrityIssue[]=[];let chapterIndexes=0,articleFiles=0,referencedArticles=0,scheduleFiles=0,verifiedSchedules=0;
  for(const source of constitutionSources){
    const prefix=sourceManifestPrefix(source),sourcePaths=jsonPaths.filter(p=>p.startsWith(prefix));
    const chapters=new Map<string,Set<string>>();
    for(const path of sourcePaths){const rest=path.slice(prefix.length),parts=rest.split('/');if(parts.length<2)continue;const [chapter,file]=parts;if(chapter==='Schedules'){scheduleFiles++;try{const schedule=await fetchJson<ConstitutionSchedule>('/katiba/'+path);if(!schedule.documentId||!schedule.schedule||schedule.documentId!==source.id)issues.push({sourceId:source.id,chapter,file,kind:'invalid_schedule',message:'Schedule metadata haijakamilika au documentId hailingani.'});else if(schedule.chanzo?.verificationStatus==='verified')verifiedSchedules++;else issues.push({sourceId:source.id,chapter,file,kind:'unverified_schedule',message:'Schedule ipo kwenye manifest lakini source verification haijakamilika.'})}catch{issues.push({sourceId:source.id,chapter,file,kind:'invalid_json',message:'Schedule haiwezi kusomwa kama JSON.'})}continue}if(!chapters.has(chapter))chapters.set(chapter,new Set());chapters.get(chapter)!.add(file);if(/^(?:Ibara|Article) .+\.json$/i.test(file))articleFiles++}
    for(const [chapter,files] of chapters){
      const indexFile=chapter+'.json';
      if(!files.has(indexFile)){issues.push({sourceId:source.id,chapter,file:indexFile,kind:'missing_chapter_index',message:'Chapter index haipo kwenye manifest.'});continue}
      chapterIndexes++;
      let data:ConstitutionChapter;
      try{data=await fetchJson<ConstitutionChapter>(source.basePath+'/'+chapter+'/'+indexFile)}catch{issues.push({sourceId:source.id,chapter,file:indexFile,kind:'invalid_json',message:'Chapter index haiwezi kusomwa kama JSON.'});continue}
      const refs=new Set(data.ibara||[]);referencedArticles+=refs.size;
      for(const file of refs)if(!files.has(file))issues.push({sourceId:source.id,chapter,file,kind:'missing_article',message:'Ibara imetajwa na chapter index lakini file haipo kwenye manifest.'});
      for(const file of files)if(/^(?:Ibara|Article) .+\.json$/i.test(file)&&!refs.has(file))issues.push({sourceId:source.id,chapter,file,kind:'unreferenced_article',message:'Article file ipo kwenye manifest lakini haijatajwa na chapter index.'});
    }
  }
  return {manifestFiles:paths.length,jsonFiles:jsonPaths.length,chapterIndexes,articleFiles,referencedArticles,scheduleFiles,verifiedSchedules,issues};
}

export function articleFileName(articleNumber:number|string){
  return `Ibara ${articleNumber}.json`;
}


export interface ConstitutionSchedule {
  documentId:string;
  schedule:string;
  title?:string;
  referredToIn?:string;
  language?:'sw'|'en';
  items?:Array<{number?:number;reference?:string|null;text:string}>;
  lists?:Array<{name:string;referredToIn?:string;description?:string;items:Array<{number?:number;reference?:string|null;text:string}>}>;
  chanzo:SourceInfo&{authoritativeSource?:string;sourceDocument?:string};
}

export async function loadSchedules(documentId:string){
  const source=getSource(documentId);if(!source)return [];
  let paths:string[]=[];try{paths=await loadManifestPaths()}catch{return []}
  const prefix=sourceManifestPrefix(source)+'Schedules/';
  const files=paths.filter(p=>p.startsWith(prefix)&&p.toLowerCase().endsWith('.json'));
  const rows=await Promise.all(files.map(async p=>{try{return await fetchJson<ConstitutionSchedule>('/katiba/'+p)}catch{return undefined}}));
  return rows.filter((x):x is ConstitutionSchedule=>Boolean(x));
}

export async function loadSchedule(documentId:string,scheduleName:string){
  const rows=await loadSchedules(documentId),needle=decodeURIComponent(scheduleName).toLocaleLowerCase('en');
  return rows.find(x=>x.schedule.toLocaleLowerCase('en')===needle);
}
