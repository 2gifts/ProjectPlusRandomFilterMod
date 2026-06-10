# Address & fact sheet — Project+ 3.1.5 (Netplay build, RSBE01)

Everything below was read directly out of the build's own shipped source
(`build/Project+/Source/...`, `RSBE01.TXT`), not guessed. The CSS lives in the
`sora_menu_sel_char` REL, which loads at the **same base as vanilla Brawl** —
P+'s codes hook `$8068xxxx` directly.

## The random-character pipeline (as shipped)

| What | Where | Notes |
|---|---|---|
| CSS roster table (43 slot IDs) | `$80680DE0` | "CSS Roster Data v3&K", `Source/ProjectM/CSS.ASM` |
| Random pool table (42 slot IDs) | `$80680E80` | "CSS Random Data" — roster minus Random itself |
| Random pool count | immediate of `li r23, 42` @ `$806857F0` | read back as halfword at `$806857F2` |
| Vanilla random pick patch | `CODE @ $80685824` | `char = byte[$80680E80 + r0]` |
| **Melee Random v2 hook** | `C2 @ $8068AE24` (+ `04 @ $8068AE20` NOP) | inline hex in `RSBE01.TXT` ~lines 2123–2191; replaced instruction = `mr r3, r29` |

### Decoded Melee Random v2 (stock code; disabled — same hook site as our instant roll, and stale on P+)

Context at `$8068AE24`: `r27` = slot kind being placed (0x28 = Random),
`r28` = per-player CSS object, `r31` = related object (stock icons), original op `mr r3, r29`.

Flow: if r27==0x28 → bl $803F130C → randf($805A0420) → count = lhz($806857F2) →
float→int → `char = byte[$80680E80 + idx]` → exchangeCharKindDetail($806948D4) →
initCharKind($80693D18) → roll costume: getNumCharColor($800AF8D0) × randf →
`stw costume, 0x1BC(r28)` → setCharPic($8069742C) with args from
r28+{0x1B8,0x1B4,0x1BC,0x1F4→+0x5C8,0x1C0,0x1C4} → $800AF82C/$800AF6F0 →
$800B7900(r28+0xB8) → if r31+0x3DC: setStockCharKind($80692498).

### Per-player CSS object offsets (r28 above)

- `+0xB8` — char kind / franchise icon ref (hover write site: `stb r29, 184(r20)` hook @ `$80684940`)
- `+0x1B8` — selected/hovered CSS slot ID
- `+0x1BC` — costume index
- `+0x1B4`, `+0x1C0`, `+0x1C4`, `+0x1F4` — setCharPic args
- **port index: UNKNOWN — primary remaining RE task.** (Tag-menu objects store
  ASCII port digit at +0x57: `lbz rX,0x57(obj); subi rX,rX,0x31` — check for the
  same pattern. Resolve via static disasm of sora_menu_sel_char.rel or live scan.)

## DOL symbols (identical across vanilla/PM/P+ — DOL is never modified)

From `Source/Project+/Random.asm` aliases:

- `randi = 0x8003fc7c` — `r3 = n` → returns 0..n-1 (used via `%randi(n)` macros)
- `randf = 0x8003faf8` — float RNG (what Melee Random uses; we'll use randi)
- `g_gfPadSystem = 0x805A0040`, `gfPadSystem__getSysPadStatus = 0x8002ae48`
  - usage: `r3=g_gfPadSystem, r4=channel, r5=&buf(stack)`; buttons word at `buf+4`
- `g_sndSystem = 0x805A01D0`, `sndSystem__playSE = 0x800742b0`
  - CSSCustomControls plays menu SFX via `bla 0x6A83F4` with `r3=lis 0x805A, r4=soundID`
    (SFX ids: 0x01 select, 0x26 enter, 0x28 exit, 0x03 max-page)
- `g_GameGlobal = 0x805a00E0`
- CSS pac pointer chain (valid only on CSS — usable as a scene gate):
  `lwz r, 0x60(0x805A0000-style); lwz r, 0x4(r); lwz r, 0x410(r)` → sc_selcharacter.pac

## Pad button bits (GC, standard Brawl layout)

Left=0x0001 Right=0x0002 Down=0x0004 Up=0x0008 Z=0x0010 R=0x0020 L=0x0040
A=0x0100 B=0x0200 X=0x0400 Y=0x0800 Start=0x1000

Already used on main CSS in P+: A/B (select/back), X/Y (costume; Y=clone hover),
R hold (random cursor warp), L/R hold (fast costume scroll), Start (begin match),
tag menu uses Y/Z/Start. **GC D-pad appears unused on main CSS** → toggle combo
candidate: D-pad Down = toggle hovered char; D-pad Up = re-enable all (per port).

## Scratch RAM (survives scene changes, reset on boot)

`0x800028xx` region is the established codeset scratch area:
- `0x80002800` — CSSCustomControls flag
- `0x80002810–0x8000283C` — MusicSelect (documented block)
- **`0x80002840+` — unclaimed (audited whole Source/ + TXTs). We claim:**
  - `0x80002840` — magic word (init-once marker)
  - `0x80002848/50/58/60` — four 8-byte port masks (bit i = random-table index i enabled)
  - `0x80002868–0x8000286F` — per-port prev-frame button state (edge detection)

## Build pipeline

- Edit/add `.asm` under `Source/`, reference from `RSBE01.TXT` (and `NETPLAY.TXT`)
  via `.include`; raw hex codes live inline in the TXTs.
- `compile_codesets.bat` + `GCTRealMate.exe` rebuild `RSBE01.GCT`, `BOOST.GCT`,
  `NETPLAY.GCT`, `NETBOOST.GCT` in place.
- Files live inside `sd.raw` (FAT32) — read/write with `tools/sdfat.py`
  (backup at `sd.raw.bak`). 8.3 filenames only for new files (e.g. `RNDSUB.ASM`).
- Console build = same `Project+/` folder layout on physical SD; P+ Launcher (HBC)
  uses `RSBE01.GCT`/`BOOST.GCT`. The Netplay PC build must not be copied to Wii.

## Open questions (Phase 1 targets)

1. Port index offset inside the per-player CSS object (r28).
2. How to enumerate the 4 player objects from a global (for the toggle hook), or
   find a per-player per-frame hook site where the object is already in a register.
3. Whether `buf+4` from getSysPadStatus is held or pressed-this-frame bits
   (we do our own edge detection regardless).
4. Confirm D-pad Down is truly inert on main CSS (P+ might map something).
