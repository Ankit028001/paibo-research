import json
import subprocess

out = subprocess.run(
    ["python3", "/home/ankit/paibo-research/multi_ue_setup/_parse_iperf_results.py"],
    capture_output=True, text=True
).stdout
d = json.loads(out)
for r in d["rows"]:
    if int(r["ue_id"]) >= 12:
        print(r["ue_id"], r["profile"], "jitter_ms=", r.get("jitter_ms"),
              "loss=", r.get("loss_percent"),
              "seconds=", r.get("iperf3_seconds", r.get("iperf3_active_seconds")),
              "wall=", r.get("wall_seconds", r.get("wall_seconds_incl_idle")))
