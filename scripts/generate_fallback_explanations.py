#!/usr/bin/env python3
"""Deterministic fallback explanation generator — no LLM needed.

For each missing article, generates a minimal-but-valid explanation derived
purely from the article's source text. Safe defaults are used for fields
that need verified external info (examples [], history placeholder,
expertPerspectives []).

Output schema matches ConstitutionExplanation interface.

Usage:
    python3 generate_fallback_explanations.py --dataset=rasimu
"""
import argparse
import json
import re
from pathlib import Path

REPO = Path("/home/z/my-project/Katiba-Yetu-Web")
REPORT_PATH = REPO / "scripts" / "discovery_report.json"

DISCLAIMER = (
    "Ufafanuzi huu unarahisisha maandishi ya Ibara yaliyopo kwenye source ya mradi. "
    "Si maandishi rasmi ya Katiba wala ushauri wa kisheria."
)
HISTORY_PLACEHOLDER = {
    "summary": "Historia na marekebisho ya Ibara hii bado hayajaongezwa mpaka vyanzo rasmi vihakikiwe.",
    "notes": [],
}


def strip_bom(s: str) -> str:
    if s and s[0] == "\ufeff":
        return s[1:]
    return s


def load_article(path: Path) -> dict:
    return json.loads(strip_bom(path.read_text(encoding="utf-8")))


def build_plain_language(article: dict) -> str:
    """Build plain-language Swahili summary from article maudhui (1st sentence) + jina."""
    jina = (article.get("jina") or "").strip()
    maudhui = (article.get("maudhui") or "").strip()
    if not maudhui:
        if jina:
            return f'Ibara hii inaitwa "{jina}". Maandishi yake bado hayajawekwa kikamilifu kwenye source.'
        return "Maandishi ya Ibara hii bado hayajawekwa kikamilifu kwenye source."
    # Use first sentence of maudhui as plain language
    # Try to split on common Swahili sentence terminators
    parts = re.split(r'(?<=[.!?])\s+', maudhui)
    first = parts[0] if parts else maudhui
    intro = f'Ibara hii ({jina}) ' if jina else "Ibara hii "
    return intro + "inasema: " + first


def build_meaning(article: dict) -> str:
    """Build meaning/athari from the article maudhui (use 2nd sentence if available)."""
    jina = (article.get("jina") or "").strip()
    maudhui = (article.get("maudhui") or "").strip()
    vifungu = article.get("vifungu") or []
    if not maudhui and not vifungu:
        return "Maana ya kisheria ya Ibara hii inategemea maandishi yaliyopo kwenye source ya mradi."
    parts = re.split(r'(?<=[.!?])\s+', maudhui)
    if len(parts) > 1:
        # Use the second sentence as the meaning
        meaning = parts[1]
    elif maudhui:
        meaning = maudhui
    else:
        meaning = "Ibara inaweka masharti yaliyo orodheshwa kwenye vifungu vyake."
    ctx = f"Katika muktadha wa {jina}, " if jina else ""
    return ctx + "maana ya kisheria ni: " + meaning


def build_key_points(article: dict) -> list:
    """Use the article's vifungu (sub-clauses) as key points, falling back to jina-based points."""
    vifungu = article.get("vifungu") or []
    if isinstance(vifungu, list) and len(vifungu) > 0:
        # Use each sub-clause (truncated for readability)
        points = []
        for i, v in enumerate(vifungu, 1):
            text = str(v).strip()
            # Truncate at 220 chars
            if len(text) > 220:
                text = text[:217] + "..."
            points.append(f"({i}) {text}")
        return points
    # Fallback: derive 2-3 points from maudhui
    maudhui = (article.get("maudhui") or "").strip()
    if maudhui:
        parts = re.split(r'(?<=[.!?])\s+', maudhui)
        points = []
        for p in parts[:3]:
            p = p.strip()
            if len(p) > 220:
                p = p[:217] + "..."
            if p:
                points.append(p)
        if len(points) >= 1:
            return points
    # Last resort: single generic point
    jina = article.get("jina") or "Ibara hii"
    return [f"Ibara hii ({jina}) inaweka masharti yake mahususi."]


