#!/usr/bin/env python3
"""Offline tests of the release tooling (no GitHub, no Godot): platform selector, manifest verification,
SHA-parity refusal, packaging names/checksums. Run: python3 tools/test_release_tools.py"""
import hashlib, json, os, re, subprocess, sys, tempfile

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

# ---- android signing (behavioural: real keytool + fake apksigner; secrets here are throw-away test values) ----
sys.path.insert(0, HERE)
import android_signing as AS
import shutil
D1, D2 = "1" * 64, "2" * 64
out = lambda d: "Signer #1 certificate SHA-256 digest: " + d
check("sign: release + matching pin passes", AS.check(out(D1), "release", D1)[0])
check("sign: release + wrong signer blocked", not AS.check(out(D1), "release", D2)[0])
check("sign: release + EMPTY pin blocked (fail closed)", not AS.check(out(D1), "release", "")[0])
check("sign: release + malformed pin blocked with its message", AS.check(out(D1), "release", "", "pin line 3 malformed")[1] == "pin line 3 malformed")
check("sign: APK cert != keystore cert blocked in every mode", not AS.check(out(D1), "validate", "", "", D2)[0])
check("sign: two signers / unsigned output blocked", not AS.check(out(D1) + "\n" + out(D2), "release", D1)[0] and not AS.check("", "release", D1)[0])
check("sign: validate mode needs no pin", AS.check(out(D1), "validate", "")[0])
for txt, want in (("SHA256: " + ":".join([D1[i:i+2] for i in range(0, 64, 2)]).upper(), D1), ("sha256=" + D1, D1), (D1[:60], ""), ("nonsense", "")):
    check("pin syntax %r" % txt[:16], AS.norm_digest(txt) == want)
