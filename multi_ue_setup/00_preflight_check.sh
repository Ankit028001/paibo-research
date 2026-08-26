#!/bin/bash
# Read-only gate. Verifies CU, DU, 5GC and UE1 are already up via YOUR existing
# procedure. Never starts, stops, or restarts anything -- if something here is
# down, go bring it up the way you already do, then re-run this check.
set -uo pipefail

ok=1

echo "=== 5GC containers ==="
need="oai-amf oai-smf oai-upf oai-ausf oai-udm oai-udr oai-nrf mysql oai-ext-dn"
for c in $need; do
    status=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
    if [[ "$status" == "running" ]]; then
        echo "  $c: running"
    else
        echo "  $c: ${status:-not found}  <-- NOT UP"
        ok=0
    fi
done

echo ""
echo "=== CU / DU processes ==="
if pgrep -af "nr-softmodem.*gnb-cu" >/dev/null; then
    echo "  CU: running ($(pgrep -af 'nr-softmodem.*gnb-cu'))"
else
    echo "  CU: NOT FOUND  <-- NOT UP"
    ok=0
fi
if pgrep -af "nr-softmodem.*gnb-du" >/dev/null; then
    echo "  DU: running ($(pgrep -af 'nr-softmodem.*gnb-du'))"
else
    echo "  DU: NOT FOUND  <-- NOT UP"
    ok=0
fi

echo ""
echo "=== UE1 (baseline, native, IMSI ...031) ==="
if pgrep -af "nr-uesoftmodem" >/dev/null; then
    echo "  UE1: running ($(pgrep -af 'nr-uesoftmodem'))"
    if ip -4 addr show oaitun_ue1 >/dev/null 2>&1; then
        ip -4 addr show oaitun_ue1 | awk '/inet /{print "  oaitun_ue1: " $2}'
    fi
else
    echo "  UE1: NOT FOUND -- bring it up with your existing single-UE command first"
    ok=0
fi

echo ""
if [[ $ok -eq 1 ]]; then
    echo "PREFLIGHT OK -- safe to run 01_create_namespaces.sh / 02_launch_ues.sh for UE2-16"
else
    echo "PREFLIGHT FAILED -- fix the items above via your existing startup procedure."
    echo "This script will not start/stop anything for you."
    exit 1
fi
