#!/bin/bash
echo "=== timestamp ==="
date -u '+%Y-%m-%d %H:%M:%S UTC'
echo "=== AMF registration table (most recent) ==="
docker logs --tail 60 oai-amf 2>&1 | grep -A20 "5GMM State" | tail -20
echo "=== per-UE tunnel IPs (unchanged?) ==="
sudo -n /home/ankit/paibo-research/multi_ue_setup/08_test_connectivity.sh verify none
echo "=== process liveness (same PIDs as before traffic?) ==="
echo -n "CU: "; pgrep -af 'gnb-cu' | grep -v grep
echo -n "DU: "; pgrep -af 'gnb-du' | grep -v grep
echo "UE process count: $(pgrep -af nr-uesoftmodem | grep -vc grep)"
echo "=== DU log error scan (last 1000 lines, post-traffic) ==="
tail -n 1000 /home/ankit/paibo-research/multi_ue_setup/logs/du_stdout.log | grep -icE "RA Procedure failed|rejecting UE|cannot allocate resources for|UE Context Release|RRCReject|frame drop|sync loss|segfault"
echo "=== docker container health ==="
docker ps --format '{{.Names}}: {{.Status}}'
echo "=== quick reachability re-check (1 ping per UE) ==="
sudo -n /home/ankit/paibo-research/multi_ue_setup/08_test_connectivity.sh precheck 1 16 192.168.70.130 2>&1 | grep -E "^---|packet loss"
