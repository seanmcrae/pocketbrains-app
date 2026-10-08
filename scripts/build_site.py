"""Build the static docs site (GitHub Pages) from a CI build log and the repo docs.

Every number on the site is parsed from the ``EVALJSON`` and test-summary lines that
the iOS test suite prints in CI (``build.log`` and ``build-embedding.log`` in the
``ios-build-log`` artifact). Prose comes from README.md and docs/*.md, so the site never
drifts from the repository. Output is plain HTML and CSS; Mermaid diagrams render from a
CDN when it is reachable and otherwise stay readable as source.

    pip install -r docs/site/requirements.txt
    python3 scripts/build_site.py --log build.log --embedding-log build-embedding.log \\
        --run-id 123 --out site

Without ``--log`` the site still builds, with a notice in place of the eval tables.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import markdown
from jinja2 import Environment, FileSystemLoader, select_autoescape

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / "docs" / "site"
REPO_URL = "https://github.com/seanmcrae/pocketbrains-app"
PAGES_URL = "https://seanmcrae.github.io/pocketbrains-app/"
MD_EXTENSIONS = ["tables", "fenced_code", "sane_lists", "toc"]
MERMAID_BLOCK = re.compile(r"```mermaid\n(.*?)```", flags=re.DOTALL)

# README sections shown on the landing page, in order.
README_SECTIONS = ("In 60 seconds", "Architecture", "Why on-device", "Build and run", "Limitations")

# Doc pages: output name, source, heading.
DOC_PAGES = (
    ("architecture.html", "docs/ARCHITECTURE.md", "Architecture"),
    ("product.html", "docs/PRODUCT.md", "Product brief"),
    ("verification.html", "docs/VERIFICATION.md", "Verification checklist"),
)

# How each router split may be used. Order is the display order.
SPLIT_ROLES: dict[str, tuple[str, str]] = {
    "v1 canonical": ("gated", "documented phrasing (v0.1)"),
    "v1 paraphrase": ("tuned", "seen during v0.2 tuning"),
    "v2 canonical": ("gated", "documented phrasing (v0.2 tools)"),
    "v2 compound": ("gated", "multi-step requests"),
    "v2 dev paraphrase": ("tuned", "v0.2 dev split"),
    "v0.2 held-out (reported)": ("honest", "frozen; score published with v0.2"),
    "v0.3 dev paraphrase": ("tuned", "v0.3 dev split, the only one v0.3 tuned on"),
    "v0.3 held-out (frozen)": ("honest", "frozen before v0.3 router work; never tuned"),
    "original 40 (v1)": ("", "the v0.1 corpus, for continuity"),
    "overall": ("", "every case"),
}


@dataclass(frozen=True)
class Stat:
    label: str
    value: str
    detail: str


@dataclass(frozen=True)
class Table:
    title: str
    anchor: str
    intro: str
    headers: list[str]
    rows: list[list[str]]


@dataclass
class EvalLog:
    records: list[dict[str, Any]]
    tests: str | None

    def router(self) -> dict[str, dict[str, Any]]:
        return {r["split"]: r for r in self.records if r.get("suite") == "router"}

    def trim(self) -> dict[tuple[int, str], dict[str, Any]]:
        return {(int(r["k"]), r["split"]): r for r in self.records if r.get("suite") == "trim"}

    def rag(self) -> list[dict[str, Any]]:
        """One record per method; a later log (the embedding step) wins."""
        by_method: dict[str, dict[str, Any]] = {}
        for r in self.records:
            if r.get("suite") == "rag":
                by_method[r["method"]] = r
        return list(by_method.values())

    def latency(self) -> dict[str, Any] | None:
        return next((r for r in self.records if r.get("suite") == "latency"), None)


def read_log(*paths: Path | None) -> EvalLog:
    """EVALJSON records and the Swift Testing summary from one or more build logs."""
    records: list[dict[str, Any]] = []
    tests: str | None = None
    for path in paths:
        if path is None or not path.exists():
            continue
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if "EVALJSON " in line:
                payload = line.split("EVALJSON ", 1)[1].strip()
                try:
                    records.append(json.loads(payload))
                except json.JSONDecodeError:
                    continue
            found = re.search(r"Test run with (\d+) tests? in (\d+) suites? passed", line)
            if found and tests is None:
                tests = f"{found.group(1)} tests in {found.group(2)} suites"
    return EvalLog(records, tests)


def pct(value: float | None) -> str:
    return "n/a" if value is None else f"{100 * value:.1f}%"


def role_tag(split: str) -> str:
    kind, _ = SPLIT_ROLES.get(split, ("", ""))
    labels = {"gated": "gated", "tuned": "dev", "honest": "held-out"}
    return f'<span class="tag {kind}">{labels[kind]}</span>' if kind else ""


def router_table(current: EvalLog, baseline: EvalLog | None) -> Table:
    now, before = current.router(), (baseline.router() if baseline else {})
    headers = ["Split", "Role", "n"]
    if before:
        headers += ["Tool (before)", "End-to-end (before)"]
    headers += ["Tool accuracy", "End-to-end"]
    rows = []
    for split in [s for s in SPLIT_ROLES if s in now] + [s for s in now if s not in SPLIT_ROLES]:
        r = now[split]
        row = [split, role_tag(split) + " " + SPLIT_ROLES.get(split, ("", ""))[1], str(r["n"])]
        if before:
            b = before.get(split)
            row += [pct(b["tool"]) if b else "n/a", pct(b["e2e"]) if b else "n/a"]
        row += [pct(r["tool"]), f"<strong>{pct(r['e2e'])}</strong>"]
        rows.append(row)
    return Table(
        "Deterministic router",
        "router",
        "Every utterance runs through the deterministic brain's real entry point against a "
        "freshly seeded in-memory store. Tool accuracy: the right tool (for compound requests, "
        "the exact sequence). End-to-end: right tool, every call succeeded, and the resulting "
        "state is right. The v0.3 held-out row is the honest generalization number.",
        headers,
        rows,
    )


def trim_table(log: EvalLog) -> Table | None:
    trim = log.trim()
    if not trim:
        return None
    splits = [s for s in SPLIT_ROLES if (8, s) in trim]
    rows = []
    for split in splits:
        six, eight = trim.get((6, split)), trim[(8, split)]
        rows.append([split, role_tag(split), str(eight["n"]),
                     pct(six["recall"]) if six else "n/a", f"<strong>{pct(eight['recall'])}</strong>"])
    return Table(
        "Tool trimming for the Foundation Models brain (recall@k)",
        "trimming",
        "Share of cases whose expected tool (every step, for compound requests) is inside the "
        "set <code>ToolSelector</code> would offer the on-device model, out of 24 tools. This "
        "measures the trim, not the model. The selector reuses the deterministic grammar, so "
        "canonical rows are not independent of it.",
        ["Split", "Role", "n", "recall@6", "recall@8"],
        rows,
    )


def rag_table(log: EvalLog) -> tuple[Table | None, list[str]]:
    notes: list[str] = []
    rows = []
    for r in log.rag():
        if "skipped" in r:
            notes.append(f"Retrieval eval, {r['method']}: skipped ({r['skipped']}).")
            continue
        rows.append([r["method"], str(r["n"]), pct(r["recall_at_1"]), pct(r["recall_at_3"]),
                     pct(r["span_hit"]), f"{pct(r['citation_faithfulness'])} of {r['markers']}",
                     pct(r["span_attribution"])])
    if not rows:
        return None, notes
    table = Table(
        "Ask your notes (retrieval and citations)",
        "rag",
        "Synthetic fixture of 22 notes and 61 questions, each with one relevant note and an "
        "answer span. recall@k: the relevant note is among the notes of the top k passages. "
        "Citation faithfulness: every <code>[n]</code> in the extractive answer follows a "
        "sentence found in a retrieved passage of note n. Span attribution: when the answer "
        "contains the span, its <code>[n]</code> points at a passage that contains the span.",
        ["Method", "n", "recall@1", "recall@3", "Answer contains span", "Citation faithfulness",
         "Span attribution"],
        rows,
    )
    return table, notes


def headline_stats(log: EvalLog) -> list[Stat]:
    stats: list[Stat] = []
    router = log.router()
    if log.tests:
        stats.append(Stat("Tests passing", log.tests.split(" ")[0], f"Swift Testing, {log.tests}, CI simulator"))
    if (held := router.get("v0.3 held-out (frozen)")) is not None:
        stats.append(Stat("Held-out paraphrases, end-to-end", pct(held["e2e"]),
                          f"{held['n']} utterances never used for tuning (deterministic brain)"))
    trim = log.trim()
    if (overall := trim.get((8, "overall"))) is not None:
        stats.append(Stat("Tool trimming recall@8", pct(overall["recall"]),
                          f"expected tool kept when offering 8 of 24 tools, {overall['n']} cases"))
    bm25 = next((r for r in log.rag() if r.get("method") == "bm25" and "skipped" not in r), None)
    if bm25 is not None:
        stats.append(Stat("Notes retrieval recall@3", pct(bm25["recall_at_3"]),
                          f"BM25, {bm25['n']} synthetic questions"))
    return stats


def rewrite_links(text: str) -> str:
    """Point repo-relative links at their site page or at GitHub."""
    pages = {"docs/PRODUCT.md": "product.html", "docs/ARCHITECTURE.md": "architecture.html",
             "docs/VERIFICATION.md": "verification.html", "PRODUCT.md": "product.html",
             "ARCHITECTURE.md": "architecture.html", "VERIFICATION.md": "verification.html"}
    for source, page in pages.items():
        text = text.replace(f"]({source})", f"]({page})")
    text = text.replace("](docs/img/", "](img/")
    return re.sub(r"\]\((?!https?://|#|img/|[a-z]+\.html)([^)]+)\)", rf"]({REPO_URL}/blob/main/\1)", text)


def render_markdown(text: str, md: markdown.Markdown | None = None) -> str:
    def diagram(match: re.Match[str]) -> str:
        source = match.group(1).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        return f'\n<pre class="mermaid">\n{source}</pre>\n'

    converter = md or markdown.Markdown(extensions=MD_EXTENSIONS)
    return converter.convert(MERMAID_BLOCK.sub(diagram, rewrite_links(text)))


def split_sections(text: str) -> dict[str, str]:
    """Markdown body of each ``## `` section, keyed by heading text."""
    sections: dict[str, str] = {}
    current: str | None = None
    lines: list[str] = []
    in_fence = False
    for line in text.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
        if not in_fence and line.startswith("## "):
            if current is not None:
                sections[current] = "\n".join(lines).strip()
            current, lines = line[3:].strip(), []
        elif current is not None:
            lines.append(line)
    if current is not None:
        sections[current] = "\n".join(lines).strip()
    return sections


