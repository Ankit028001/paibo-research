import json

for path in [
    "/home/ankit/paibo-research/multi_ue_setup/results/ue1_mmtc.json",
    "/home/ankit/paibo-research/multi_ue_setup/results/ue12_vod.json",
]:
    print("=====", path)
    text = open(path).read()
    obj, idx = json.JSONDecoder().raw_decode(text)
    print("end keys:", list(obj["end"].keys()))
    print("end.sum:", json.dumps(obj["end"].get("sum"), indent=2))
    if "streams" in obj["end"]:
        print("streams[0] keys:", list(obj["end"]["streams"][0].keys()))
        print("streams[0].udp:", json.dumps(obj["end"]["streams"][0].get("udp"), indent=2))
