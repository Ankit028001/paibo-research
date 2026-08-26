#!/bin/bash
# Runs each UE's Phase-4 traffic profile (namespaced for UE2-16, native for UE1),
# per the approved 16UE_traffic_model_proposal.md Phase 3 targets and Phase 4 Option B
# (labeled bursty UDP for Web/Mobile -- no ext-dn container changes).
#
# All six profiles now use iperf3 -u with --logfile JSON output, captured on the
# *client* side only. For UDP, iperf3's protocol has the server relay loss/jitter
# back to the client at end-of-test, so the client's own JSON already contains bytes
# sent (sender-measured) and loss/jitter (receiver-measured, relayed) -- no dependency
# on capturing the server's own output, which is what silently lost data last time.
#
# Web/Mobile are NOT a single iperf3 call: each is a loop of short bursts (separate
# iperf3 control connections) separated by idle time. The loop always attempts the
# full planned burst count, but 06_aggregate_throughput.sh must count only bursts
# that actually produced valid JSON -- do not assume the planned count completed.
#
# Run 04_start_iperf_servers.sh first (all 16 ports).
# Usage: sudo ./05_run_traffic.sh <first_ue_id> <last_ue_id> [path/to/00_ue_matrix.csv]
set -uo pipefail
[[ $(id -u) -eq 0 ]] || { echo "run as root"; exit 1; }
[[ $# -ge 2 ]] || { echo "usage: $0 <first_ue_id> <last_ue_id> [matrix.csv]"; exit 1; }

FIRST=$1
LAST=$2
MATRIX="${3:-/home/ankit/paibo-research/multi_ue_setup/00_ue_matrix.csv}"
EXT_DN=192.168.70.130
RESULT_DIR=/home/ankit/paibo-research/multi_ue_setup/results
mkdir -p "$RESULT_DIR"

run_in() {
    local ue_id=$1; shift
    if [[ "$ue_id" -eq 1 ]]; then
        "$@"
    else
        ip netns exec "ue$ue_id" "$@"
    fi
}

get_tun_ip() {
    run_in "$1" ip -4 addr show oaitun_ue1 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1
}

# Wraps one iperf3 invocation with wall-clock start/end (captures real elapsed time,
# including TCP control-connection setup/teardown overhead that iperf3's own "seconds"
# field does not include) and records the invocation's exit code so callers can tell
# a genuinely completed run from one that failed outright.
timed_iperf() {
    local out_json=$1 side_file=$2; shift 2
    local t0 t1 rc
    t0=$(date +%s.%N)
    "$@" --logfile "$out_json" -J
    rc=$?
    t1=$(date +%s.%N)
    echo "wall_start=$t0 wall_end=$t1 exit_code=$rc" > "$side_file"
    return $rc
}

while IFS=, read -r ue_id imsi use_case profile; do
    [[ $ue_id -ge $FIRST && $ue_id -le $LAST ]] || continue

    ue_ip=$(get_tun_ip "$ue_id")
    if [[ -z "$ue_ip" ]]; then
        echo "ue$ue_id: no IP on oaitun_ue1 yet -- is it attached? skipping"
        continue
    fi
    port=$((5200 + ue_id))
    echo "ue$ue_id ($use_case, $profile) -- tun IP $ue_ip, port $port"

    case "$profile" in
        mmtc)
            # 100B UDP payload, 57,143 bps configured rate -> ~14ms interval, 60s
            out="$RESULT_DIR/ue${ue_id}_mmtc.json"
            timed_iperf "$out" "${out}.time" \
                run_in "$ue_id" iperf3 -c "$EXT_DN" -p "$port" -u -b 57143 -l 100 -t 60 -B "$ue_ip" &
            ;;
        v2x)
            # 150B UDP payload (BSM-sized), 800,000 bps configured rate -> ~1.5ms interval, 60s
            out="$RESULT_DIR/ue${ue_id}_v2x.json"
            timed_iperf "$out" "${out}.time" \
                run_in "$ue_id" iperf3 -c "$EXT_DN" -p "$port" -u -b 800K -l 150 -t 60 -B "$ue_ip" &
            ;;
        web)
            # Labeled synthetic bursty UDP representative of Web request-response timing
            # -- NOT literal HTTP. 10 planned bursts x (1s @ 9.6Mbps + 5s idle) = 60s.
            (
                completed=0
                for i in $(seq 1 10); do
                    out="$RESULT_DIR/ue${ue_id}_web_burst${i}.json"
                    if timed_iperf "$out" "${out}.time" \
                        run_in "$ue_id" iperf3 -c "$EXT_DN" -p "$port" -u -b 9.6M -t 1 -B "$ue_ip"; then
                        completed=$((completed + 1))
                    fi
                    sleep 5
                done
                echo "planned=10 completed=$completed" > "$RESULT_DIR/ue${ue_id}_web_burstcount.txt"
            ) &
            ;;
        mobile)
            # Labeled synthetic bursty UDP representative of Mobile-app timing -- NOT a
            # real mobile application. 12 planned bursts x (1s @ 10Mbps + 4s idle) = 60s.
            (
                completed=0
                for i in $(seq 1 12); do
                    out="$RESULT_DIR/ue${ue_id}_mobile_burst${i}.json"
                    if timed_iperf "$out" "${out}.time" \
                        run_in "$ue_id" iperf3 -c "$EXT_DN" -p "$port" -u -b 10M -t 1 -B "$ue_ip"; then
                        completed=$((completed + 1))
                    fi
                    sleep 4
                done
                echo "planned=12 completed=$completed" > "$RESULT_DIR/ue${ue_id}_mobile_burstcount.txt"
            ) &
            ;;
        vod)
            out="$RESULT_DIR/ue${ue_id}_vod.json"
            timed_iperf "$out" "${out}.time" \
                run_in "$ue_id" iperf3 -c "$EXT_DN" -p "$port" -u -b 7M -t 60 -B "$ue_ip" &
            ;;
        live)
            out="$RESULT_DIR/ue${ue_id}_live.json"
            timed_iperf "$out" "${out}.time" \
                run_in "$ue_id" iperf3 -c "$EXT_DN" -p "$port" -u -b 5M -t 60 -B "$ue_ip" &
            ;;
        *)
            echo "ue$ue_id: unknown profile '$profile', skipping"
            ;;
    esac
done < <(tail -n +2 "$MATRIX")

wait
echo "done. results in $RESULT_DIR -- run 06_aggregate_throughput.sh next for measured per-UE + cell traffic-volume percentages"
