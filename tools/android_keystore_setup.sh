#!/usr/bin/env bash
# ONE-TIME owner setup of the persistent Android signing identity. Run on your own machine (needs JDK keytool + GitHub CLI `gh`
# logged in with admin rights to the repo). Never prints or commits the key or password.
#   tools/android_keystore_setup.sh [owner/repo]
set -euo pipefail
REPO="${1:-verbal76/Backrooms-Survivor}"
DIR="$HOME/backrooms-signing-backup"
KS="$DIR/backroomssurvivor.p12"
[ -e "$KS" ] && { echo "refusing to overwrite existing $KS (a key already exists - see docs/ANDROID_SIGNING.md)"; exit 1; }
mkdir -p "$DIR"; chmod 700 "$DIR"
PASS="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 28)"
keytool -genkeypair -alias backroomssurvivor -keyalg RSA -keysize 4096 -validity 36500 \
  -dname "CN=Backrooms Survivor,O=Hot Attic Games" -keystore "$KS" -storetype PKCS12 \
  -storepass "$PASS" -keypass "$PASS" >/dev/null
chmod 600 "$KS"
base64 -w0 "$KS" 2>/dev/null | gh secret set ANDROID_KEYSTORE_B64 --repo "$REPO" || base64 < "$KS" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_B64 --repo "$REPO"
printf '%s' "$PASS" | gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$REPO"
printf '%s' "$PASS" > "$DIR/PASSWORD.txt"; chmod 600 "$DIR/PASSWORD.txt"
FP="$(keytool -list -v -keystore "$KS" -storepass "$PASS" | grep -m1 'SHA256:' | sed 's/.*SHA256: *//' | tr -d ':' | tr 'A-F' 'a-f')"
echo "$FP" > "$DIR/cert.sha256"
echo
echo "Done. Secrets ANDROID_KEYSTORE_B64 and ANDROID_KEYSTORE_PASSWORD are set on $REPO."
echo "BACK UP $DIR (keystore + PASSWORD.txt) to a password manager / offline storage NOW. Losing it means one more reinstall."
echo "Public certificate fingerprint (safe to share/commit): $FP"
echo "Tell Claude this fingerprint (or put it in tools/android_signing_cert.sha256 on dev) to pin it."
