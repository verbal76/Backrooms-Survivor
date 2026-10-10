@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ==========================================================
REM  LOVE2D Universal Builder + Inno Setup Installer (One Step)
REM  - Packages EVERYTHING in the folder (you remove what you don't want)
REM  - Builds portable EXE folder with custom game icon
REM  - Builds a Windows installer (Inno Setup) if ISCC is found
REM ==========================================================

REM ------------------ EDIT THESE ------------------
set "GAME_NAME=BackroomsSurvivor"
set "APP_PUBLISHER=Your Studio Name"
set "APP_URL=https://example.com"
set "LOVE_VERSION=11.4"
set "EXE_NAME=BackroomsSurvivor.exe"

REM Icons (put .ico files next to this bat):
REM   game.ico  = icon on the game EXE, desktop shortcut, taskbar
REM   setup.ico = icon on the installer wizard window
set "GAME_ICON=game.ico"
set "SETUP_ICON=setup.ico"

REM Version string:
set "APP_VERSION=1.0.0"
REM ------------------------------------------------

set "LOVE_ZIP=love-%LOVE_VERSION%-win64.zip"
set "LOVE_DIR=love-%LOVE_VERSION%-win64"
set "RCEDIT=rcedit-x64.exe"

set "TEMP_DIR=_build_temp"
set "PORTABLE_DIR=Packaged Build Executable"
set "INSTALLER_OUT=Installer Output"
set "ISS_FILE=_installer.iss"

REM --- Always run from the folder this BAT is in ---
pushd "%~dp0"

REM --- Absolute paths for everything ---
set "BASEDIR=%CD%"
set "LOG=%BASEDIR%\build_log.txt"
set "ABS_TEMP=%BASEDIR%\%TEMP_DIR%"
set "ABS_LOVE=%BASEDIR%\%GAME_NAME%.love"
set "ABS_ZIP=%BASEDIR%\%GAME_NAME%.zip"
set "ABS_PORTABLE=%BASEDIR%\%PORTABLE_DIR%"

REM --- Start log (overwrite each run) ---
> "%LOG%" (
  echo ============================================
  echo  LOVE2D Builder + Inno Setup - LOG
  echo  Started: %DATE% %TIME%
  echo  Folder:  %BASEDIR%
  echo ============================================
  echo.
)

call :log "[INFO] Working dir: %BASEDIR%"

REM --- Verify main.lua exists ---
if not exist "%BASEDIR%\main.lua" (
  call :log "[ERROR] main.lua not found in this folder."
  call :log "        Put this .bat next to main.lua and run again."
  goto :fail
)
call :log "[OK] Found main.lua"

REM ==========================================================
REM  [1/5] Build .love by copying EVERYTHING into TEMP_DIR
REM ==========================================================
call :log "[1/5] Packaging EVERYTHING into .love archive..."

if exist "%ABS_TEMP%" rmdir /s /q "%ABS_TEMP%" >nul 2>&1
mkdir "%ABS_TEMP%" 2>nul
if not exist "%ABS_TEMP%\" (
  call :log "[ERROR] Could not create %ABS_TEMP%"
  goto :fail
)

if exist "%ABS_LOVE%" del /q "%ABS_LOVE%" >nul 2>&1
if exist "%ABS_ZIP%"  del /q "%ABS_ZIP%"  >nul 2>&1

call :log "Copying files/folders to %TEMP_DIR% ..."

REM --- Copy everything except exclusions ---
for /f "delims=" %%I in ('dir /b /a:-h 2^>nul') do (
  call :copyitem "%%I"
)

call :log "Creating .love archive via .NET ZipFile..."

REM --- Use .NET ZipFile::CreateFromDirectory (handles spaces, avoids zip64 issues) ---
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Add-Type -Assembly 'System.IO.Compression.FileSystem'; " ^
  "[System.IO.Compression.ZipFile]::CreateFromDirectory(" ^
    "[string]'%ABS_TEMP%', " ^
    "[string]'%ABS_ZIP%', " ^
    "[System.IO.Compression.CompressionLevel]::Optimal, " ^
    "$false)" >> "%LOG%" 2>&1

