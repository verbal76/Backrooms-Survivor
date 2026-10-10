@echo off
title Backrooms Survivor - 3D Model to Spritesheet
setlocal enabledelayedexpansion

echo.
echo ================================================================
echo   BACKROOMS SURVIVOR - 3D Model to Spritesheet Converter
echo ================================================================
echo.
echo   This script takes a 3D model and renders it into a top-down
echo   sprite that the game uses for characters and world objects.
echo.
echo   PREREQUISITES:
echo   1. Blender 4.x or 5.x installed (free: blender.org/download)
echo.
echo   SUPPORTED FORMATS:
echo   .fbx  .obj  .glb  .gltf  .dae  .stl  .blend
echo.
echo ================================================================
echo.

REM ──────────────────────────────────────────────────
REM  CONFIGURATION
REM ──────────────────────────────────────────────────

set FRAME_SIZE=128
set NUM_ANGLES=16
set OUTPUT_SUBFOLDER=

REM ──────────────────────────────────────────────────
REM  FIND BLENDER
REM ──────────────────────────────────────────────────

set BLENDER_EXE=

if exist "C:\Program Files\Blender Foundation\Blender 3.6\blender.exe" (
    set "BLENDER_EXE=C:\Program Files\Blender Foundation\Blender 3.6\blender.exe"
)
if exist "C:\Program Files\Blender Foundation\Blender 4.0\blender.exe" (
    set "BLENDER_EXE=C:\Program Files\Blender Foundation\Blender 4.0\blender.exe"
)
if exist "C:\Program Files\Blender Foundation\Blender 4.1\blender.exe" (
    set "BLENDER_EXE=C:\Program Files\Blender Foundation\Blender 4.1\blender.exe"
)
if exist "C:\Program Files\Blender Foundation\Blender 4.2\blender.exe" (
    set "BLENDER_EXE=C:\Program Files\Blender Foundation\Blender 4.2\blender.exe"
)
if exist "C:\Program Files\Blender Foundation\Blender 4.3\blender.exe" (
    set "BLENDER_EXE=C:\Program Files\Blender Foundation\Blender 4.3\blender.exe"
)
if exist "C:\Program Files\Blender Foundation\Blender 4.4\blender.exe" (
    set "BLENDER_EXE=C:\Program Files\Blender Foundation\Blender 4.4\blender.exe"
)
if exist "C:\Program Files\Blender Foundation\Blender 5.0\blender.exe" (
    set "BLENDER_EXE=C:\Program Files\Blender Foundation\Blender 5.0\blender.exe"
)

if "%BLENDER_EXE%"=="" (
    where blender >nul 2>nul
    if not errorlevel 1 (
        for /f "tokens=*" %%i in ('where blender') do set "BLENDER_EXE=%%i"
    )
)

if "%BLENDER_EXE%"=="" (
    if exist "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe" (
        set "BLENDER_EXE=C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe"
    )
)

if "%BLENDER_EXE%"=="" (
    echo [FAIL] Blender not found!
    echo.
    echo   Download Blender for free from: https://www.blender.org/download/
    echo   Install it with default settings, then run this script again.
    pause
    exit /b 1
)

echo [OK] Found Blender: %BLENDER_EXE%

REM ──────────────────────────────────────────────────
REM  GET MODEL FILE
REM ──────────────────────────────────────────────────

set MODEL_FILE=%~1

if "%MODEL_FILE%"=="" (
    echo.
    echo   No file was dragged onto this script.
    echo   Enter the path to your 3D model file:
    echo.
    set /p MODEL_FILE="   Model path: "
)

if "%MODEL_FILE%"=="" (
    echo [FAIL] No model file specified.
    pause
    exit /b 1
)

if not exist "%MODEL_FILE%" (
    echo [FAIL] File not found: %MODEL_FILE%
    pause
    exit /b 1
)

echo [OK] Model: %MODEL_FILE%

REM ──────────────────────────────────────────────────
REM  FIND THE PYTHON SCRIPT
REM ──────────────────────────────────────────────────

set SCRIPT_DIR=%~dp0
set PY_SCRIPT=%SCRIPT_DIR%render_spritesheet.py

if not exist "%PY_SCRIPT%" (
    echo [FAIL] render_spritesheet.py not found in %SCRIPT_DIR%
    echo        Make sure render_spritesheet.py is in the same folder as this .bat
    pause
    exit /b 1
)

echo [OK] Script: %PY_SCRIPT%

REM ──────────────────────────────────────────────────
REM  SELECT SPRITE TYPE
REM ──────────────────────────────────────────────────

