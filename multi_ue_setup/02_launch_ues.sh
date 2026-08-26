#!/bin/bash
# Launches nr-uesoftmodem for UE IDs <first>..<last> inside their namespaces, using the
# same validated RF parameters as the single-UE baseline in ASSIGNMENT_REPORT.md
# (band 78, 106 PRB, numerology 1, -C 3450720000, --ssb 516). Only --uicc0.imsi
# and --rfsimulator.[0].serveraddr vary per UE.
#
# NOTE: an earlier version of this script also passed --telnetsrv
# --telnetsrv.listenport (per doc/NR_SA_Tutorial_OAI_multi_UE.md) to give each UE
# a distinct telnet port. This build's nr-uesoftmodem rejects --telnetsrv.listenport
# as an unknown option and force-exits via config_check_unknown_cmdlineopt() --
# confirmed in Stage 1: UE2/3/4 all completed Registration Accept + PDU Session
# Establishment + TUN interface up, then immediately self-terminated on this
# exact unknown-option check. Telnet control isn't required for this experiment,
# so the flags are dropped entirely rather than guessing at alternate syntax.
#
# UE1 is never touched by this script -- it must already be running natively
# (your existing single-UE process/command). Run 00_preflight_check.sh first.
#
# Prereqs: CU + DU + 5GC + UE1 already running, namespaces already
# created via 01_create_namespaces.sh for this same ID range.
#
# Usage: sudo ./02_launch_ues.sh <first_ue_id> <last_ue_id>   (first must be >= 2)
set -euo pipefail
[[ $(id -u) -eq 0 ]] || { echo "run as root"; exit 1; }
[[ $# -eq 2 ]] || { echo "usage: $0 <first_ue_id> <last_ue_id>"; exit 1; }
[[ $1 -ge 2 ]] || { echo "refusing: UE1 is native and already running, this script only launches UE2-16"; exit 1; }

OAI_RAN=/home/ankit/oai/openairinterface5g
UE_BIN_DIR="$OAI_RAN/cmake_targets/ran_build/build"
UE_CONF="$OAI_RAN/targets/PROJECTS/GENERIC-NR-5GC/CONF/ue.conf"
LOG_DIR=/home/ankit/paibo-research/multi_ue_setup/logs
mkdir -p "$LOG_DIR"

cd "$UE_BIN_DIR"

for i in $(seq "$1" "$2"); do
    msin=$(printf "%010d" $((30 + i)))
    imsi="20895${msin}"                  # ue1 -> 208950000000031 ... ue16 -> 208950000000046 (all pre-provisioned in oai_db2.sql)
    base_ip=$((200 + i))
    serveraddr="10.$base_ip.1.100"

    echo "launching UE $i  imsi=$imsi  serveraddr=$serveraddr"
    ip netns exec "ue$i" ./nr-uesoftmodem \
        -O "$UE_CONF" \
        --rfsim -C 3450720000 -r 106 --numerology 1 --band 78 --ssb 516 \
        --uicc0.imsi "$imsi" \
        --rfsimulator.[0].serveraddr "$serveraddr" \
        > "$LOG_DIR/ue$i.log" 2>&1 &
    echo $! > "$LOG_DIR/ue$i.pid"
    sleep 2   # stagger RACH attempts instead of all UEs hitting PRACH at once
done

echo "launched UEs $1..$2. Tail logs in $LOG_DIR, e.g.: tail -f $LOG_DIR/ue$1.log"
# Phase 4 (paibo-research): keep this script's sudo/PAM session open so the
# backgrounded nr-uesoftmodem children aren't reaped when the session closes.
wait