if not exist "%ABS_ZIP%" (
  call :log "[ERROR] Failed to create %GAME_NAME%.zip"
  call :log "[ERROR] PowerShell .NET ZipFile failed. Check path for special characters."
  goto :fail
)

REM --- Rename .zip to .love ---
ren "%ABS_ZIP%" "%GAME_NAME%.love" >nul 2>&1
if not exist "%ABS_LOVE%" (
  call :log "[ERROR] Failed to rename .zip to .love"
  goto :fail
)

REM --- Size check: .love should be at least 50 KB ---
for %%F in ("%ABS_LOVE%") do set "LOVE_SIZE=%%~zF"
call :log "[INFO] %GAME_NAME%.love size: %LOVE_SIZE% bytes"
if %LOVE_SIZE% LSS 50000 (
  call :log "[ERROR] .love file is suspiciously small (%LOVE_SIZE% bytes). Archive may be empty."
  goto :fail
)

call :log "[OK] Created %GAME_NAME%.love (%LOVE_SIZE% bytes)"

REM Clean up temp dir
if exist "%ABS_TEMP%" rmdir /s /q "%ABS_TEMP%" >nul 2>&1

REM ==========================================================
REM  [2/5] Ensure LOVE2D runtime is present
REM ==========================================================
call :log "[2/5] Ensuring LOVE2D runtime exists..."

if exist "%BASEDIR%\%LOVE_DIR%\love.exe" (
  call :log "[OK] LOVE2D already present: %LOVE_DIR%\love.exe"
) else (
  call :log "[INFO] LOVE2D not found. Downloading %LOVE_ZIP% ..."

  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "Invoke-WebRequest -Uri 'https://github.com/love2d/love/releases/download/%LOVE_VERSION%/%LOVE_ZIP%' " ^
    "-OutFile '%BASEDIR%\%LOVE_ZIP%'" >> "%LOG%" 2>&1

  if not exist "%BASEDIR%\%LOVE_ZIP%" (
    call :log "[ERROR] Download failed. Put %LOVE_ZIP% next to this bat and rerun."
    goto :fail
  )

  call :log "[INFO] Extracting %LOVE_ZIP% ..."
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Expand-Archive -Path '%BASEDIR%\%LOVE_ZIP%' -DestinationPath '%BASEDIR%' -Force" >> "%LOG%" 2>&1

  if not exist "%BASEDIR%\%LOVE_DIR%\love.exe" (
    call :log "[ERROR] Extraction failed. %LOVE_DIR%\love.exe not found."
    goto :fail
  )

  call :log "[OK] LOVE2D extracted to %LOVE_DIR%"
)

REM ==========================================================
REM  [3/5] Ensure rcedit is present (for custom EXE icon)
REM ==========================================================
call :log "[3/5] Checking for rcedit (EXE icon tool)..."

if exist "%BASEDIR%\%RCEDIT%" (
  call :log "[OK] rcedit already present: %RCEDIT%"
) else (
  if exist "%BASEDIR%\%GAME_ICON%" (
    call :log "[INFO] rcedit not found. Downloading %RCEDIT% ..."

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
      "Invoke-WebRequest -Uri 'https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe' " ^
      "-OutFile '%BASEDIR%\%RCEDIT%'" >> "%LOG%" 2>&1

    if not exist "%BASEDIR%\%RCEDIT%" (
      call :log "[WARN] rcedit download failed. EXE will use default LOVE icon."
      call :log "       Download rcedit-x64.exe manually from https://github.com/electron/rcedit/releases"
    ) else (
      call :log "[OK] rcedit downloaded: %RCEDIT%"
    )
  ) else (
    call :log "[INFO] No %GAME_ICON% found, skipping rcedit download."
  )
)

REM ==========================================================
REM  [4/5] Build portable folder (EXE + DLLs + custom icon)
REM ==========================================================
call :log "[4/5] Building portable executable folder..."

