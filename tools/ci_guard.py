#!/usr/bin/env python3
"""Fail-closed publication guards shared by the manual release workflows (dev-build.yml OTA publish, release-build.yml).

Every decision is made from TRUSTED inputs only: GitHub's own context values (event name, ref, actor, triggering actor,
run attempt) and the output of GitHub's permission API. Anything typed into a workflow_dispatch form (source_sha,
build_number, ...) is validated here but never treated as authorization.

  ci_guard.py authorize --event E --ref R --actor A --triggering-actor T --run-attempt N --permission-file F [--allow-ref refs/heads/dev]
  ci_guard.py sequence  --number N --ota-build B --tags "build-12 build-13"
  ci_guard.py source    --sha S --dev-tip D
  ci_guard.py compat    --manifest M.json --pck P --min-base-file F --build N --sha S

Exit 0 = allowed; exit 1 = refused (reason on stdout, workflow-command formatted).
"""
import argparse, hashlib, json, os, re, sys

ALLOWED_ROLES = ("admin", "maintain")      # repository roles that may publish
SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def refuse(msg):
    print(f"::error::REFUSED: {msg}")
    return 1


def authorize(event, ref, actor, triggering_actor, run_attempt, perm, allow_ref):
    if event != "workflow_dispatch":
        return refuse(f"publication only runs from a manual workflow_dispatch (event was '{event}')")
    if ref != allow_ref:
        return refuse(f"must be dispatched from {allow_ref} (ref was '{ref}')")
    if not actor or not triggering_actor or actor != triggering_actor:
        return refuse("initiating actor and triggering actor differ or are missing (re-runs by another user are not accepted)")
    if str(run_attempt) != "1":
        return refuse("re-runs are not accepted; dispatch the workflow again")
    if not isinstance(perm, dict) or perm.get("user", {}).get("login", "").lower() != actor.lower():
        return refuse("permission lookup does not describe the initiating actor")
    role = perm.get("role_name") or perm.get("permission")
    if role not in ALLOWED_ROLES:
        return refuse(f"actor '{actor}' has repository role '{role}', publishing needs one of {', '.join(ALLOWED_ROLES)}")
    print(f"authorized: {actor} ({role}) via workflow_dispatch on {ref}")
    return 0


def tag_numbers(tags):
    nums = []
    for t in tags.split():
        m = re.fullmatch(r"(?:refs/tags/)?build-(\d+)", t)
        if m:
            nums.append(int(m.group(1)))
    return nums


def sequence(number, ota_build, tags):
    """ONE sequence for native/coordinated builds (build-NN tags) and OTA patches: the next number is exactly latest + 1."""
    if not re.fullmatch(r"[1-9][0-9]{0,3}", str(number)):
        return refuse(f"build number '{number}' is not a positive integer")
    if not re.fullmatch(r"[0-9]+", str(ota_build)):
        return refuse(f"OTA channel build '{ota_build}' could not be read (failing closed)")
    n, ota = int(number), int(ota_build)
    used = tag_numbers(tags)
    latest = max([ota] + used)
    if n in used or n == ota:
        return refuse(f"build number {n} is already used (duplicate)")
    if n < latest:
        return refuse(f"build number {n} is stale; latest is {latest}")
    if n != latest + 1:
        return refuse(f"build number {n} is out of sequence; the next number is {latest + 1}")
    print(f"sequence ok: {n} follows {latest} (OTA channel {ota}, tags {sorted(used)})")
    return 0


def source(sha, dev_tip):
    if not SHA_RE.match(sha or ""):
        return refuse("source_sha must be a full 40-character lowercase SHA")
    if sha != dev_tip:
        return refuse(f"source {sha} is not the current tip of dev ({dev_tip})")
    print(f"source ok: {sha}")
    return 0


def compat(manifest_path, pck_path, min_base_file, build, sha):
    try:
        m = json.load(open(manifest_path))
    except Exception as e:
        return refuse(f"OTA manifest unreadable: {e}")
    h = hashlib.sha256(open(pck_path, "rb").read()).hexdigest()
    if m.get("sha256") != h:
        return refuse("manifest sha256 does not match patch.pck")
    if m.get("size") != os.path.getsize(pck_path):
        return refuse("manifest size does not match patch.pck")
    if m.get("build") != int(build):
        return refuse(f"manifest build {m.get('build')} != requested {build}")
    if not str(m.get("sha", "")) or not sha.startswith(str(m["sha"])):
        return refuse(f"manifest sha {m.get('sha')} is not a prefix of the verified source {sha}")
    want_min = int(open(min_base_file).read().strip())
    if m.get("min_base_build") != want_min:
        return refuse(f"manifest min_base_build {m.get('min_base_build')} != source value {want_min}")
    if want_min > int(build):
        return refuse("min_base_build exceeds the build number")
    print(f"compat ok: build {build}, min_base_build {want_min}, sha256 {h[:12]}")
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("authorize")
    a.add_argument("--event", required=True); a.add_argument("--ref", required=True)
    a.add_argument("--actor", required=True); a.add_argument("--triggering-actor", required=True)
    a.add_argument("--run-attempt", required=True); a.add_argument("--permission-file", required=True)
    a.add_argument("--allow-ref", default="refs/heads/dev")
    s = sub.add_parser("sequence")
    s.add_argument("--number", required=True); s.add_argument("--ota-build", required=True); s.add_argument("--tags", default="")
    c = sub.add_parser("source")
    c.add_argument("--sha", required=True); c.add_argument("--dev-tip", required=True)
    k = sub.add_parser("compat")
    k.add_argument("--manifest", required=True); k.add_argument("--pck", required=True)
    k.add_argument("--min-base-file", required=True); k.add_argument("--build", required=True); k.add_argument("--sha", required=True)
    x = ap.parse_args()
    if x.cmd == "authorize":
        try:
            perm = json.load(open(x.permission_file))
        except Exception:
            perm = None
        return authorize(x.event, x.ref, x.actor, x.triggering_actor, x.run_attempt, perm, x.allow_ref)
    if x.cmd == "sequence":
        return sequence(x.number, x.ota_build, x.tags)
    if x.cmd == "source":
        return source(x.sha, x.dev_tip)
    return compat(x.manifest, x.pck, x.min_base_file, x.build, x.sha)


if __name__ == "__main__":
    sys.exit(main())
