#!/bin/bash
# Stops nr-uesoftmodem processes and deletes namespaces for UE IDs <first>..<last>,
# giving each UE time to deregister cleanly before its namespace disappears.
# Refuses to run against UE1 (native, not namespaced) and never touches CU, DU, or
# the 5GC containers -- those are yours to stop, if/when you choose to, separately.
# Usage: sudo ./07_teardown.sh <first_ue_id> <last_ue_id>   (first must be >= 2)
set -euo pipefail
[[ $(id -u) -eq 0 ]] || { echo "run as root"; exit 1; }
[[ $# -eq 2 ]] || { echo "usage: $0 <first_ue_id> <last_ue_id>"; exit 1; }
[[ $1 -ge 2 ]] || { echo "refusing: this script only tears down UE2-16, never UE1/CU/DU/5GC"; exit 1; }

OAI_RAN=/home/ankit/oai/openairinterface5g
MULTI_UE_SH="$OAI_RAN/tools/scripts/multi-ue.sh"
LOG_DIR=/home/ankit/paibo-research/multi_ue_setup/logs

for i in $(seq "$1" "$2"); do
    if [[ -f "$LOG_DIR/ue$i.pid" ]]; then
        pid=$(cat "$LOG_DIR/ue$i.pid")
        echo "stopping ue$i (pid $pid)"
        kill -SIGINT "$pid" 2>/dev/null || true
    fi
done

sleep 5   # allow RRC/NAS deregistration to complete before tearing down the namespace

for i in $(seq "$1" "$2"); do
    if [[ -f "$LOG_DIR/ue$i.pid" ]]; then
        pid=$(cat "$LOG_DIR/ue$i.pid")
        if kill -0 "$pid" 2>/dev/null; then
            echo "ue$i (pid $pid) ignored SIGINT, forcing SIGKILL"
            pkill -SIGKILL -P "$pid" 2>/dev/null || true
            kill -SIGKILL "$pid" 2>/dev/null || true
        fi
    fi
done
sleep 1

for i in $(seq "$1" "$2"); do
    "$MULTI_UE_SH" -d "$i" 2>/dev/null || echo "ue$i namespace already gone"
done

docker exec oai-ext-dn pkill iperf3 2>/dev/null || true
echo "teardown complete for UEs $1..$2 (UE1, CU, DU, 5GC untouched)"