if exist "%ABS_PORTABLE%" rmdir /s /q "%ABS_PORTABLE%" >nul 2>&1
mkdir "%ABS_PORTABLE%" 2>nul
if not exist "%ABS_PORTABLE%\" (
  call :log "[ERROR] Could not create portable folder: %PORTABLE_DIR%"
  goto :fail
)

REM --- Fuse love.exe + .love into single EXE ---
copy /b "%BASEDIR%\%LOVE_DIR%\love.exe"+"%ABS_LOVE%" "%ABS_PORTABLE%\%EXE_NAME%" >nul 2>&1
if not exist "%ABS_PORTABLE%\%EXE_NAME%" (
  call :log "[ERROR] Failed to fuse EXE."
  goto :fail
)

REM --- Size check: fused EXE should be bigger than love.exe alone ---
for %%F in ("%ABS_PORTABLE%\%EXE_NAME%") do set "EXE_SIZE=%%~zF"
for %%F in ("%BASEDIR%\%LOVE_DIR%\love.exe") do set "LOVE_EXE_SIZE=%%~zF"
call :log "[INFO] Fused EXE size: %EXE_SIZE% bytes (love.exe: %LOVE_EXE_SIZE%, .love: %LOVE_SIZE%)"

REM --- Apply custom game icon to the EXE ---
if exist "%BASEDIR%\%GAME_ICON%" (
  if exist "%BASEDIR%\%RCEDIT%" (
    call :log "[INFO] Applying custom icon: %GAME_ICON%"
    "%BASEDIR%\%RCEDIT%" "%ABS_PORTABLE%\%EXE_NAME%" --set-icon "%BASEDIR%\%GAME_ICON%" >> "%LOG%" 2>&1
    if errorlevel 1 (
      call :log "[WARN] rcedit failed to set icon. EXE will use default LOVE icon."
    ) else (
      call :log "[OK] Custom icon applied to %EXE_NAME%"
    )
  ) else (
    call :log "[WARN] %GAME_ICON% found but rcedit missing. EXE will use default LOVE icon."
  )
) else (
  call :log "[INFO] No %GAME_ICON% found. EXE will use default LOVE icon."
  call :log "       To add a custom icon: put game.ico (256x256 .ico) next to this bat and rebuild."
)

copy "%BASEDIR%\%LOVE_DIR%\*.dll" "%ABS_PORTABLE%\" >nul 2>&1
if exist "%BASEDIR%\%LOVE_DIR%\license.txt" copy "%BASEDIR%\%LOVE_DIR%\license.txt" "%ABS_PORTABLE%\" >nul 2>&1

call :log "[OK] Portable build ready: %PORTABLE_DIR%\%EXE_NAME%"

REM ==========================================================
REM  [5/5] Build installer (Inno Setup) if ISCC is found
REM ==========================================================
call :log "[5/5] Building installer via Inno Setup (if available)..."

REM Find ISCC.exe (common locations)
set "ISCC="
for %%P in (
  "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
  "%ProgramFiles%\Inno Setup 6\ISCC.exe"
) do (
  if exist "%%~P" set "ISCC=%%~P"
)

if "%ISCC%"=="" (
  call :log "[WARN] ISCC.exe not found. Installer step skipped."
  call :log "       Install Inno Setup 6 and rerun to generate a setup installer."
  goto :success
)

if exist "%BASEDIR%\%INSTALLER_OUT%" rmdir /s /q "%BASEDIR%\%INSTALLER_OUT%" >nul 2>&1
mkdir "%BASEDIR%\%INSTALLER_OUT%" 2>nul

