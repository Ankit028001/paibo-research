import glob
import os

RD = "/home/ankit/paibo-research/multi_ue_setup/results"
earliest = None
latest = None
per_ue_span = {}

for path in glob.glob(f"{RD}/*.json.time"):
    vals = {}
    for tok in open(path).read().split():
        k, v = tok.split("=", 1)
        vals[k] = v
    ws, we = float(vals["wall_start"]), float(vals["wall_end"])
    if earliest is None or ws < earliest:
        earliest = ws
    if latest is None or we > latest:
        latest = we
    fname = os.path.basename(path)
    ue = fname.split("_")[0]
    lo, hi = per_ue_span.get(ue, (ws, we))
    per_ue_span[ue] = (min(lo, ws), max(hi, we))

print(f"overall earliest wall_start={earliest}")
print(f"overall latest   wall_end  ={latest}")
print(f"TOTAL REAL WALL-CLOCK SPAN OF PHASE 4 RUN: {latest - earliest:.3f} seconds")
print()
for ue in sorted(per_ue_span, key=lambda x: int(x[2:])):
    lo, hi = per_ue_span[ue]
    print(f"{ue}: span={hi - lo:.3f}s")
