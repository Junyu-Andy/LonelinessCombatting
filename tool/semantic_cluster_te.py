#!/usr/bin/env python3
"""
DMP Layer 11 — Thought Exercise semantic clustering (lab-side derived
analysis, NOT real-time, NOT user-facing in Phase A).

Per Phase A Proposal §7.6 + Product Overview §5.2 §"Server-side semantic
pattern analysis":

  Per-user clustering of the anonymised Thought Exercise corpus to
  identify thematically connected cognitions over time.  Visible only in
  the researcher dashboard, never to users in Phase A.  Phase B decides
  based on Phase A whether to surface a user-facing version.

Pipeline:
  1.  Pull anonymised TE entries from the analyst-blind weekly export
      NDJSON files (`gs://{bucket}/exports/{date}/thought_exercise.ndjson`).
  2.  For each entry, concatenate Field 1 (situation) + Field 3 (thought).
  3.  Compute a multilingual sentence embedding
      (default: text-embedding-3-small; configurable).
  4.  Per-user (per uidHash) HDBSCAN clustering with cosine distance,
      min_cluster_size=2.
  5.  LLM-generated descriptive cluster labels (descriptive only).
  6.  Output per-user metrics: cluster count, average cluster size,
      semantic spread; plus per-cluster artefacts.
  7.  Manual quality review on 30%: clusters rated 1–5 on coherence;
      <3 excluded from downstream analysis.

This script is the runnable shell of the pipeline.  Embedding + LLM
calls are stubbed behind environment variables so the script runs in
demo mode without external services.

Usage:
  python tool/semantic_cluster_te.py \
    --input exports/2026-05-17/thought_exercise.ndjson \
    --output analysis/te_clusters_2026-W20/ \
    [--embedding-model text-embedding-3-small] \
    [--label-model deepseek-chat] \
    [--demo]                     # skip external calls; synthetic output

Dependencies (production):
  pip install hdbscan numpy scikit-learn openai
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import Path


def load_entries(path: Path) -> list[dict]:
    """Read NDJSON; each line is one TE entry (post-blinding)."""
    entries = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            entries.append(json.loads(line))
    return entries


def group_by_user(entries: list[dict]) -> dict[str, list[dict]]:
    groups: dict[str, list[dict]] = defaultdict(list)
    for e in entries:
        uid = e.get("uidHash") or "unknown"
        groups[uid].append(e)
    return groups


def compose_text(entry: dict) -> str:
    """Concat Field 1 (situation) + Field 3 (thought) for embedding."""
    parts = []
    if entry.get("situation"):
        parts.append(entry["situation"])
    if entry.get("thought"):
        parts.append(entry["thought"])
    return " | ".join(parts)


def embed_texts(texts: list[str], model: str, demo: bool) -> list[list[float]]:
    """Stub.  Production: call the embedding API in batches of ≤100."""
    if demo:
        # Tiny deterministic synthetic embedding so the rest of the
        # pipeline runs without an API key.
        return [[float((hash(t + str(i)) % 1000) / 1000.0) for i in range(8)]
                for t in texts]
    # Production path — requires `openai` package configured.
    try:
        from openai import OpenAI  # noqa: F401
    except ImportError:
        sys.exit("[semantic_cluster] openai package not installed; "
                 "run with --demo or pip install openai")
    sys.exit("[semantic_cluster] production embedding not implemented in "
             "the shell.  Wire OPENAI_API_KEY + the call to "
             "client.embeddings.create() here before running.")


def cluster_user(embeddings: list[list[float]]) -> list[int]:
    """HDBSCAN min_cluster_size=2 with cosine distance.  Falls back to
    a trivial 1-per-cluster output in demo mode if hdbscan is missing."""
    try:
        import hdbscan  # noqa
        import numpy as np  # noqa
    except ImportError:
        return list(range(len(embeddings)))  # one cluster per entry
    import numpy as np
    import hdbscan
    if len(embeddings) < 2:
        return [-1] * len(embeddings)  # noise
    arr = np.array(embeddings, dtype=float)
    # Cosine distance via 1 - cosine similarity
    norms = np.linalg.norm(arr, axis=1, keepdims=True)
    arr_n = arr / np.where(norms == 0, 1, norms)
    sim = arr_n @ arr_n.T
    dist = 1 - sim
    np.fill_diagonal(dist, 0)
    clusterer = hdbscan.HDBSCAN(
        min_cluster_size=2, metric="precomputed",
    )
    labels = clusterer.fit_predict(dist.astype("float64"))
    return labels.tolist()


def label_cluster(texts: list[str], model: str, demo: bool) -> str:
    if demo:
        # Take the first 12 chars of the first text as a fake label.
        first = (texts[0] or "")[:12]
        return f"[demo] {first}…"
    sys.exit("[semantic_cluster] production cluster labelling not "
             "implemented in the shell.")


def per_user_metrics(labels: list[int]) -> dict[str, float]:
    from collections import Counter
    counts = Counter(l for l in labels if l != -1)
    cluster_count = len(counts)
    avg_cluster_size = (sum(counts.values()) / cluster_count) if cluster_count else 0
    noise = sum(1 for l in labels if l == -1)
    return {
        "n_entries": len(labels),
        "cluster_count": cluster_count,
        "avg_cluster_size": avg_cluster_size,
        "noise_count": noise,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True,
                        help="NDJSON path: anonymised TE entries")
    parser.add_argument("--output", required=True,
                        help="Output directory")
    parser.add_argument("--embedding-model", default="text-embedding-3-small")
    parser.add_argument("--label-model", default="deepseek-chat")
    parser.add_argument("--demo", action="store_true",
                        help="Skip external API calls; emit synthetic output")
    args = parser.parse_args()

    in_path = Path(args.input)
    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    entries = load_entries(in_path)
    print(f"[semantic_cluster] loaded {len(entries)} entries from {in_path}")

    groups = group_by_user(entries)
    summary: dict[str, dict] = {}

    for uid, user_entries in groups.items():
        texts = [compose_text(e) for e in user_entries]
        embs = embed_texts(texts, args.embedding_model, demo=args.demo)
        labels = cluster_user(embs)
        metrics = per_user_metrics(labels)
        per_cluster_texts: dict[int, list[str]] = defaultdict(list)
        for t, l in zip(texts, labels):
            per_cluster_texts[l].append(t)
        cluster_labels = {
            l: label_cluster(ts, args.label_model, demo=args.demo)
            for l, ts in per_cluster_texts.items() if l != -1
        }
        summary[uid] = {
            "metrics": metrics,
            "cluster_labels": cluster_labels,
            "label_assignment": labels,
        }

    out_path = out_dir / "per_user_clusters.json"
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
    print(f"[semantic_cluster] wrote {out_path}")
    print(f"[semantic_cluster] users processed: {len(summary)}")


if __name__ == "__main__":
    main()
