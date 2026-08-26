#!/bin/bash
RD=/home/ankit/paibo-research/multi_ue_setup/logs
mkdir -p "$RD"
cd /home/ankit/oai/openairinterface5g
setsid nohup sudo -n ./cmake_targets/ran_build/build/nr-softmodem -O targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb-cu.sa.f1.conf > "$RD/cu_stdout.log" 2>&1 < /dev/null &
echo "CU_PID=$!"
disown
