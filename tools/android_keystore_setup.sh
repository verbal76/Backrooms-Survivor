#!/usr/bin/env bash
# Owner setup of the persistent Android signing identity. Run on your own machine (JDK `keytool`, `openssl`, GitHub CLI `gh`
# logged in with admin rights to the repo). Never prints or commits the key or password.
#   tools/android_keystore_setup.sh [owner/repo]
# Recoverable + idempotent: the keystore and its password are written to ~/backrooms-signing-backup BEFORE anything is uploaded.
# If a step fails, fix the cause and run it again: an existing, valid keystore is REUSED (never regenerated or overwritten) and the
# secrets are simply uploaded again from the saved files.
set -euo pipefail
REPO="${1:-verbal76/Backrooms-Survivor}"
ALIAS=backroomssurvivor
DIR="$HOME/backrooms-signing-backup"
KS="$DIR/backroomssurvivor.p12"
PWF="$DIR/PASSWORD.txt"
umask 077
mkdir -p "$DIR"; chmod 700 "$DIR"

if [ -e "$KS" ] && [ ! -s "$PWF" ]; then
  echo "A keystore exists but its password file is missing/empty: $PWF"
  echo "Restore the password from your backup into that file (do NOT delete the keystore), then run this again."; exit 1
fi
if [ ! -e "$KS" ]; then
  # 48 hex chars from openssl: no pipe tricks, fixed length, safe in every shell and in the Godot settings file.
  openssl rand -hex 24 > "$PWF"
  keytool -genkeypair -alias "$ALIAS" -keyalg RSA -keysize 4096 -validity 36500 \
    -dname "CN=Backrooms Survivor,O=Hot Attic Games" -keystore "$KS" -storetype PKCS12 \
    -storepass:file "$PWF" -keypass:file "$PWF" >/dev/null
  echo "Created a new keystore in $DIR"
else
  echo "Reusing the existing keystore in $DIR"
fi
chmod 600 "$KS" "$PWF"
# Prove the saved pair opens and holds the alias before uploading anything.
FPLINE="$(keytool -list -v -keystore "$KS" -alias "$ALIAS" -storepass:file "$PWF" | grep -m1 'SHA256:')" \
  || { echo "The keystore does not open with the saved password or lacks alias $ALIAS - not uploading."; exit 1; }
FP="$(printf '%s' "$FPLINE" | sed 's/.*SHA256: *//' | tr -d ':' | tr 'A-F' 'a-f')"
echo "$FP" > "$DIR/cert.sha256"

# Uploads: base64 without line wraps (GNU `-w0` or BSD/macOS fallback), password from the saved file; never echoed.
B64="$(base64 -w0 "$KS" 2>/dev/null || base64 < "$KS" | tr -d '\n')"
[ -n "$B64" ] || { echo "base64 produced nothing"; exit 1; }
printf '%s' "$B64" | gh secret set ANDROID_KEYSTORE_B64 --repo "$REPO"
gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$REPO" < "$PWF"

echo
echo "Done. Secrets ANDROID_KEYSTORE_B64 and ANDROID_KEYSTORE_PASSWORD are set on $REPO."
echo "BACK UP $DIR (keystore + PASSWORD.txt) to a password manager / offline storage NOW. Losing it means one more reinstall."
echo "Public certificate fingerprint (safe to share/commit): $FP"
echo "Next: put it in tools/android_signing_cert.sha256 on dev (release builds refuse to run until it is pinned)."
