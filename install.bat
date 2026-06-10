@echo off
setlocal EnableExtensions
::
:: Per-Port Random Subset installer for Project+ (Windows).
::
:: Usage:  install.bat "E:\Project+"     (or just double-click and type the path)
::
:: This script does the same three steps described in README.md:
::   1. copy RANDSUB.ASM into the build's Source\Community\ folder
::   2. add one ".include" line to RSBE01.TXT (idempotent; backup kept)
::   3. rebuild RSBE01.GCT with the GCTRealMate.exe that ships in the build
::

:: ---- locate RANDSUB.ASM next to this script (repo: src\, release zip: root)
set "ASM=%~dp0src\RANDSUB.ASM"
if not exist "%ASM%" set "ASM=%~dp0RANDSUB.ASM"
if not exist "%ASM%" echo error: RANDSUB.ASM not found next to install.bat & goto :fail

:: ---- target folder: first argument, or ask
set "TARGET=%~1"
if "%TARGET%"=="" set /p "TARGET=Path to your Project+ folder (e.g. E:\Project+): "
set "TARGET=%TARGET:"=%"
if "%TARGET%"=="" echo error: no path given & goto :fail
if not exist "%TARGET%\RSBE01.TXT" echo error: RSBE01.TXT not found in "%TARGET%" & goto :fail
if not exist "%TARGET%\GCTRealMate.exe" echo error: GCTRealMate.exe not found in "%TARGET%" & goto :fail

echo Installing Per-Port Random Subset into "%TARGET%" ...

:: ---- one-time backups (restore these to uninstall)
if not exist "%TARGET%\RSBE01.TXT.randsub-backup" copy /y "%TARGET%\RSBE01.TXT" "%TARGET%\RSBE01.TXT.randsub-backup" >nul
if not exist "%TARGET%\RSBE01.GCT.randsub-backup" if exist "%TARGET%\RSBE01.GCT" copy /y "%TARGET%\RSBE01.GCT" "%TARGET%\RSBE01.GCT.randsub-backup" >nul

:: ---- step 1: copy the code into the build
if not exist "%TARGET%\Source\Community" mkdir "%TARGET%\Source\Community"
copy /y "%ASM%" "%TARGET%\Source\Community\RANDSUB.ASM" >nul
echo   copied RANDSUB.ASM to Source\Community\

:: ---- step 2: add the .include line to RSBE01.TXT (skip if already there)
findstr /c:"Source/Community/RANDSUB.ASM" "%TARGET%\RSBE01.TXT" >nul 2>&1
if not errorlevel 1 (
    echo   RSBE01.TXT already has the include line
) else (
    powershell -NoProfile -Command "$p = '%TARGET%\RSBE01.TXT';" ^
        "$t = [IO.File]::ReadAllText($p);" ^
        "$a = '.include Source/LegacyTE/CSSCustomControls.asm';" ^
        "if (-not $t.Contains($a)) { Write-Output 'ANCHOR-MISSING'; exit 1 };" ^
        "$t = $t.Replace($a, $a + \"`r`n`r`n.include Source/Community/RANDSUB.ASM\");" ^
        "[IO.File]::WriteAllText($p, $t)"
    if errorlevel 1 echo error: could not find the include anchor in RSBE01.TXT -- is this a Project+ 3.x build? & goto :fail
    echo   RSBE01.TXT patched
)

:: ---- step 3: rebuild RSBE01.GCT (GCTRealMate stays open when finished; we
::      watch for the new GCT and close it -- same as pressing a key yourself)
echo   rebuilding RSBE01.GCT ...
powershell -NoProfile -Command "$build = '%TARGET%';" ^
    "$gct = Join-Path $build 'RSBE01.GCT';" ^
    "$before = if (Test-Path $gct) { (Get-Item $gct).LastWriteTime } else { Get-Date 0 };" ^
    "$p = Start-Process -FilePath (Join-Path $build 'GCTRealMate.exe') -ArgumentList '.\RSBE01.TXT' -WorkingDirectory $build -PassThru -WindowStyle Hidden;" ^
    "$deadline = (Get-Date).AddSeconds(90);" ^
    "while ((Get-Date) -lt $deadline) { Start-Sleep 2; if ((Test-Path $gct) -and (Get-Item $gct).LastWriteTime -ne $before) { Start-Sleep 2; break } };" ^
    "Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue;" ^
    "if (-not (Test-Path $gct) -or (Get-Item $gct).LastWriteTime -eq $before) { Write-Output 'BUILD-FAILED'; exit 1 }"
if errorlevel 1 echo error: GCTRealMate did not produce a new RSBE01.GCT & goto :fail

:: ---- verify the mod's four hooks are in the new GCT
powershell -NoProfile -Command "$b = [IO.File]::ReadAllBytes('%TARGET%\RSBE01.GCT');" ^
    "$hex = [BitConverter]::ToString($b) -replace '-','';" ^
    "$missing = @('C26898E8','C2685824','C268B818','C26892C4') | Where-Object { -not $hex.Contains($_) };" ^
    "if ($missing) { Write-Output ('missing hooks: ' + ($missing -join ' ')); exit 1 };" ^
    "Write-Output '  all 4 hooks present in RSBE01.GCT'"
if errorlevel 1 echo error: rebuilt GCT failed verification & goto :fail

echo Done! Put the SD card back (or start Dolphin) and enjoy.
echo (Uninstall: restore the .randsub-backup files, or re-run your P+ updater.)
if "%~1"=="" pause
exit /b 0

:fail
if "%~1"=="" pause
exit /b 1
