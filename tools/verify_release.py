#!/usr/bin/env python3
"""Verify a coordinated multiplatform release directory against its release_manifest.json.

Usage: verify_release.py <out-dir> --sha <full-40-char-source-sha> [--require windows,linux,android,patch]

Fails (non-zero) if: the manifest is missing/invalid, its source SHA differs from the approved SHA, any required
platform artifact is missing/empty or its recorded sha256/size does not match the file, or any artifact claims a
different source SHA. Missing platforms are never skipped silently.
"""
import argparse, hashlib, json, os, sys


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("--sha", required=True)
    ap.add_argument("--require", default="windows,linux,android,patch")
    a = ap.parse_args()
    errs = []
    mpath = os.path.join(a.out_dir, "release_manifest.json")
    if not os.path.isfile(mpath):
        print("FAIL: release_manifest.json missing"); return 1
    m = json.load(open(mpath))
    src = m.get("source", {})
    if len(a.sha) != 40:
        errs.append("approved SHA must be the full 40-char commit id")
    if src.get("sha") != a.sha:
        errs.append(f"manifest source sha {src.get('sha')} != approved sha {a.sha}")
    for k in ("ref", "app_version", "build", "built_at", "engine"):
        if not src.get(k) and not m.get(k):
            errs.append(f"manifest missing field: {k}")
    arts = {x.get("platform"): x for x in m.get("artifacts", [])}
    for plat in [p for p in a.require.split(",") if p]:
        x = arts.get(plat)
        if not x:
            errs.append(f"required platform artifact missing from manifest: {plat}"); continue
        path = os.path.join(a.out_dir, x["file"])
        if not os.path.isfile(path) or os.path.getsize(path) == 0:
            errs.append(f"{plat}: file missing or empty: {x['file']}"); continue
        if os.path.getsize(path) != x.get("size"):
            errs.append(f"{plat}: size mismatch for {x['file']}")
        if sha256(path) != x.get("sha256"):
            errs.append(f"{plat}: sha256 mismatch for {x['file']}")
        if x.get("source_sha") != a.sha:
            errs.append(f"{plat}: artifact built from {x.get('source_sha')} not {a.sha}")
    if errs:
        print("RELEASE VERIFICATION FAILED:")
        for e in errs: print("  -", e)
        return 1
    print(f"Release verified: {len(arts)} artifacts, all from {a.sha[:7]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
