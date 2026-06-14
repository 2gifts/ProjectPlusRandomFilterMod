# Per-Port Random Subset for Project+

![Project+ 3.1.5](https://img.shields.io/badge/Project%2B-3.1.5-1fc28e)
![Platforms](https://img.shields.io/badge/platform-Wii%20%7C%20Dolphin-blue)
![License](https://img.shields.io/badge/license-MIT-green)

A Project+ code mod that gives **each controller port its own random-character
list**, built and edited live on the character select screen. Pick the
characters *you* feel like playing, drop your coin on Random, and the game
only rolls from your list — while every other player keeps their own.
Works on **Wii console** and **Project+ Dolphin**.

![Demo: building a list with L, dropping the coin on Random, and the match rolling from the list](assets/demo.gif)

*Player 3 taps L on a few favorites (each tap plays a confirm sound), drops
the coin on the '?' Random tile — the pick stays a mystery on the select
screen — and the match loads with a character rolled from that list.*

## What it does

| On the character select screen | Effect |
|---|---|
| Hover a character, **tap L** | Add it to your random list (tap again to remove — a menu sound confirms) |
| Hover the **'?' (Random) tile** with your coin in hand, **tap L** | Clear your list (reset sound) |
| **Drop your coin on Random** | Mystery random: the panel keeps showing '?' and the match rolls a fresh character **from your list** when it loads. Leave the coin there and every following match re-rolls. |
| **Drop your coin outside the grid** | Melee-style instant random: a character **from your list** is rolled and placed on the spot. Pick the coin up (B) and drop again to re-roll. |

- Every port's list is independent — four players, four lists.
- **Empty list = vanilla behavior** (random over the whole roster), so the mod
  is invisible until you build a list.
- Lists persist across matches and CSS visits; they reset on power off.

## Compatibility

Built and tested against **Project+ v3.1.5** (Wii console and Project+
Dolphin). The mod is one self-contained assembly file compiled into the
build's codeset by the GCTRealMate pipeline that ships inside every P+ build —
no game files are replaced. The only stock code touched is "[Legacy TE]
Melee Random v2", which is commented out because this mod hooks the same
address with a per-port-aware replacement (that code is where the
drop-outside-the-grid instant random comes from).

**Netplay: supported.** The installer patches the netplay codeset
(`NETPLAY.GCT`) as well as the offline one, and it has been tested over
netplay. Project+ netplay is lockstep-deterministic — every port's inputs are
synced and both clients run identical emulation — so the lists, the rolls
(which use the game's own RNG), and the per-port state stay bit-identical on
both ends. **Both players must be on a build with the mod installed**; as with
any code mod, a mismatched codeset between players desyncs regardless of this
mod.

## Install

### Wii (SD card)

Put your Project+ SD card in your PC, then either:

**Option A — the standard Project+ code workflow** (any OS):

1. Copy [`src/RANDSUB.ASM`](src/RANDSUB.ASM) to `Project+/Source/Community/RANDSUB.ASM`
   on the SD card (create the `Community` folder).
2. Open `Project+/RSBE01.TXT` in a text editor:
   - comment out (prefix `#`) the `[Legacy TE] Melee Random v2` code — the
     header line and each of its `* xxxxxxxx xxxxxxxx` hex lines — and
   - add this line right after the
     `.include Source/LegacyTE/CSSCustomControls.asm` line:

   ```
   .include Source/Community/RANDSUB.ASM
   ```

3. Drag `RSBE01.TXT` onto `GCTRealMate.exe` (both are already in the
   `Project+` folder) to rebuild `RSBE01.GCT`.
4. **For netplay**, repeat steps 2–3 on `Project+/NETPLAY.TXT` (it contains
   the same two anchors) to rebuild `NETPLAY.GCT`. Skip this for offline-only.

**Option B — the install script** (Windows): run
[`install.bat`](install.bat) and give it your SD card's `Project+` folder
(double-click it, or `install.bat "E:\Project+"`). It does the same steps for
both the offline and netplay codesets, keeps backups, and verifies the result.

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

Restore the `.randsub-backup` files the script created (or, manually: delete
the `.include Source/Community/RANDSUB.ASM` line from `RSBE01.TXT` — and
`NETPLAY.TXT` if you patched it — un-comment the Melee Random v2 block, and
drag the file(s) onto `GCTRealMate.exe` again). Updating Project+ also wipes
the mod — just reinstall after updating.

## FAQ

**Does this work with regular Brawl or Project M?**
Not yet — the current hooks target Project+'s character select screen.
Vanilla Brawl / PM variants are planned (the addresses barely differ).

**Will it desync netplay?**
No. Both the offline and netplay codesets are patched, and netplay has been
tested. Project+ netplay runs both clients in lockstep on identical emulated
state, so the per-port lists and rolls stay in sync. The only requirement is
that **both players have the mod installed** — a codeset mismatch between
players desyncs with or without this mod.

**A Project+ update broke it?**
Updates replace the codeset files. Reinstall (it's idempotent and safe to
re-run any time).

**How is this different from "Custom Random" codes?**
Classic custom-random codes (spunit262's, Sammi-Husky's Melee Random) use
**one global pool** shared by everyone. This mod gives each port its own
pool, editable live on the CSS without leaving the screen.

## How it works

Five small PowerPC assembly hooks injected as Gecko codes through Project+'s
own code pipeline: one reads each port's buttons on the CSS and edits that
port's list (with sound feedback), one rolls each port's hidden pre-pick at
CSS entry, two re-roll it from the current list whenever a coin lands on
Random (the mystery path), and one performs the melee-style instant roll
when a coin is dropped outside the grid — a per-port-aware replacement for
the stock Melee Random v2 code, which hooks the same address.
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
