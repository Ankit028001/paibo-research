#!/bin/bash
# Creates network namespaces ue<N1>..ue<N2> using OAI's own tools/scripts/multi-ue.sh.
# UE1 is NOT namespaced -- it is your existing native single-UE process and this
# script must never be called with range including 1. Namespaces are only for
# the 15 additional UEs (2-16) added on top of your already-working setup.
# Usage: sudo ./01_create_namespaces.sh <first_ue_id> <last_ue_id>
# Example (stage 1, adds UEs 2-4 alongside native UE1): sudo ./01_create_namespaces.sh 2 4
set -euo pipefail
[[ $(id -u) -eq 0 ]] || { echo "run as root"; exit 1; }
[[ $# -eq 2 ]] || { echo "usage: $0 <first_ue_id> <last_ue_id>"; exit 1; }
[[ $1 -ge 2 ]] || { echo "refusing: UE1 is native (not namespaced), range must start at 2"; exit 1; }

OAI_RAN=/home/ankit/oai/openairinterface5g
MULTI_UE_SH="$OAI_RAN/tools/scripts/multi-ue.sh"

for i in $(seq "$1" "$2"); do
    if ip netns list | grep -q "^ue$i "; then
        echo "namespace ue$i already exists, skipping"
        continue
    fi
    "$MULTI_UE_SH" -c "$i"
done

echo "--- namespaces now present ---"
ip netns list
