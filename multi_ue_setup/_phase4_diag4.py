import json

for ue, profile, n in [(8, "web", 10), (10, "mobile", 12)]:
    print(f"===== ue{ue} {profile}")
    for i in range(1, n + 1):
        base = f"/home/ankit/paibo-research/multi_ue_setup/results/ue{ue}_{profile}_burst{i}"
        try:
            vals = {}
            for tok in open(f"{base}.json.time").read().split():
                k, v = tok.split("=", 1)
                vals[k] = v
            dur = float(vals["wall_end"]) - float(vals["wall_start"])
            print(f"  burst{i}: wall_duration={dur:.3f}s exit_code={vals['exit_code']}")
        except FileNotFoundError:
            print(f"  burst{i}: NO FILE")
