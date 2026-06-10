#!/usr/bin/env python3
"""Per-Port Random Subset installer for Project+.

Works on two kinds of targets:

  1. A Project+ build folder (console SD card, or an extracted Dolphin build):
       python install.py "D:/Project+"

  2. A Project+ Dolphin virtual SD image (the mod is installed inside it):
       python install.py "C:/path/to/Dolphin/User/Wii/sd.raw"

What it does:
  * backs up RSBE01.TXT and RSBE01.GCT (.randsub-backup, first run only)
  * copies RANDSUB.ASM into Source/Community/
  * patches RSBE01.TXT: disables the old "Melee Random v2" code and includes
    RANDSUB.ASM (idempotent -- safe to run again after a P+ update)
  * rebuilds RSBE01.GCT with the GCTRealMate.exe that ships in the build
  * verifies the mod's hooks are present in the rebuilt GCT

Requirements: Windows (GCTRealMate.exe is a Windows program) and Python 3.8+.
On macOS/Linux, run GCTRealMate under Wine manually after the patch step
(pass --no-build to skip the build).

Uninstall: restore the .randsub-backup files (or re-run your P+ updater).
"""
import argparse
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ASM_NAME = "RANDSUB.ASM"
INCLUDE_LINE = ".include Source/Community/RANDSUB.ASM"
ANCHOR_INCLUDE = ".include Source/LegacyTE/CSSCustomControls.asm"
BLOCK_HEADER = "Melee Random v2"
BLOCK_LAST_HEX = "7FA3EB78"
HOOK_SIGS = ["C26898E8", "C268AE24", "C2685824", "C268B818",
             "C268B828", "C26892C4", "C26892C8"]
BACKUP_SUFFIX = ".randsub-backup"


def find_asm() -> Path:
    for cand in (HERE / ASM_NAME, HERE / "src" / ASM_NAME):
        if cand.exists():
            return cand
    sys.exit(f"error: {ASM_NAME} not found next to install.py")


def patch_txt(text: str) -> str:
    """Disable Melee Random v2 and include RANDSUB.ASM. Idempotent."""
    if INCLUDE_LINE in text:
        print("  RSBE01.TXT already patched -- leaving as is")
        return text
    lines = text.splitlines()
    out, in_block, done_block, included = [], False, False, False
    for line in lines:
        stripped = line.strip()
        if not done_block and BLOCK_HEADER in line:
            in_block = True
        if in_block:
            if stripped.startswith("*") or stripped.startswith("#") \
                    or BLOCK_HEADER in line or not stripped:
                out.append("#" + line if stripped and not stripped.startswith("#") else line)
                if stripped.startswith("*") and BLOCK_LAST_HEX in line:
                    in_block, done_block = False, True
                    out.append("# ^ Melee Random v2 disabled by Per-Port Random Subset")
                continue
            in_block, done_block = False, True
        if ANCHOR_INCLUDE in line and not included:
            out.append(line)
            out.append("")
            out.append(INCLUDE_LINE)
            included = True
            continue
        out.append(line)
    if not included:
        sys.exit("error: could not find the CSSCustomControls include in "
                 "RSBE01.TXT -- is this a Project+ 3.x build?")
    if not done_block:
        print("  warning: Melee Random v2 block not found (already removed?)")
    return "\n".join(out) + "\n"


