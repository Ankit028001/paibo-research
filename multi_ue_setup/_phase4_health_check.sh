#!/bin/bash
echo "=== AMF registered UE count ==="
docker exec oai-amf bash -c "cat /openair-amf/bin/../etc/*.cfg" >/dev/null 2>&1
docker logs oai-amf 2>&1 | grep -c "5GMM-REGISTERED"
echo "=== AMF nr-cli registration table ==="
docker exec oai-amf /openair-amf/bin/nr-cli amf --exec "amf-ue-ngap-id-list" 2>&1 | head -40
echo "=== DU log: errors/RA failures (last 500 lines) ==="
tail -n 500 /home/ankit/paibo-research/multi_ue_setup/logs/du_stdout.log | grep -icE "RA Procedure failed|rejecting UE|cannot allocate resources for|UE Context Release|RRCReject|frame drop|sync loss|segfault"
echo "=== DU CPU ==="
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | grep nr-softmodem | head -6
echo "=== ext-dn actual current IP ==="
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' oai-ext-dn
