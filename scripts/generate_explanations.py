#!/usr/bin/env python3
"""Bulk Constitution Explanation Generator using z-ai CLI.

Reads discovery_report.json, processes each missing explanation by calling
the z-ai chat CLI, parses the JSON response, validates the schema, and saves
the file. Idempotent — skips articles that already have an explanation file.

Usage:
    python3 generate_explanations.py --dataset=union [--limit=N] [--offset=N]
    python3 generate_explanations.py --dataset=zanzibar
    python3 generate_explanations.py --dataset=rasimu
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path("/home/z/my-project/Katiba-Yetu-Web")
REPORT_PATH = REPO / "scripts" / "discovery_report.json"
LOG_PATH = REPO / "scripts" / "generation_log.csv"

SYSTEM_PROMPT = """Wewe ni mtaalamu wa Katiba ya Tanzania unaotoa ufafanuzi wa lugha rahisi kwa Kiswahili.

KAZI YAKO:
- Soma maandishi rasmi ya Ibara iliyotolewa.
- Andika ufafanuzi wa Kiswahili sanifu unaoeleza Ibara kwa urahisi bila kupotosha.
- Tumia TU maandishi yaliyotolewa. USITUMIE maarifa ya kawaida kujaza pengo.
- USITUMIE maneno ya kisheria yasiyoonekana kwenye maandishi.
- USITAFUTI kesi, marekebisho, au maoni ya wataalamu. AZIMA TU kutoka kwenye maandishi.
- Kama huwezi kutoa mifano inayoingia akilini kutoka kwenye maandishi yenyewe, tumia [] (orodha tupu).

SCHEMA YA OUTPUT (JSON tu, hakuna maoni ya ziada, hakuna markdown code fences):
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
- examples: daima [] (orodha tupu)
- history: daima tumia placeholder iliyo hapo juu
- expertPerspectives: daima []
- legalTerms: TOA tu maneno ya kisheria yaliyopo KARIBU sana kwenye maandishi
- Hakuna kitu cha kubahatisha - kama huhakiki, acha

