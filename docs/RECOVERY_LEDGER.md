# Recovery ledger (branch accounting)

Audit date: 2026-10-12. Method: ref/ancestry inventory of all local and remote branches, tags, worktrees and releases;
`git rev-list` against the authoritative line; `git cherry` patch equivalence; per-worktree uncommitted-change check;
file/semantic review of superseded or intentionally changed behavior. Regenerate the table any time with
`tools/branch_inventory.sh origin/dev` (read-only).

**Authoritative line: `dev`** @ `222225a25d7b557b52b622783a699e00e2ac0883` (identical to
`claude/fervent-franklin-hrrnb7` and PR #4's head; the rolling release `dev` and tag `dev` point to the same SHA).
`main` (`33c8e64`, protected production) is an ancestor of it and 41 commits behind; bringing `main` up to date needs the
owner's approval (merge PR #4).

## Branches, tags, releases

| Ref | Tip | Purpose | Classification | Proposed disposition |
|---|---|---|---|---|
| `origin/dev` | 222225a | integration/release line, source of the rolling `dev` release | **Authoritative** | keep |
| `claude/fervent-franklin-hrrnb7` (local+origin) | 222225a | working branch of the Godot port; PR #4 head | Integrated (identical to dev) | keep until PR #4 is merged by owner |
| `origin/main` | 33c8e64 | protected production branch (PR #3 merged) | Integrated (ancestor), outdated | owner merges PR #4 |
| `origin/claude/jolly-cori-g4l8rg` | 916c3e1 | PR #2: folder reorg, Godot skeleton, CC0 assets | Integrated (all commits reachable from dev; its content merged via #3/#4) | owner may close PR #2 as superseded; do not delete without approval |
| `origin/claude/exciting-cerf-8bng06` | 075d2fd | PR #1: LÖVE shortcuts | **Unknown - owner review** (1 commit, not integrated) | see item L-1 |
| local `main` | f57a2ac | stale local copy of an early commit | Integrated (ancestor) | none (local only) |
| `worktree-agent-a26b4377...` | bb4fe49 | Steam Deck / Linux pass | Integrated | local only; delete only with approval |
| `worktree-agent-a284b0ba...` | 43e5c6a | lighting + FX + chunk visuals | Integrated | same |
| `worktree-agent-a2ecacd0...` | 4cc7a8d | combat (weapons/bombs) | Integrated | same |
| `worktree-agent-a3d64a64...` | 79f7c9a | UI, input, meta progression | Integrated | same |
| `worktree-agent-a88aa55f...` | b3d7fbc | juice pass + held-weapon fix | Integrated | same |
| `worktree-agent-a993d463...` | e707c62 | crow enemy | Integrated | same |
| `worktree-agent-aa324b4b...` | fc9f4e7 | enemies | Integrated | same |
| `worktree-agent-aa86ab5f...` | d42f0de | world objects | Integrated | same |
| `worktree-agent-abcdaf49...` | 9161a5a | tutorial, controls, touch, intro | Integrated | same |
| `worktree-agent-adadeafa...` | f6e9f12 | balance pass + sim harness | Integrated | same |
| `worktree-agent-ae125020...` | 3ae576a | audio system | Integrated | same |
| `worktree-agent-afed0be9...` | 09866dc | traps | Integrated | same |
| tag/release `dev` | 222225a | rolling prerelease (dev build 12: apk, zip, tar.gz, patch.pck, manifest.json) | Built from the authoritative SHA | keep; it is rebuilt from `dev` only |

All 12 worktree branches have 0 commits and 0 patch-unique commits relative to `dev`, and no worktree has uncommitted
tracked changes (one untracked `crow_sheet.png.import` was already committed on the authoritative line).

## Findings by audit category

1. Branches with commits not reachable from the authoritative line: only `origin/claude/exciting-cerf-8bng06` (1 commit).
2. Completed features never integrated: none. Every feature branch (combat, enemies, objects, UI, audio, FX/juice,
   tutorial/controls, balance, crow, traps, Steam Deck) is reachable from `dev`.
3. Bug fixes only on abandoned branches: none found.
4. Performance improvements lost: none found (Deck occluder merge and quality presets are on `dev`).
5. UI/visual improvements missing from current builds: none found. Builds 1-12 were produced from ancestors of `dev`
   and dev build 12 is the authoritative SHA.
6. Platform fixes that never reached other platforms: none. Android's ETC2/ASTC project setting and the CI SDK install
   are in shared project/CI config; Linux/Steam Deck work is in shared code plus an extra export preset.
7. Assets/config/build improvements left behind: none on branches. Known absent by owner decision/license: the
   restricted asset packs (Post Apoc Office, Abandoned Office, Low Poly PSX, Glass UI, scarymobs) and the owner's
   earlier game folders (`BUILD_APK`, `Older versions`, `BR-isometric V1`, `new files temp`) were never in this repo.
8. Experimental work still valuable: none outstanding (traps minimap markers and enemy trap-avoidance are
   documented non-goals in the traps report).
9. Reverted/changed behavior investigated (all intentional or superseded):
   - Held-weapon mirroring: my negative-rect-height fix was **superseded** by the juice agent's
     transform-based fix with hand anchors (`weapon_view.gd`); verified by rendering at 8 angles.
   - Flee-from-headlamp enemy AI: **intentionally removed** (`FLEE_FROM_LIGHT=false`) because the Lua light level was a
     constant so enemies never fled; it made enemies hover outside melee reach.
   - Overlap contact damage (Lua) replaced by reach-based wind-up attacks: **intentional behavior change** (owner request).
   - Stamina/difficulty numbers changed by the balance pass: **intentional**, documented old->new in `godot/docs/BALANCE.md`.
10. Releases built from commits no longer in active development: none; the only release is the rolling `dev` release
    (previous builds 1-11 were replaced in place and were all ancestors of `dev`).

## Open items

- **L-1 (owner review) `origin/claude/exciting-cerf-8bng06` @ 075d2fd, PR #1 (draft):** adds `Documentation.url`, `LOVE.lnk`,
  `Uninstall.lnk` (Windows shortcuts from a LÖVE install) and `.claude/settings.local.json` (a machine-local agent
  settings file). Not recovered: unrelated to the Godot product, machine-specific, and the settings file should not be
  versioned. Options: leave unmerged and close PR #1, or ask for an explicit decision. No branch has been deleted.
- **L-2:** PR #2 (draft) is superseded by #3/#4; owner may close it.
- **L-3:** `main` is 41 commits behind `dev`; merge PR #4 (owner approval) to make `main` equal to the authoritative line.
- **L-4:** 12 local `worktree-agent-*` branches exist only locally. All their work is on `dev`; delete them only with approval.
