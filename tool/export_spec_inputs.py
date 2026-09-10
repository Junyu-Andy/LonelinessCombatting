#!/usr/bin/env python3
"""export_spec_inputs.py — regenerate the spec hand-off packs in docs/spec_inputs/.

Two files are produced, both marked GENERATED:

  docs/spec_inputs/agent_system_prompts_v1.md
      The three companion system prompts verbatim, plus everything the
      runtime adds around them (variant substitution, context suffix,
      per-agent decoding temperature, safety acknowledgements).

  docs/spec_inputs/safety_lexicon_v4.md
      The DistressDetector term inventory, extracted from the Dart source
      rather than retyped, plus matching semantics and open decisions.

Why generated and not hand-written: the sources of truth are
`functions/prompts/*.txt` (loaded by the Cloud Function at cold start) and
`lib/core/safety/distress_detector.dart` (compiled into the app). A manual
copy in docs/ silently drifts the moment either changes. Re-run this after
any prompt or lexicon edit:

    python3 tool/export_spec_inputs.py

No dependencies, no network, no API key.
"""

from __future__ import annotations

import re
import subprocess
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROMPT_DIR = ROOT / "functions" / "prompts"
DETECTOR = ROOT / "lib" / "core" / "safety" / "distress_detector.dart"
OUT_DIR = ROOT / "docs" / "spec_inputs"

AGENTS = [
    # (prompt key, display, agent id, temperature, PPR sub-component, owned modules)
    ("siu_yan_v1", "小欣 / Siu Yan", "siu_yan", "0.7", "PPR-Caring",
     "M2 daily check-in, M9 motivational + weekly narrative"),
    ("ah_jan_ah_bak_v1", "阿珍／阿伯 / Ah Jan · Ah Bak", "ah_jan_ah_bak", "0.5",
     "PPR-Understanding", "M3 reminiscence (4 themes), reflective dialogue"),
    ("tung_tung_v1", "通通 / Tung Tung", "tung_tung", "0.85",
     "PPR-Social-Integration", "Curious companion, article Q&A, search"),
]


def git_sha() -> str:
    try:
        out = subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True)
        return out.stdout.strip()
    except Exception:
        return "unknown"


def banner(sources: list[str]) -> str:
    src = "\n".join(f">   - {s}" for s in sources)
    return (
        "\n> **GENERATED FILE — do not edit by hand.**\n"
        "> Produced by `tool/export_spec_inputs.py` from:\n"
        f"{src}\n"
        f">\n"
        f"> Source commit `{git_sha()}` · exported {date.today().isoformat()}.\n"
        "> Edit the sources and re-run the exporter; edits made here are lost\n"
        "> and, worse, make the spec disagree with what actually ships.\n"
    )


# --------------------------------------------------------------------------
# Pack 1 — system prompts
# --------------------------------------------------------------------------

