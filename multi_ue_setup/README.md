# Multi-UE staged ramp (16-UE ceiling, 6 use-case proportions)

Nothing here has been run. Nothing will touch your existing CU, DU, 5GC, or
native UE1 process -- see "Safety guarantees" below.

## Why 16 UEs

`MAX_MOBILES_PER_GNB = 16`, `common/openairinterface5g_limits.h:8`, at your
currently checked-out commit `2b69bde6aeafe892cda1531a0f0cbba2e37792cd`
(branch `develop`). This file has no local modifications (`git status` is
clean on it), and `git blame` traces the line to upstream commit
`721b8e9d9f2` (francescomani, 2022-12-13) -- it is not something introduced
by your local changes. This array sizes the DU's connected-UE list
(`nr_mac_gNB.h:868`: `connected_ue_list[MAX_MOBILES_PER_GNB + 1]`), so it is
the hard ceiling on RRC/MAC-connected UEs per gNB-DU for this build.

Separately, the RF simulator transport itself supports far more concurrent
client connections (`MAX_FD_RFSIMU = 250`, `radio/rfsimulator/simulator.cpp:55`)
-- so 16 is the MAC-layer ceiling, not a transport bottleneck. No source
change is needed or planned: 16 already comfortably covers every use-case
bucket below (largest bucket is 7).

## Safety guarantees (per your instructions)

- **CU, DU, 5GC, and UE1 are never started, stopped, or reconfigured by any
  script here.** `00_preflight_check.sh` only reads process/container state
  and refuses to continue if they are not already up the way you already run
  them -- it never brings anything up itself.
- **No OAI config file is edited.** `gnb-cu.sa.f1.conf`,
  `gnb-du.sa.band78.106prb.rfsim.pci0.conf`, and `ue.conf` already carry your
  local customizations (PLMN 208/95, AMF IP, IMSI/key/opc, `utc_time`
  logging) -- confirmed via `git diff`, untouched by anything here. UEs 2-16
  only add CLI overrides (`--uicc0.imsi`, `--rfsimulator.[0].serveraddr`,
  `--telnetsrv.listenport`) on top of the same `ue.conf`.
