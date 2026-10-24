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

## Owner setup (Windows, copy-paste; you keep the key - nothing secret goes through chat)
**Tools needed once:** Git for Windows (gives *Git Bash* and `openssl`), a JDK (e.g. `winget install EclipseAdoptium.Temurin.17.JDK`, gives `keytool`),
GitHub CLI (`winget install GitHub.cli`, then `gh auth login` with the account that owns the repo), and Android platform-tools (`adb`).
Open **Git Bash** (not PowerShell) in a clone of the repo on `dev`/this branch and run:

1. `keytool -version && openssl version && gh auth status` - all three must answer.
2. `tools/android_keystore_setup.sh` - creates `~/backrooms-signing-backup/` (keystore `backroomssurvivor.p12`, `PASSWORD.txt`, public
   `cert.sha256`), proves the pair opens and holds the alias, then uploads the two repo secrets. Nothing is printed except the public
   fingerprint. If anything fails, fix the cause and run it again: the saved keystore is reused, never regenerated.
3. **Back up `~/backrooms-signing-backup/` now**: copy the whole folder to (a) a password manager attachment or encrypted drive and
   (b) one offline copy (USB stick). Keep the keystore and password together but away from the repo and from chat. GitHub secrets are
   write-only, so this folder is the only copy of the key.
4. Send me **only the fingerprint** (the 64-hex line the script prints, or the content of `cert.sha256`). I pin it in
   `tools/android_signing_cert.sha256`; release builds refuse to run without a valid pin and refuse any APK signed by another key.

## Before the one final uninstall: back up your save (debug builds only)
No build has an in-game export, `allowBackup` is false and Android's cloud backup is off, so the save would be lost on uninstall unless
copied out. The shipped APKs are **debuggable** (verified from Build 14's manifest), so `adb run-as` can copy app data. USB debugging on,
phone connected, in PowerShell or Git Bash:

    adb shell run-as com.verbal76.backroomssurvivor ls files            # expect backrooms_save.json (+ .bak), options.json
    adb exec-out run-as com.verbal76.backroomssurvivor cat files/backrooms_save.json > backrooms_save.json
    adb exec-out run-as com.verbal76.backroomssurvivor cat files/options.json > options.json

Keep those files. After installing the first APK signed with the new key, run it once (so the app data folder exists), close it, then:

    adb push backrooms_save.json /data/local/tmp/
    adb shell run-as com.verbal76.backroomssurvivor cp /data/local/tmp/backrooms_save.json files/backrooms_save.json
    adb shell rm /data/local/tmp/backrooms_save.json

(Same for `options.json`.) Not yet proven on the owner's phone: the `files/` location is Godot's usual internal `user://`; the `ls` in the
first command confirms it. If `run-as` is refused the save cannot be extracted, and the uninstall loses progress.

## Update-continuity test (one private APK pair; I run the builds after the pin is merged)
1. Build A (private, `local_only`, signed with the key) -> install -> play a few minutes so a save exists -> note the level/day.
2. Build B (next number, same key) -> install **over A with no uninstall** (`adb install -r` or open the APK) -> the save, options and
   progress are all still there. `adb shell dumpsys package com.verbal76.backroomssurvivor | grep versionCode` shows B's number.
3. `apksigner verify --print-certs` of A and B (the workflow already does this) shows the identical pinned certificate.

## Recovery / rotation
- Secrets lost, keystore backup intact: re-run `gh secret set` with the backed-up values (same key, updates keep working).
- Keystore lost: unrecoverable; a new key forces a reinstall for everyone (installed players lose saves unless exported).
  Update the pinned fingerprint deliberately. Google Play App Signing (if ever used) holds the key separately.
- Never paste the keystore or password into chat, issues, logs or commits.
