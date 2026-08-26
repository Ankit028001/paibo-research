import json
for ue, name in [(12, "vod"), (16, "v2x")]:
    path = f"/home/ankit/paibo-research/multi_ue_setup/results/ue{ue}_{name}.json"
    try:
        d = json.load(open(path))
        print(ue, "keys:", list(d.keys()))
        print(ue, "error field:", d.get("error", "none"))
        if "end" in d:
            print(ue, "end keys:", list(d["end"].keys()))
            print(ue, "sum:", d["end"].get("sum"))
    except Exception as e:
        print(ue, "PARSE FAILED:", e)
        raw = open(path).read()
        print(ue, "last 300 chars:", raw[-300:])
