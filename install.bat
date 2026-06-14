@echo off
setlocal EnableExtensions
::
:: Per-Port Random Subset installer for Project+ (Windows).
::
:: Usage:  install.bat "E:\Project+"     (or just double-click and type the path)
::
:: This script does the same steps described in README.md, for BOTH the offline
:: codeset (RSBE01) and the netplay codeset (NETPLAY), so the mod works online too:
::   1. copy RANDSUB.ASM into the build's Source\Community\ folder
::   2. patch the .TXT: comment out the stock "Melee Random v2" code (it hooks
::      the same address this mod uses) and add one ".include" line
::      (idempotent; backups kept)
::   3. rebuild the .GCT with the GCTRealMate.exe that ships in the build
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

:: ---- copy the code into the build (shared by both codesets)
if not exist "%TARGET%\Source\Community" mkdir "%TARGET%\Source\Community"
copy /y "%ASM%" "%TARGET%\Source\Community\RANDSUB.ASM" >nul
echo   copied RANDSUB.ASM to Source\Community\

:: ---- offline codeset (always present)
call :do_codeset RSBE01 || goto :fail

:: ---- netplay codeset (present on netplay builds; skipped otherwise)
if exist "%TARGET%\NETPLAY.TXT" (
    call :do_codeset NETPLAY || goto :fail
) else (
    echo   NETPLAY.TXT not found -- offline-only build, skipping netplay codeset
)

echo Done! Put the SD card back (or start Dolphin) and enjoy.
echo (Uninstall: restore the .randsub-backup files, or re-run your P+ updater.)
if "%~1"=="" pause
exit /b 0


:: ===========================================================================
:: :do_codeset <NAME>   -- patch <NAME>.TXT and rebuild <NAME>.GCT
:: ===========================================================================
:do_codeset
set "CS=%~1"
set "TXT=%TARGET%\%CS%.TXT"
set "GCT=%TARGET%\%CS%.GCT"

:: one-time backups (restore these to uninstall)
if not exist "%TXT%.randsub-backup" copy /y "%TXT%" "%TXT%.randsub-backup" >nul
if not exist "%GCT%.randsub-backup" if exist "%GCT%" copy /y "%GCT%" "%GCT%.randsub-backup" >nul

:: patch the .TXT (skip if already done): comment out the stock Melee Random v2
:: block (it patches 0x8068AE20/24, the same site this mod hooks) and add our
:: .include right after the CSSCustomControls include
findstr /c:"Source/Community/RANDSUB.ASM" "%TXT%" >nul 2>&1
if not errorlevel 1 (
    echo   %CS%.TXT already patched
) else (
    powershell -NoProfile -Command "$p = '%TXT%';" ^
        "$lines = [IO.File]::ReadAllLines($p);" ^
        "$in = $false; $done = $false;" ^
        "for ($i = 0; $i -lt $lines.Count; $i++) {" ^
        "  if (-not $done -and $lines[$i] -match 'Melee Random v2') { $in = $true };" ^
        "  if ($in) {" ^
        "    if ($lines[$i].Trim() -and -not $lines[$i].StartsWith('#')) { $lines[$i] = '#' + $lines[$i] };" ^
        "    if ($lines[$i] -match '7FA3EB78') { $done = $true; $in = $false }" ^
        "  }" ^
        "};" ^
        "if (-not $done) { Write-Output '  note: Melee Random v2 block not found (already removed?)' };" ^
        "$t = [string]::Join([Environment]::NewLine, $lines);" ^
        "$a = '.include Source/LegacyTE/CSSCustomControls.asm';" ^
        "if (-not $t.Contains($a)) { Write-Output 'ANCHOR-MISSING'; exit 1 };" ^
        "$t = $t.Replace($a, $a + \"`r`n`r`n.include Source/Community/RANDSUB.ASM\");" ^
        "[IO.File]::WriteAllText($p, $t)"
    if errorlevel 1 echo error: could not find the include anchor in %CS%.TXT -- is this a Project+ 3.x build? & exit /b 1
    echo   %CS%.TXT patched
)

:: rebuild the .GCT (GCTRealMate stays open when finished; we watch for the new
:: GCT and close it -- same as pressing a key yourself)
echo   rebuilding %CS%.GCT ...
powershell -NoProfile -Command "$build = '%TARGET%';" ^
    "$gct = '%GCT%';" ^
    "$before = if (Test-Path $gct) { (Get-Item $gct).LastWriteTime } else { Get-Date 0 };" ^
    "$p = Start-Process -FilePath (Join-Path $build 'GCTRealMate.exe') -ArgumentList '.\%CS%.TXT' -WorkingDirectory $build -PassThru -WindowStyle Hidden;" ^
    "$deadline = (Get-Date).AddSeconds(90);" ^
    "while ((Get-Date) -lt $deadline) { Start-Sleep 2; if ((Test-Path $gct) -and (Get-Item $gct).LastWriteTime -ne $before) { Start-Sleep 2; break } };" ^
    "Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue;" ^
    "if (-not (Test-Path $gct) -or (Get-Item $gct).LastWriteTime -eq $before) { Write-Output 'BUILD-FAILED'; exit 1 }"
if errorlevel 1 echo error: GCTRealMate did not produce a new %CS%.GCT & exit /b 1

:: verify the mod's five hooks are in the new GCT
powershell -NoProfile -Command "$b = [IO.File]::ReadAllBytes('%GCT%');" ^
    "$hex = [BitConverter]::ToString($b) -replace '-','';" ^
    "$missing = @('C26898E8','C268AE24','C2685824','C268B818','C26892C4') | Where-Object { -not $hex.Contains($_) };" ^
    "if ($missing) { Write-Output ('missing hooks: ' + ($missing -join ' ')); exit 1 };" ^
    "Write-Output ('  all 5 hooks present in %CS%.GCT')"
if errorlevel 1 echo error: rebuilt %CS%.GCT failed verification & exit /b 1
exit /b 0

:fail
if "%~1"=="" pause
exit /b 1
