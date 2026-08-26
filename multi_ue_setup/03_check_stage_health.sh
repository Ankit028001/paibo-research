#!/bin/bash
# Comprehensive stage gate: run this after each ramp step (UEs 2-4, then 2-8, then 2-16)
# and confirm a clean pass before proceeding to the next stage. Read-only -- does not
# restart or kill anything.
#
# Checks:
#   1. Per-UE registration (PDU session established) from each UE's own log
#   2. DU log: frame drops / sync loss / timing errors
#   3. DU log: failed UE contexts / RA failures / resource-allocation rejections
#      (real OAI log strings, e.g. "RA Procedure failed", "cannot allocate resources
#      for PUCCH0, rejecting UE" -- grep'd from openair2/LAYER2/NR_MAC_gNB and F1AP source)
#   4. Host CPU load and memory pressure (12 cores / 15GB available in this WSL VM)
#
# Usage: sudo ./03_check_stage_health.sh <first_ue_id> <last_ue_id>
# Example, checking the whole fleet after stage 2: ./03_check_stage_health.sh 1 8
set -uo pipefail
[[ $# -eq 2 ]] || { echo "usage: $0 <first_ue_id> <last_ue_id>"; exit 1; }

LOG_DIR=/home/ankit/paibo-research/multi_ue_setup/logs
DU_LOG=/tmp/du.log   # update to match wherever your DU run actually redirects stdout/stderr

echo "=== 1. per-UE registration ==="
ok=0; total=0
for i in $(seq "$1" "$2"); do
    total=$((total + 1))
    if [[ $i -eq 1 ]]; then
        # UE1 native baseline -- check via its own tunnel interface, not a log file
        if ip -4 addr show oaitun_ue1 >/dev/null 2>&1; then
            echo "ue1: OK (native, oaitun_ue1 present)"
            ok=$((ok + 1))
        else
            echo "ue1: NOT CONFIRMED -- oaitun_ue1 not found"
        fi
        continue
    fi
    if grep -q "PDU Session Establishment Accept\|PDU session ID .* status established" "$LOG_DIR/ue$i.log" 2>/dev/null; then
        echo "ue$i: OK (PDU session established)"
        ok=$((ok + 1))
    else
        echo "ue$i: NOT CONFIRMED -- check $LOG_DIR/ue$i.log manually"
    fi
done
echo "$ok / $total UEs confirmed in range $1-$2"

echo ""
echo "=== 2. DU log: frame drop / sync / timing ==="
if [[ -f "$DU_LOG" ]]; then
    hits=$(tail -n 2000 "$DU_LOG" | grep -icE "frame drop|late|overflow|sync loss|out of sync|scheduling request timeout|segfault")
    if [[ "$hits" -gt 0 ]]; then
        echo "FOUND $hits matches -- inspect before proceeding:"
        tail -n 2000 "$DU_LOG" | grep -inE "frame drop|late|overflow|sync loss|out of sync|scheduling request timeout|segfault" | tail -20
    else
        echo "clean -- no frame-drop/sync/timing errors in the last 2000 DU log lines"
    fi
else
    echo "DU log not found at $DU_LOG -- update DU_LOG path in this script"
fi

echo ""
echo "=== 3. DU/CU log: failed UE contexts / RA failures / resource rejections ==="
if [[ -f "$DU_LOG" ]]; then
    hits=$(tail -n 2000 "$DU_LOG" | grep -icE "RA Procedure failed|RA Contention Resolution timer expired|rejecting UE|cannot allocate resources for|UE Context Release|RA failed at state|RRCReject")
    if [[ "$hits" -gt 0 ]]; then
        echo "FOUND $hits matches -- inspect (may indicate the 16-UE / PUCCH-resource ceiling is being hit):"
        tail -n 2000 "$DU_LOG" | grep -inE "RA Procedure failed|RA Contention Resolution timer expired|rejecting UE|cannot allocate resources for|UE Context Release|RA failed at state|RRCReject" | tail -20
    else
        echo "clean -- no RA failures, context releases, or resource-allocation rejections in the last 2000 DU log lines"
    fi
else
    echo "DU log not found at $DU_LOG -- update DU_LOG path in this script"
fi

echo ""
echo "=== 4. host CPU / memory pressure ==="
echo "cores: $(nproc)"
echo "load average (1/5/15 min):$(cut -d' ' -f1-3 /proc/loadavg | sed 's/^/ /')"
free -h | head -2
echo ""
echo "top CPU consumers among the RAN processes:"
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | grep -E "nr-softmodem|nr-uesoftmodem" | head -20

echo ""
echo "=== summary ==="
echo "Review sections 2-4 manually. If section 1 shows fewer confirmed UEs than expected,"
echo "or sections 2/3 show new hits vs the previous stage, or load average exceeds ~$(nproc)"
echo "(i.e. fully saturating the ${HOSTNAME:-VM}'s $(nproc) cores), STOP here -- this stage's"
echo "UE count is the practical capacity, not 16. Recompute the proportions against that N."
