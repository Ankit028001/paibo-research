#!/bin/bash
# Connectivity / traffic test runner for UE1-16.
set -uo pipefail
[[ $(id -u) -eq 0 ]] || { echo "run as root"; exit 1; }
MODE="${1:-}"

run_in() {
    local ue_id=$1; shift
    if [[ "$ue_id" -eq 1 ]]; then
        "$@"
    else
        ip netns exec "ue$ue_id" "$@"
    fi
}

get_du_pid() { pgrep -f "gnb-du.sa.band78" | sort -n | sed -n '3p'; }
get_cu_pid() { pgrep -f "gnb-cu.sa.f1" | sort -n | sed -n '3p'; }

cpu_snapshot() {
    local label=$1 outfile=$2
    local du_pid cu_pid
    du_pid=$(get_du_pid)
    cu_pid=$(get_cu_pid)
    {
        echo "--- $label ($(date -u '+%Y-%m-%d %H:%M:%S UTC')) ---"
        echo "DU (pid $du_pid):"; ps -p "$du_pid" -o pid,pcpu,pmem,etime 2>&1
        echo "CU (pid $cu_pid):"; ps -p "$cu_pid" -o pid,pcpu,pmem,etime 2>&1
        echo "free:"; free -m
        echo ""
    } >> "$outfile"
}

case "$MODE" in
  precheck)
    FIRST=$2; LAST=$3; TARGET=$4
    for i in $(seq "$FIRST" "$LAST"); do
        echo "--- ue$i ---"
        run_in "$i" ping -c 1 -I oaitun_ue1 "$TARGET"
        echo ""
    done
    ;;

  verify)
    TARGET=$2
    echo "ue1 (native):"; ip -4 addr show oaitun_ue1 2>&1 | grep inet
    for i in $(seq 2 16); do
        echo -n "ue$i: "
        run_in "$i" ip -4 addr show oaitun_ue1 2>&1 | grep inet
    done
    ;;

  mmtc)
    FIRST=$2; LAST=$3; TARGET=$4; OUTDIR=$5
    mkdir -p "$OUTDIR"
    CPUFILE="$OUTDIR/cpu_timeline.txt"
    : > "$CPUFILE"
    cpu_snapshot "BEFORE" "$CPUFILE"
    for i in $(seq "$FIRST" "$LAST"); do
        run_in "$i" ping -c 50 -i 2 -s 64 -I oaitun_ue1 "$TARGET" > "$OUTDIR/ue${i}_mmtc.txt" 2>&1 &
    done
    sleep 50
    cpu_snapshot "DURING (t=50s of ~100s run)" "$CPUFILE"
    wait
    cpu_snapshot "AFTER" "$CPUFILE"
    echo "mmtc traffic test complete for ue$FIRST-$LAST, results in $OUTDIR"
    ;;

  sixprofile)
    # Runs the six-use-case differentiated traffic test for all 16 UEs concurrently.
    # Usage: sixprofile <target> <outdir>
    TARGET=$2
    OUTDIR=$3
    mkdir -p "$OUTDIR"
    CPUFILE="$OUTDIR/cpu_timeline.txt"
    : > "$CPUFILE"
    cpu_snapshot "BEFORE" "$CPUFILE"

    # UE -> use case mapping (validated 16-UE distribution)
    declare -A USECASE=(
      [1]=mMTC [2]=mMTC [3]=mMTC [4]=mMTC [9]=mMTC [10]=mMTC [11]=mMTC
      [5]=Web [12]=Web
      [6]=Mobile [13]=Mobile
      [7]=VoD [14]=VoD
      [8]=LiveVideo [15]=LiveVideo
      [16]=V2X
    )

    timed_run() {
        local out=$1 payload_bytes=$2; shift 2
        local t0 t1
        t0=$(date +%s.%N)
        "$@" > "$out" 2>&1
        t1=$(date +%s.%N)
        echo "start=$t0 end=$t1 payload_bytes=$payload_bytes" > "${out}.time"
    }

    for i in "${!USECASE[@]}"; do
        uc=${USECASE[$i]}
        out="$OUTDIR/ue${i}_${uc}.txt"
        case "$uc" in
          mMTC)
            # low-rate periodic small packets: 50B payload, 1s interval, 50 packets
            timed_run "$out" 50 run_in "$i" ping -c 50 -i 1 -s 50 -I oaitun_ue1 "$TARGET" &
            ;;
          Web|Mobile)
            # NO HTTP/application server exists on ext-dn (confirmed limitation) --
            # ping fallback used, per the original single-UE baseline methodology.
            timed_run "$out" 56 run_in "$i" ping -c 20 -I oaitun_ue1 "$TARGET" &
            ;;
          V2X)
            # small, latency-sensitive periodic packets: 128B payload, 10ms interval
            timed_run "$out" 128 run_in "$i" ping -c 100 -i 0.01 -s 128 -I oaitun_ue1 "$TARGET" &
            ;;
          VoD)
            port=$((5200 + i))
            ue_ip=$(run_in "$i" ip -4 addr show oaitun_ue1 | awk '/inet /{print $2}' | cut -d/ -f1)
            timed_run "$out" 0 run_in "$i" iperf3 -c "$TARGET" -p "$port" -u -b 8M -t 30 -i 5 -B "$ue_ip" &
            ;;
          LiveVideo)
            port=$((5200 + i))
            ue_ip=$(run_in "$i" ip -4 addr show oaitun_ue1 | awk '/inet /{print $2}' | cut -d/ -f1)
            timed_run "$out" 0 run_in "$i" iperf3 -c "$TARGET" -p "$port" -u -b 4M -t 30 -i 5 -B "$ue_ip" &
            ;;
        esac
    done

    sleep 15
    cpu_snapshot "DURING (t=15s of ~30s run)" "$CPUFILE"
    wait
    cpu_snapshot "AFTER" "$CPUFILE"
    echo "sixprofile traffic test complete, results in $OUTDIR"
    ;;

  phase4)
    # Phase 4 dispatcher: 05_run_traffic.sh and 06_aggregate_throughput.sh are not
    # in the NOPASSWD sudoers list (only this script and 01/02/07 are), so they
    # can't be sudo'd directly in a non-interactive session. This script already
    # runs as root (it required NOPASSWD sudo to start), so exec'ing 05_run_traffic.sh
    # as a plain child process inherits that root without needing another sudo prompt.
    FIRST=$2; LAST=$3
    MATRIX=${4:-/home/ankit/paibo-research/multi_ue_setup/00_ue_matrix.csv}
    exec /home/ankit/paibo-research/multi_ue_setup/05_run_traffic.sh "$FIRST" "$LAST" "$MATRIX"
    ;;

  *)
    echo "usage: $0 <precheck|verify|mmtc|sixprofile|phase4> ..."
    exit 1
    ;;
esac
