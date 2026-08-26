#!/bin/bash
RD=/home/ankit/paibo-research/multi_ue_setup/logs
mkdir -p "$RD"
cd /home/ankit/oai/openairinterface5g
setsid nohup sudo -n ./cmake_targets/ran_build/build/nr-softmodem -O targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb-du.sa.band78.106prb.rfsim.pci0.conf --rfsim --device.name rfsimulator > "$RD/du_stdout.log" 2>&1 < /dev/null &
echo "DU_PID=$!"
disown
