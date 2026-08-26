#!/bin/bash
echo "=== timestamp ==="
date -u '+%Y-%m-%d %H:%M:%S UTC'
echo "=== AMF registration table (most recent) ==="
docker logs --tail 60 oai-amf 2>&1 | grep -A20 "5GMM State"| tail -20
echo "=== per-UE tunnel IPs ==="
sudo -n /home/ankit/paibo-research/multi_ue_setup/08_test_connectivity.sh verify none
echo "=== process liveness ==="
echo -n "CU: "; pgrep -af 'gnb-cu' | grep -vc grep
echo -n "DU: "; pgrep -af 'gnb-du' | grep -vc grep
echo -n "UE processes (native+namespaced): "; pgrep -af 'nr-uesoftmodem' | grep -vc grep
echo "=== DU log error scan (last 500 lines) ==="
tail -n 500 /home/ankit/paibo-research/multi_ue_setup/logs/du_stdout.log | grep -icE "RA Procedure failed|rejecting UE|cannot allocate resources for|UE Context Release|RRCReject|frame drop|sync loss|segfault"
echo "=== docker container health ==="
docker ps --format '{{.Names}}: {{.Status}}'
echo "=== iperf3 server ports listening ==="
docker exec oai-ext-dn ss -ltn 2>/dev/null | grep -cE ':(52[0-9]{2})\b'
