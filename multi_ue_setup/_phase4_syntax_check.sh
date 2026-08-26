#!/bin/bash
chmod +x /home/ankit/paibo-research/multi_ue_setup/04_start_iperf_servers.sh \
         /home/ankit/paibo-research/multi_ue_setup/05_run_traffic.sh \
         /home/ankit/paibo-research/multi_ue_setup/06_aggregate_throughput.sh \
         /home/ankit/paibo-research/multi_ue_setup/_parse_iperf_results.py

echo "=== bash -n syntax checks ==="
for f in 04_start_iperf_servers.sh 05_run_traffic.sh 06_aggregate_throughput.sh; do
    printf "%s: " "$f"
    bash -n "/home/ankit/paibo-research/multi_ue_setup/$f" && echo OK
done

echo "=== python3 syntax check ==="
python3 -m py_compile /home/ankit/paibo-research/multi_ue_setup/_parse_iperf_results.py && echo "python OK"
