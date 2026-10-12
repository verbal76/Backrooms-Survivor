#!/usr/bin/env bash
# Publication gate used (twice: before building and again inside the publishing job) by dev-build.yml and release-build.yml.
# All authorization inputs come from trusted GitHub context passed in the environment; user-typed values are only validated.
# Required env: GH_TOKEN REPO EVENT REF ACTOR TRIGGERING_ACTOR RUN_ATTEMPT SRC NUM
# Fails closed: any lookup error aborts.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${GH_TOKEN:?}" "${REPO:?}" "${EVENT:?}" "${REF:?}" "${ACTOR:?}" "${TRIGGERING_ACTOR:?}" "${RUN_ATTEMPT:?}" "${SRC:?}" "${NUM:?}"
TMP="$(mktemp -d)"

# 1. trusted initiator + repository role (GitHub's own API, not anything the dispatcher typed)
gh api "repos/${REPO}/collaborators/${TRIGGERING_ACTOR}/permission" > "$TMP/perm.json"
python3 "$HERE/ci_guard.py" authorize --event "$EVENT" --ref "$REF" --actor "$ACTOR" --triggering-actor "$TRIGGERING_ACTOR" \
  --run-attempt "$RUN_ATTEMPT" --permission-file "$TMP/perm.json" --allow-ref refs/heads/dev

# 2. source must be the live tip of dev
DEV_TIP="$(git ls-remote origin refs/heads/dev | cut -f1)"
[ -n "$DEV_TIP" ] || { echo "::error::REFUSED: cannot read dev tip"; exit 1; }
python3 "$HERE/ci_guard.py" source --sha "$SRC" --dev-tip "$DEV_TIP"

# 3. one build/OTA number sequence (live OTA channel build + every build-NN tag); lookup failure refuses
OTA="$(curl -fsSL --retry 3 "https://github.com/${REPO}/releases/download/dev/manifest.json" | python3 -c 'import json,sys; print(int(json.load(sys.stdin)["build"]))')"
TAGS="$(git ls-remote --tags origin 'refs/tags/build-*' | cut -f2 | tr '\n' ' ')"
python3 "$HERE/ci_guard.py" sequence --number "$NUM" --ota-build "$OTA" --tags "$TAGS"
