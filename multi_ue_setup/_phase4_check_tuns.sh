#!/bin/bash
echo "=== UE process count ==="
pgrep -af nr-uesoftmodem | grep -v grep | wc -l
echo "=== ue1 (native) ==="
ip -4 addr show oaitun_ue1 2>/dev/null | awk '/inet /{print "ue1: " $2}'
echo "=== ue2-16 (namespaced) ==="
for i in $(seq 2 16); do
    ip=$(sudo -n ip netns exec "ue$i" ip -4 addr show oaitun_ue1 2>/dev/null | awk '/inet /{print $2}')
    echo "ue$i: ${ip:-NO IP YET}"
done