def build_prompts_doc() -> str:
    parts: list[str] = []
    parts.append("# Spec input — companion system prompts (verbatim)\n")
    parts.append(banner([
        "`functions/prompts/siu_yan_v1.txt`",
        "`functions/prompts/ah_jan_ah_bak_v1.txt`",
        "`functions/prompts/tung_tung_v1.txt`",
        "`functions/prompts/safety_acknowledgements.json`",
        "`functions/index.js` — assembly, decoding params, prompt hash",
        "`lib/core/agents/persona_resolver.dart` — context suffix",
    ]))
    parts.append("""
## What "the system prompt" means at runtime

The file text below is **not** the whole system message the model sees. The
Cloud Function assembles it, in this order, in `resolvePrompt()`
(`functions/index.js`):

1. `functions/prompts/{promptKey}.txt` — the text in this document.
2. `{{VARIANT_NAME}}` substituted (Ah Jan / Ah Bak only). The client sends the
   participant's chosen variant display name (`阿珍` feminine / `阿伯`
   masculine); with no selection the function falls back to the literal
   string `阿珍／阿伯`.
3. `\\n\\n` + `contextSuffix` — built client-side by `PersonaResolver` and
   appended verbatim server-side. Its shape is fixed (see next section).

The assembled string is then SHA-256 hashed after whitespace collapsing
(`computePromptHash`) and the digest written onto the turn document, so an
analyst can prove which prompt produced which turn. Arm B turns write
`systemPromptHash: null`.

Call parameters, same for all three agents unless noted:

| Parameter | Value |
| --- | --- |
| Model | `deepseek-chat` (DeepSeek-V3), endpoint `api.deepseek.com` |
| `max_tokens` | 800 |
| `top_p` | 0.95 |
| `temperature` | per agent — see the table below |
| Timeout | 55 s (Cloud Function), region `asia-east2` |
| Outgoing PII | every message passed through `stripPII()`; auth uid replaced by a per-call coded session id |

| Agent | `agentId` | Prompt key | Temperature | PPR sub-component | Owns |
| --- | --- | --- | --- | --- | --- |
""")
    for key, display, aid, temp, ppr, modules in AGENTS:
        parts.append(f"| {display} | `{aid}` | `{key}` | {temp} | {ppr} | {modules} |\n")
    parts.append("""
Temperatures are documented in `functions/index.js` as *starting* values to be
micro-tuned with `tool/agent_prompt_bench.py` — treat them as provisional in
the spec, not as locked constants.

## The context suffix (appended to every prompt, all three agents)

Composed by `PersonaResolver.resolve()`. Blocks are emitted only when they
have content, in this order. The first block is **always** present once a
profile exists — it is the Appendix A anti-fabrication guardrail:

```text
[過往摘要]
{rolling summary, or 「（暫時未有，今次係第一次同佢傾偈）」 when empty}
[注意] 只可以引用上面真實寫咗嘅嘢；上面空嘅就當第一次傾，唔好扮記得任何嘢。

[Named entities recently mentioned]
- {name} ({type}, x{mentions})     ← top 5, most-recently-mentioned first

[Theme threads]
- {theme}: {thread}

[Recent mood snippet]
{shared mood summary}              ← Siu Yan only (includeSharedMood)
```

Note the mismatch worth resolving in the spec: the prompt files describe the
injected context as `rolling_summary` / `named_entities` / `recent_mood` /
`module_id` / `theme` / `theme_threads`, but the resolver actually emits the
Chinese-labelled blocks above and does **not** inject `module_id` or `theme`
into the suffix at all — modules pass those separately. Either the prompt text
or the resolver is describing something that does not exist.

## Safety interaction (why these prompts are not the safety layer)

`DistressDetector` runs client-side before the LLM call. At **acute** the call
is short-circuited in `LlmGateway.complete()`
(`lib/core/llm/llm_gateway.dart:115` — returns empty text with
`shortCircuited: true`): the participant sees the crisis surface, and the model
is never consulted, so no prompt text below can affect an acute turn. At
**moderate** the model does answer, and the overlay is surfaced after. The
templated acknowledgements at the end of this document are shown verbatim, not
generated.

---
""")

    for key, display, _aid, _t, _ppr, _m in AGENTS:
        text = (PROMPT_DIR / f"{key}.txt").read_text(encoding="utf-8").rstrip("\n")
        parts.append(f"\n## {display} — `functions/prompts/{key}.txt`\n\n")
        parts.append("```text\n" + text + "\n```\n")

    acks = (PROMPT_DIR / "safety_acknowledgements.json").read_text(encoding="utf-8").rstrip("\n")
    parts.append("\n## Templated safety acknowledgements — "
                 "`functions/prompts/safety_acknowledgements.json`\n\n")
    parts.append("Surfaced verbatim when the detector raises moderate-or-above. "
                 "The LLM is not consulted on these turns.\n\n")
    parts.append("```json\n" + acks + "\n```\n")
    return "".join(parts)


# --------------------------------------------------------------------------
# Pack 2 — safety lexicon
# --------------------------------------------------------------------------

STRING_RE = re.compile(r'"([^"]*)"|\'([^\']*)\'')


def extract_list(src: str, name: str) -> list[tuple[str, list[str]]]:
    """Return [(group comment, [terms])] for a `static const _name = <String>[...]`."""
    start = src.index(f"static const _{name} = <String>[")
    body_start = src.index("[", start) + 1
    end = src.index("];", body_start)
    body = src[body_start:end]

    groups: list[tuple[str, list[str]]] = []
    current = ("(ungrouped)", [])
    groups.append(current)
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("//"):
            label = stripped[2:].strip()
            current = (label, [])
            groups.append(current)
            continue
        for m in STRING_RE.finditer(line):
            current[1].append(m.group(1) if m.group(1) is not None else m.group(2))
    return [(label, terms) for label, terms in groups if terms]


def render_tier(title: str, routing: str, groups: list[tuple[str, list[str]]]) -> str:
    total = sum(len(t) for _, t in groups)
    out = [f"\n### {title} — {total} terms\n\n{routing}\n"]
    for label, terms in groups:
        out.append(f"\n**{label}** ({len(terms)})\n\n")
        out.append("".join(f"- `{t}`\n" for t in terms))
    return "".join(out)


