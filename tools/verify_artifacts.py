#!/usr/bin/env python3
"""Independently verify each platform artifact (format + embedded build provenance).

Usage: verify_artifacts.py <out-dir> --sha <full-40-char-source-sha>

Unlike verify_release.py (which trusts the manifest), this opens every artifact and checks:
  * the artifact is the right kind of file for its platform (zip with an .exe / ELF x86-64 executable / signed APK
    with arm64 libs / Godot pck),
  * the build_info.json embedded in the game data carries the SAME full source SHA, and (when present) the same build
    number as the manifest.
Any failure or any missing platform fails the run.
"""
import argparse, io, json, os, re, struct, sys, tarfile, zipfile


def embedded_info(blobs, sha):
    """Find the embedded build_info.json object containing the approved sha; return the parsed dict or None."""
    needle = re.compile(rb'"full_sha"\s*:\s*"%s"' % re.escape(sha.encode()))
    for b in blobs:
        m = needle.search(b)
        if not m:
            continue
        start = b.rfind(b"{", 0, m.start())
        end = b.find(b"}", m.end())
        if start < 0 or end < 0:
            continue
        try:
            return json.loads(b[start:end + 1].decode("utf-8", "replace"))
        except ValueError:
            continue
    return None


def any_other_sha(blobs, sha):
    for b in blobs:
        for m in re.finditer(rb'"full_sha"\s*:\s*"([0-9a-f]{40})"', b):
            if m.group(1).decode() != sha:
                return m.group(1).decode()
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("--sha", required=True)
    a = ap.parse_args()
    errs, ok = [], []
    man = json.load(open(os.path.join(a.out_dir, "release_manifest.json")))
    build = man.get("build")
    files = {x["platform"]: os.path.join(a.out_dir, x["file"]) for x in man["artifacts"]}

    def check(plat, blobs, extra=None):
        info = embedded_info(blobs, a.sha)
        other = any_other_sha(blobs, a.sha)
        if other:
            errs.append(f"{plat}: embeds a DIFFERENT source sha {other}")
        if info is None:
            errs.append(f"{plat}: embedded build_info.json with full_sha {a.sha} not found")
        else:
            if build is not None and info.get("build") != build:
                errs.append(f"{plat}: embedded build {info.get('build')} != manifest build {build}")
            ok.append(f"{plat}: embedded sha {a.sha[:7]}, build {info.get('build')}, branch {info.get('branch')}")
        if extra:
            extra()

    # ---- windows: zip with exe + pck
    p = files.get("windows")
    if p:
        try:
            z = zipfile.ZipFile(p)
            names = z.namelist()
            exes = [n for n in names if n.lower().endswith(".exe") and "console" not in n.lower()]
            pcks = [n for n in names if n.lower().endswith(".pck")]
            if not exes or z.read(exes[0])[:2] != b"MZ":
                errs.append("windows: no valid .exe (MZ header) in zip")
            if not pcks:
                errs.append("windows: no .pck in zip")
            check("windows", [z.read(n) for n in pcks])
        except Exception as e:
            errs.append(f"windows: cannot open zip: {e}")
    else:
        errs.append("windows artifact missing")

    # ---- linux: tar.gz with an executable ELF x86-64 (pck embedded)
    p = files.get("linux")
    if p:
        try:
            t = tarfile.open(p, "r:gz")
            mem = [m for m in t.getmembers() if m.isfile() and m.name.endswith(".x86_64")]
            if not mem:
                errs.append("linux: no .x86_64 executable in tar")
            else:
                m = mem[0]
                data = t.extractfile(m).read()
                if data[:4] != b"\x7fELF" or struct.unpack_from("<H", data, 18)[0] != 62:
                    errs.append("linux: executable is not an ELF x86-64 binary")
                if not (m.mode & 0o111):
                    errs.append("linux: executable bit missing")
                check("linux", [data])
        except Exception as e:
            errs.append(f"linux: cannot open tar: {e}")
    else:
        errs.append("linux artifact missing")

    # ---- android: signed apk with arm64 native lib + embedded game data
    p = files.get("android")
    if p:
        try:
            z = zipfile.ZipFile(p)
            names = z.namelist()
            if "AndroidManifest.xml" not in names:
                errs.append("android: AndroidManifest.xml missing")
            if not any(n.startswith("lib/arm64-v8a/") and n.endswith(".so") for n in names):
                errs.append("android: no arm64-v8a native library")
            raw = open(p, "rb").read()
            if not (any(n.startswith("META-INF/") for n in names) or b"APK Sig Block 42" in raw):
                errs.append("android: apk is not signed")
            manifest_xml = z.read("AndroidManifest.xml") if "AndroidManifest.xml" in names else b""
            if "com.verbal76.backroomssurvivor".encode("utf-16-le") not in manifest_xml and b"com.verbal76.backroomssurvivor" not in manifest_xml:
                errs.append("android: package id com.verbal76.backroomssurvivor not found in manifest")
            blobs = [z.read(n) for n in names if n.startswith("assets/")]
            check("android", blobs)
        except Exception as e:
            errs.append(f"android: cannot open apk: {e}")
    else:
        errs.append("android artifact missing")

    # ---- patch (OTA pck)
    p = files.get("patch")
    if p:
        data = open(p, "rb").read()
        if data[:4] != b"GDPC":
            errs.append("patch: not a Godot pck (GDPC magic missing)")
        check("patch", [data])
    else:
        errs.append("patch artifact missing")

    for line in ok:
        print("OK  ", line)
    if errs:
        print("ARTIFACT VERIFICATION FAILED:")
        for e in errs:
            print("  -", e)
        return 1
    print("All platform artifacts independently verified for", a.sha[:7])
    return 0


if __name__ == "__main__":
    sys.exit(main())
