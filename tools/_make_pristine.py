"""Dev helper: revert a copied RSBE01.TXT to pre-mod state (for installer tests)."""
import sys

p = sys.argv[1]
lines = open(p, encoding="utf-8", errors="replace").read().splitlines(keepends=True)
out, in_blk, done = [], False, False
for l in lines:
    if "RANDSUB" in l or "Per-Port Random Subset" in l:
        continue  # our include line + markers
    if not done and "Melee Random v2" in l:
        in_blk = True
    if in_blk:
        s = l.lstrip("#")
        if l.strip().startswith("#") and (s.strip().startswith("*") or "Melee Random v2" in s):
            l = s  # un-comment the block back to stock
        if "7FA3EB78" in l:
            in_blk, done = False, True
    out.append(l)
t = "".join(out)
open(p, "w", encoding="utf-8", newline="").write(t)
print("pristine:", "RANDSUB" not in t, "| stock block active:", "\n* 0468AE20" in t.replace("\r", ""))