def build_lexicon_doc() -> str:
    src = DETECTOR.read_text(encoding="utf-8")
    version = re.search(r"wordlistVersion = '([^']+)'", src).group(1)

    acute = extract_list(src, "acute")
    moderate = extract_list(src, "moderate")
    low = extract_list(src, "low")
    n = lambda g: sum(len(t) for _, t in g)  # noqa: E731

    parts = [f"# Spec input — safety lexicon `{version}` (full term inventory)\n"]
    parts.append(banner([
        "`lib/core/safety/distress_detector.dart` — the terms, source of truth",
        "`docs/safety/distress_detector_lexicon_v4-2026-07.md` — the v3→v4 policy record",
    ]))
    parts.append(f"""
The policy narrative — why each v3→v4 change was made, which are approved and
which are not — lives in `docs/safety/distress_detector_lexicon_v4-2026-07.md`
and is **not** duplicated here. This file is the enumerated list, so the spec
can state coverage without anyone retyping {n(acute) + n(moderate) + n(low)} terms.

## Matching semantics

- Input lower-cased, then plain **substring `contains`**. No tokenisation, no
  word boundaries, no negation or sarcasm handling, no normalisation of
  script variants at match time.
- Tiers are checked **acute → moderate → low → none**; first tier with any hit
  wins. This order is load-bearing: several acute terms contain moderate terms
  (`真係想死` ⊃ `想死`), and reversing the order would silently downgrade them.
- Only the *first* matched term is recorded (`DistressMatch.matchedTerm`), for
  analytics and audit. It is never shown to the participant.
- Deterministic and identical in both arms, by design — safety equivalence
  between Arm A and Arm B requires the trigger not to depend on the LLM.
- 冇-based terms are explicitly enumerated in three script forms (冇 / 沒 / 無),
  with 没 forms in the simplified sections. Over-generation is deliberate: an
  unnatural variant is a substring that never occurs, so it costs list size,
  not precision.

## Tier sizes

| Tier | Terms | Routing |
| --- | --- | --- |
| acute | {n(acute)} | full-screen crisis page (hotline / 999); LLM call short-circuited; research team notified within 24 h |
| moderate | {n(moderate)} | soft bottom sheet after the reply; flagged for weekly research review |
| low | {n(low)} | pill only; copy may soften; no escalation |
| none | — | nothing |

## Open items that block a final spec

1. **D4 — hopelessness tier is not signed off.** `冇晒希望` / `没有希望` were
   demoted acute → moderate so escalation does not depend on which script the
   participant types. This is applied in code *for testing*, pending PI
   clinical sign-off, and the reviewer may instead choose option B (unify at
   acute, fail-safe). The spec cannot state a final hopelessness rule until
   that comes back. Everything downstream of it — expected acute recall,
   crisis-page trigger rate — moves with the decision.
2. **D3 — harm-to-others routes to the suicide crisis surface.** First-person
   harm-to-others terms currently open the same hotline / 999 page as suicidal
   ideation. Whether that matches the Phase A HREC protocol's handling of
   harm-to-others disclosure is unverified.
3. **No precision (negative) set in the corpus.** Recall is measured; the
   false-positive rate is not. The required negative set is listed in the
   policy doc under "Corpus additions required before ship".
4. **Accepted residual false positives** (also in the policy doc): `熱到想死`
   → moderate, `燒炭爐` → acute, `失去咗份工` → moderate, `唔小心𠝹手` → acute.
   These are deliberate fail-safe choices, not bugs, and the spec should say so
   explicitly rather than leave a reviewer to rediscover them.

---

## Full term inventory
""")
    parts.append(render_tier(
        "Acute", "Self-harm / suicidal ideation. Optimised for recall — a false "
        "negative is the unsafe outcome.", acute))
    parts.append(render_tier(
        "Moderate", "Hopelessness, burden cognitions, recent loss / grief. "
        "Balances recall and precision — over-triggering pesters.", moderate))
    parts.append(render_tier(
        "Low", "Persistent loneliness, sadness, isolation. Precision-leaning; "
        "never escalates.", low))
    return "".join(parts)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, content in (
        ("agent_system_prompts_v1.md", build_prompts_doc()),
        ("safety_lexicon_v4.md", build_lexicon_doc()),
    ):
        path = OUT_DIR / name
        path.write_text(content, encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)} ({len(content)} chars)")


if __name__ == "__main__":
    main()
