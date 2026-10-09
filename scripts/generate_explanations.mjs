// Bulk Constitution Explanation Generator
//
// Reads the discovery report, processes each missing explanation by calling
// the z-ai-web-dev-sdk LLM with the article's source text, parses the JSON
// response, validates the schema, and saves the file.
//
// Usage:
//   node scripts/generate_explanations.mjs --dataset=union
//   node scripts/generate_explanations.mjs --dataset=zanzibar
//   node scripts/generate_explanations.mjs --dataset=rasimu
//   node scripts/generate_explanations.mjs --dataset=union --limit=20
//   node scripts/generate_explanations.mjs --dataset=union --resume
//
// Idempotent: skips articles that already have an explanation file.

import ZAI from 'z-ai-web-dev-sdk';
import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';

const REPO = '/home/z/my-project/Katiba-Yetu-Web';
const REPORT_PATH = join(REPO, 'scripts', 'discovery_report.json');
const LOG_PATH = join(REPO, 'scripts', 'generation_log.csv');

// Parse args
const args = Object.fromEntries(
  process.argv.slice(2).map(a => {
    const m = a.match(/^--([\w-]+)(?:=(.*))?$/);
    return [m[1], m[2] ?? 'true'];
  })
);
const DATASET = args.dataset;
const LIMIT = args.limit ? parseInt(args.limit, 10) : null;
const RESUME = args.resume === 'true';

if (!DATASET || !['union', 'zanzibar', 'rasimu'].includes(DATASET)) {
  console.error('Usage: node generate_explanations.mjs --dataset=union|zanzibar|rasimu [--limit=N] [--resume=true]');
  process.exit(1);
}

const SYSTEM_PROMPT = `Wewe ni mtaalamu wa Katiba ya Tanzania unaotoa ufafanuzi wa lugha rahisi kwa Kiswahili.

KAZI YAKO:
- Soma maandishi rasmi ya Ibara iliyotolewa.
- Andika ufafanuzi wa Kiswahili sanifu unaoeleza Ibara kwa urahisi bila kupotosha.
- Tumia TU maandishi yaliyotolewa. USITUMIE maarifa ya kawaida kujaza pengo.
- USITUMIE maneno ya kisheria yasiyoonekana kwenye maandishi.
- USITAFUTI kesi, marekebisho, au maoni ya wataalamu. AZIMA TU kutoka kwenye maandishi.
- Kama huwezi kutoa mifano inayoingia akilini kutoka kwenye maandishi yenyewe, tumia [] (orodha tupu).

SCHEMA YA OUTPUT (JSON tu, hakuna maoni ya ziada):
{
  "plainLanguage": "string - eleza Ibara kwa Kiswahili sanifu (angalau sentensi 2-3)",
  "meaning": "string - eleza maana ya kisheria / athari ya Ibara (angalau sentensi 2-3)",
  "keyPoints": ["string", "string", ...] - orodha ya pointi muhimu zinazotokana na maandishi (angalau 3)",
  "legalTerms": [
    {"term": "string - neno la kisheria kutoka Ibara", "meaning": "string - maana yake kwa Kiswahili"}
  ],
  "examples": [],
  "history": {
    "summary": "Historia na marekebisho ya Ibara hii bado hayajaongezwa mpaka vyanzo rasmi vihakikiwe.",
    "notes": []
  },
  "expertPerspectives": [],
  "debateQuestion": "string - swali moja la mjadala linaloingia akilini kutoka kwenye Ibara",
  "disclaimer": "Ufafanuzi huu unarahisisha maandishi ya Ibara yaliyopo kwenye source ya mradi. Si maandishi rasmi ya Katiba wala ushauri wa kisheria."
}

MKANGA MUHIMU:
- examples: daima [] (orodha tupu) - tutaongeza mifano baadaye kama inahitajika
- history: daima tumia placeholder iliyo hapo juu - tusitafute marekebisho
- expertPerspectives: daima [] - hatuna wataalamu waliothibitishwa
- legalTerms: TOA tu maneno ya kisheria yaliyopo KARIBU sana kwenye maandishi
- Hakuna kitu cha kubahatisha - kama huhakiki, acha

RUDISHA JSON tu bila maandishi ya ziada, bila markdown, bila code blocks.`;

function buildUserMessage(article, dataset) {
  const ctx = [];
  ctx.push(`DATASET: ${dataset}`);
  if (article.sura) ctx.push(`SURA: ${article.sura}`);
  if (article.sehemu) ctx.push(`SEHEMU: ${article.sehemu}`);
  if (article.jina) ctx.push(`JINA LA IBARA: ${article.jina}`);
  ctx.push(`NAMBA YA IBARA: ${article.ibara}`);
  if (article.maudhui) ctx.push(`MAUDHUI: ${article.maudhui}`);
  if (Array.isArray(article.vifungu) && article.vifungu.length > 0) {
    ctx.push(`VIFUNGU (sub-clauses):`);
    article.vifungu.forEach((v, i) => ctx.push(`  (${i + 1}) ${v}`));
  }
  if (article.chanzo?.verificationStatus === 'pending') {
    ctx.push(`TAARIFA: Ibara hii bado haijathibitishwa kikamilifu. Ufafanuzi unapaswa kueleza tu yaliyomo - usidai kuwa kuna marekebisho yaliyothibitishwa.`);
  }
  ctx.push(``);
  ctx.push(`Andika ufafanuzi wa JSON kulingana na schema mahsusi. Rudisha JSON tu.`);
  return ctx.join('\n');
}

