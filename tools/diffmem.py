#!/usr/bin/env python3
"""Differential memory snapshots against a running Dolphin.

  snap <name>              save MEM1+MEM2 snapshot to build/snaps/<name>.bin
  diff <a> <b> <c>         print addresses equal in a==b but changed in c
                           (kills animation noise), grouped into runs
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from dolmem import DolphinMem, MEM1_SIZE, MEM2_SIZE

SNAPDIR = Path(__file__).parent.parent / "build" / "snaps"
REGIONS = ((0x80000000, MEM1_SIZE), (0x90000000, MEM2_SIZE))


def snap(name):
    m = DolphinMem()
    SNAPDIR.mkdir(parents=True, exist_ok=True)
    with open(SNAPDIR / f"{name}.bin", "wb") as f:
        for base, size in REGIONS:
            for off in range(0, size, 0x100000):
                f.write(m.read(base + off, 0x100000))
    print(f"snapped {name}")


def addr_of(file_off):
    if file_off < MEM1_SIZE:
        return 0x80000000 + file_off
    return 0x90000000 + (file_off - MEM1_SIZE)


def diff(a, b, c, limit=400):
    da = (SNAPDIR / f"{a}.bin").read_bytes()
    db = (SNAPDIR / f"{b}.bin").read_bytes()
    dc = (SNAPDIR / f"{c}.bin").read_bytes()
    runs = []
    i = 0
    n = len(da)
    CH = 0x10000
    for off in range(0, n, CH):
        ca, cb, cc = da[off : off + CH], db[off : off + CH], dc[off : off + CH]
        if ca == cb and cb == cc:
            continue
        for i in range(len(ca)):
            if ca[i] == cb[i] and cb[i] != cc[i]:
                pos = off + i
                if runs and pos == runs[-1][0] + runs[-1][1]:
                    runs[-1] = (runs[-1][0], runs[-1][1] + 1)
                else:
                    runs.append((pos, 1))
    print(f"{len(runs)} stable->changed runs")
    for pos, length in runs[:limit]:
        old = da[pos : pos + min(length, 8)].hex()
        new = dc[pos : pos + min(length, 8)].hex()
        print(f"{addr_of(pos):08X} len={length:<5d} {old} -> {new}")
    if len(runs) > limit:
        print(f"... {len(runs)-limit} more")


if __name__ == "__main__":
    if sys.argv[1] == "snap":
        snap(sys.argv[2])
    else:
        diff(*sys.argv[2:5])
