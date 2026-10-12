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
for f in ("docs/ENGINEERING_POLICY.md", "docs/PLATFORM_SUPPORT.md", "docs/BRANCH_LEDGER.md", "tools/verify_release.py",
          "tools/branch_inventory.sh", "tools/verify_artifacts.py", "tools/test_release_tools.py", "tools/platforms.py", "docs/RELEASES.md", "godot/tools/smoke_test.gd", "godot/tools/regression_tests.gd"):
    read(f)

wfdir = os.path.join(root, ".github", "workflows")
wf_all = ""
for fn in sorted(os.listdir(wfdir)) if os.path.isdir(wfdir) else []:
    wf_all += read(f".github/workflows/{fn}")
build_all = read(".github/workflows/build-all.yml")
dev_build = read(".github/workflows/dev-build.yml")
validate = read(".github/workflows/validate-build.yml")
release_build = read(".github/workflows/release-build.yml")
if re.search(r"continue-on-error:\s*true", wf_all):
    errs.append("workflows must not use continue-on-error: true (no silent platform skips)")
for needle in ("guard:", "needs.guard.outputs.sha", "tools/verify_release.py", "tools/verify_artifacts.py",
               "smoke_test.gd", "regression_tests.gd", "release_manifest.json", "git merge-base --is-ancestor"):
    if needle not in build_all:
        errs.append(f"build-all.yml is missing required safeguard: {needle}")
for plat in ("Windows", "Linux", "Android"):
    if f"Export {plat}" not in build_all:
        errs.append(f"build-all.yml must export {plat}")
if "uses: ./.github/workflows/build-all.yml" not in dev_build:
    errs.append("dev-build.yml must call the shared build-all.yml (one pipeline for release and validation)")
if "uses: ./.github/workflows/build-all.yml" not in validate:
    errs.append("validate-build.yml must call the shared build-all.yml")
if "uses: ./.github/workflows/build-all.yml" not in release_build or "workflow_dispatch" not in release_build:
    errs.append("release-build.yml must be a manual workflow_dispatch that calls the shared build-all.yml")
if re.search(r"^\s*(push|pull_request|schedule):", release_build, re.M):
    errs.append("release-build.yml must stay manual-only (no push/pull_request/schedule trigger)")
if re.search(r"gh release (delete|create|edit|upload)\s+dev\b", release_build) or "--prerelease" in release_build:
    errs.append("release-build.yml must never touch the OTA `dev` release")
if re.search(r"gh release|contents:\s*write|--prerelease", validate):
    errs.append("validate-build.yml must never publish (no gh release / contents: write)")
if "needs.build" not in dev_build or "needs: build" not in dev_build:
    errs.append("publish must depend on the verified build")

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