function stripBOM(s) {
  if (s.charCodeAt(0) === 0xFEFF) return s.slice(1);
  return s;
}

async function loadArticle(articlePath) {
  const raw = await readFile(articlePath, 'utf8');
  return JSON.parse(stripBOM(raw));
}

function validateExplanation(obj) {
  if (typeof obj !== 'object' || obj === null) throw new Error('not object');
  const required = ['plainLanguage', 'meaning', 'keyPoints', 'legalTerms', 'examples', 'history', 'expertPerspectives', 'debateQuestion', 'disclaimer'];
  for (const k of required) {
    if (!(k in obj)) throw new Error(`missing field: ${k}`);
  }
  if (typeof obj.plainLanguage !== 'string' || obj.plainLanguage.trim().length < 10) throw new Error('plainLanguage too short');
  if (typeof obj.meaning !== 'string' || obj.meaning.trim().length < 10) throw new Error('meaning too short');
  if (!Array.isArray(obj.keyPoints) || obj.keyPoints.length < 2) throw new Error('keyPoints must have 2+');
  if (!Array.isArray(obj.legalTerms)) throw new Error('legalTerms must be array');
  if (!Array.isArray(obj.examples)) throw new Error('examples must be array');
  if (typeof obj.history !== 'object') throw new Error('history must be object');
  if (!Array.isArray(obj.expertPerspectives)) throw new Error('expertPerspectives must be array');
  if (typeof obj.debateQuestion !== 'string') throw new Error('debateQuestion must be string');
  if (typeof obj.disclaimer !== 'string') throw new Error('disclaimer must be string');
  return true;
}

function extractJson(text) {
  // LLM may return JSON with code fences or prose around it
  // Try direct parse first
  try { return JSON.parse(text); } catch {}
  // Try to find first { ... } block
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start !== -1 && end !== -1 && end > start) {
    const slice = text.slice(start, end + 1);
    try { return JSON.parse(slice); } catch (e) { throw new Error('JSON parse failed: ' + e.message); }
  }
  throw new Error('no JSON found in response');
}

async function main() {
  const reportRaw = await readFile(REPORT_PATH, 'utf8');
  const report = JSON.parse(stripBOM(reportRaw));
  const ds = report[DATASET];
  if (!ds) {
    console.error(`Dataset ${DATASET} not found in report`);
    process.exit(1);
  }

  // Filter to missing only (or all if RESUME, then re-check existence at runtime)
  let toProcess = ds.articles.filter(a => !a.explanation_exists);
  // Re-check existence (in case we've already started)
  toProcess = toProcess.filter(a => !existsSync(join(REPO, a.explanation_path)));
  if (LIMIT) toProcess = toProcess.slice(0, LIMIT);

  console.log(`[${DATASET}] Processing ${toProcess.length} missing explanations (of ${ds.total_articles} total articles, ${ds.existing_explanations} existing)`);

  const zai = await ZAI.create();
  let success = 0, failed = 0;
  const failures = [];

  // Init log
  const logHeader = 'timestamp,dataset,article_path,status,error\n';
  const logExists = existsSync(LOG_PATH);
  if (!logExists) await writeFile(LOG_PATH, logHeader, 'utf8');

  for (let i = 0; i < toProcess.length; i++) {
    const entry = toProcess[i];
    const articlePath = join(REPO, entry.article_path);
    const explanationPath = join(REPO, entry.explanation_path);
    const ts = new Date().toISOString();
    try {
      const article = await loadArticle(articlePath);
      const userMessage = buildUserMessage(article, DATASET);
      const completion = await zai.chat.completions.create({
        messages: [
          { role: 'assistant', content: SYSTEM_PROMPT },
          { role: 'user', content: userMessage },
        ],
        thinking: { type: 'disabled' },
      });
      const raw = completion.choices[0]?.message?.content;
      if (!raw || raw.trim().length === 0) throw new Error('empty LLM response');
      const obj = extractJson(raw);
      validateExplanation(obj);
      // Ensure explanation directory exists
      await mkdir(dirname(explanationPath), { recursive: true });
      await writeFile(explanationPath, JSON.stringify(obj, null, 2) + '\n', 'utf8');
      success++;
      const pct = ((i + 1) / toProcess.length * 100).toFixed(1);
      console.log(`  [${i + 1}/${toProcess.length}] ${pct}% OK: ${entry.filename}`);
      await writeFile(LOG_PATH, `${ts},${DATASET},${entry.article_path},ok,\n`, { flag: 'a' });
    } catch (e) {
      failed++;
      failures.push({ article: entry.article_path, error: e.message });
      console.error(`  [${i + 1}/${toProcess.length}] FAIL: ${entry.filename} — ${e.message}`);
      await writeFile(LOG_PATH, `${ts},${DATASET},${entry.article_path},fail,${(e.message || '').replace(/,/g, ';')}\n`, { flag: 'a' });
    }
    // Small delay to avoid rate limits
    if ((i + 1) % 10 === 0) await new Promise(r => setTimeout(r, 500));
  }

  console.log(`\n[${DATASET}] Done. Success: ${success}, Failed: ${failed}`);
  if (failures.length > 0) {
    console.log('Failures:');
    failures.forEach(f => console.log(`  - ${f.article}: ${f.error}`));
  }
}

main().catch(e => {
  console.error('Fatal:', e);
  process.exit(1);
});