def marketing_version() -> str:
    found = re.search(r'MARKETING_VERSION: "([^"]+)"', (ROOT / "project.yml").read_text(encoding="utf-8"))
    return found.group(1) if found else "unreleased"


def build_site(out_dir: Path, log: EvalLog, baseline: EvalLog | None, run_id: str | None,
               baseline_run_id: str | None) -> Path:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    (out_dir / "img").mkdir(parents=True)
    shutil.copyfile(ROOT / "docs" / "img" / "icon-256.png", out_dir / "img" / "icon-256.png")

    env = Environment(loader=FileSystemLoader(TEMPLATES), autoescape=select_autoescape(["html"]))
    common = {
        "repo_url": REPO_URL,
        "pages_url": PAGES_URL,
        "css": (TEMPLATES / "style.css").read_text(encoding="utf-8"),
        "version": marketing_version(),
        "run_id": run_id,
        "mermaid": True,
    }

    tables: list[Table] = []
    notes: list[str] = []
    if log.records:
        tables.append(router_table(log, baseline if baseline and baseline.records else None))
        if (trim := trim_table(log)) is not None:
            tables.append(trim)
        rag, rag_notes = rag_table(log)
        if rag is not None:
            tables.append(rag)
        notes += rag_notes
        if (latency := log.latency()) is not None:
            notes.append(f"Routing plus tool execution latency on the CI simulator (in-memory store): "
                         f"p50 {latency['p50_ms']:.2f} ms, p95 {latency['p95_ms']:.2f} ms. "
                         "Latency varies between runner instances; accuracy is deterministic.")

    readme = split_sections((ROOT / "README.md").read_text(encoding="utf-8"))
    missing = [s for s in README_SECTIONS if s not in readme]
    if missing:
        raise KeyError(f"README.md is missing sections the site renders: {missing}")
    sections = [(title, re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-"), render_markdown(readme[title]))
                for title in README_SECTIONS]

    index = env.get_template("index.html").render(
        **common,
        title="PocketBrains: an on-device AI chief of staff for iOS",
        stats=headline_stats(log) if log.records else [],
        tables=tables,
        notes=notes,
        sections=sections,
        baseline_run_id=baseline_run_id if baseline and baseline.records else None,
    )
    (out_dir / "index.html").write_text(index, encoding="utf-8")

    for name, source, heading in DOC_PAGES:
        md = markdown.Markdown(extensions=MD_EXTENSIONS)
        body_md = (ROOT / source).read_text(encoding="utf-8").split("\n", 1)[1]  # drop the H1
        body = render_markdown(body_md, md)
        page = env.get_template("doc.html").render(
            **common, title=f"PocketBrains: {heading.lower()}", heading=heading, body=body,
            toc=md.toc_tokens,  # type: ignore[attr-defined]
        )
        (out_dir / name).write_text(page, encoding="utf-8")
    (out_dir / ".nojekyll").write_text("", encoding="utf-8")
    return out_dir


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the PocketBrains docs site.")
    parser.add_argument("--log", type=Path, help="build.log from the CI iOS job")
    parser.add_argument("--embedding-log", type=Path, help="build-embedding.log from the same job")
    parser.add_argument("--run-id", help="GitHub Actions run id the logs came from")
    parser.add_argument("--baseline-log", type=Path, help="build.log of a 'before' run, optional")
    parser.add_argument("--baseline-run-id", help="run id of the baseline log")
    parser.add_argument("--out", type=Path, default=Path("site"))
    args = parser.parse_args()
    log = read_log(args.log, args.embedding_log)
    baseline = read_log(args.baseline_log) if args.baseline_log else None
    out = build_site(args.out, log, baseline, args.run_id, args.baseline_run_id)
    found = f"{len(log.records)} eval records" if log.records else "no eval records (notice shown)"
    print(f"wrote {out}/index.html and {len(DOC_PAGES)} doc pages from {found}")


if __name__ == "__main__":
    main()
