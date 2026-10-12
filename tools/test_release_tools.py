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

print("RELEASE TOOLS: " + ("PASSED" if not fails else "FAILED " + ", ".join(fails)))
sys.exit(1 if fails else 0)