def extract_legal_terms(article: dict) -> list:
    """Extract candidate legal terms from the article text using simple patterns.
    Only includes terms that appear with capital letters or in quotes — these are
    likely proper nouns or defined terms in the source text."""
    maudhui = article.get("maudhui") or ""
    vifungu = article.get("vifungu") or []
    full_text = maudhui
    if isinstance(vifungu, list):
        full_text += " " + " ".join(str(v) for v in vifungu)

    terms = []
    seen = set()

    # Pattern 1: Quoted terms like "Jamhuri ya Muungano wa Tanzania"
    for m in re.finditer(r'"([^"]{3,60})"', full_text):
        term = m.group(1).strip()
        if term not in seen and len(term) >= 3:
            seen.add(term)
            terms.append({
                "term": term,
                "meaning": "Neno/taarifa iliyotajwa kwenye maandishi ya Ibara hii.",
            })

    # Pattern 2: Capitalized multi-word phrases (proper nouns)
    # Match sequences of 2-4 Capitalized words
    for m in re.finditer(r'\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,3})\b', full_text):
        term = m.group(1).strip()
        # Filter out common false positives
        if term in seen:
            continue
        if term.startswith("Ibara") or term.startswith("Sura"):
            continue
        if len(term) < 5:
            continue
        seen.add(term)
        if len(terms) >= 6:
            break
        terms.append({
            "term": term,
            "meaning": "Jina au neno la kisheria linaloonekana kwenye maandishi ya Ibara hii.",
        })

    return terms[:6]


def build_debate_question(article: dict) -> str:
    """Generate a debate question derived from the article title."""
    jina = (article.get("jina") or "").strip()
    if jina:
        return f'Je, masharti yaliyowekwa katika "{jina}" yanatosha kutekeleza lengo la Ibara hii?'
    return "Je, masharti ya Ibara hii yanatosha kutekeleza lengo lake?"


def build_explanation(article: dict, dataset: str) -> dict:
    """Build a minimal-but-valid explanation from the article source text."""
    rasimu_note = ""
    if dataset == "rasimu":
        rasimu_note = " (Rasimu ya Katiba — si nakala ya Katiba inayotumika)"
    return {
        "plainLanguage": build_plain_language(article) + rasimu_note,
        "meaning": build_meaning(article),
        "keyPoints": build_key_points(article),
        "legalTerms": extract_legal_terms(article),
        "examples": [],
        "history": dict(HISTORY_PLACEHOLDER),
        "expertPerspectives": [],
        "debateQuestion": build_debate_question(article),
        "disclaimer": DISCLAIMER,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", required=True, choices=["union", "zanzibar", "rasimu"])
    ap.add_argument("--limit", type=int, default=None)
    args = ap.parse_args()

    report = json.loads(strip_bom(REPORT_PATH.read_text(encoding="utf-8")))
    ds = report.get(args.dataset)
    if not ds:
        print(f"Dataset {args.dataset} not found", file=__import__('sys').stderr)
        __import__('sys').exit(1)

    # Re-discover missing at runtime
    to_process = []
    for a in ds["articles"]:
        if (REPO / a["explanation_path"]).exists():
            continue
        to_process.append(a)
    if args.limit:
        to_process = to_process[: args.limit]

    total = len(to_process)
    print(f"[{args.dataset}] Generating {total} fallback explanations (no LLM)...")

    success = 0
    failed = 0
    for i, entry in enumerate(to_process):
        try:
            article = load_article(REPO / entry["article_path"])
            explanation = build_explanation(article, args.dataset)
            # Validate it can be JSON-serialized
            json_str = json.dumps(explanation, ensure_ascii=False, indent=2)
            # Re-parse to verify
            json.loads(json_str)
            out_path = REPO / entry["explanation_path"]
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_text(json_str + "\n", encoding="utf-8")
            success += 1
            pct = (i + 1) / total * 100
            print(f"  [{i + 1}/{total}] {pct:5.1f}% OK: {entry['filename']}")
        except Exception as e:
            failed += 1
            print(f"  [{i + 1}/{total}] FAIL: {entry['filename']} — {e}")

    print(f"\n[{args.dataset}] Done. Success: {success}, Failed: {failed}")


if __name__ == "__main__":
    main()
