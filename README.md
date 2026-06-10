# Per-Port Random Subset for Project+

A Project+ code mod that gives **each controller port its own random-character
list**, built and edited live on the character select screen. Pick the
characters *you* feel like playing, drop your coin on Random, and the game
only rolls from your list — while every other player keeps their own.
Works on **Wii console** and **Project+ Dolphin**.

## What it does

| On the character select screen | Effect |
|---|---|
| Hover a character, **tap L** | Add it to your random list (tap again to remove — a menu sound confirms) |
| Hover the **'?' (Random) tile** with your coin in hand, **tap L** | Clear your list (reset sound) |
| **Drop your coin on Random** | Mystery random: the panel keeps showing '?' and the match rolls a fresh character **from your list** when it loads. Leave the coin there and every following match re-rolls. |

- Every port's list is independent — four players, four lists.
- The game's instant random (revealed on the CSS) rolls from your list too.
- **Empty list = vanilla behavior** (random over the whole roster), so the mod
  is invisible until you build a list.
- Lists persist across matches and CSS visits; they reset on power off.

## Compatibility

Built and tested against **Project+ v3.1.5** (Wii console and Project+
Dolphin). The mod is one self-contained assembly file compiled into the
build's codeset by the GCTRealMate pipeline that ships inside every P+ build —
no game files are replaced. The stock codeset is left untouched (the included
"Melee Random v2" code hooks a code path that never runs on Project+'s CSS,
so nothing needs to be disabled).

Offline only: the netplay codeset is intentionally not patched, because the
lists live in local console memory and would desync online rolls.

## Install

### Wii (SD card)

Put your Project+ SD card in your PC, then either:

**Option A — the standard Project+ code workflow** (any OS):

1. Copy [`src/RANDSUB.ASM`](src/RANDSUB.ASM) to `Project+/Source/Community/RANDSUB.ASM`
   on the SD card (create the `Community` folder).
2. Open `Project+/RSBE01.TXT` in a text editor and add this line right after
   the `.include Source/LegacyTE/CSSCustomControls.asm` line:

   ```
   .include Source/Community/RANDSUB.ASM
   ```

3. Drag `RSBE01.TXT` onto `GCTRealMate.exe` (both are already in the
   `Project+` folder) to rebuild `RSBE01.GCT`.

**Option B — the install script** (Windows): run
[`install.bat`](install.bat) and give it your SD card's `Project+` folder
(double-click it, or `install.bat "E:\Project+"`). It does the same three
steps, keeps backups, and verifies the result.

Eject the card and launch Project+ on the Wii as usual.

### Project+ Dolphin

The Dolphin build keeps its files inside a virtual SD card image; Dolphin
can unpack and repack it for you:

1. Open Project+ Dolphin → **Config → Wii → SD Card Settings** and click
   **Convert File to Folder Now**.
2. Apply the Wii steps above to the `Project+` folder inside the converted
   SD folder (`User/Wii/sd/`).
3. Back in Dolphin, click **Convert Folder to File Now**, then launch the
   game.

## Uninstall

Restore the two `.randsub-backup` files the script created (or, manually:
delete the `.include Source/Community/RANDSUB.ASM` line from `RSBE01.TXT`
and drag it onto `GCTRealMate.exe` again). Updating Project+ also wipes the
mod — just reinstall after updating.

## FAQ

**Does this work with regular Brawl or Project M?**
Not yet — the current hooks target Project+'s character select screen.
Vanilla Brawl / PM variants are planned (the addresses barely differ).

**Will it desync netplay?**
No — only the offline codeset (`RSBE01.GCT`) is patched. The netplay codeset
is intentionally left untouched.

**A Project+ update broke it?**
Updates replace `RSBE01.TXT` and `RSBE01.GCT`. Reinstall (it's idempotent and
safe to re-run any time).

**How is this different from "Custom Random" codes?**
Classic custom-random codes (spunit262's, Sammi-Husky's Melee Random) use
**one global pool** shared by everyone. This mod gives each port its own
pool, editable live on the CSS without leaving the screen.

## How it works

Four small PowerPC assembly hooks injected as Gecko codes through Project+'s
own code pipeline: one reads each port's buttons on the CSS and edits that
port's list (with sound feedback), one rolls each port's hidden pre-pick at
CSS entry, and two re-roll it from the current list whenever a coin lands on
Random, so both the instant and mystery random paths draw from the list.
[`src/RANDSUB.ASM`](src/RANDSUB.ASM) is heavily commented; the full
reverse-engineering notes and address tables are in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) and
[docs/addresses.md](docs/addresses.md). The `tools/` folder holds the Python
tooling used to develop and verify the mod against a live Dolphin instance
(not needed to install or play).

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
