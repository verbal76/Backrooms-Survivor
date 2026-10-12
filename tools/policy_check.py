#!/usr/bin/env python3
"""Repository policy check (CI + local): makes the Single-Source-of-Truth policy testable.

Fails if the persistent policy docs are missing, the release workflow regresses (silent skips, unpinned source,
no guard/verify), or platform-forked code directories appear. Run from the repo root: python3 tools/policy_check.py
"""
import os, re, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
errs = []


def read(p):
    try:
        return open(os.path.join(root, p), encoding="utf-8").read()
    except OSError:
        errs.append(f"missing file: {p}"); return ""


claude = read("CLAUDE.md")
if "SINGLE-SOURCE-OF-TRUTH POLICY" not in claude:
    errs.append("CLAUDE.md must contain the 'SINGLE-SOURCE-OF-TRUTH POLICY' section")
if "docs/ENGINEERING_POLICY.md" not in claude:
    errs.append("CLAUDE.md must link docs/ENGINEERING_POLICY.md")
for f in ("docs/ENGINEERING_POLICY.md", "docs/PLATFORMS.md", "docs/RECOVERY_LEDGER.md", "tools/verify_release.py",
          "tools/branch_inventory.sh", "godot/tools/smoke_test.gd"):
    read(f)

wf = read(".github/workflows/dev-build.yml")
if re.search(r"continue-on-error:\s*true", wf):
    errs.append("release workflow must not use continue-on-error: true (no silent platform skips)")
for needle in ("guard:", "needs.guard.outputs.sha", "tools/verify_release.py", "smoke_test.gd", "release_manifest.json",
               "git merge-base --is-ancestor"):
    if needle not in wf:
        errs.append(f"release workflow is missing required safeguard: {needle}")

# no platform-forked game logic
for bad in ("godot/scripts/android", "godot/scripts/windows", "godot/scripts/linux", "godot/scripts/steamdeck",
            "godot_android", "godot_windows", "android_version", "windows_version"):
    if os.path.exists(os.path.join(root, bad)):
        errs.append(f"platform-forked code path is not allowed: {bad}")

if errs:
    print("POLICY CHECK FAILED:")
    for e in errs: print("  -", e)
    sys.exit(1)
print("policy check passed")
