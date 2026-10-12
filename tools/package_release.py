#!/usr/bin/env python3
"""Offline release packager: turns a verified CI output directory into human-readable, checksummed release assets.

Usage: package_release.py --in <verified-out-dir> --out <dir> --build <N> [--platform all|android|windows|linux] [--title "Backrooms Survivor"]

Input  (what .github/workflows/build-all.yml produces and tools/verify_release.py/verify_artifacts.py verified):
    BackroomsSurvivor-dev.apk, BackroomsSurvivor-windows-dev.zip, BackroomsSurvivor-linux-dev.tar.gz,
    patch.pck, release_manifest.json
Output (studio naming, one coordinated build):
    <Title> Build NN APK.apk
    <Title> Build NN EXE.zip
    <Title> Build NN Linux.tar.gz
    checksums.sha256                       (sha256 of the packages above, `sha256sum -c` compatible)
    build-manifest.json                    (the verified release manifest + final file names + build number)
It never talks to GitHub and never publishes. The OTA files (patch.pck, manifest.json) are not renamed or copied:
the OTA pipeline is separate and unchanged.
"""
import argparse, hashlib, json, os, shutil, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import platforms as pl

MAP = [  # (platform in manifest, suffix of the human-readable name)
    ("android", "APK.apk"),
    ("windows", "EXE.zip"),
    ("linux", "Linux.tar.gz"),
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--build", type=int, required=True)
    ap.add_argument("--platform", default="all")
    ap.add_argument("--title", default="Backrooms Survivor")
    a = ap.parse_args()
    mpath = os.path.join(a.src, "release_manifest.json")
    if not os.path.isfile(mpath):
        print("FAIL: release_manifest.json not found (run verify_release.py / verify_artifacts.py first)"); return 1
    man = json.load(open(mpath))
    arts = {x["platform"]: x for x in man.get("artifacts", [])}
    prefix = f"{a.title} Build {a.build:02d}"
    os.makedirs(a.out, exist_ok=True)
    sums, final = [], {}
    want = pl.selected(a.platform)
    for plat, suffix in MAP:
        if plat not in want:
            continue
        x = arts.get(plat)
        if not x:
            print(f"FAIL: platform {plat} missing from the manifest"); return 1
        src = os.path.join(a.src, x["file"])
        if not os.path.isfile(src) or sha256(src) != x["sha256"]:
            print(f"FAIL: {x['file']} missing or does not match the manifest hash"); return 1
        name = f"{prefix} {suffix}"
        shutil.copyfile(src, os.path.join(a.out, name))
        digest = sha256(os.path.join(a.out, name))
        sums.append(f"{digest}  {name}")
        final[plat] = {"file": name, "sha256": digest, "size": os.path.getsize(os.path.join(a.out, name)),
                       "source_sha": x["source_sha"]}
    shas = {v["source_sha"] for v in final.values()}
    if len(shas) != 1:
        print("FAIL: artifacts come from different source SHAs:", shas); return 1
    with open(os.path.join(a.out, "checksums.sha256"), "w") as f:
        f.write("\n".join(sums) + "\n")
    out_man = dict(man)
    out_man["release_name"] = prefix
    out_man["release_build"] = a.build
    out_man["release_platforms"] = a.platform
    out_man["release_files"] = final
    json.dump(out_man, open(os.path.join(a.out, "build-manifest.json"), "w"), indent=2)
    print(f"Packaged {prefix} from source {shas.pop()[:7]}:")
    for n in sums:
        print("  ", n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