REM Write a fresh .iss each run
(
  echo ; Auto-generated installer script
  echo [Setup]
  echo AppName=%GAME_NAME%
  echo AppVersion=%APP_VERSION%
  echo AppPublisher=%APP_PUBLISHER%
  echo AppPublisherURL=%APP_URL%
  echo DefaultDirName={autopf}\%GAME_NAME%
  echo DefaultGroupName=%GAME_NAME%
  echo UninstallDisplayIcon={app}\%EXE_NAME%
  echo OutputDir=%BASEDIR%\%INSTALLER_OUT%
  echo OutputBaseFilename=%GAME_NAME%_Setup_%APP_VERSION%
  echo Compression=lzma2
  echo SolidCompression=yes
  echo WizardStyle=modern
  echo DisableProgramGroupPage=no
  echo PrivilegesRequired=lowest
  if exist "%BASEDIR%\%SETUP_ICON%" echo SetupIconFile=%BASEDIR%\%SETUP_ICON%
  echo.
  echo [Files]
  echo Source: "%ABS_PORTABLE%\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
  echo.
  echo [Icons]
  echo Name: "{group}\%GAME_NAME%"; Filename: "{app}\%EXE_NAME%"
  echo Name: "{autodesktop}\%GAME_NAME%"; Filename: "{app}\%EXE_NAME%"; Tasks: desktopicon
  echo.
  echo [Tasks]
  echo Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"
  echo.
  echo [Run]
  echo Filename: "{app}\%EXE_NAME%"; Description: "Launch %GAME_NAME%"; Flags: nowait postinstall skipifsilent
) > "%BASEDIR%\%ISS_FILE%"

call :log "[INFO] Compiling installer: %ISS_FILE%"
"%ISCC%" "%BASEDIR%\%ISS_FILE%" >> "%LOG%" 2>&1
if errorlevel 1 (
  call :log "[ERROR] Inno Setup compile failed. Check build_log.txt"
  goto :fail
)

call :log "[OK] Installer created in: %INSTALLER_OUT%"
goto :success

:success
call :log "============================================"
call :log "BUILD COMPLETE"
call :log "============================================"
echo.
echo BUILD COMPLETE.
echo Portable: "%ABS_PORTABLE%"
echo Installer: "%BASEDIR%\%INSTALLER_OUT%"  (if ISCC found)
echo Log: "%LOG%"
echo.
explorer "%ABS_PORTABLE%"
if exist "%BASEDIR%\%INSTALLER_OUT%\" explorer "%BASEDIR%\%INSTALLER_OUT%"
popd
exit /b 0

:fail
call :log "============================================"
call :log "BUILD FAILED"
call :log "============================================"
echo.
echo BUILD FAILED. See "%LOG%" for details.
echo.
popd
pause
exit /b 1

:copyitem
set "CNAME=%~1"
if "%CNAME%"=="" exit /b 0
if /i "%CNAME%"=="%LOVE_DIR%" ( call :log "  Skipping LOVE folder: %CNAME%" & exit /b 0 )
if /i "%CNAME%"=="%PORTABLE_DIR%" ( call :log "  Skipping portable output: %CNAME%" & exit /b 0 )
if /i "%CNAME%"=="%INSTALLER_OUT%" ( call :log "  Skipping installer output: %CNAME%" & exit /b 0 )
if /i "%CNAME%"=="%TEMP_DIR%" ( call :log "  Skipping temp folder: %CNAME%" & exit /b 0 )
if /i "%CNAME%"=="%~nx0" ( call :log "  Skipping builder bat: %CNAME%" & exit /b 0 )
set "CEXT=%~x1"
if /i "%CEXT%"==".love" ( call :log "  Skipping build artifact: %CNAME%" & exit /b 0 )
if /i "%CEXT%"==".zip" ( call :log "  Skipping build artifact: %CNAME%" & exit /b 0 )
if /i "%CNAME%"=="build_log.txt" ( call :log "  Skipping log: %CNAME%" & exit /b 0 )
if /i "%CNAME%"=="_installer.iss" ( call :log "  Skipping ISS: %CNAME%" & exit /b 0 )
if exist "%CNAME%\*" (
  call :log "  Copy folder: %CNAME%"
  xcopy "%CNAME%" "%ABS_TEMP%\%CNAME%\" /e /i /q /y >nul 2>&1
) else (
  call :log "  Copy file: %CNAME%"
  copy /y "%CNAME%" "%ABS_TEMP%\" >nul 2>&1
)
exit /b 0

:log
>> "%LOG%" echo %~1
echo %~1
exit /b 0