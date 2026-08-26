#!/usr/bin/env python3
"""Phase 4: builds per-UE measured KPIs and the final traffic-volume percentage
table strictly from actual iperf3 JSON byte counters -- never from the configured
target bytes in 16UE_traffic_model_proposal.md. Used by 06_aggregate_throughput.sh.

For UDP, iperf3's protocol has the *server* relay loss/jitter back to the *client*
at end-of-test, so a client-side --logfile JSON already contains sender-measured
bytes plus receiver-measured loss/jitter -- nothing here depends on server-side
output (that's what silently lost data in the prior run).

"Actual bytes received" is not a field iperf3 prints directly for UDP; it is derived
here as bytes * (received_packets / packets), i.e. bytes scaled by the receiver-
reported delivery ratio. This is an approximation (assumes uniform packet size,
true for iperf3's own CBR traffic) and is labeled as derived, not measured directly.
"""
import csv
import json
import os
import sys

RESULT_DIR = "/home/ankit/paibo-research/multi_ue_setup/results"
MATRIX = "/home/ankit/paibo-research/multi_ue_setup/00_ue_matrix.csv"

CONFIGURED_RATE_BPS = {
    "mmtc": 57143, "v2x": 800000,
    "web": 9_600_000,   # in-burst rate; not a sustained rate
    "mobile": 10_000_000,
    "vod": 7_000_000, "live": 5_000_000,
}
CONFIGURED_PKT_SIZE = {"mmtc": 100, "v2x": 150, "web": None, "mobile": None, "vod": None, "live": None}


def load_json(path):
    """Parses the first complete JSON object in the file, ignoring anything after it.

    Known environment quirk (documented in Phase 1 of the traffic-model proposal,
    reproduced again in this run for ue12/ue16 and one burst each on ue8/ue10):
    iperf3 sometimes appends 'error - control socket has closed unexpectedly' after
    an otherwise complete, valid JSON summary. The data transfer and the JSON report
    both finished correctly before that; only the post-test control-channel teardown
    is affected. A strict full-file json.load() would reject real, valid data over
    this trailing garbage, so raw_decode() is used to take just the JSON object.
    """
    if not os.path.isfile(path):
        return None
    try:
        with open(path) as f:
            text = f.read()
        obj, _ = json.JSONDecoder().raw_decode(text)
        return obj
    except (json.JSONDecodeError, OSError, ValueError):
        return None


def had_control_socket_error(path):
    if not os.path.isfile(path):
        return False
    with open(path) as f:
        return "control socket has closed unexpectedly" in f.read()


def load_time_sidecar(path):
    if not os.path.isfile(path):
        return None
    vals = {}
    with open(path) as f:
        for tok in f.read().split():
            if "=" in tok:
                k, v = tok.split("=", 1)
                vals[k] = v
    try:
        return {
            "wall_start": float(vals["wall_start"]),
            "wall_end": float(vals["wall_end"]),
            "exit_code": int(vals["exit_code"]),
        }
    except (KeyError, ValueError):
        return None


def extract_udp_sum(doc):
    """Pulls the end.sum UDP block out of one iperf3 -J document, if present and valid."""
    if not doc:
        return None
    try:
        s = doc["end"]["sum"]
        return {
            "bytes": s.get("bytes", 0),
            "seconds": s.get("seconds", 0.0),
            "bits_per_second": s.get("bits_per_second", 0.0),
            "jitter_ms": s.get("jitter_ms", 0.0),
            "packets": s.get("packets", 0),
            "lost_packets": s.get("lost_packets", 0),
            "lost_percent": s.get("lost_percent", 0.0),
        }
    except (KeyError, TypeError):
        return None


def single_shot_ue(ue_id, profile):
    """mmtc / v2x / vod / live: one iperf3 call, one JSON file."""
    base = f"{RESULT_DIR}/ue{ue_id}_{profile}"
    json_path = f"{base}.json"
    doc = load_json(json_path)
    side = load_time_sidecar(f"{json_path}.time")
    udp = extract_udp_sum(doc)
    if udp is None:
        return {"status": "NO DATA (iperf3 run missing/failed)", "bytes_sent": 0}
    recv_bytes = udp["bytes"] * ((udp["packets"] - udp["lost_packets"]) / udp["packets"]) if udp["packets"] else 0
    wall_duration = (side["wall_end"] - side["wall_start"]) if side else None
    if side and side["exit_code"] == 0:
        status = "OK"
    elif had_control_socket_error(json_path):
        status = "OK (data valid; iperf3 exit!=0: control socket closed after transfer)"
    else:
        status = "iperf3 exit != 0"
    return {
        "status": status,
        "bytes_sent": udp["bytes"],
        "bytes_received_derived": round(recv_bytes),
        "iperf3_seconds": round(udp["seconds"], 3),
        "wall_seconds": round(wall_duration, 3) if wall_duration is not None else "n/a",
        "loss_percent": round(udp["lost_percent"], 4),
        "jitter_ms": round(udp["jitter_ms"], 4),
        "throughput_bps": round(udp["bits_per_second"]),
    }