echo.
echo ================================================================
echo   What are you making? Pick a number:
echo ================================================================
echo.
echo   === CHARACTERS (16 angles, 128px, goes in game root) ===
echo.
echo     1. Player Character        (player_spritesheet)
echo     2. Hound                   (enemy_hound_spritesheet)
echo     3. Crawler                 (enemy_crawler_spritesheet)
echo     4. Wretch                  (enemy_wretch_spritesheet)
echo     5. Shade                   (enemy_shade_spritesheet)
echo     6. Skin Stealer            (enemy_skinstealer_spritesheet)
echo.
echo   === WORLD PROPS (1 angle, 32px, goes in world_assets/) ===
echo.
echo   --- Dead Bodies ---
echo     7.  body_facedown          10. body_crawling
echo     8.  body_slumped
echo     9.  body_fetal
echo.
echo   --- Desks ---
echo     11. desk_standard          14. desk_overturned
echo     12. desk_monitor
echo     13. desk_papers
echo.
echo   --- Chairs ---
echo     15. chair_office           18. chair_broken
echo     16. chair_knocked
echo     17. chair_simple
echo.
echo   --- Coffee/Vending ---
echo     19. coffee_machine         22. vending_machine
echo     20. water_cooler
echo     21. coffee_mugs
echo.
echo   --- Clutter ---
echo     23. papers_scattered       26. debris_pile
echo     24. papers_folder
echo     25. cardboard_box
echo.
echo   --- Shelving ---
echo     27. filing_cabinet         30. shelf_toppled
echo     28. bookshelf
echo     29. cabinet_open
echo.

set /p SPRITE_CHOICE="   Enter number [1-30]: "

REM === CHARACTERS ===
if "%SPRITE_CHOICE%"=="1" (
    set SPRITE_NAME=player_spritesheet.png
    set CHAR_LABEL=Player Character
    set FRAME_SIZE=128
    set NUM_ANGLES=16
    set OUTPUT_SUBFOLDER=
)
if "%SPRITE_CHOICE%"=="2" (
    set SPRITE_NAME=enemy_hound_spritesheet.png
    set CHAR_LABEL=Hound
    set FRAME_SIZE=128
    set NUM_ANGLES=16
    set OUTPUT_SUBFOLDER=
)
if "%SPRITE_CHOICE%"=="3" (
    set SPRITE_NAME=enemy_crawler_spritesheet.png
    set CHAR_LABEL=Crawler
    set FRAME_SIZE=128
    set NUM_ANGLES=16
    set OUTPUT_SUBFOLDER=
)
if "%SPRITE_CHOICE%"=="4" (
    set SPRITE_NAME=enemy_wretch_spritesheet.png
    set CHAR_LABEL=Wretch
    set FRAME_SIZE=128
    set NUM_ANGLES=16
    set OUTPUT_SUBFOLDER=
)
if "%SPRITE_CHOICE%"=="5" (
    set SPRITE_NAME=enemy_shade_spritesheet.png
    set CHAR_LABEL=Shade
    set FRAME_SIZE=128
    set NUM_ANGLES=16
    set OUTPUT_SUBFOLDER=
)
if "%SPRITE_CHOICE%"=="6" (
    set SPRITE_NAME=enemy_skinstealer_spritesheet.png
    set CHAR_LABEL=Skin Stealer
    set FRAME_SIZE=128
    set NUM_ANGLES=16
    set OUTPUT_SUBFOLDER=
)

