# SteamPipe templates (preparation only)

Nothing here uploads anything and no Steam App ID, depot ID or credential exists in this repository. The `*.template`
files carry `@PLACEHOLDER@` values that the owner fills in after creating the app in Steamworks.

Layout expected by the templates: `content/windows/` = unzipped `Backrooms Survivor Build NN EXE.zip`,
`content/linux/` = extracted `Backrooms Survivor Build NN Linux.tar.gz` (the tarball keeps the execute bit).

**Blocker before a real depot upload (owner decision R-4):** the only export presets are the *debug* "Windows Dev" /
"Linux Dev" ones, and debug builds contain the OTA updater (`Patcher.updater_enabled()`), which store builds must not use
(Steam updates through Steam). A release-template Steam preset is a change to `export_presets.cfg`, which per policy needs
a native build and a `min_base_build.txt` decision, so it is deliberately NOT added here. Run `BackroomsSurvivor` with
`--no-update` (Steam launch option) only as a stop-gap for internal testing.
Also not done: `steam_appid.txt` (local launches only, never ship it in a depot), GodotSteam, Steam Cloud
(Auto-Cloud root `WinAppDataRoaming` / `LinuxXdgDataHome`, files `backrooms_save.json`, `options.json`).
