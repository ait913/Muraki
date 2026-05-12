#!/usr/bin/env python3
"""Regenerate Muraki/knowledge/INDEX.md from all knowledge entries.

Walks:
- Muraki/knowledge/{library,pattern,gotcha,tool-quirk}/*.md  (cross-project)
- Muraki/projects/*/.knowledge/*.md                          (project-specific)

Reads YAML-ish frontmatter (title, category, project) and emits INDEX.md
grouped by category.
"""
from __future__ import annotations
from pathlib import Path
from datetime import date

ROOT = Path(__file__).resolve().parent.parent
KDIR = ROOT / "knowledge"
PDIR = ROOT / "projects"
CATS = ["library", "pattern", "gotcha", "tool-quirk"]


def parse_frontmatter(path: Path) -> dict:
    txt = path.read_text(encoding="utf-8")
    if not txt.startswith("---\n"):
        return {}
    end = txt.find("\n---\n", 4)
    if end == -1:
        return {}
    body = txt[4:end]
    out: dict = {}
    for line in body.splitlines():
        if ":" in line and not line.lstrip().startswith("-"):
            k, _, v = line.partition(":")
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def first_para(path: Path) -> str:
    txt = path.read_text(encoding="utf-8")
    if txt.startswith("---\n"):
        end = txt.find("\n---\n", 4)
        if end != -1:
            txt = txt[end + 5:]
    for line in txt.splitlines():
        s = line.strip()
        if s and not s.startswith("#") and not s.startswith(">"):
            return s[:120]
    return ""


def collect() -> dict:
    out: dict = {c: [] for c in CATS}
    out["other"] = []

    for cat in CATS:
        cat_dir = KDIR / cat
        if not cat_dir.is_dir():
            continue
        for md in sorted(cat_dir.glob("*.md")):
            if md.name.startswith("_"):
                continue
            fm = parse_frontmatter(md)
            out[cat].append({
                "title": fm.get("title", md.stem),
                "path": str(md.relative_to(KDIR)),
                "project": "global",
                "summary": first_para(md),
            })

    if PDIR.is_dir():
        for proj in sorted(PDIR.iterdir()):
            if not proj.is_dir():
                continue
            kd = proj / ".knowledge"
            if not kd.is_dir():
                continue
            for md in sorted(kd.glob("*.md")):
                if md.name.startswith("_"):
                    continue
                fm = parse_frontmatter(md)
                cat = fm.get("category", "other")
                target = out.get(cat, out["other"])
                target.append({
                    "title": fm.get("title", md.stem),
                    "path": f"../projects/{proj.name}/.knowledge/{md.name}",
                    "project": proj.name,
                    "summary": first_para(md),
                })
    return out


def render(out: dict) -> str:
    lines = [
        "# Knowledge Index",
        "",
        f"Generated: {date.today().isoformat()}",
        "",
        "_Run `python3 Muraki/scripts/gen-knowledge-index.py` to regenerate._",
        "",
    ]
    for cat in CATS:
        lines.append(f"## {cat}")
        if not out[cat]:
            lines.append("(なし)")
        else:
            for e in out[cat]:
                lines.append(
                    f"- [{e['title']}]({e['path']}) — `{e['project']}` — {e['summary']}"
                )
        lines.append("")
    if out["other"]:
        lines.append("## other (uncategorized)")
        for e in out["other"]:
            lines.append(
                f"- [{e['title']}]({e['path']}) — `{e['project']}` — {e['summary']}"
            )
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    KDIR.mkdir(parents=True, exist_ok=True)
    out = collect()
    (KDIR / "INDEX.md").write_text(render(out), encoding="utf-8")
    total = sum(len(v) for v in out.values())
    print(f"wrote {KDIR / 'INDEX.md'} ({total} entries)")


if __name__ == "__main__":
    main()
