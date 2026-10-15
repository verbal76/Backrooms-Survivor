# Android signing identity (persistent)

**Why:** until Build 15 every CI run generated a fresh debug keystore, so no APK could update the previous one (Android refuses a
different signer) and players had to uninstall, losing their saves. Fixed: one persistent keystore, held in GitHub Actions
secrets, used by every `release-build.yml` / `dev-build.yml` APK.

## How it works
- Secrets `ANDROID_KEYSTORE_B64` (base64 PKCS12) and `ANDROID_KEYSTORE_PASSWORD` (store = key password), alias `backroomssurvivor`.
- `build-all.yml` (Export Android): with the secrets -> signs with that key. **release mode without the secrets fails closed.**
  validate mode (PR checks, forks, no secrets) uses a throw-away key and prints a warning; such APKs are test-only.
- `tools/android_signing.py verify` runs `apksigner verify` on every built APK and, once `tools/android_signing_cert.sha256`
  holds the public certificate SHA-256, refuses any APK signed by a different key.
- Application id is fixed (`com.verbal76.backroomssurvivor`, checked by `verify_artifacts.py`); `versionCode` = the coordinated build
  number, which the publish gate keeps strictly increasing. Same id + same signer + higher versionCode = in-place update; saves
  (`user://`) are kept. Never reuse a lower number for a distributed build.
- Nothing secret is in the repo; only the public certificate digest is committed.

## One-time owner setup (minimum steps)
On your own machine (JDK `keytool` + GitHub CLI logged in as the repo admin):
1. `tools/android_keystore_setup.sh` - creates `~/backrooms-signing-backup/` (keystore + password), sets both secrets, prints the
   public fingerprint. It refuses to overwrite an existing key.
2. **Back up `~/backrooms-signing-backup/` immediately** (password manager + offline copy). The key cannot be recovered from GitHub
   (secrets are write-only).
3. Put the printed fingerprint into `tools/android_signing_cert.sha256` (or send it to the agent) and merge via `dev`.
4. Build once; install it (one last uninstall of the old build is unavoidable - different key). Every later build updates in place.
   Verify: `adb install -r` / just open the APK over the previous one; progress is kept.

## Recovery / rotation
- Secrets lost, keystore backup intact: re-run `gh secret set` with the backed-up values (same key, updates keep working).
- Keystore lost: unrecoverable; a new key forces a reinstall for everyone (installed players lose saves unless exported).
  Update the pinned fingerprint deliberately. Google Play App Signing (if ever used) holds the key separately.
- Never paste the keystore or password into chat, issues, logs or commits.
