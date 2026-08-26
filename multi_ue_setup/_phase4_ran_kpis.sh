#!/bin/bash
LOG_DIR=/home/ankit/paibo-research/multi_ue_setup/logs
echo "=== per-UE latest PHY/MAC snapshot ==="
for i in $(seq 1 16); do
    f="$LOG_DIR/ue$i.log"
    echo "--- ue$i ---"
    if [[ -f "$f" ]]; then
        grep "DL Chan: SSB" "$f" | tail -1
        grep "DL harq:" "$f" | tail -1
        grep "UL harq:" "$f" | tail -1
    else
        echo "NO LOG FILE"
    fi
done

echo ""
echo "=== DU/CU CPU (live) ==="
DU_PID=$(pgrep -f "gnb-du.sa.band78" | sort -n | tail -1)
CU_PID=$(pgrep -f "gnb-cu.sa.f1" | sort -n | tail -1)
echo "DU_PID=$DU_PID"; ps -p "$DU_PID" -o pid,pcpu,pmem,etime 2>&1
echo "CU_PID=$CU_PID"; ps -p "$CU_PID" -o pid,pcpu,pmem,etime 2>&1

echo ""
echo "=== memory ==="
free -m

echo ""
echo "=== F1/NGAP/PFCP status (post-traffic error scan) ==="
echo -n "DU log F1 errors (last 2000 lines): "
tail -n 2000 "$LOG_DIR/du_stdout.log" | grep -icE "F1AP.*(error|fail|reject)"
echo -n "AMF NGAP errors (docker logs, since 10m): "
docker logs --since 10m oai-amf 2>&1 | grep -icE "ngap.*(error|fail)"
echo -n "SMF PFCP errors (docker logs, since 10m): "
docker logs --since 10m oai-smf 2>&1 | grep -icE "pfcp.*(error|fail|reject)"
echo -n "UPF PFCP errors (docker logs, since 10m): "
docker logs --since 10m oai-upf 2>&1 | grep -icE "pfcp.*(error|fail|reject)"

echo ""
echo "=== PRB utilization check (known limitation from Phase 1/2) ==="
grep -i "prb" "$LOG_DIR/du_stdout.log" | tail -3