- **UE1 stays native.** It is not moved into a namespace. Only UE2-16 run in
  namespaces (`ue2`...`ue16`, via OAI's own `tools/scripts/multi-ue.sh`).
  `01_create_namespaces.sh`, `02_launch_ues.sh`, and `07_teardown.sh` all
  refuse to run against UE1.
- **No source code changes.** Nothing here touches `openairinterface5g/`
  source, only reads it (for the proof above) and calls its existing binaries
  with CLI flags.
- **Nothing is committed or pushed.** `multi_ue_setup/` is currently
  untracked in `paibo-research`. It stays that way until the experiment is
  run and validated.

## Final UE matrix (`00_ue_matrix.csv`)

UE-count proportions (used for this matrix) and traffic-volume proportions
(your original message, kept for reference only) are **not** mixed --
rounding below uses only the UE-count % column, largest-remainder method,
summing exactly to 16:

| Use case | UE-count % (given) | UEs (this test) | Traffic-volume % (given, NOT used for rounding) |
|---|---|---|---|
| mMTC | 40% | 7 (ue1-7) | <1% |
| Web application | 15% | 2 (ue8-9) | ~8% |
| Mobile application | 15% | 2 (ue10-11) | ~10% |
| Video on Demand | 12% | 2 (ue12-13) | ~35% |
| Live video | 13% | 2 (ue14-15) | ~25% |
| V2X | 5% | 1 (ue16) | ~2% |
| **Total** | **100%** | **16** | ~101%* |

\* traffic-volume percentages as given sum to ~101% (rounding in the
original figures) -- reproduced as given, not adjusted.

IMSIs 208950000000031-046 are pre-provisioned in
`oai-cn5g-fed/docker-compose/database/oai_db2.sql` with identical key/opc --
no database changes needed.

## Exact commands (what `02_launch_ues.sh` runs, per UE)

Example expansion for UE 5 (mMTC, namespace `ue5`):

```bash
msin=$(printf "%010d" 35); imsi="20895${msin}"   # -> 208950000000035
ip netns exec ue5 ./nr-uesoftmodem \
    -O /home/ankit/oai/openairinterface5g/targets/PROJECTS/GENERIC-NR-5GC/CONF/ue.conf \
    --rfsim -C 3450720000 -r 106 --numerology 1 --band 78 --ssb 516 \
    --uicc0.imsi 208950000000035 \
    --rfsimulator.[0].serveraddr 10.205.1.100
```

(`10.205.1.100` = the namespace's host-side veth address created by
`multi-ue.sh -c 5`; NAT'd to loopback where the DU's rfsim server listens,
per `doc/NR_SA_Tutorial_OAI_multi_UE.md`.) All 16 launch lines follow this
same pattern with `imsi` and `serveraddr` computed from `ue_id` -- see
`02_launch_ues.sh` for the loop. (`--telnetsrv`/`--telnetsrv.listenport` were
dropped after Stage 1 showed this build rejects `--telnetsrv.listenport` as an
unknown option and force-exits -- see Stage 1 results below.)

## Staged ramp (4 -> 8 -> 16), with full health gate at each step

UE1 (native) plus the listed namespaced UEs:

```bash
# Preflight -- confirms CU/DU/5GC/UE1 already up; starts/stops nothing
./00_preflight_check.sh

# Stage 1: UE1 (native, already running) + UEs 2-4 (namespaced)
sudo ./01_create_namespaces.sh 2 4
sudo ./02_launch_ues.sh 2 4
sudo ./03_check_stage_health.sh 1 4

# Stage 2: + UEs 5-8
sudo ./01_create_namespaces.sh 5 8
sudo ./02_launch_ues.sh 5 8
sudo ./03_check_stage_health.sh 1 8

# Stage 3: + UEs 9-16
sudo ./01_create_namespaces.sh 9 16
sudo ./02_launch_ues.sh 9 16
sudo ./03_check_stage_health.sh 1 16
```

`03_check_stage_health.sh` checks, every stage, before proceeding:
1. Per-UE registration (PDU session established, from each UE's own log;
   UE1 checked via its own `oaitun_ue1` interface).
2. DU log: frame drops / sync loss / timing errors.
3. DU log: failed UE contexts, RA failures, resource-allocation rejections
   (real OAI log strings, e.g. `"RA Procedure failed"`,
   `"cannot allocate resources for PUCCH0, rejecting UE"` -- grepped from
   `openair2/LAYER2/NR_MAC_gNB` and `F1AP` source, not guessed).
4. Host CPU load average and memory (`free`, `/proc/loadavg`, 12 cores /
   15GB available in this VM) plus per-process CPU% for the RAN binaries.

If any check regresses at a given stage, stop there -- that stage's UE count
is the practical capacity, not 16, and the matrix above should be
recomputed against that smaller N (still using only the UE-count %
column).

## Traffic and KPI collection

```bash
./04_start_iperf_servers.sh              # one iperf3 server per VoD/Live UE, inside oai-ext-dn
sudo ./05_run_traffic.sh 1 16            # each UE's profile-specific test, concurrently
./06_aggregate_throughput.sh             # per-UE throughput + summed aggregate cell throughput
```

### KPI tiers

- **Per-UE** (one value per connected UE, tied to its radio/NAS context,
  not to a specific traffic test): DL/UL SINR, DL/UL RSSI, DL/UL BLER, MCS
  (DL), HARQ errors, RRC state, Bearer Setup Latency, PDU Session Time.
- **Per-flow** (tied to the specific traffic test a UE is running; a UE
  could in principle run more than one flow): E2E Latency (RTT), per-UE
  Throughput, Packet Loss, Jitter.
- **Cell-level / aggregate** (a property of the shared cell resource or
  the whole UE population, not attributable to any one UE or flow): PRB
  Utilization, F1 Setup Time, and **Aggregate Cell Throughput** (sum of all
  per-UE/per-flow throughputs -- computed by `06_aggregate_throughput.sh`).

## Teardown (UE2-16 only)

```bash
sudo ./07_teardown.sh 2 16
```

Never touches UE1, CU, DU, or the 5GC -- those remain exactly as you left
them.
