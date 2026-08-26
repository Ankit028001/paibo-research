#!/bin/bash
LOG_DIR=/home/ankit/paibo-research/multi_ue_setup/logs
DU_LOG=/home/ankit/paibo-research/multi_ue_setup/logs/du_stdout.log
for i in $(seq 1 16); do
    f="$LOG_DIR/ue$i.log"
    rnti=$(grep -oE "RNTI [0-9a-f]+" "$f" | tail -1 | awk '{print $2}')
    echo -n "ue$i rnti=${rnti:-unknown} "
    if [[ -n "$rnti" ]]; then
        line=$(grep -i "UE $rnti: ulsch_rounds" "$DU_LOG" | tail -1)
        echo "$line"
    else
        echo "NO RNTI FOUND"
    fi
done
