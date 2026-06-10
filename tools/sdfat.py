#!/usr/bin/env python3
"""Minimal FAT32 read/write utility for Dolphin's sd.raw virtual SD images.

Commands:
  list    <image> [sdpath]              List a directory (default: root)
  extract <image> <sdpath> <dest>      Extract a file, or a directory recursively
  replace <image> <sdpath> <localfile> Replace an existing file's contents
  add     <image> <sddir> <localfile> [name83]
                                        Add a new file into an existing directory.
                                        Name must fit 8.3 (e.g. RNDSUB.ASM) unless
                                        it already exists (then use replace).

Writes update both FAT copies and the directory entry. Always keep a backup of
the image before writing (the build's GCTs can be regenerated, but pf/ cannot).
"""
import struct
import sys
from pathlib import Path

EOC = 0x0FFFFFF8  # end-of-chain threshold


class Fat32:
    def __init__(self, path, writable=False):
        self.f = open(path, "r+b" if writable else "rb")
        bs = self.f.read(512)
        self.bps = struct.unpack_from("<H", bs, 11)[0]
        self.spc = bs[13]
        self.reserved = struct.unpack_from("<H", bs, 14)[0]
        self.nfats = bs[16]
        self.fatsz = struct.unpack_from("<I", bs, 36)[0]
        self.root_cluster = struct.unpack_from("<I", bs, 44)[0]
        if struct.unpack_from("<H", bs, 22)[0] != 0 or self.fatsz == 0:
            raise SystemExit("not FAT32")
        self.fat_off = self.reserved * self.bps
        self.data_off = (self.reserved + self.nfats * self.fatsz) * self.bps
        self.cluster_size = self.spc * self.bps
        self.n_clusters = self.fatsz * self.bps // 4 - 2

    # ---- FAT access ----
    def fat_get(self, c):
        self.f.seek(self.fat_off + c * 4)
        return struct.unpack("<I", self.f.read(4))[0] & 0x0FFFFFFF

    def fat_set(self, c, val):
        for i in range(self.nfats):
            off = self.fat_off + i * self.fatsz * self.bps + c * 4
            self.f.seek(off)
            old = struct.unpack("<I", self.f.read(4))[0]
            self.f.seek(off)
            self.f.write(struct.pack("<I", (old & 0xF0000000) | (val & 0x0FFFFFFF)))

    def chain(self, c):
        out = []
        while 2 <= c < EOC:
            out.append(c)
            c = self.fat_get(c)
        return out

    def free_clusters(self, n):
        out = []
        c = 2
        while len(out) < n and c < self.n_clusters + 2:
            if self.fat_get(c) == 0:
                out.append(c)
            c += 1
        if len(out) < n:
            raise SystemExit("image full")
        return out

    # ---- cluster data ----
    def cluster_pos(self, c):
        return self.data_off + (c - 2) * self.cluster_size

    def read_chain(self, first, size=None):
        out = bytearray()
        for c in self.chain(first):
            self.f.seek(self.cluster_pos(c))
            out += self.f.read(self.cluster_size)
        return bytes(out[:size]) if size is not None else bytes(out)

    # ---- directories ----
    def entries(self, dir_cluster):
        """Yield (name, attr, first_cluster, size, dirent_abs_offset)."""
        lfn = ""
        for c in self.chain(dir_cluster):
            base = self.cluster_pos(c)
            self.f.seek(base)
            data = self.f.read(self.cluster_size)
            for i in range(0, self.cluster_size, 32):
                e = data[i : i + 32]
                if e[0] == 0:
                    return
                if e[0] == 0xE5:
                    lfn = ""
                    continue
                attr = e[11]
                if attr == 0x0F:
                    part = e[1:11] + e[14:26] + e[28:32]
                    lfn = part.decode("utf-16-le", "ignore").split("\x00")[0] + lfn
                    continue
                base_name = e[0:8].decode("ascii", "ignore").rstrip()
                ext = e[8:11].decode("ascii", "ignore").rstrip()
                name = lfn if lfn else (base_name + ("." + ext if ext else ""))
                lfn = ""
                first = struct.unpack_from("<H", e, 26)[0] | (
                    struct.unpack_from("<H", e, 20)[0] << 16
                )
                size = struct.unpack_from("<I", e, 28)[0]
                if name in (".", ".."):
                    continue
                yield name, attr, first, size, base + i

    def lookup(self, sdpath):
        """Resolve a path; returns (name, attr, first, size, dirent_off) or None."""
        parts = [p for p in sdpath.replace("\\", "/").split("/") if p]
        cur = self.root_cluster
        ent = ("/", 0x10, cur, 0, None)
        for part in parts:
            if not (ent[1] & 0x10):
                return None
            found = None
            for e in self.entries(cur):
                if e[0].lower() == part.lower():
                    found = e
                    break
            if not found:
                return None
            ent = found
            cur = ent[2]
        return ent

    # ---- write ops ----
    def _write_data(self, clusters, data):
        for i, c in enumerate(clusters):
            chunk = data[i * self.cluster_size : (i + 1) * self.cluster_size]
            chunk = chunk.ljust(self.cluster_size, b"\x00")
            self.f.seek(self.cluster_pos(c))
            self.f.write(chunk)
        for i, c in enumerate(clusters):
            self.fat_set(c, clusters[i + 1] if i + 1 < len(clusters) else 0x0FFFFFFF)

    def replace_file(self, sdpath, data):
        ent = self.lookup(sdpath)
        if ent is None or ent[1] & 0x10:
            raise SystemExit(f"not an existing file: {sdpath}")
        _, _, first, _, dirent_off = ent
        if first:
            for c in self.chain(first):
                self.fat_set(c, 0)
        new_first = 0
        if data:
            need = (len(data) + self.cluster_size - 1) // self.cluster_size
            clusters = self.free_clusters(need)
            self._write_data(clusters, data)
            new_first = clusters[0]
        self.f.seek(dirent_off + 20)
        self.f.write(struct.pack("<H", new_first >> 16))
        self.f.seek(dirent_off + 26)
        self.f.write(struct.pack("<HI", new_first & 0xFFFF, len(data)))
        self.f.flush()

    def add_file(self, sddir, name, data):
        if self.lookup(sddir.rstrip("/") + "/" + name):
            return self.replace_file(sddir.rstrip("/") + "/" + name, data)
        ent = self.lookup(sddir)
        if ent is None or not (ent[1] & 0x10):
            raise SystemExit(f"not a directory: {sddir}")
        dir_cluster = ent[2] if ent[4] is not None else self.root_cluster
        stem, _, ext = name.upper().partition(".")
        if len(stem) > 8 or len(ext) > 3 or not stem:
            raise SystemExit(f"name doesn't fit 8.3: {name}")
        slot = None
        chain = self.chain(dir_cluster)
        for c in chain:
            base = self.cluster_pos(c)
            self.f.seek(base)
            d = self.f.read(self.cluster_size)
            for i in range(0, self.cluster_size, 32):
                if d[i] in (0x00, 0xE5):
                    slot = base + i
                    break
            if slot:
                break
        if slot is None:  # extend directory with one fresh cluster
            new = self.free_clusters(1)[0]
            self.fat_set(chain[-1], new)
            self.fat_set(new, 0x0FFFFFFF)
            self.f.seek(self.cluster_pos(new))
            self.f.write(b"\x00" * self.cluster_size)
            slot = self.cluster_pos(new)
        new_first = 0
        if data:
            need = (len(data) + self.cluster_size - 1) // self.cluster_size
            clusters = self.free_clusters(need)
            self._write_data(clusters, data)
            new_first = clusters[0]
        e = bytearray(32)
        e[0:8] = stem.ljust(8).encode("ascii")
        e[8:11] = ext.ljust(3).encode("ascii")
        e[11] = 0x20  # archive
        struct.pack_into("<H", e, 20, new_first >> 16)
        struct.pack_into("<H", e, 24, (2026 - 1980) << 9 | 1 << 5 | 1)  # date
        struct.pack_into("<H", e, 26, new_first & 0xFFFF)
        struct.pack_into("<I", e, 28, len(data))
        self.f.seek(slot)
        self.f.write(bytes(e))
        self.f.flush()

    def extract(self, sdpath, dest):
        ent = self.lookup(sdpath)
        if ent is None:
            raise SystemExit(f"not found: {sdpath}")
        dest = Path(dest)
        if ent[1] & 0x10:
            dest.mkdir(parents=True, exist_ok=True)
            for name, attr, first, size, _ in self.entries(ent[2]):
                self.extract(sdpath.rstrip("/") + "/" + name, dest / name)
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(self.read_chain(ent[2], ent[3]))
            print(f"{sdpath} -> {dest} ({ent[3]} bytes)")


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    cmd, image = args[0], args[1]
    if cmd == "list":
        fs = Fat32(image)
        ent = fs.lookup(args[2]) if len(args) > 2 else ("/", 0x10, fs.root_cluster, 0, None)
        if ent is None:
            raise SystemExit("not found")
        for name, attr, first, size, _ in fs.entries(ent[2]):
            kind = "DIR " if attr & 0x10 else "    "
            print(f"{kind}{size:>10}  {name}")
    elif cmd == "extract":
        Fat32(image).extract(args[2], args[3])
    elif cmd == "replace":
        Fat32(image, writable=True).replace_file(args[2], Path(args[3]).read_bytes())
        print(f"replaced {args[2]} ({Path(args[3]).stat().st_size} bytes)")
    elif cmd == "add":
        name = args[4] if len(args) > 4 else Path(args[3]).name
        Fat32(image, writable=True).add_file(args[2], name, Path(args[3]).read_bytes())
        print(f"added {args[2]}/{name}")
    else:
        raise SystemExit(f"unknown command {cmd}")


if __name__ == "__main__":
    main()
