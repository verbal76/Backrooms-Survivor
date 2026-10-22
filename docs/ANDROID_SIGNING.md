# Android signing identity (persistent)

**Why:** until Build 15 every CI run generated a fresh debug keystore, so no APK could update the previous one (Android refuses a
different signer) and players had to uninstall, losing their saves. Fixed: one persistent keystore, held in GitHub Actions
secrets, used by every `release-build.yml` / `dev-build.yml` APK.

## Provenance of existing installs (verified 2026-10-22 from the public release APKs)
| APK | Signer certificate SHA-256 | Created |
|---|---|---|
| Dev build 13 (OTA release `dev`) | `E8:98:99:54:FC:CD:E2:D1:A9:3A:2C:BA:A9:8C:8C:62:BF:52:46:2D:34:81:61:B1:76:22:64:3A:24:8A:C5:06` | 2026-10-13 02:19 UTC |
| Build 14 (release `build-14`) | `86:8F:20:4F:A7:9E:62:1D:55:FB:BF:F3:5A:83:79:A4:9C:28:2E:F3:25:1F:E8:50:B1:53:20:87:66:41:A8:78` | 2026-10-13 04:19 UTC |

Each was a throw-away key generated on a CI runner and discarded with it; no keystore for either exists anywhere. **There is therefore
no established signing identity to continue**: builds 12-15 cannot update each other, and a persistent key can never be made to match
them. These fingerprints must NOT be pinned. The first APK signed with the persistent key needs one last uninstall.

## How it works
- Secrets `ANDROID_KEYSTORE_B64` (base64 PKCS12) and `ANDROID_KEYSTORE_PASSWORD` (store = key password), alias `backroomssurvivor`.
- `build-all.yml` (Export Android): with the secrets -> signs with that key. **release mode without the secrets fails closed.**
  validate mode (PR checks, forks, no secrets) uses a throw-away key and prints a warning; such APKs are test-only.
- Release mode fails closed, before any SDK download, unless `tools/android_signing_cert.sha256` holds a valid pinned fingerprint
  and both secrets exist. PR checks (`policy_check.py`) validate the pin file's syntax on every pull request.
- The keystore secret is decoded, checked (non-empty, opens with the password, alias present) before export. The Godot export is not
  success-masked, any stale APK is deleted first, and `tools/android_signing.py verify` then checks the freshly built APK: valid
  signature, certificate == the keystore's certificate (Godot used the configured key) and, in release mode, == the pin.
- The keystore and Godot settings file are removed at the end of the step; the password is never echoed (escaped for the settings file).
- Application id is fixed (`com.verbal76.backroomssurvivor`, checked by `verify_artifacts.py`); `versionCode` = the coordinated build
  number, which the publish gate keeps strictly increasing. Same id + same signer + higher versionCode = in-place update; saves
  (`user://`) are kept. Never reuse a lower number for a distributed build.
- Nothing secret is in the repo; only the public certificate digest is committed.

## One-time owner setup (minimum steps)
On your own machine (JDK `keytool` + GitHub CLI logged in as the repo admin):
1. `tools/android_keystore_setup.sh` - (re-runnable; reuses an existing keystore and saves credentials before uploading) creates `~/backrooms-signing-backup/` (keystore + password), sets both secrets, prints the
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