def bursty_ue(ue_id, profile, planned_bursts):
    """web / mobile: N separate 1s bursts; sum only bursts that actually produced data."""
    total_bytes = 0
    total_recv_bytes = 0
    total_iperf_seconds = 0.0
    total_wall_seconds = 0.0
    weighted_jitter_num = 0.0
    total_packets = 0
    total_lost = 0
    completed = 0
    control_socket_quirk_count = 0
    first_wall_start = None
    last_wall_end = None

    for i in range(1, planned_bursts + 1):
        base = f"{RESULT_DIR}/ue{ue_id}_{profile}_burst{i}"
        json_path = f"{base}.json"
        doc = load_json(json_path)
        side = load_time_sidecar(f"{json_path}.time")
        udp = extract_udp_sum(doc)
        if udp is None or side is None:
            continue  # no usable data at all -- genuinely not completed
        if first_wall_start is None:
            first_wall_start = side["wall_start"]
        last_wall_end = side["wall_end"]
        if side["exit_code"] != 0:
            if had_control_socket_error(json_path):
                # Data transfer itself finished and was reported; only the post-test
                # control-channel teardown errored. Counts as completed.
                control_socket_quirk_count += 1
            else:
                continue  # attempted, genuinely not completed -- excluded from the byte total
        completed += 1
        total_bytes += udp["bytes"]
        if udp["packets"]:
            total_recv_bytes += udp["bytes"] * ((udp["packets"] - udp["lost_packets"]) / udp["packets"])
        total_iperf_seconds += udp["seconds"]
        total_wall_seconds += (side["wall_end"] - side["wall_start"])
        weighted_jitter_num += udp["jitter_ms"] * udp["packets"]
        total_packets += udp["packets"]
        total_lost += udp["lost_packets"]

    covered_wall_seconds = (last_wall_end - first_wall_start) if (first_wall_start and last_wall_end) else None
    status = f"{completed}/{planned_bursts} bursts completed"
    if control_socket_quirk_count:
        status += f" ({control_socket_quirk_count} via control-socket-closed quirk, data valid)"
    return {
        "status": status,
        "bursts_planned": planned_bursts,
        "bursts_completed": completed,
        "bytes_sent": round(total_bytes),
        "bytes_received_derived": round(total_recv_bytes),
        "iperf3_active_seconds": round(total_iperf_seconds, 3),
        "wall_seconds_in_bursts": round(total_wall_seconds, 3),
        "wall_seconds_incl_idle": round(covered_wall_seconds, 3) if covered_wall_seconds else "n/a",
        "startup_overhead_seconds": round(total_wall_seconds - total_iperf_seconds, 3),
        "loss_percent": round((total_lost / total_packets * 100), 4) if total_packets else "n/a",
        "jitter_ms": round(weighted_jitter_num / total_packets, 4) if total_packets else "n/a",
        "throughput_bps": round((total_bytes * 8 / total_iperf_seconds)) if total_iperf_seconds else 0,
    }


def main():
    rows = []
    with open(MATRIX) as f:
        r = csv.DictReader(f)
        for row in r:
            ue_id = row["ue_id"]
            use_case = row["use_case"]
            profile = row["traffic_profile"]
            if profile in ("web", "mobile"):
                planned = 10 if profile == "web" else 12
                m = bursty_ue(ue_id, profile, planned)
            else:
                m = single_shot_ue(ue_id, profile)
            m["ue_id"] = ue_id
            m["use_case"] = use_case
            m["profile"] = profile
            m["configured_rate_bps"] = CONFIGURED_RATE_BPS.get(profile, "n/a")
            m["configured_packet_size_bytes"] = CONFIGURED_PKT_SIZE.get(profile, "n/a (variable, iperf3 default MSS)")
            rows.append(m)

    total_measured_bytes = sum(r.get("bytes_sent", 0) for r in rows)
    for r in rows:
        r["measured_pct_of_total"] = (
            round(r.get("bytes_sent", 0) / total_measured_bytes * 100, 4) if total_measured_bytes else 0.0
        )

    if "--table" in sys.argv:
        print(f"{'UE':<4}{'use_case':<24}{'status':<26}{'bytes_sent':>12}{'loss%':>9}{'jitter_ms':>11}{'mbps':>10}{'measured%':>11}")
        for r in rows:
            mbps = round(r.get("throughput_bps", 0) / 1_000_000, 3)
            print(f"{r['ue_id']:<4}{r['use_case']:<24}{r['status']:<26}{r.get('bytes_sent', 0):>12}"
                  f"{str(r.get('loss_percent', 'n/a')):>9}{str(r.get('jitter_ms', 'n/a')):>11}{mbps:>10}{r['measured_pct_of_total']:>11}")
        print(f"\nTOTAL MEASURED BYTES (sum of actual bytes sent, all 16 UEs): {total_measured_bytes}")
        return

    print(json.dumps({"rows": rows, "total_measured_bytes": total_measured_bytes}, indent=2))


if __name__ == "__main__":
    main()
