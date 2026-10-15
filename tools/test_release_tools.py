#!/usr/bin/env python3
"""Offline tests of the release tooling (no GitHub, no Godot): platform selector, manifest verification,
SHA-parity refusal, packaging names/checksums. Run: python3 tools/test_release_tools.py"""
import hashlib, json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SHA = "a" * 40
fails = []


def run(*args):
    return subprocess.run([sys.executable, *args], capture_output=True, text=True)


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    if not cond:
        fails.append(name)


def make_out(d, sha=SHA, drop=None):
    files = {"android": "BackroomsSurvivor-dev.apk", "windows": "BackroomsSurvivor-windows-dev.zip",
             "linux": "BackroomsSurvivor-linux-dev.tar.gz", "patch": "patch.pck"}
    arts = []
    for plat, f in files.items():
        if plat == drop:
            continue
        data = (plat * 50).encode()
        open(os.path.join(d, f), "wb").write(data)
        arts.append({"platform": plat, "file": f, "config": "debug", "source_sha": sha,
                     "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)})
    man = {"schema": 1, "app_version": "0.1.0", "build": 13, "built_at": "x", "engine": "4.3",
           "source": {"repo": "r", "sha": sha, "ref": "refs/heads/dev", "workflow_run": "1"}, "artifacts": arts}
    json.dump(man, open(os.path.join(d, "release_manifest.json"), "w"))


# platform selector
check("selector all", run(os.path.join(HERE, "platforms.py"), "require", "all").stdout.strip() == "android,windows,linux,patch")
check("selector linux", run(os.path.join(HERE, "platforms.py"), "require", "linux").stdout.strip() == "linux,patch")
check("selector rejects junk", run(os.path.join(HERE, "platforms.py"), "check", "mac").returncode != 0)

with tempfile.TemporaryDirectory() as d:
    make_out(d)
    check("verify_release passes a consistent set", run(os.path.join(HERE, "verify_release.py"), d, "--sha", SHA).returncode == 0)
    check("verify_release refuses another SHA", run(os.path.join(HERE, "verify_release.py"), d, "--sha", "b" * 40).returncode != 0)
    open(os.path.join(d, "BackroomsSurvivor-dev.apk"), "ab").write(b"x")
    check("verify_release refuses a tampered artifact", run(os.path.join(HERE, "verify_release.py"), d, "--sha", SHA).returncode != 0)

with tempfile.TemporaryDirectory() as d:
    make_out(d, drop="linux")
    check("verify_release refuses a missing platform", run(os.path.join(HERE, "verify_release.py"), d, "--sha", SHA).returncode != 0)
    check("verify_release accepts it when linux is not requested",
          run(os.path.join(HERE, "verify_release.py"), d, "--sha", SHA, "--require", "android,windows,patch").returncode == 0)

with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as o:
    make_out(d)
    r = run(os.path.join(HERE, "package_release.py"), "--in", d, "--out", o, "--build", "13")
    names = sorted(os.listdir(o))
    check("package names", names == ["Backrooms Survivor Build 13 APK.apk", "Backrooms Survivor Build 13 EXE.zip",
                                     "Backrooms Survivor Build 13 Linux.tar.gz", "build-manifest.json", "checksums.sha256"], str(names) + r.stdout + r.stderr)
    sums = subprocess.run(["sha256sum", "-c", "checksums.sha256"], cwd=o, capture_output=True, text=True)
    check("checksums.sha256 verifies with sha256sum -c", sums.returncode == 0, sums.stdout + sums.stderr)
    bm = json.load(open(os.path.join(o, "build-manifest.json")))
    check("build-manifest carries build and source sha", bm.get("release_build") == 13 and bm["source"]["sha"] == SHA)

with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as o:
    make_out(d)
    run(os.path.join(HERE, "package_release.py"), "--in", d, "--out", o, "--build", "14", "--platform", "android")
    check("single-platform package", sorted(os.listdir(o)) == ["Backrooms Survivor Build 14 APK.apk", "build-manifest.json", "checksums.sha256"], str(os.listdir(o)))

with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as o:
    make_out(d)
    m = json.load(open(os.path.join(d, "release_manifest.json")))
    m["artifacts"][0]["source_sha"] = "c" * 40
    json.dump(m, open(os.path.join(d, "release_manifest.json"), "w"))
    check("package refuses mixed source SHAs", run(os.path.join(HERE, "package_release.py"), "--in", d, "--out", o, "--build", "13").returncode != 0)

# ---------------------------------------------------------------- publication gate (R-2)
sys.path.insert(0, HERE)
import ci_guard, workflow_rules  # noqa: E402


def quiet(fn, *a):
    import contextlib, io
    with contextlib.redirect_stdout(io.StringIO()):
        return fn(*a)


def perm(login, role):
    return {"user": {"login": login}, "role_name": role, "permission": role}


ok_args = ("workflow_dispatch", "refs/heads/dev", "owner", "owner", "1", perm("owner", "admin"), "refs/heads/dev")
check("authorize: admin dispatching from dev is allowed", quiet(ci_guard.authorize, *ok_args) == 0)
check("authorize: maintain is allowed", quiet(ci_guard.authorize, "workflow_dispatch", "refs/heads/dev", "m", "m", "1", perm("m", "maintain"), "refs/heads/dev") == 0)
for role in ("write", "triage", "read", "none", None):
    check(f"authorize: role {role} cannot publish",
          quiet(ci_guard.authorize, "workflow_dispatch", "refs/heads/dev", "u", "u", "1", perm("u", role), "refs/heads/dev") != 0)
for ev in ("push", "pull_request", "schedule", "workflow_run", "release", "repository_dispatch", "workflow_call", "create"):
    check(f"authorize: non-manual event {ev} cannot publish",
          quiet(ci_guard.authorize, ev, "refs/heads/dev", "owner", "owner", "1", perm("owner", "admin"), "refs/heads/dev") != 0)
check("authorize: wrong ref refused", quiet(ci_guard.authorize, "workflow_dispatch", "refs/heads/feature", "owner", "owner", "1", perm("owner", "admin"), "refs/heads/dev") != 0)
check("authorize: tag ref refused", quiet(ci_guard.authorize, "workflow_dispatch", "refs/tags/dev", "owner", "owner", "1", perm("owner", "admin"), "refs/heads/dev") != 0)
check("authorize: actor != triggering actor refused", quiet(ci_guard.authorize, "workflow_dispatch", "refs/heads/dev", "owner", "intruder", "1", perm("intruder", "admin"), "refs/heads/dev") != 0)
check("authorize: re-run refused", quiet(ci_guard.authorize, "workflow_dispatch", "refs/heads/dev", "owner", "owner", "2", perm("owner", "admin"), "refs/heads/dev") != 0)
check("authorize: permission record for a different user refused", quiet(ci_guard.authorize, "workflow_dispatch", "refs/heads/dev", "mallory", "mallory", "1", perm("owner", "admin"), "refs/heads/dev") != 0)
check("authorize: missing permission record refused", quiet(ci_guard.authorize, "workflow_dispatch", "refs/heads/dev", "owner", "owner", "1", None, "refs/heads/dev") != 0)
check("authorize: empty actor refused", quiet(ci_guard.authorize, "workflow_dispatch", "refs/heads/dev", "", "", "1", perm("", "admin"), "refs/heads/dev") != 0)

check("sequence: latest+1 accepted", quiet(ci_guard.sequence, "13", "12", "") == 0)
check("sequence: after a tag, next accepted", quiet(ci_guard.sequence, "14", "12", "refs/tags/build-13") == 0)
check("sequence: duplicate of OTA build refused", quiet(ci_guard.sequence, "12", "12", "") != 0)
check("sequence: duplicate tag refused", quiet(ci_guard.sequence, "13", "12", "refs/tags/build-13") != 0)
check("sequence: stale number refused", quiet(ci_guard.sequence, "11", "12", "") != 0)
check("sequence: stale vs tag refused", quiet(ci_guard.sequence, "12", "10", "refs/tags/build-13") != 0)
check("sequence: gap (out of sequence) refused", quiet(ci_guard.sequence, "15", "12", "") != 0)
check("sequence: non-integer refused", all(quiet(ci_guard.sequence, v, "12", "") != 0 for v in ("abc", "0", "-3", "13.5", "013", "", "13; rm")))
check("sequence: unreadable OTA build fails closed", quiet(ci_guard.sequence, "13", "", "") != 0 and quiet(ci_guard.sequence, "13", "none", "") != 0)
check("source: tip accepted", quiet(ci_guard.source, SHA, SHA) == 0)
check("source: non-tip refused", quiet(ci_guard.source, SHA, "b" * 40) != 0)
check("source: short or malformed sha refused", all(quiet(ci_guard.source, v, v) != 0 for v in ("abc1234", "A" * 40, "g" * 40, "")))

with tempfile.TemporaryDirectory() as d:
    pck = os.path.join(d, "patch.pck"); open(pck, "wb").write(b"GDPC" + b"x" * 100)
    mf = os.path.join(d, "manifest.json"); mn = os.path.join(d, "min.txt"); open(mn, "w").write("7\n")
    good = {"build": 13, "sha": SHA[:7], "pck": "patch.pck", "sha256": hashlib.sha256(open(pck, "rb").read()).hexdigest(), "size": os.path.getsize(pck), "min_base_build": 7}
    def run_compat(m, build=13):
        json.dump(m, open(mf, "w")); return quiet(ci_guard.compat, mf, pck, mn, build, SHA)
    check("compat: consistent OTA manifest accepted", run_compat(good) == 0)
    check("compat: wrong hash refused", run_compat({**good, "sha256": "0" * 64}) != 0)
    check("compat: wrong size refused", run_compat({**good, "size": 5}) != 0)
    check("compat: wrong build refused", run_compat({**good, "build": 12}) != 0)
    check("compat: wrong source sha refused", run_compat({**good, "sha": "deadbee"}) != 0)
    check("compat: min_base_build mismatch refused", run_compat({**good, "min_base_build": 3}) != 0)
    check("compat: min_base_build above build refused", run_compat({**good, "min_base_build": 20}, 13) != 0)

# static workflow rules: the real repository workflows comply, and each unsafe mutation is caught
wfdir = os.path.join(os.path.dirname(HERE), ".github", "workflows")
real = {fn: open(os.path.join(wfdir, fn)).read() for fn in sorted(os.listdir(wfdir))}
check("workflow rules: repository workflows comply", workflow_rules.check(real) == [], str(workflow_rules.check(real)))
check("workflow rules: dev-build.yml triggers are exactly workflow_dispatch", workflow_rules.triggers(real["dev-build.yml"]) == {"workflow_dispatch"})
check("workflow rules: release-build.yml triggers are exactly workflow_dispatch", workflow_rules.triggers(real["release-build.yml"]) == {"workflow_dispatch"})
check("workflow rules: nothing but dispatch publishes", all(workflow_rules.triggers(t) == {"workflow_dispatch"} for t in real.values() if workflow_rules.PUBLISH_RE.search(t)))


def mutate(name, fn):
    w = dict(real); w[name] = fn(real[name]); return workflow_rules.check(w)


check("mutation: push trigger on OTA publish is caught", mutate("dev-build.yml", lambda t: t.replace("on:\n  workflow_dispatch:", "on:\n  push:\n    branches: [dev]\n  workflow_dispatch:", 1)) != [])
check("mutation: schedule on OTA publish is caught", mutate("dev-build.yml", lambda t: t.replace("on:\n  workflow_dispatch:", "on:\n  schedule:\n    - cron: '0 3 * * *'\n  workflow_dispatch:", 1)) != [])
check("mutation: inline `on: push` is caught", mutate("dev-build.yml", lambda t: t.replace("on:\n  workflow_dispatch:", "on: push\nxx:\n  workflow_dispatch:", 1)) != [])
check("mutation: tag trigger on release build is caught", mutate("release-build.yml", lambda t: t.replace("on:\n  workflow_dispatch:", "on:\n  push:\n    tags: ['*']\n  workflow_dispatch:", 1)) != [])
check("mutation: removing the in-job gate is caught", mutate("dev-build.yml", lambda t: t.replace("tools/publish_gate.sh", "true", 1)) != [])
check("mutation: removing the compat check is caught", mutate("dev-build.yml", lambda t: t.replace("tools/ci_guard.py compat", "true")) != [])
check("mutation: publish without needing the build is caught", mutate("dev-build.yml", lambda t: t.replace("needs: [authorize, build]", "needs: authorize")) != [])
check("mutation: validate workflow publishing is caught", mutate("validate-build.yml", lambda t: t + "\n      - run: gh release create x\n") != [])
check("mutation: release build touching the OTA channel is caught", mutate("release-build.yml", lambda t: t + "\n      - run: gh release delete dev --yes\n") != [])
check("mutation: write permission in build-all is caught", mutate("build-all.yml", lambda t: t.replace("contents: read", "contents: write", 1)) != [])
check("mutation: workflow_run chaining is caught", mutate("validate-build.yml", lambda t: t + "\n  workflow_run:\n") != [])
check("mutation: gh workflow run is caught", mutate("validate-build.yml", lambda t: t + "\n      - run: gh workflow run dev-build.yml\n") != [])
check("mutation: continue-on-error is caught", mutate("build-all.yml", lambda t: t + "\n        continue-on-error: true\n") != [])

# publish_gate.sh end to end with stubbed gh / curl / git (fail-closed behaviour)
def gate(role="admin", ota=12, tags="", curl_ok=True, gh_ok=True, event="workflow_dispatch", num="13", attempt="1", trig="owner", src=SHA, ref="refs/heads/dev"):
    with tempfile.TemporaryDirectory() as d:
        b = os.path.join(d, "bin"); os.makedirs(b)
        def w(n, body):
            open(os.path.join(b, n), "w").write("#!/bin/sh\n" + body); os.chmod(os.path.join(b, n), 0o755)
        w("gh", ("echo '%s'" % json.dumps({"user": {"login": trig}, "role_name": role})) if gh_ok else "exit 1")
        w("curl", ("echo '%s'" % json.dumps({"build": ota})) if curl_ok else "exit 22")
        gitbody = 'if [ "$2" = "--tags" ]; then for t in %s; do printf "x\\trefs/tags/%%s\\n" "$t"; done; else printf "%s\\trefs/heads/dev\\n"; fi' % (tags, SHA)
        w("git", gitbody)
        env = {"PATH": b + ":" + os.environ["PATH"], "GH_TOKEN": "t", "REPO": "o/r", "EVENT": event, "REF": ref, "ACTOR": "owner",
               "TRIGGERING_ACTOR": trig, "RUN_ATTEMPT": attempt, "SRC": src, "NUM": num}
        return subprocess.run(["bash", os.path.join(HERE, "publish_gate.sh")], env=env, capture_output=True, text=True).returncode


check("gate.sh: authorized admin, tip source, next number passes", gate() == 0)
check("gate.sh: write role refused", gate(role="write") != 0)
check("gate.sh: push event refused", gate(event="push") != 0)
check("gate.sh: stale number refused", gate(num="12") != 0)
check("gate.sh: duplicate tag refused", gate(tags="build-13") != 0)
check("gate.sh: OTA lookup failure fails closed", gate(curl_ok=False) != 0)
check("gate.sh: permission lookup failure fails closed", gate(gh_ok=False) != 0)
check("gate.sh: non-tip source refused", gate(src="b" * 40) != 0)
check("gate.sh: re-run refused", gate(attempt="2") != 0)

# android signing: pinned certificate gate (pure function; no apksigner needed)
sys.path.insert(0, HERE)
import android_signing as AS
D1, D2 = "1" * 64, "2" * 64
out1 = "Signer #1 certificate SHA-256 digest: " + D1
check("signing: matching pin passes", AS.check(out1, "release", D1)[0])
check("signing: different key refused (would break in-place updates)", not AS.check(out1, "release", D2)[0])
check("signing: no pin yet passes but says so", AS.check(out1, "release", "")[0] and "pinned" in AS.check(out1, "release", "")[1])
check("signing: invalid pin file refused", not AS.check(out1, "release", "invalid")[0])
check("signing: two signers refused", not AS.check(out1 + "\nSigner #2 certificate SHA-256 digest: " + D2, "release", "")[0])
check("signing: unsigned output refused", not AS.check("", "release", "")[0])
bw = open(os.path.join(HERE, "..", ".github/workflows/build-all.yml")).read()
check("workflow: release mode fails closed without the signing secrets", 'inputs.mode }}" = "release" ]; then' in bw and "ANDROID_KEYSTORE_B64" in bw)
check("workflow: manual publish workflows pass the signing secrets", all("secrets: inherit" in open(os.path.join(HERE, "..", ".github/workflows", f)).read() for f in ("release-build.yml", "dev-build.yml")))
check("workflow: validate build passes no secrets", "secrets:" not in open(os.path.join(HERE, "..", ".github/workflows/validate-build.yml")).read().split("uses: ./.github/workflows/build-all.yml")[1])

print("RELEASE TOOLS: " + ("PASSED" if not fails else "FAILED " + ", ".join(fails)))
sys.exit(1 if fails else 0)
