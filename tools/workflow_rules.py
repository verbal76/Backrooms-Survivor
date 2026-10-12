#!/usr/bin/env python3
"""Static publication-safety rules for .github/workflows (used by policy_check.py and tested by test_release_tools.py).

check(workflows) takes {filename: text} and returns a list of violations (empty = compliant).
No YAML dependency: the trigger block is read from the top-level `on:` mapping.
"""
import re

PUBLISH_RE = re.compile(r"gh release (create|delete|upload|edit)|contents:\s*write|--prerelease|action-gh-release|gh api[^\n]*(releases|git/refs)")
INDIRECT_RE = re.compile(r"gh workflow run|repository_dispatch|workflow_run:|/dispatches|actions:\s*write|createWorkflowDispatch")
OTA_CHANNEL_RE = re.compile(r"gh release (delete|create|edit|upload)\s+dev\b")


def triggers(text):
    """Set of top-level trigger names under `on:`."""
    m = re.search(r"^on:[ \t]*(.*)$", text, re.M)
    if not m:
        return set()
    inline = m.group(1).strip()
    if inline:                                   # `on: push` or `on: [push, pull_request]`
        return {t.strip() for t in re.split(r"[,\[\]\s]+", inline) if t.strip()}
    out = set()
    for line in text[m.end():].splitlines():
        if line.strip() == "" or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):             # next top-level key
            break
        km = re.match(r"^  ([A-Za-z_]+):", line)
        if km:
            out.add(km.group(1))
    return out


def check(wf):
    errs = []
    for name, text in wf.items():
        trig = triggers(text)
        if INDIRECT_RE.search(text):
            errs.append(f"{name}: indirect workflow triggering / dispatch / actions:write is not allowed")
        if re.search(r"continue-on-error:\s*true", text):
            errs.append(f"{name}: continue-on-error: true is not allowed")
        if PUBLISH_RE.search(text):
            if trig != {"workflow_dispatch"}:
                errs.append(f"{name}: a workflow that can publish must have workflow_dispatch as its ONLY trigger (has {sorted(trig)})")
            if "tools/publish_gate.sh" not in text or text.count("tools/publish_gate.sh") < 2:
                errs.append(f"{name}: publishing workflow must run tools/publish_gate.sh before building AND again inside the publish job")
            if "needs: [authorize, build]" not in text and "needs: package" not in text:
                errs.append(f"{name}: publish job must depend on authorization and the verified build/package jobs")
            if "contents: write" in text and text.count("contents: write") != 1:
                errs.append(f"{name}: contents: write must be granted to exactly one (publish) job")
    names = set(wf)
    for need in ("build-all.yml", "dev-build.yml", "release-build.yml", "validate-build.yml"):
        if need not in names:
            errs.append(f"{need} is missing")
    if errs and len(names) < 4:
        return errs
    ba, dev, rel, val = (wf.get(n, "") for n in ("build-all.yml", "dev-build.yml", "release-build.yml", "validate-build.yml"))
    if triggers(ba) != {"workflow_call"}:
        errs.append("build-all.yml must be a reusable workflow only (workflow_call)")
    if re.search(r"contents:\s*write", ba):
        errs.append("build-all.yml (build) must never have write access")
    if triggers(dev) != {"workflow_dispatch"}:
        errs.append(f"dev-build.yml (OTA publish) must be manual only; triggers are {sorted(triggers(dev))}")
    if triggers(rel) != {"workflow_dispatch"}:
        errs.append(f"release-build.yml must be manual only; triggers are {sorted(triggers(rel))}")
    if not triggers(val) <= {"pull_request", "workflow_dispatch"}:
        errs.append(f"validate-build.yml may only run on pull_request/workflow_dispatch; has {sorted(triggers(val))}")
    if PUBLISH_RE.search(val):
        errs.append("validate-build.yml must never publish")
    if OTA_CHANNEL_RE.search(rel) or "--prerelease" in rel:
        errs.append("release-build.yml must never touch the OTA `dev` release")
    for n, t in (("dev-build.yml", dev), ("release-build.yml", rel), ("validate-build.yml", val)):
        if "uses: ./.github/workflows/build-all.yml" not in t:
            errs.append(f"{n} must call the shared build-all.yml")
    if "tools/ci_guard.py compat" not in dev or "github.triggering_actor" not in dev or "PUBLISH-OTA" not in dev:
        errs.append("dev-build.yml must re-check compatibility, use the trusted triggering actor and require the confirmation phrase")
    if "inputs.build_number" not in dev or "inputs.build_number" not in rel:
        errs.append("manual publishing workflows must pass the build number through the single-sequence gate")
    return errs