REM === DEAD BODIES ===
if "%SPRITE_CHOICE%"=="7" (
    set SPRITE_NAME=body_facedown.png
    set CHAR_LABEL=Body Facedown
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="8" (
    set SPRITE_NAME=body_slumped.png
    set CHAR_LABEL=Body Slumped
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="9" (
    set SPRITE_NAME=body_fetal.png
    set CHAR_LABEL=Body Fetal
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="10" (
    set SPRITE_NAME=body_crawling.png
    set CHAR_LABEL=Body Crawling
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)

REM === DESKS ===
if "%SPRITE_CHOICE%"=="11" (
    set SPRITE_NAME=desk_standard.png
    set CHAR_LABEL=Desk Standard
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="12" (
    set SPRITE_NAME=desk_monitor.png
    set CHAR_LABEL=Desk with Monitor
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="13" (
    set SPRITE_NAME=desk_papers.png
    set CHAR_LABEL=Desk with Papers
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="14" (
    set SPRITE_NAME=desk_overturned.png
    set CHAR_LABEL=Desk Overturned
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)

REM === CHAIRS ===
if "%SPRITE_CHOICE%"=="15" (
    set SPRITE_NAME=chair_office.png
    set CHAR_LABEL=Office Chair
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="16" (
    set SPRITE_NAME=chair_knocked.png
    set CHAR_LABEL=Knocked Over Chair
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="17" (
    set SPRITE_NAME=chair_simple.png
    set CHAR_LABEL=Simple Chair
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="18" (
    set SPRITE_NAME=chair_broken.png
    set CHAR_LABEL=Broken Chair
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)

REM === COFFEE/VENDING ===
if "%SPRITE_CHOICE%"=="19" (
    set SPRITE_NAME=coffee_machine.png
    set CHAR_LABEL=Coffee Machine
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="20" (
    set SPRITE_NAME=water_cooler.png
    set CHAR_LABEL=Water Cooler
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="21" (
    set SPRITE_NAME=coffee_mugs.png
    set CHAR_LABEL=Coffee Mugs
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="22" (
    set SPRITE_NAME=vending_machine.png
    set CHAR_LABEL=Vending Machine
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)

REM === CLUTTER ===
if "%SPRITE_CHOICE%"=="23" (
    set SPRITE_NAME=papers_scattered.png
    set CHAR_LABEL=Scattered Papers
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="24" (
    set SPRITE_NAME=papers_folder.png
    set CHAR_LABEL=Paper Folder
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="25" (
    set SPRITE_NAME=cardboard_box.png
    set CHAR_LABEL=Cardboard Box
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="26" (
    set SPRITE_NAME=debris_pile.png
    set CHAR_LABEL=Debris Pile
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)

REM === SHELVING ===
if "%SPRITE_CHOICE%"=="27" (
    set SPRITE_NAME=filing_cabinet.png
    set CHAR_LABEL=Filing Cabinet
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="28" (
    set SPRITE_NAME=bookshelf.png
    set CHAR_LABEL=Bookshelf
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="29" (
    set SPRITE_NAME=cabinet_open.png
    set CHAR_LABEL=Open Cabinet
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)
if "%SPRITE_CHOICE%"=="30" (
    set SPRITE_NAME=shelf_toppled.png
    set CHAR_LABEL=Toppled Shelf
    set FRAME_SIZE=32
    set NUM_ANGLES=1
    set OUTPUT_SUBFOLDER=world_assets
)

if "%SPRITE_NAME%"=="" (
    echo [FAIL] Invalid selection. Enter a number 1-30.
    pause
    exit /b 1
)

echo.
echo   Selected: %CHAR_LABEL%
echo   Output:   %SPRITE_NAME%
echo   Size:     %FRAME_SIZE%x%FRAME_SIZE%    Angles: %NUM_ANGLES%

REM ──────────────────────────────────────────────────
REM  OPTIONAL SETTINGS OVERRIDE
REM ──────────────────────────────────────────────────

echo.
echo   Press ENTER to keep defaults, or type new values:
echo.

set /p INPUT_SIZE="   Frame size [%FRAME_SIZE%]: "
if not "%INPUT_SIZE%"=="" set FRAME_SIZE=%INPUT_SIZE%

set /p INPUT_ANGLES="   Number of angles [%NUM_ANGLES%]: "
if not "%INPUT_ANGLES%"=="" set NUM_ANGLES=%INPUT_ANGLES%

echo.
echo ================================================================
echo   Rendering %CHAR_LABEL%
echo   %NUM_ANGLES% frame(s) at %FRAME_SIZE%x%FRAME_SIZE%...
echo   This may take 1-5 minutes depending on model complexity.
echo ================================================================
echo.

REM ──────────────────────────────────────────────────
REM  CREATE OUTPUT FOLDER
REM ──────────────────────────────────────────────────

if "%OUTPUT_SUBFOLDER%"=="" (
    set OUTPUT_DIR=%SCRIPT_DIR%Spritesheet_Output
) else (
    set OUTPUT_DIR=%SCRIPT_DIR%Spritesheet_Output\%OUTPUT_SUBFOLDER%
)

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
echo [OK] Output folder: %OUTPUT_DIR%

REM ──────────────────────────────────────────────────
REM  RUN BLENDER IN BACKGROUND MODE
REM ──────────────────────────────────────────────────

"%BLENDER_EXE%" --background --python "%PY_SCRIPT%" -- "%MODEL_FILE%" %FRAME_SIZE% %NUM_ANGLES% "%OUTPUT_DIR%" "%SPRITE_NAME%"

if errorlevel 1 (
    echo.
    echo [FAIL] Blender exited with an error.
    echo   Check the output above for details.
    echo.
    echo   Common fixes:
    echo   - Make sure the model file is a supported format
    echo   - Try opening the model in Blender manually first
    echo   - Update Blender to the latest version
    pause
    exit /b 1
)

REM ──────────────────────────────────────────────────
REM  CHECK OUTPUT
REM ──────────────────────────────────────────────────

set FINAL_OUTPUT=%OUTPUT_DIR%\%SPRITE_NAME%

if exist "%FINAL_OUTPUT%" (
    echo.
    echo ================================================================
    echo   SUCCESS!
    echo ================================================================
    echo.
    echo   %CHAR_LABEL% sprite saved to:
    echo   %FINAL_OUTPUT%
    echo.
    if "%OUTPUT_SUBFOLDER%"=="" (
        echo   Drop this file into your game folder [next to main.lua]
    ) else (
        echo   Drop this file into your game's %OUTPUT_SUBFOLDER%/ folder
    )
    echo   and the game will auto-detect and use it.
    echo.
    echo ================================================================
    echo.
    explorer "%OUTPUT_DIR%"
) else (
    echo.
    echo [WARN] Expected output file not found: %FINAL_OUTPUT%
    echo        Check the Blender output above for errors.
)

echo.
pause