def run_gctrm(build: Path) -> None:
    """GCTRealMate compiles the codeset but does not exit afterwards; watch
    the GCT mtime and kill the process when the output is written."""
    gctrm = build / "GCTRealMate.exe"
    gct = build / "RSBE01.GCT"
    if not gctrm.exists():
        sys.exit("error: GCTRealMate.exe not found in the build folder")
    before = gct.stat().st_mtime if gct.exists() else 0
    proc = subprocess.Popen([str(gctrm), ".\\RSBE01.TXT"], cwd=str(build),
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 90
    while time.time() < deadline:
        time.sleep(2)
        if gct.exists() and gct.stat().st_mtime != before:
            time.sleep(2)  # let it finish writing
            break
    proc.kill()
    if not gct.exists() or gct.stat().st_mtime == before:
        sys.exit("error: GCTRealMate did not produce a new RSBE01.GCT -- "
                 "run it manually and check its output for errors")


def verify_gct(data: bytes) -> None:
    missing = [s for s in HOOK_SIGS if data.find(bytes.fromhex(s)) < 0]
    if missing:
        sys.exit(f"error: rebuilt GCT is missing hooks: {missing}")
    print(f"  all {len(HOOK_SIGS)} hooks present in RSBE01.GCT")


def install_into_folder(build: Path, no_build: bool) -> None:
    txt = next((p for p in build.iterdir()
                if p.name.lower() == "rsbe01.txt"), None)
    if txt is None:
        sys.exit(f"error: RSBE01.TXT not found in {build}")
    gct = build / "RSBE01.GCT"

    for f in (txt, gct):
        bak = f.with_name(f.name + BACKUP_SUFFIX)
        if f.exists() and not bak.exists():
            shutil.copy2(f, bak)
            print(f"  backup: {bak.name}")

    dest = build / "Source" / "Community" / ASM_NAME
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(find_asm(), dest)
    print(f"  copied {ASM_NAME} -> {dest.relative_to(build)}")

    patched = patch_txt(txt.read_text(encoding="utf-8", errors="replace"))
    txt.write_text(patched, encoding="utf-8", newline="\r\n")
    print("  RSBE01.TXT patched")

    if no_build:
        print("  --no-build: run GCTRealMate.exe on RSBE01.TXT yourself")
        return
    print("  rebuilding RSBE01.GCT (takes ~10s)...")
    run_gctrm(build)
    verify_gct(gct.read_bytes())


def install_into_sdraw(sdraw: Path, no_build: bool) -> None:
    sys.path.insert(0, str(HERE / "tools"))
    try:
        from sdfat import Fat32
    except ImportError:
        sys.exit("error: tools/sdfat.py is required for sd.raw installs")
    import tempfile

    bak = sdraw.with_name(sdraw.name + BACKUP_SUFFIX)
    if not bak.exists():
        print(f"  backing up sd.raw (~2GB, one time)...")
        shutil.copy2(sdraw, bak)

    with tempfile.TemporaryDirectory() as td:
        work = Path(td) / "Project+"
        work.mkdir()
        fs = Fat32(str(sdraw))
        print("  extracting build files from sd.raw...")
        fs.extract("Project+/RSBE01.TXT", work / "RSBE01.TXT")
        fs.extract("Project+/BOOST.TXT", work / "BOOST.TXT")
        fs.extract("Project+/GCTRealMate.exe", work / "GCTRealMate.exe")
        fs.extract("Project+/Source", work / "Source")
        install_into_folder(work, no_build)
        print("  writing changes back into sd.raw...")
        fs = Fat32(str(sdraw), writable=True)
        fs.replace_file("Project+/RSBE01.TXT", (work / "RSBE01.TXT").read_bytes())
        fs.replace_file("Project+/RSBE01.GCT", (work / "RSBE01.GCT").read_bytes())
        fs.add_file("Project+/Source/Community", ASM_NAME,
                    (work / "Source" / "Community" / ASM_NAME).read_bytes())


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target", help="Project+ build folder (SD card) or Dolphin sd.raw")
    ap.add_argument("--no-build", action="store_true",
                    help="patch only; skip running GCTRealMate")
    args = ap.parse_args()

    target = Path(args.target)
    if not target.exists():
        sys.exit(f"error: {target} does not exist")
    print(f"Installing Per-Port Random Subset into {target} ...")
    if target.is_file() and target.suffix.lower() == ".raw":
        install_into_sdraw(target, args.no_build)
    elif target.is_dir():
        install_into_folder(target, args.no_build)
    else:
        sys.exit("error: target must be a Project+ folder or an sd.raw image")
    print("Done! Start the game and enjoy.")
    print("(Uninstall: restore the *.randsub-backup files.)")


if __name__ == "__main__":
    main()
