#!/usr/bin/env python3
"""Discover all Constitution articles across the three datasets and identify
which explanations are missing.

Outputs a JSON file describing:
- union: list of {article_path, article_number, explanation_path, exists}
- zanzibar: same
- rasimu: same
"""
import json
import os
import re
from pathlib import Path

REPO = Path("/home/z/my-project/Katiba-Yetu-Web")
KATIBA = REPO / "public" / "katiba"

DATASETS = [
    {
        "name": "union",
        "source_root": KATIBA / "Katiba" / "Tanzania",
        "explanation_dir": KATIBA / "Katiba" / "Tanzania" / "Explanations",
        "rasimu": False,
    },
    {
        "name": "zanzibar",
        "source_root": KATIBA / "Katiba" / "Zanzibar",
        "explanation_dir": KATIBA / "Katiba" / "Zanzibar" / "Explanations",
        "rasimu": False,
    },
    {
        "name": "rasimu",
        "source_root": KATIBA / "Rasimu za Katiba" / "Tanzania",
        "explanation_dir": KATIBA / "Rasimu za Katiba" / "Tanzania" / "Explanations",
        "rasimu": True,
    },
]


def ibara_filename_from_article(article_path: Path) -> str:
    """Given an article path like .../Sura ya Kwanza/Ibara 1.json, return 'Ibara 1.json'."""
    return article_path.name


def discover_dataset(name: str, source_root: Path, explanation_dir: Path, rasimu: bool):
    """Walk the source_root recursively and find all Ibara *.json files (article files only,
    not Sura ya X.json chapter files)."""
    articles = []
    if not source_root.exists():
        return articles
    for root, dirs, files in os.walk(source_root):
        # Skip the Explanations directory itself
        if "Explanations" in Path(root).parts:
            continue
        for fname in sorted(files):
            if not fname.startswith("Ibara ") or not fname.endswith(".json"):
                continue
            article_path = Path(root) / fname
            # Build the matching explanation path
            explanation_path = explanation_dir / fname
            articles.append({
                "article_path": str(article_path.relative_to(REPO)),
                "explanation_path": str(explanation_path.relative_to(REPO)),
                "explanation_exists": explanation_path.exists(),
                "filename": fname,
                "dataset": name,
            })
    return articles


def main():
    report = {}
    for ds in DATASETS:
        articles = discover_dataset(ds["name"], ds["source_root"], ds["explanation_dir"], ds["rasimu"])
        # Make sure explanation directory exists
        ds["explanation_dir"].mkdir(parents=True, exist_ok=True)
        existing = sum(1 for a in articles if a["explanation_exists"])
        missing = sum(1 for a in articles if not a["explanation_exists"])
        report[ds["name"]] = {
            "source_root": str(ds["source_root"].relative_to(REPO)),
            "explanation_dir": str(ds["explanation_dir"].relative_to(REPO)),
            "total_articles": len(articles),
            "existing_explanations": existing,
            "missing_explanations": missing,
            "articles": articles,
        }
        print(f"[{ds['name']}] {len(articles)} articles, {existing} existing, {missing} missing")

    # Save full report
    out_path = REPO / "scripts" / "discovery_report.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nReport saved to {out_path}")


if __name__ == "__main__":
    main()