with tempfile.TemporaryDirectory() as td:
    def pinfile(body):
        f = os.path.join(td, "pin"); open(f, "w").write(body); return AS.read_pin(f)
    check("pin file: comments only = nothing pinned, no error", pinfile("# c\n\n") == ("", ""))
    check("pin file: valid", pinfile("# c\n" + D1 + "\n") == (D1, ""))
    d, e = pinfile("# c\nSHA256=zz\n")
    check("pin file: malformed -> actionable error naming the line", d == "" and "line 2" in e and "64 hex" in e)
    check("pin file: two fingerprints refused", pinfile(D1 + "\n" + D2 + "\n")[1] != "")
    check("repo pin file is valid (PR check)", AS.read_pin()[1] == "")

    # keystore preparation with a real keystore whose password has shell/.tres-special characters
    kt = shutil.which("keytool")
    if kt:
        PW = 'p$a"s\\w`o r d!'
        def mk(name, alias, pw):
            ks = os.path.join(td, name)
            subprocess.run([kt, "-genkeypair", "-alias", alias, "-keyalg", "RSA", "-keysize", "2048", "-validity", "30", "-dname", "CN=t",
                            "-keystore", ks, "-storetype", "PKCS12", "-storepass:env", "TP", "-keypass:env", "TP"],
                           env={**os.environ, "TP": pw}, capture_output=True, check=True)
            return ks
        def prep(b64, pw, al="backroomssurvivor", kp=""):
            return subprocess.run([sys.executable, os.path.join(HERE, "android_signing.py"), "prepare", "--keystore", os.path.join(td, "out.ks")],
                                  env={**os.environ, "KS_B64": b64, "KS_PASS": pw, "KS_ALIAS": al, "KEY_PASS": kp}, capture_output=True, text=True)
        import base64
        good = mk("good.p12", "backroomssurvivor", PW)
        gb = base64.b64encode(open(good, "rb").read()).decode()
        r = prep(gb, PW)
        fp = r.stdout.strip()
        check("keystore: valid keystore (special-char password) prepares and prints only a public fingerprint", r.returncode == 0 and AS.norm_digest(fp) == fp and PW not in r.stdout + r.stderr)
        check("keystore: wrong password blocked, password not echoed", prep(gb, "nope").returncode != 0 and PW not in prep(gb, "nope").stderr)
        check("keystore: wrong alias blocked", prep(gb, PW, "other").returncode != 0)
        check("keystore: empty alias blocked", prep(gb, PW, "").returncode != 0)
        check("keystore: PKCS12 with a differing key password still prepares (key password unused)", prep(gb, PW, "backroomssurvivor", "different").returncode == 0)
        jks = os.path.join(td, "k.jks")
        subprocess.run([kt, "-genkeypair", "-alias", "backroomssurvivor", "-keyalg", "RSA", "-keysize", "2048", "-validity", "30", "-dname", "CN=t", "-keystore", jks, "-storetype", "JKS", "-storepass:env", "SP", "-keypass:env", "KP"], env={**os.environ, "SP": "storepass1", "KP": "keypass22"}, capture_output=True, check=True)
        jb = base64.b64encode(open(jks, "rb").read()).decode()
        check("keystore: JKS with a different key password is aligned for Godot", prep(jb, "storepass1", "backroomssurvivor", "keypass22").returncode == 0)
        check("keystore: JKS with a wrong key password blocked", prep(jb, "storepass1", "backroomssurvivor", "bad-key-pass").returncode != 0)
        check("keystore: empty / non-base64 / truncated / garbage blocked", all(prep(b, PW).returncode != 0 for b in ("", "not base64!!", gb[:40], base64.b64encode(b"x" * 500).decode())))
        # editor settings: the password survives escaping byte-for-byte and file is private
        sf = os.path.join(td, "es.tres")
        subprocess.run([sys.executable, os.path.join(HERE, "android_signing.py"), "settings", "--out", sf, "--sdk", "/s", "--jdk", "/j", "--keystore", "/k", "--alias", "a"],
                       env={**os.environ, "KS_PASS": PW}, check=True)
        line = [l for l in open(sf).read().splitlines() if l.startswith("export/android/debug_keystore_pass")][0]
        val = line.split(" = ", 1)[1][1:-1]
        check("settings: special-character password round-trips through .tres escaping", val.replace('\\"', '"').replace("\\\\", "\\") == PW and oct(os.stat(sf).st_mode & 0o777) == "0o600")

        # verify against a fake apksigner (output format of the real tool)
        def fake(name, body):
            f = os.path.join(td, name); open(f, "w").write("#!/bin/sh\n" + body); os.chmod(f, 0o755); return f
        apk = os.path.join(td, "a.apk"); open(apk, "wb").write(b"apk")
        def ver(signer, mode, expect="", apkp=apk):
            args = [sys.executable, os.path.join(HERE, "android_signing.py"), "verify", apkp, "--apksigner", signer, "--mode", mode] + (["--expect-cert", expect] if expect else [])
            return subprocess.run(args, capture_output=True, text=True).returncode
        okf = fake("ok", 'echo "Signer #1 certificate SHA-256 digest: %s"' % D1)
        check("verify: unsigned APK (apksigner rejects) blocked", ver(fake("bad", "echo 'DOES NOT VERIFY' >&2; exit 1"), "validate") != 0)
        check("verify: missing / empty / stale-absent APK blocked", ver(okf, "validate", apkp=os.path.join(td, "none.apk")) != 0)
        check("verify: wrong keystore certificate blocked", ver(okf, "validate", D2) != 0)
        check("verify: matching keystore certificate passes (validate)", ver(okf, "validate", D1) == 0)
        check("verify: release without a pin blocked (repo pin is empty until the owner sets it)", AS.read_pin()[0] != "" or ver(okf, "release", D1) != 0)
        check("verify: missing apksigner binary blocked", ver(os.path.join(td, "nope"), "validate") != 0)
    else:
        print("SKIP keystore tests (no keytool)")

    # SDK tool resolution
    sdk = os.path.join(td, "sdk"); os.makedirs(os.path.join(sdk, "build-tools", "33.0.2")); os.makedirs(os.path.join(sdk, "build-tools", "34.0.0"))
    for v in ("33.0.2", "34.0.0"): open(os.path.join(sdk, "build-tools", v, "apksigner"), "w").write("")
    check("apksigner resolves to 34.0.0 when present", AS.find_apksigner(sdk).endswith("34.0.0/apksigner"))
    check("apksigner missing -> clear failure", subprocess.run([sys.executable, os.path.join(HERE, "android_signing.py"), "find-apksigner", os.path.join(td, "nosdk")], capture_output=True).returncode != 0)

    # owner setup script: idempotent + recoverable, with a fake gh and a throw-away HOME (no network, no real secrets)
    if kt and shutil.which("openssl"):
        home = os.path.join(td, "home"); os.makedirs(os.path.join(home, "bin"))
        log = os.path.join(td, "gh.log")
        gh = os.path.join(home, "bin", "gh"); open(gh, "w").write('#!/bin/sh\n[ -n "$GH_FAIL" ] && exit 1\ncase "$*" in *"secret set"*) echo "$@" >> "%s"; cat > /dev/null;; esac\n' % log); os.chmod(gh, 0o755)
        env = {**os.environ, "HOME": home, "PATH": os.path.join(home, "bin") + ":" + os.environ["PATH"]}
        setup = os.path.join(HERE, "android_keystore_setup.sh")
        r1 = subprocess.run(["bash", setup, "o/r"], env={**env, "GH_FAIL": "1"}, capture_output=True, text=True)
        bk = os.path.join(home, "backrooms-signing-backup")
        check("setup: failed upload still leaves keystore AND password saved", r1.returncode != 0 and os.path.getsize(os.path.join(bk, "PASSWORD.txt")) > 0 and os.path.exists(os.path.join(bk, "backroomssurvivor.p12")))
        ks_before = open(os.path.join(bk, "backroomssurvivor.p12"), "rb").read()
        r2 = subprocess.run(["bash", setup, "o/r"], env=env, capture_output=True, text=True)
        pw = open(os.path.join(bk, "PASSWORD.txt")).read().strip()
        check("setup: re-run reuses the same keystore (idempotent) and uploads all four secrets", r2.returncode == 0 and open(os.path.join(bk, "backroomssurvivor.p12"), "rb").read() == ks_before and open(log).read().count("secret set") == 4)
        check("setup: password is never printed", pw not in r1.stdout + r1.stderr + r2.stdout + r2.stderr)
        check("setup: prints the public fingerprint, files are private", AS.norm_digest(open(os.path.join(bk, "cert.sha256")).read()) != "" and oct(os.stat(os.path.join(bk, "PASSWORD.txt")).st_mode & 0o777) == "0o600")

