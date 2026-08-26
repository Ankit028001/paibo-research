#!/bin/bash
set -uo pipefail
OAI_RAN=/home/ankit/oai/openairinterface5g
UE_BIN_DIR="$OAI_RAN/cmake_targets/ran_build/build"
UE_CONF="$OAI_RAN/targets/PROJECTS/GENERIC-NR-5GC/CONF/ue.conf"
LOG_DIR=/home/ankit/paibo-research/multi_ue_setup/logs
mkdir -p "$LOG_DIR"
cd "$UE_BIN_DIR"

for i in $(seq 2 16); do
    msin=$(printf "%010d" $((30 + i)))
    imsi="20895${msin}"
    base_ip=$((200 + i))
    serveraddr="10.$base_ip.1.100"
    echo "launching UE $i  imsi=$imsi  serveraddr=$serveraddr"
    sudo -n ip netns exec "ue$i" "$UE_BIN_DIR/nr-uesoftmodem" \
        -O "$UE_CONF" \
        --rfsim -C 3450720000 -r 106 --numerology 1 --band 78 --ssb 516 \
        --uicc0.imsi "$imsi" \
        --rfsimulator.[0].serveraddr "$serveraddr" \
        > "$LOG_DIR/ue$i.log" 2>&1 &
    echo $! > "$LOG_DIR/ue$i.pid"
    sleep 2
done

echo "all UE2-16 launched, waiting (this keeps the session/processes alive)"
wait
