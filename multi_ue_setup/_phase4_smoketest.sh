#!/bin/bash
iperf3 -c 192.168.70.130 -p 5201 -u -b 57143 -l 100 -t 1 -B 12.1.1.130 --logfile /tmp/smoketest.json -J
echo "iperf3 exit code: $?"
echo "--- parsed fields ---"
python3 - <<'EOF'
import json
d = json.load(open('/tmp/smoketest.json'))
s = d['end']['sum']
print("bytes=", s['bytes'], "seconds=", s['seconds'], "jitter_ms=", s['jitter_ms'],
      "lost_percent=", s['lost_percent'], "bps=", s['bits_per_second'])
EOF
