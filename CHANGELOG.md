# Changelog

## v1.2.0

- **Netplay support.** The installer now patches the netplay codeset
  (`NETPLAY.GCT`) alongside the offline one, and netplay has been tested
  end-to-end. Project+ netplay is lockstep-deterministic, so the per-port
  lists and rolls stay in sync between clients. Both players need the mod
  installed (a codeset mismatch desyncs regardless of this mod).
- **Louder list-edit sounds.** The add/remove/clear blips now play twice in
  the same frame (`SfxRepeat` in `RANDSUB.ASM`) so the feedback is more
  tactile. `playSE` has no volume argument, so stacking identical
  sample-aligned voices is how the volume is raised without changing the
  sound.

## v1.1.1

- Restored the decide-path hook (`$8068AE24`) that performs the melee-style
  instant random when a coin is dropped outside the character grid. v1.1 had
  removed it as "vestigial" — it is not; it is the entire edge-drop feature.
  The stock "Melee Random v2" code hooks the same address and is broken on
  Project+ (stale REL-relative calls), so the installer disables it.

## v1.1.0

- Removed the Z-modifier instant-roll drop mode (redundant) and the two
  panel-state hooks that only existed to support it.
- Python-free Windows installer (`install.bat`).

## v1.0.0

- First release. Per-port random-character lists built live on the Project+
  character select screen: tap L to add/remove, drop on Random for a mystery
  roll from your list, empty list = vanilla behavior. Verified on Wii console
  and Project+ Dolphin.
