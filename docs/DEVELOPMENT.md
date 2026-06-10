# Development notes

Internal documentation: architecture, hook addresses, build pipeline, and the
tooling used to develop and verify the mod. End users should read the
top-level README instead.

A code mod for **Project+** (Super Smash Bros. Brawl engine) where each of the
4 controller ports has its **own** random-character pool. When a port picks
**Random** on the character select screen, the game rolls only from that port's
pool. Ports' pools are fully independent.

> **Status: both modes verified in P+ Dolphin matches** — instant (L+drop)
> rolled and spawned Pikachu from a one-character list; mystery (plain drop on
> '?') spawned Fox from a one-character list without ever revealing it on the
> CSS. Remaining: Wii console deploy, debug-counter strip, vanilla Brawl /
> Project M variants.

## How to use it (in game)

Every port has its own independent random list:

- **Hover a character and tap L** — add it to your list (tap again to remove;
  a menu sound confirms each change).
- **Hover the Random ('?') tile with the coin in hand and tap L** — clear your
  list (reset sound confirms; nothing is placed).
- **Drop your coin on Random** — your character stays a **mystery**: the panel
  shows '?', and when the match loads you get a fresh roll from your list.
  Leave the coin there and keep playing — every match re-rolls from your list.
- The game's own instant random (screen-edge drop) consumes the same hidden
  pre-roll the mod maintains, so it also rolls from your list.
- **Empty list = no restriction** (vanilla random over the full roster).
- Lists live in RAM: they persist across matches and CSS visits, reset at
  power-off.

## Layout

```
src/RANDSUB.ASM        the whole mod: 4 GCTRM hooks + storage (heavily commented)
tools/sdfat.py         read/write files inside Dolphin's virtual SD (sd.raw)
tools/wiidisc.py       extract files from a Wii ISO (used for the CSS module)
tools/dolmem.py        read/poke/search live Dolphin emulated memory
tools/diffmem.py       3-snapshot differential RAM analysis
build/Project+/        working copy of the P+ build's code pipeline (from sd.raw)
docs/addresses.md      verified address fact sheet (P+ 3.1.5)
```

## Build & install (Dolphin)

1. `src/RANDSUB.ASM` → `build/Project+/Source/Community/RANDSUB.ASM`
2. `RSBE01.TXT` includes it (after CSSCustomControls). The stock codeset is
   left untouched — "Melee Random v2" only patches `$8068AE20/24`, a decide-path
   branch that never executes on P+'s CSS (it acts on slot `0x28`; P+ random
   placements carry `0x29`), so it coexists harmlessly.
3. From `build/Project+` in PowerShell: `& .\GCTRealMate.exe ".\RSBE01.TXT"`
   (GCTRM hangs after printing "bytes written" — kill the process; the GCT is done).
4. Inject into the virtual SD (stop Dolphin first):
   `python tools/sdfat.py replace <sd.raw> "Project+/RSBE01.GCT" build/Project+/RSBE01.GCT`
   (a pristine backup is at `sd.raw.bak`).
5. Launch the "Project+ Offline Launcher" entry in P+ Dolphin.

Netplay is intentionally **not** modified (`NETPLAY.TXT` untouched): pools are
local RAM, so online use would desync rolls.

## Wii console install (verified working)

The same two file changes (`Source/Community/RANDSUB.ASM`, `RSBE01.TXT`) apply to
the **console** build's `Project+/` folder on the physical SD card; rebuild
`RSBE01.GCT` on PC with the GCTRealMate.exe that ships on that card, then launch
P+ through the Homebrew Channel as usual. (The PC "Netplay" build must never be
copied to a Wii.)

## How it works

Four hooks (all verified live against P+ 3.1.5; see `docs/addresses.md`):

1. **Toggle** (`HOOK @ $806898E8`) — per-port CSS input processor (every frame,
   port + player object in registers). Reads held buttons directly from the pad
   system (`*0x805A0040 + 0x40 + port*0x40`; never call `getSysPadStatus` from a
   hook — it consumes press edges), edge-detects L, toggles the list byte, and
   **re-rolls the port's hidden pre-roll** (`player_object+0x410`) so a coin
   sitting on '?' always reflects the current list.
2. **Drop hooks** (`$8068B818` and `$806892C4` — the game has two parallel
   random-drop code paths). A coin landing on the '?' tile keeps slot `0x29`
   (mystery: the panel never reveals) and refreshes the hidden pre-roll from
   the current list; empty list leaves the CSS-entry roll. The clear gesture
   lives in the toggle hook: L pressed while the hovered slot reads `0x29`
   (the '?' tile; `0x28` is the empty-space value) with the coin still in hand
   (`hand+0xA0` non-null).
3. **CSS-entry roll** (`HOOK @ $80685824`, `muSelCharTask::initPlayerArea`) —
   the source of the hidden pre-roll each time the CSS (re)loads, rolled
   per port (`r25`) from the port's list. This is what the match consumes for
   ports left on raw random, so consecutive matches each get a fresh roll.

Removed in v1.1: a Z-modifier instant-roll drop mode (redundant — the game's
own instant random already consumes the pre-roll), the panel-state pair hooks
`$8068B828`/`$806892C8` (only needed by the Z mode), and a belt-and-braces
hook at `$8068AE24` on the vanilla decide path (never executes on P+; it is
also the site Melee Random v2 patches, so dropping it removes the only
codeset overlap). A vanilla-Brawl/PM variant will need that decide-path hook
back.

Key data flow: the CSS hands each port's selection to the match via the player
object (static pointer array `0x805882E0`); a port still on `0x29` uses the
hidden pre-roll at `player_object+0x410` (mapped from the init param block by
the constructor at `0x80693570`/`0x806939C4`).

Storage: magic `'RSUB'` @ `0x80002840`, 4 lists of 0x30 bytes @ `0x80002848`
(1 byte per random-table index, 1 = listed; all-zero = unrestricted), prev-pad
words @ `0x80002920`.
