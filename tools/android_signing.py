#!/usr/bin/env python3
"""Android signing identity helper (CI + owner tooling). Never prints keys or passwords.

  check-pin [--require]        validate tools/android_signing_cert.sha256 (syntax; --require: also non-empty). Used by PR checks.
  prepare --keystore F         decode ANDROID_RELEASE_KEYSTORE_BASE64 (env KS_B64) to F, check it is a readable non-empty keystore that
                               opens with the store password (env KS_PASS) and holds the alias (env KS_ALIAS); if the key password
                               (env KEY_PASS) differs from the store password, align it on this temporary copy (Godot takes ONE
                               password). Prints the certificate SHA-256 (public).
  settings --out F --sdk S --jdk J --keystore F --alias A    write Godot editor settings (password from env KS_PASS, escaped).
  find-apksigner SDK           resolve the SDK's apksigner (prefers build-tools 34.0.0).
  verify APK --apksigner P --mode release|validate [--expect-cert HEX]
                               apksigner-verify the APK; signer must equal --expect-cert (the keystore's own certificate) and,
                               in release mode, the pinned certificate - which must exist and be valid (fail closed).
See docs/ANDROID_SIGNING.md.
"""
import argparse
import base64
import binascii
import glob
import os
import re
import subprocess
import sys

PIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "android_signing_cert.sha256")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def die(msg):
    print("FAIL: " + msg, file=sys.stderr)
    sys.exit(1)


def norm_digest(text):
    """'SHA256: AB:CD..', 'sha256=abcd..', 'ab cd ..' -> 64 lowercase hex, or '' when not a digest."""
    t = re.sub(r"^\s*sha-?256\s*[:=]?\s*", "", text.strip(), flags=re.I)
    t = re.sub(r"[\s:]", "", t).lower()
    return t if HEX64.match(t) else ""


def read_pin(path=PIN):
    """Returns (digest, error). digest '' + error '' = nothing pinned yet; error is an actionable message."""
    if not os.path.exists(path):
        return "", ""
    with open(path) as f:
        lines = [(i + 1, l.strip()) for i, l in enumerate(f) if l.strip() and not l.strip().startswith("#")]
    if not lines:
        return "", ""
    if len(lines) > 1:
        return "", "%s: exactly one fingerprint line is allowed, found %d (line %d is the second)" % (os.path.basename(path), len(lines), lines[1][0])
    n, raw = lines[0]
    d = norm_digest(raw)
    if not d:
        return "", ("%s line %d is not a SHA-256 certificate fingerprint (need 64 hex digits, optional ':' separators or a 'SHA256:' prefix). "
                    "Print it with tools/android_keystore_setup.sh or: keytool -list -v -keystore <ks> | grep SHA256" % (os.path.basename(path), n))
    return d, ""


def signer_digests(apksigner_out):
    return [d.lower() for d in re.findall(r"certificate SHA-256 digest:\s*([0-9a-fA-F]{64})", apksigner_out)]


def check(apksigner_out, mode, pin, pin_err="", expect_cert=""):
    """Pure decision function -> (ok, message)."""
    digests = signer_digests(apksigner_out)
    if len(digests) != 1:
        return False, "expected exactly one signer certificate in the APK, found %d (unsigned APK?)" % len(digests)
    d = digests[0]
    if expect_cert and d != expect_cert:
        return False, "the APK is signed with %s but the keystore certificate is %s: Godot did not use the configured key" % (d, expect_cert)
    if mode == "release":
        if pin_err:
            return False, pin_err
        if not pin:
            return False, ("no certificate is pinned in tools/android_signing_cert.sha256, so release continuity cannot be proven. "
                           "Run tools/android_keystore_setup.sh once and commit the fingerprint it prints (this build's signer: %s)" % d)
        if d != pin:
            return False, "APK signer %s does not match the pinned certificate %s (wrong or regenerated key: installed apps could not update)" % (d, pin)
        return True, "signer %s == pinned" % d
    return True, "signer %s (validate mode: not a release signature)" % d


def run(cmd, env=None):
    return subprocess.run(cmd, capture_output=True, text=True, env=env)


def keystore_cert(ks, alias, password_env="KS_PASS"):
    """SHA-256 of the alias certificate; dies with an actionable message."""
    env = dict(os.environ)
    r = run(["keytool", "-list", "-v", "-keystore", ks, "-alias", alias, "-storepass:env", password_env], env)
    if r.returncode != 0:
        msg = (r.stdout + r.stderr).lower()
        if "alias" in msg and ("does not exist" in msg or "not exist" in msg):
            die("the keystore has no alias '%s' (re-run tools/android_keystore_setup.sh or fix the secret)" % alias)
        if "password" in msg or "tampered" in msg:
            die("the keystore does not open with ANDROID_RELEASE_KEYSTORE_PASSWORD (wrong password or corrupt keystore)")
        die("keytool could not read the keystore (corrupt or not PKCS12): " + (r.stderr.strip().splitlines() or ["?"])[-1][:200])
    m = re.search(r"SHA-?256:\s*([0-9A-Fa-f:]{95,})", r.stdout)
    d = norm_digest(m.group(1)) if m else ""
    if not d:
        die("could not read the certificate fingerprint of alias '%s'" % alias)
    return d