RUDISHA JSON tu bila maandishi ya ziada, bila markdown, bila code blocks.anza na { na maliza na }."""


def strip_bom(s: str) -> str:
    if s and s[0] == "\ufeff":
        return s[1:]
    return s


def load_article(path: Path) -> dict:
    raw = path.read_text(encoding="utf-8")
    return json.loads(strip_bom(raw))


def build_user_message(article: dict, dataset: str) -> str:
    ctx = []
    ctx.append(f"DATASET: {dataset}")
    if article.get("sura"):
        ctx.append(f"SURA: {article['sura']}")
    if article.get("sehemu"):
        ctx.append(f"SEHEMU: {article['sehemu']}")
    if article.get("jina"):
        ctx.append(f"JINA LA IBARA: {article['jina']}")
    if article.get("ibara") is not None:
        ctx.append(f"NAMBA YA IBARA: {article['ibara']}")
    if article.get("maudhui"):
        ctx.append(f"MAUDHUI: {article['maudhui']}")
    vifungu = article.get("vifungu") or []
    if isinstance(vifungu, list) and len(vifungu) > 0:
        ctx.append("VIFUNGU (sub-clauses):")
        for i, v in enumerate(vifungu):
            ctx.append(f"  ({i + 1}) {v}")
    chanzo = article.get("chanzo") or {}
    if chanzo.get("verificationStatus") == "pending":
        ctx.append("TAARIFA: Ibara hii bado haijathibitishwa kikamilifu. Ufafanuzi unapaswa kueleza tu yaliyomo - usidai kuwa kuna marekebisho yaliyothibitishwa.")
    ctx.append("")
    ctx.append("Andika ufafanuzi wa JSON kulingana na schema mahsusi. Rudisha JSON tu, bila markdown fences.")
    return "\n".join(ctx)


def validate_explanation(obj) -> None:
    if not isinstance(obj, dict):
        raise ValueError("not object")
    required = ["plainLanguage", "meaning", "keyPoints", "legalTerms", "examples", "history", "expertPerspectives", "debateQuestion", "disclaimer"]
    for k in required:
        if k not in obj:
            raise ValueError(f"missing field: {k}")
    if not isinstance(obj["plainLanguage"], str) or len(obj["plainLanguage"].strip()) < 10:
        raise ValueError("plainLanguage too short")
    if not isinstance(obj["meaning"], str) or len(obj["meaning"].strip()) < 10:
        raise ValueError("meaning too short")
    if not isinstance(obj["keyPoints"], list) or len(obj["keyPoints"]) < 2:
        raise ValueError("keyPoints must have 2+")
    if not isinstance(obj["legalTerms"], list):
        raise ValueError("legalTerms must be array")
    if not isinstance(obj["examples"], list):
        raise ValueError("examples must be array")
    if not isinstance(obj["history"], dict):
        raise ValueError("history must be object")
    if not isinstance(obj["expertPerspectives"], list):
        raise ValueError("expertPerspectives must be array")
    if not isinstance(obj["debateQuestion"], str):
        raise ValueError("debateQuestion must be string")
    if not isinstance(obj["disclaimer"], str):
        raise ValueError("disclaimer must be string")


def extract_json(text: str) -> dict:
    text = strip_bom(text).strip()
    # Remove markdown code fences if present
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*\n", "", text)
        text = re.sub(r"\n```\s*$", "", text)
    # Try direct parse
    try:
        return json.loads(text)
    except Exception:
        pass
    # Try to find first { ... } block
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        slice = text[start : end + 1]
        return json.loads(slice)
    raise ValueError("no JSON found in response")


def call_zai(system: str, user: str, timeout: int = 90, retries: int = 2) -> str:
    """Invoke the z-ai chat CLI and return the assistant's content text.
    Retries with longer backoff on rate-limit (429) / network errors."""
    last_err = None
    for attempt in range(retries):
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False, mode="w+") as tf:
            out_path = tf.name
        try:
            cmd = [
                "z-ai", "chat",
                "--system", system,
                "--prompt", user,
                "--output", out_path,
            ]
            result = subprocess.run(
                cmd,
                timeout=timeout,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )
            if result.returncode != 0:
                err_msg = result.stderr.decode("utf-8", errors="replace")[:500]
                # Rate limit (429) / API error → retry with long backoff
                if "Failed to make API request" in err_msg or "429" in err_msg or "Too many requests" in err_msg:
                    last_err = RuntimeError(f"z-ai 429 rate limited")
                    wait = 60 * (attempt + 1)  # 60s, 120s
                    time.sleep(wait)
                    continue
                raise RuntimeError(f"z-ai exited {result.returncode}: {err_msg}")
            with open(out_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
            if not content:
                raise RuntimeError("empty content")
            return content
        except subprocess.TimeoutExpired:
            last_err = RuntimeError("z-ai timed out")
            time.sleep(30 * (attempt + 1))
            continue
        finally:
            try:
                os.unlink(out_path)
            except OSError:
                pass
    raise last_err or RuntimeError("z-ai failed after retries")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", required=True, choices=["union", "zanzibar", "rasimu"])
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--offset", type=int, default=0)
    ap.add_argument("--delay", type=float, default=0.3, help="Delay between calls (sec)")
    ap.add_argument("--abort-after-fails", type=int, default=5,
                    help="Abort batch after N consecutive failures (default 5)")
    args = ap.parse_args()

    report = json.loads(strip_bom(REPORT_PATH.read_text(encoding="utf-8")))
    ds = report.get(args.dataset)
    if not ds:
        print(f"Dataset {args.dataset} not found", file=sys.stderr)
        sys.exit(1)

    to_process = [a for a in ds["articles"] if not a["explanation_exists"]]
    # Re-check existence at runtime (in case we already started)
    to_process = [a for a in to_process if not (REPO / a["explanation_path"]).exists()]
    to_process = to_process[args.offset:]
    if args.limit:
        to_process = to_process[: args.limit]

    total = len(to_process)
    print(f"[{args.dataset}] Processing {total} missing explanations "
          f"(of {ds['total_articles']} total articles, {ds['existing_explanations']} existing)")

    # Init log
    write_header = not LOG_PATH.exists()
    if write_header:
        with LOG_PATH.open("w", encoding="utf-8") as f:
            f.write("timestamp,dataset,article_path,status,error\n")

    success = 0
    failed = 0
    failures = []
    consecutive_fails = 0

    for i, entry in enumerate(to_process):
        article_path = REPO / entry["article_path"]
        explanation_path = REPO / entry["explanation_path"]
        ts = time.strftime("%Y-%m-%dT%H:%M:%S")
        try:
            article = load_article(article_path)
            user_msg = build_user_message(article, args.dataset)
            content = call_zai(SYSTEM_PROMPT, user_msg)
            try:
                obj = extract_json(content)
            except ValueError as json_err:
                # Retry: ask LLM to fix the malformed JSON
                fix_prompt = (
                    "Hii JSON iliyotolewa haina format sahihi: "
                    + str(json_err)
                    + "\n\nAndika tena JSON kamili sahihi kulingana na schema. Rudisha JSON tu.\n\nContent ya awali:\n"
                    + content[:3000]
                )
                content2 = call_zai(SYSTEM_PROMPT, fix_prompt)
                obj = extract_json(content2)
            validate_explanation(obj)
            explanation_path.parent.mkdir(parents=True, exist_ok=True)
            explanation_path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            success += 1
            consecutive_fails = 0
            pct = (i + 1) / total * 100
            print(f"  [{i + 1}/{total}] {pct:5.1f}% OK: {entry['filename']}")
            with LOG_PATH.open("a", encoding="utf-8") as f:
                f.write(f"{ts},{args.dataset},{entry['article_path']},ok,\n")
        except Exception as e:
            failed += 1
            consecutive_fails += 1
            err = str(e).replace(",", ";").replace("\n", " ")[:300]
            failures.append({"article": entry["article_path"], "error": err})
            print(f"  [{i + 1}/{total}] FAIL: {entry['filename']} — {err}")
            with LOG_PATH.open("a", encoding="utf-8") as f:
                f.write(f"{ts},{args.dataset},{entry['article_path']},fail,{err}\n")
            # Early abort if too many consecutive failures (rate limit)
            if consecutive_fails >= args.abort_after_fails:
                print(f"\n[{args.dataset}] ABORTED: {consecutive_fails} consecutive failures — "
                      f"likely persistent rate limit. Stopping to avoid wasting time.")
                break
        if args.delay > 0:
            time.sleep(args.delay)

    print(f"\n[{args.dataset}] Done. Success: {success}, Failed: {failed}")
    if failures:
        print("First 5 failures:")
        for f in failures[:5]:
            print(f"  - {f['article']}: {f['error']}")


if __name__ == "__main__":
    main()