# ---- workflow structure (kept deliberately small; the behaviour is tested above) ----
W = lambda f: open(os.path.join(HERE, "..", ".github/workflows", f)).read()
bw, rw, dw, vw = W("build-all.yml"), W("release-build.yml"), W("dev-build.yml"), W("validate-build.yml")
exp = bw[bw.index("Export Android"):bw.index("Write release manifest")]
check("workflow: Godot Android export is not success-masked", not re.search(r"godot[^\n]*export-debug[^\n]*\|\|\s*true", exp) and "pipefail" in exp)
check("workflow: stale APK removed before export, verify runs on the fresh APK", exp.index("rm -f build/android/BackroomsSurvivor-dev.apk") < exp.index("export-debug") < exp.index("android_signing.py verify"))
check("workflow: release requires pin + secrets before any SDK download", exp.index("check-pin --require") < exp.index("sdkmanager"))
check("workflow: keystore validated before export and removed after", exp.index("android_signing.py prepare") < exp.index("export-debug") and "trap cleanup EXIT" in exp)
check("workflow: signing settings file is never printed", "cat ~/.config/godot/editor_settings" not in exp)
check("workflow: no secrets: inherit, only the four signing secrets are passed", "secrets: inherit" not in rw + dw + vw and all(n in w for w in (rw, dw) for n in tuple("ANDROID_RELEASE_%s: ${{ secrets.ANDROID_RELEASE_%s }}" % (n, n) for n in ("KEYSTORE_BASE64", "KEYSTORE_PASSWORD", "KEY_ALIAS", "KEY_PASSWORD"))))
check("workflow: validate build passes no secrets", "secrets:" not in vw.split("uses: ./.github/workflows/build-all.yml")[1])
check("workflow: release artifact name defined once and used by upload and download", rw.count("RELEASE_ASSETS") == 3 and "coordinated-release-assets-b" in rw and rw.count("coordinated-release-assets-b") == 1)

print("RELEASE TOOLS: " + ("PASSED" if not fails else "FAILED " + ", ".join(fails)))
sys.exit(1 if fails else 0)