def cmd_prepare(a):
    b64, pw = os.environ.get("KS_B64", ""), os.environ.get("KS_PASS", "")
    alias, kpw = os.environ.get("KS_ALIAS", "").strip(), os.environ.get("KEY_PASS", "")
    if not b64.strip() or not pw or not alias:
        die("ANDROID_RELEASE_KEYSTORE_BASE64 / ANDROID_RELEASE_KEYSTORE_PASSWORD / ANDROID_RELEASE_KEY_ALIAS must all be set and non-empty")
    try:
        raw = base64.b64decode(b64.strip(), validate=True)
    except (binascii.Error, ValueError):
        die("ANDROID_RELEASE_KEYSTORE_BASE64 is not valid base64 (truncated or pasted with extra characters)")
    if len(raw) < 64:
        die("the decoded keystore is empty or too small (%d bytes)" % len(raw))
    fd = os.open(a.keystore, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(raw)
    cert = keystore_cert(a.keystore, alias)
    if kpw and kpw != pw:
        env = dict(os.environ)
        r = run(["keytool", "-keypasswd", "-alias", alias, "-keystore", a.keystore, "-storepass:env", "KS_PASS",
                 "-keypass:env", "KEY_PASS", "-new:env", "KS_PASS"], env)
        if r.returncode != 0 and "PKCS12" not in run(["keytool", "-list", "-v", "-keystore", a.keystore, "-storepass:env", "KS_PASS"], env).stdout:
            die("ANDROID_RELEASE_KEY_PASSWORD does not unlock the key '%s' (wrong key password)" % alias)
        # PKCS12 keystores use the store password for keys, so a differing key password is simply not used.
    print(cert)


def tres_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def cmd_settings(a):
    pw = os.environ.get("KS_PASS", "")
    if not pw:
        die("KS_PASS is empty")
    body = ('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
            'export/android/android_sdk_path = "%s"\nexport/android/java_sdk_path = "%s"\n'
            'export/android/debug_keystore = "%s"\nexport/android/debug_keystore_user = "%s"\n'
            'export/android/debug_keystore_pass = "%s"\n') % tuple(tres_escape(x) for x in (a.sdk, a.jdk, a.keystore, a.alias, pw))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    fd = os.open(a.out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(body)


def find_apksigner(sdk):
    cands = sorted(glob.glob(os.path.join(sdk, "build-tools", "*", "apksigner")))
    pref = os.path.join(sdk, "build-tools", "34.0.0", "apksigner")
    if pref in cands:
        return pref
    if cands:
        return cands[-1]
    die("apksigner not found under %s/build-tools/*/ (Android SDK build-tools missing; found: %s)" % (sdk, ", ".join(os.listdir(sdk)) if os.path.isdir(sdk) else "no SDK dir"))


def cmd_verify(a):
    if not os.path.isfile(a.apk) or os.path.getsize(a.apk) == 0:
        die("APK %s does not exist or is empty (the Godot export did not produce it)" % a.apk)
    if not os.path.isfile(a.apksigner):
        die("apksigner not found at %s" % a.apksigner)
    r = run([a.apksigner, "verify", "--print-certs", a.apk])
    if r.returncode != 0:
        die("apksigner verify rejected the APK (unsigned or corrupt):\n" + (r.stdout + r.stderr)[-600:])
    pin, perr = read_pin()
    ok, msg = check(r.stdout, a.mode, pin, perr, a.expect_cert.lower())
    print(("OK: " if ok else "FAIL: ") + msg)
    sys.exit(0 if ok else 1)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("check-pin"); p.add_argument("--require", action="store_true")
    p = sub.add_parser("prepare"); p.add_argument("--keystore", required=True)
    p = sub.add_parser("settings")
    for k in ("out", "sdk", "jdk", "keystore", "alias"):
        p.add_argument("--" + k, required=True)
    p = sub.add_parser("find-apksigner"); p.add_argument("sdk")
    p = sub.add_parser("verify"); p.add_argument("apk"); p.add_argument("--apksigner", required=True)
    p.add_argument("--mode", default="validate", choices=["release", "validate"]); p.add_argument("--expect-cert", default="")
    a = ap.parse_args()
    if a.cmd == "check-pin":
        d, err = read_pin()
        if err:
            die(err)
        if a.require and not d:
            die("no certificate pinned in tools/android_signing_cert.sha256 (run tools/android_keystore_setup.sh)")
        print("pin: " + (d if d else "(none yet)"))
    elif a.cmd == "prepare":
        cmd_prepare(a)
    elif a.cmd == "settings":
        cmd_settings(a)
    elif a.cmd == "find-apksigner":
        print(find_apksigner(a.sdk))
    else:
        cmd_verify(a)


if __name__ == "__main__":
    main()
