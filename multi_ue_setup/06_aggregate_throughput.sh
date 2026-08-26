#!/bin/bash
# Phase 4: computes per-UE measured KPIs and the final traffic-volume percentage
# table strictly from actual iperf3 JSON byte counters (see _parse_iperf_results.py
# for exactly what's measured vs derived). Superseded the old ping/estimate-based
# version -- all six profiles are iperf3 UDP now, so there is no more mmtc/v2x/web/
# mobile "estimate" branch vs. an iperf3 "measured" branch; every profile is measured
# the same way, which is what makes the percentages comparable at all.
# Usage: ./06_aggregate_throughput.sh [--table|--json]
set -uo pipefail
python3 /home/ankit/paibo-research/multi_ue_setup/_parse_iperf_results.py "${1:---table}"
