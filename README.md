# Per-Port Random Subset for Project+

A Project+ mod that gives **each controller port its own random-character
list**. Pick the characters *you* feel like playing, drop your coin on Random,
and the game only rolls characters from your list — while every other player
keeps their own list. Works on **Wii console** (Homebrew Channel) and
**Project+ Dolphin**.

## What it does

| On the character select screen | Effect |
|---|---|
| Hover a character, **tap L** | Add it to your random list (tap again to remove — a menu sound confirms) |
| Hover the **'?' (Random) tile** with your coin in hand, **tap L** | Clear your list (reset sound) |
| **Drop your coin on Random** | Classic mystery random: panel keeps showing '?', and the match rolls a fresh character **from your list** when it loads. Leave the coin there and every following match re-rolls. |
| **Hold Z while dropping on Random** | Melee-style instant random: the character is rolled from your list and revealed immediately. Pick the coin up (B) and Z-drop again to re-roll. |

- Every port's list is independent — four players, four lists.
- **Empty list = vanilla behavior** (random over the whole roster), so the mod
  is invisible until you build a list.
- Lists persist across matches and CSS visits; they reset when the console
  powers off.

## Requirements

- **Project+ 3.x** (NTSC). Built and tested against Project+ 3.1.5.
- Windows + [Python 3.8+](https://python.org) for the installer
  (manual install instructions below work anywhere).
- Not active in netplay builds' online mode (lists are local and would desync —
  the offline/console codeset is patched only).

## Install

### Console (SD card)

1. Put your Project+ SD card in your PC.
2. Download this repository (green **Code** button → *Download ZIP*) and
   extract it.
3. Run:

   ```
   python install.py "E:\Project+"
   ```

   (replace `E:\Project+` with your SD card's Project+ folder)
4. Eject the card, put it back in the Wii, launch Project+ from the Homebrew
   Channel as usual.

### Project+ Dolphin

Point the installer at the virtual SD card inside your P+ Dolphin folder:

```
python install.py "C:\path\to\Project+ Dolphin\User\Wii\sd.raw"
```

(Quit Dolphin first. The installer backs the image up, patches the build
inside it, and rebuilds the codeset.)

### What the installer does (or: manual install)

If you'd rather do it by hand — it's three steps inside the `Project+` folder:

1. Copy `src/RANDSUB.ASM` to `Source/Community/RANDSUB.ASM`.
2. Edit `RSBE01.TXT`:
   - comment out (prefix `#`) the whole `[Legacy TE] Melee Random v2` code
     block (the header line and its `* xxxxxxxx xxxxxxxx` hex lines), and
   - add this line right after `.include Source/LegacyTE/CSSCustomControls.asm`:

     ```
     .include Source/Community/RANDSUB.ASM
     ```
3. Drag `RSBE01.TXT` onto `GCTRealMate.exe` (both ship inside every P+ build)
   to rebuild `RSBE01.GCT`.

The installer also makes backups (`*.randsub-backup`); restoring them is a
full uninstall. Re-run the installer after updating Project+ (updates
overwrite `RSBE01.TXT`/`RSBE01.GCT`).

## FAQ

**Does this work with regular Brawl or Project M?**
Not yet — the current hooks target Project+'s character select screen.
Vanilla Brawl / PM variants are planned (the addresses barely differ).

**Will it desync netplay?**
The mod only patches the offline codeset (`RSBE01.GCT`). The netplay codeset
is intentionally left untouched.

**A Project+ update broke it?**
Updates replace `RSBE01.TXT` and `RSBE01.GCT`. Just re-run `install.py`.

**How is this different from "Custom Random" codes?**
Classic custom-random codes (spunit262's, Legacy TE's) use **one global pool**
shared by everyone. This mod gives each port its own pool, editable live on
the CSS.

## How it works

Seven small PowerPC assembly hooks injected as Gecko codes through Project+'s
own code pipeline. The full reverse-engineering notes and address tables are
in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) and
[docs/addresses.md](docs/addresses.md), and `src/RANDSUB.ASM` is heavily
commented. The `tools/` folder contains the Python tooling used to build and
verify the mod against a live Dolphin instance.

## Credits

- Built on the shoulders of the Brawl/PM/P+ code community: spunit262,
  Sammi-Husky, ds22, dantarion, DukeItOut, Eon, Kapedani, QuickLava, the
  Project+ Development Team, and many others whose shipped source made this
  mod's reverse engineering possible.
- GCT assembly by GCTRealMate (ships with Project+).

## License

MIT — see [LICENSE](LICENSE). Project+ and Super Smash Bros. Brawl are the
property of their respective owners; this repository contains only original
code and documentation.
