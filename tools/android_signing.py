#!/usr/bin/env python3
"""Android signing identity helper (public information only - never handles private keys).

  verify <apk> --apksigner <path> --mode release|validate   fail unless the APK's signature verifies and, when a certificate
                                                            is pinned in tools/android_signing_cert.sha256, the signer matches it.
  cert <apk> --apksigner <path>                             print the signer certificate SHA-256.
See docs/ANDROID_SIGNING.md.
"""
import argparse
import os
import re
import subprocess
import sys

PIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "android_signing_cert.sha256")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def pinned():
    """The pinned signer-certificate digest (lowercase hex, no colons) or '' while none is pinned yet."""
    if not os.path.exists(PIN):
        return ""
    for line in open(PIN):
        line = line.strip().lower().replace(":", "")
        if line and not line.startswith("#"):
            return line if HEX64.match(line) else "invalid"
    return ""


def signer_digests(apksigner_out):
    return [d.lower() for d in re.findall(r"certificate SHA-256 digest:\s*([0-9a-fA-F]{64})", apksigner_out)]


def check(apksigner_out, mode, pin):
    """Returns (ok, message). Pure function so it is unit-testable."""
    digests = signer_digests(apksigner_out)
    if len(digests) != 1:
        return False, "expected exactly one signer certificate, found %d" % len(digests)
    d = digests[0]
    if pin == "invalid":
        return False, "tools/android_signing_cert.sha256 is not a 64-hex SHA-256"
    if pin and d != pin:
        return False, "APK signer %s does not match the pinned certificate %s (wrong or regenerated key?)" % (d, pin)
    if not pin and mode == "release":
        return True, "signer %s (no certificate pinned yet: commit it to tools/android_signing_cert.sha256)" % d
    return True, "signer %s%s" % (d, " == pinned" if pin else "")


def run(apk, apksigner):
    r = subprocess.run([apksigner, "verify", "--print-certs", apk], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("apksigner verify failed:\n" + r.stdout + r.stderr)
    return r.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["verify", "cert"])
    ap.add_argument("apk")
    ap.add_argument("--apksigner", default="apksigner")
    ap.add_argument("--mode", default="validate")
    a = ap.parse_args()
    out = run(a.apk, a.apksigner)
    if a.cmd == "cert":
        print(signer_digests(out)[0])
        return
    ok, msg = check(out, a.mode, pinned() if a.mode == "release" else "")
    print(("OK: " if ok else "FAIL: ") + msg)
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
