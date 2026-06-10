#!/usr/bin/env python3
"""Read-only Wii disc (ISO) reader: list the FST and extract files.

Decrypts the DATA partition on demand (cluster-granular), so extracting one
small file from an 8GB ISO is fast.

Usage:
  python wiidisc.py list <iso> [path-prefix]
  python wiidisc.py extract <iso> <fst-path> <dest>
"""
import struct
import sys
from pathlib import Path

from Crypto.Cipher import AES

COMMON_KEY = bytes.fromhex("ebe42a225e8593e448d9c5457381aaf7")
CLUSTER = 0x8000
CLUSTER_DATA = 0x7C00


class WiiDisc:
    def __init__(self, path):
        self.f = open(path, "rb")
        self.f.seek(0x18)
        if struct.unpack(">I", self.f.read(4))[0] != 0x5D1C9EA3:
            raise SystemExit("not a Wii disc")
        self.part_off = self._find_data_partition()
        self._read_ticket()
        self.f.seek(self.part_off + 0x2B8)
        self.data_off = struct.unpack(">I", self.f.read(4))[0] << 2
        self._cluster_cache = {}
        self._load_fst()

    def _find_data_partition(self):
        self.f.seek(0x40000)
        tbl = self.f.read(32)
        for i in range(4):
            count, info_off = struct.unpack_from(">II", tbl, i * 8)
            info_off <<= 2
            for j in range(count):
                self.f.seek(info_off + j * 8)
                off, ptype = struct.unpack(">II", self.f.read(8))
                if ptype == 0:
                    return off << 2
        raise SystemExit("no DATA partition")

    def _read_ticket(self):
        self.f.seek(self.part_off)
        ticket = self.f.read(0x2A4)
        enc_key = ticket[0x1BF : 0x1BF + 16]
        title_id = ticket[0x1DC : 0x1DC + 8]
        self.title_key = AES.new(
            COMMON_KEY, AES.MODE_CBC, title_id + b"\x00" * 8
        ).decrypt(enc_key)

    def _cluster(self, idx):
        if idx in self._cluster_cache:
            return self._cluster_cache[idx]
        self.f.seek(self.part_off + self.data_off + idx * CLUSTER)
        raw = self.f.read(CLUSTER)
        data = AES.new(self.title_key, AES.MODE_CBC, raw[0x3D0:0x3E0]).decrypt(
            raw[0x400:]
        )
        if len(self._cluster_cache) > 256:
            self._cluster_cache.clear()
        self._cluster_cache[idx] = data
        return data

    def pread(self, offset, size):
        out = bytearray()
        while size > 0:
            idx, within = divmod(offset, CLUSTER_DATA)
            chunk = self._cluster(idx)[within : within + size]
            out += chunk
            offset += len(chunk)
            size -= len(chunk)
        return bytes(out)

    def _load_fst(self):
        fst_off = struct.unpack(">I", self.pread(0x424, 4))[0] << 2
        fst_size = struct.unpack(">I", self.pread(0x428, 4))[0] << 2
        fst = self.pread(fst_off, fst_size)
        n_entries = struct.unpack_from(">I", fst, 8)[0]
        strings = fst[n_entries * 12 :]
        self.files = {}  # path -> (offset, size)

        def name_of(i):
            off = struct.unpack_from(">I", fst, i * 12)[0] & 0xFFFFFF
            end = strings.index(b"\x00", off)
            return strings[off:end].decode("shift-jis", "replace")

        def walk(start, end, prefix):
            i = start
            while i < end:
                w0, off, size = struct.unpack_from(">III", fst, i * 12)
                is_dir = w0 >> 24
                name = name_of(i)
                if is_dir:
                    walk(i + 1, size, prefix + name + "/")
                    i = size
                else:
                    self.files[prefix + name] = (off << 2, size)
                    i += 1

        walk(1, n_entries, "")

    def extract(self, fst_path, dest):
        key = next(
            (k for k in self.files if k.lower() == fst_path.lower()), None
        )
        if key is None:
            raise SystemExit(f"not in FST: {fst_path}")
        off, size = self.files[key]
        Path(dest).parent.mkdir(parents=True, exist_ok=True)
        Path(dest).write_bytes(self.pread(off, size))
        print(f"{key} ({size} bytes) -> {dest}")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    cmd, iso = sys.argv[1], sys.argv[2]
    disc = WiiDisc(iso)
    if cmd == "list":
        prefix = sys.argv[3].lower() if len(sys.argv) > 3 else ""
        for path, (off, size) in sorted(disc.files.items()):
            if path.lower().startswith(prefix):
                print(f"{size:>10}  {path}")
    elif cmd == "extract":
        disc.extract(sys.argv[3], sys.argv[4])
    else:
        raise SystemExit(f"unknown command {cmd}")


if __name__ == "__main__":
    main()
