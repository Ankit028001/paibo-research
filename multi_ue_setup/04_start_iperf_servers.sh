#!/bin/bash
# Starts one iperf3 server per UE inside the ext-dn container, each on its own port
# (port = 5200 + ue_id), so 16 concurrent UDP flows never share a control channel.
# Extended (Phase 4) from the original VoD/Live-only version: all six profiles now
# use iperf3 (mMTC/V2X moved off ping, Web/Mobile moved to labeled bursty UDP per
# the approved Phase 3 model), so every UE needs its own server, not just VoD/Live.
# Usage: ./04_start_iperf_servers.sh [path/to/00_ue_matrix.csv]
set -euo pipefail
MATRIX="${1:-/home/ankit/paibo-research/multi_ue_setup/00_ue_matrix.csv}"

docker exec oai-ext-dn pkill iperf3 2>/dev/null || true
sleep 1

tail -n +2 "$MATRIX" | while IFS=, read -r ue_id imsi use_case profile; do
    port=$((5200 + ue_id))
    echo "starting iperf3 server for ue$ue_id ($use_case) on port $port"
    # Not relying on capturing docker exec -d's own stdout for measurement -- the
    # previous run lost server-side output that way (control-socket bug, see
    # 16UE_traffic_model_proposal.md Phase 1). This time the server's output is not
    # needed for measurement at all: iperf3's UDP protocol has the server relay
    # loss/jitter back to the *client*, so the client-side --logfile JSON (written by
    # 05_run_traffic.sh) is sufficient on its own. This server only needs to be up.
    docker exec -d oai-ext-dn iperf3 -s -p "$port"
done

sleep 2
echo "--- listening check ---"
docker exec oai-ext-dn ss -ltn 2>/dev/null | grep -E ':(52[0-9]{2})\b' | sort
