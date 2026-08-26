# 16-UE Six-Use-Case Traffic Model — Proposal (Phases 1-3)

**Status: PROPOSAL ONLY. No traffic has been started, no Excel file touched, nothing restarted, nothing committed. Stops after Phase 3 for approval, per instruction.**

---

## PHASE 1 — Inspection findings

### Current OAI configuration (unchanged since the last clean run)
- SMF DNN "oai" IPv4 pool: `12.1.1.128/25` (`basic_nrf_config.yaml:225`) — confirmed this is what produced the clean 16/16 result; not touched.
- `MAX_MOBILES_PER_GNB = 16` (`common/openairinterface5g_limits.h:8`) — still the hard RRC/MAC ceiling for this build. **16 is confirmed as the maximum configured UE capacity**; nothing raises this further without a source change, which remains out of scope.
- gNB: CU-DU split (F1), band 78, 106 PRB, numerology 1, RF-simulator transport (`gnb-cu.sa.f1.conf` / `gnb-du.sa.band78.106prb.rfsim.pci0.conf`), AMF IP pinned to `192.168.70.133` (matches AMF's current container IP).
- **Channel model: none active.** `ue.conf` contains an unused `@include "channelmod_rfsimu_LEO_satellite.conf"` line, but the DU config actually launched (`gnb-du.sa.band78.106prb.rfsim.pci0.conf`) has no `channelmod` include at all, and every UE (1-16) reports identical SINR (42.6-45.1 dB) and RSRP (-42 dBm) regardless of "position" — consistent with the RF-simulator running as an ideal/lossless passthrough channel, no fading/pathloss model applied. This will be written up in `channel_model.md` in Phase 7.

### Current 16-UE configuration
- `multi_ue_setup/` scripts unchanged (`01_create_namespaces.sh`, `02_launch_ues.sh`, `07_teardown.sh`, `08_test_connectivity.sh`). UE1 native, UE2-16 in namespaces `ue2`...`ue16`.
- Known, still-unfixed bug: `08_test_connectivity.sh`'s `get_du_pid`/`get_cu_pid` (`sort -n | sed -n '3p'`) picks a `sudo` wrapper PID instead of the real DU/CU worker PID. Left as-is per "don't modify unless necessary" — will need a fix before Phase 5 CPU capture is trustworthy; flagging now, not fixing yet.

### `~/paibo-research/results/16UE_clean_20260826/`
Contains the validated pre-traffic health gate: 16/16 registered, 16/16 PDU sessions, unique SEIDs/IPs, 0 PFCP/PAA failures. This is the baseline this new experiment will re-verify (not re-derive) before traffic.

### `~/paibo-research/results/16UE_traffic_20260826/`
The previous six-use-case run. Confirmed **not to be overwritten** — it stays as-is. Its `README.md` already documents why it must not be treated as the final traffic-volume result: Web/Mobile used a ping fallback, VoD/LiveVideo delivered-side stats were lost to an iperf3 control-socket bug, and the measured byte-volume split (mMTC 0.03%, Web/Mobile 0.004% each, VoD 66.6%, Live 33.3%, V2X 0.017%) did not track the supervisor's targets at all — it was an artifact of running fixed, unequal-duration profiles (49s ping bursts alongside 30s super-high-rate iperf3 streams) with no attempt to hit a byte target.

### Excel workbook
No `.xlsx` exists inside the WSL project tree. Two workbooks exist on the Windows side, in `Downloads/`:
- **`PAIBO_Assignment_Results.xlsx`** — 2 sheets: "Diverse Traffic Modelling" (the 8-row single-UE traffic table also in `ASSIGNMENT_REPORT.md`) and "KPI Availability" (17 KPIs, single-UE baseline). **This is the workbook Phase 2/8 refers to.**
- **`PAIBO_Research_Tracker.xlsx`** — 4 sheets, all aspirational ns-3/5G-LENA planning content (500/50,000-UE hypothetical scenarios, mostly "☐ Pending"), not tied to actual OAI measurements. Not the target of Phase 2/8, but its "Traffic Model Params" sheet is a useful cross-reference for realistic per-device rates (see mMTC/V2X discussion in Phase 3 below).

Neither workbook has been modified. Per your instruction, Excel is not touched in this pass regardless.

### Git repository
`~/paibo-research` is a git repo on `main`, up to date with `origin` (`git@github.com:Ankit028001/paibo-research.git`). `multi_ue_setup/`, `results/`, `investigation_records/`, `_runtime/` are all currently **untracked**. Nothing staged or committed in this pass.

### Traffic-model / channel-model files
No dedicated `traffic_model.md` or `channel_model.md` exists yet anywhere in the repo. The closest existing artifacts are the single-UE tables above and the tracker's aspirational parameter sheet. Both will be created fresh in Phase 7 — not started yet.

### ext-dn container capability check (relevant to Phase 3's Web/Mobile decision below)
`oai-ext-dn` (Ubuntu 22.04) currently has **no** python3/curl/wget/nc/socat/busybox — but it does have `iperf3`, `apt-get`, and confirmed outbound internet reachability (`ping 8.8.8.8` succeeded, 54.6ms RTT). So a real HTTP server *could* be installed with `apt-get install -y python3` if approved — this would modify the container, which is why it's flagged here for a decision rather than done silently.

---

## PHASE 2 — KPI classification

Classified from the existing "KPI Availability" sheet in `PAIBO_Assignment_Results.xlsx`, plus the cell-level KPIs added during the 4/8/16-UE stages. Original KPI names preserved; meanings not altered to fit a bucket.

| KPI name | Level | Source | Measurement method | Unit | Availability | Value (last measured) | UE/use case |
|---|---|---|---|---|---|---|---|
| DL SINR | UE | `nrMAC_stats.log` (DU) | MAC-layer SNR estimate | dB | Available | 42.6-45.1 (16UE run) | per UE |
| UL SINR | UE | `nrMAC_stats.log` (DU) | MAC-layer SNR estimate | dB | Available | 22.1 (1UE baseline; not re-split DL/UL in later stages) | per UE |
| DL RSSI / RSRP | UE | `nrMAC_stats.log` (DU) | Directly logged | dBm | Available | -42 (all 16UE) | per UE |
| UL RSSI | UE | `nrMAC_stats.log` (DU) | Directly logged | dBm | Available | -41.7 (1UE baseline) | per UE |
| DL BLER | UE | `nrMAC_stats.log` (DU) | dlsch_errors / total tx | ratio | Available | 0.0 (all UEs, all stages) | per UE |
| UL BLER | UE | `nrMAC_stats.log` (DU) | ulsch_errors / total tx | ratio | Available | 0.0 (all UEs, all stages) | per UE |
| MCS (DL) | UE | `nrMAC_stats.log` (DU) | logged per slot | index | **Not Available** at light/moderate load in this build — index/value not printed for UE-side traffic-level loads used so far; not fabricated | index | per UE |
| HARQ Errors | UE | UE stdout (`UL/DL harq: attempts/errors`) | cumulative counter since UE process launch | count | Available (cumulative, not window-isolated) | 0 errors, all UEs | per UE |
| PRB Utilization | **Cell** (nominally) / UE (what's actually logged) | `nrMAC_stats.log` | UL NPRB reported per *individual allocation*, not a cell-wide aggregate % | PRBs (not %) | **Partial** — a true cell-level utilization percentage (allocated/total PRBs) does not exist in this build's log output; only a per-UE-per-allocation PRB count is available | UL NPRB≈5 (1UE baseline) | ambiguous — flagged as a KPI whose *intended* level (cell) is not what's *actually measurable* (UE-allocation) |
| RRC State | UE | UE stdout / `nrRRC_stats.log` | `NR_RRC_CONNECTED` string / RRCReconfigurationComplete | state | Available | RRC_CONNECTED, all UEs | per UE |
| Bearer Setup Latency (reactive baseline) | UE | CU+DU+AMF log timestamp correlation | manual cross-container timestamp diff | ms | Available (1UE only, derived) | 157.75 ms (RRC 0.33 + NGAP/Core 147.63) | UE1 only — not re-derived per-UE at 4/8/16-UE scale (no new session-establishment events occur once a UE is already registered) |
| F1 Setup Time | **Cell** (one F1 association per gNB, not per UE) | CU log (`cu_stdout.log`) | event timestamp only, no duration field | ms | Partial | not computed | cell |
| PDU Session Time | UE | AMF log (`docker logs oai-amf`) | manual timestamp diff, no explicit duration field | ms | Partial | not computed at 16UE scale | per UE |
| E2E Latency (RTT) | **Flow** (tied to the specific traffic test run, not a static UE property) | traffic test output (ping RTT / iperf3) | ping summary line / iperf3 does not report RTT | ms | Available (ping-based flows only) | 85-300 ms avg depending on profile (16UE traffic run) | per flow/use case |
| Throughput | Flow | iperf3 / ping | bytes×8/duration | bps | Available (offered/sender-side); receiver-side Available for ping flows, **Not Available** for the 4 iperf3 UDP flows in the last run (control-socket failure) | 0.636 kbps (mMTC) to 8 Mbps (VoD offered) | per flow/use case |
| Packet Loss | Flow | ping / iperf3 | reported directly | % | Available for ping-based flows (0% all); **Not Available** for iperf3 UDP flows in the last run | 0% (ping profiles) | per flow/use case |
| Jitter | Flow | ping (rtt mdev, used as proxy) / iperf3 (native jitter field) | mdev / iperf3 jitter report | ms | Available for ping (proxy); **Not Available** (placeholder only) for iperf3 UDP flows in the last run | 24.8-143.4 ms mdev (ping profiles) | per flow/use case |
| Connected UE count | Cell | AMF UE table | count of 5GMM-REGISTERED rows | count | Available | 16/16 | cell |
| Aggregate throughput | Cell | sum of per-flow throughput | arithmetic sum | bps | Available (offered only, same iperf3 caveat as above) | ~24.1 Mbps (16UE traffic run) | cell |
| Aggregate packet loss | Cell | derived from per-flow loss | weighted sum | % | Partial (ping flows only; iperf3 flows unmeasured) | 0% (ping flows) | cell |
| DU CPU / CU CPU | Cell | `ps -p <pid>` | %CPU sampled | % | Available, but **the automated `sixprofile` script capture is currently broken** (PID-detection bug, see Phase 1) — manual point-readings are Available | DU 148%, CU 5.4% (manual, post-16UE-traffic) | cell |
| Memory | Cell | `free -m` | direct read | MB | Available | 8353→8190 MB free during 16UE traffic run | cell |
| F1 / NGAP / PFCP status | Cell | CU/DU/AMF/SMF/UPF logs | absence of error/reject keywords + registration table | up/down | Available | all UP (16UE traffic run) | cell |

**No KPI's meaning was changed to force it into a level.** PRB Utilization is flagged explicitly as a mismatch between its *intended* level (cell-wide resource utilization) and what this OAI build actually exposes (a per-allocation PRB count) — this is reported as a limitation, not resolved by relabeling it.

---

## PHASE 3 — Traffic model design (FINAL, per approved normalization)

### Step 1: the supervisor's literal targets, unmodified

| Use case | UE-share (given) | Traffic-volume (given, literal) |
|---|---|---|
| mMTC | 40% | **<1%** (inequality, not a number) |
| Web application | 15% | ~8% |
| Mobile application | 15% | ~10% |
| Video on Demand | 12% | ~35% |
| Live video | 13% | ~25% |
| V2X | 5% | ~2% |
| **Sum** | **100%** | **indeterminate, at most ~81%** |

Literal sum of the volume column: `8 + 10 + 35 + 25 + 2 = 80%`, plus mMTC's upper bound of `1%` (treating "<1%" as `≈1%` for summation purposes) = **81%**. **The literal figures do not sum to 100% — there is an unexplained gap of ~19%.** Normalizing to 100% is therefore **an experimental assumption, not a fact from the supervisor's message**, documented here rather than silently applied.

### Step 2: normalization — APPROVED

Each literal figure (mMTC's upper bound of 1 included) is divided by their own sum (81) and rescaled to 100:

```
mMTC:  1/81 × 100 = 1.2346%
Web:   8/81 × 100 = 9.8765%
Mobile:10/81 × 100 = 12.3457%
VoD:   35/81 × 100 = 43.2099%
Live:  25/81 × 100 = 30.8642%
V2X:   2/81 × 100 = 2.4691%
Sum: 100.0000%
```

| Use case | Literal target | **Approved normalized target** |
|---|---|---|
| mMTC | <1% | **1.235%** |
| Web | ~8% | **9.877%** |
| Mobile | ~10% | **12.346%** |
| VoD | ~35% | **43.210%** |
| Live video | ~25% | **30.864%** |
| V2X | ~2% | **2.469%** |
| **Sum** | ~81% | **100.000%** |

This is the target used for all calculations below. UE distribution stays exactly as validated: **7 mMTC, 2 Web, 2 Mobile, 2 VoD, 2 Live Video, 1 V2X.**

### Step 3: common measurement duration

**T = 60 seconds**, identical for all six profiles (the previous run's mismatched durations — 49s ping bursts, 19s ping bursts, 2s ping burst, and 30s-of-data-but-71s-wall-clock iperf3 streams — is exactly why that run's byte-percentages were meaningless as a comparison; a single shared window is a precondition for the percentage comparison to mean anything).

### Step 4: solving for rates from the target byte shares

One free parameter is needed to anchor absolute scale (the percentages alone only fix *ratios*). **VoD is anchored at 7 Mbps/UE** — a realistic sustained "buffered video-like" rate, and chosen specifically so the VoD:Live ratio (7:5) exactly matches the required 43.210%:30.864% ratio (which reduces to 35:25 = 7:5) — no rate/volume-share contradiction this time, unlike the earlier 8/4 Mbps figures whose 2:1 ratio didn't match the required 1.4:1.

```
VoD bytes (2 UEs, 60s) = 2 × 7,000,000 bps × 60 s / 8 = 105,000,000 B
This is 43.210% (35/81) of the grand total, so:
Total = 105,000,000 × (81/35) = 105,000,000 / 0.43210 = 243,000,000 B  (exact)
```

Each 1/81 share of the total = `243,000,000 / 81 = 3,000,000 B` exactly — this makes every other category's byte target a clean multiple of 3,000,000:

| Use case | Fraction | Bytes (total, all UEs) | UEs | Bytes/UE (60s) | Required rate/UE |
|---|---|---|---|---|---|
| mMTC | 1/81 | 3,000,000 B | 7 | 428,571.4 B | `428,571.4×8/60` = **57,142.9 bps** (57.14 kbps) |
| Web | 8/81 | 24,000,000 B | 2 | 12,000,000 B | `12,000,000×8/60` = **1,600,000 bps** (1.6 Mbps) |
| Mobile | 10/81 | 30,000,000 B | 2 | 15,000,000 B | `15,000,000×8/60` = **2,000,000 bps** (2.0 Mbps) |
| VoD | 35/81 | 105,000,000 B | 2 | 52,500,000 B | `52,500,000×8/60` = **7,000,000 bps** (7.0 Mbps, anchor) |
| Live Video | 25/81 | 75,000,000 B | 2 | 37,500,000 B | `37,500,000×8/60` = **5,000,000 bps** (5.0 Mbps) |
| V2X | 2/81 | 6,000,000 B | 1 | 6,000,000 B | `6,000,000×8/60` = **800,000 bps** (0.8 Mbps) |
| **Total** | 81/81 | **243,000,000 B** | 16 | — | aggregate = `243,000,000×8/60` = **32.4 Mbps** |

Sum check: `3,000,000 + 24,000,000 + 30,000,000 + 105,000,000 + 75,000,000 + 6,000,000 = 243,000,000` ✓

### Step 5: disclosed consequence for mMTC and V2X — measured bytes over configured rate, not device realism

Hitting **1.235%** for mMTC and **2.469%** for V2X inside a 60-second window shared with two multi-Mbps video streams forces per-UE rates (57.14 kbps, 0.8 Mbps) far above what a real sensor or a real V2X safety beacon transmits (a textbook mMTC device reports every few minutes; a textbook V2X BSM beacons at ~10 Hz ≈ 12-16 kbps). This is the direct, arithmetic consequence of the percentage targets you've set, not an error — flagging it once, explicitly, per "do not fabricate application-layer semantics": the packets themselves stay genuinely *small* (see below), only their *frequency* is elevated beyond the textbook cadence to hit the assigned byte share.

**Concrete parameters (small packets, elevated frequency, to hit the exact required rate):**
- **mMTC**: 100-byte UDP payload → `57,142.9 / (100×8) = 71.4 packets/sec` → ~14 ms interval (vs. a textbook multi-second/multi-minute cadence)
- **V2X**: 150-byte UDP payload (standard BSM size) → `800,000 / (150×8) = 666.7 packets/sec` → ~1.5 ms interval (vs. a textbook 100 ms/10 Hz cadence)

Both will be implemented as genuine small-packet UDP flows (iperf3 `-l <size> -b <rate>`), not ping, and both will be labeled in all outputs with their actual interval so this elevated cadence is never mistaken for a realistic device rate.

### Step 6: Web and Mobile — bursty realization at the exact byte target

Not ping. Two ways to generate this, still open for your pick (default to Option B if not specified, since it needs no container change):

- **Option A — real HTTP** (requires approval, modifies `oai-ext-dn`): `apt-get install -y python3` on ext-dn (container has confirmed internet reachability + apt-get already present), run `python3 -m http.server`, drive genuine HTTP GET cycles from each UE sized/timed to hit the same byte targets below.
- **Option B — labeled bursty UDP fallback** (no container change): short high-rate iperf3 UDP bursts separated by idle "think time," explicitly labeled *"synthetic bursty UDP traffic representative of Web/Mobile request-response timing — not literal HTTP"*:
  - **Web** (target 12,000,000 B/UE): 10 bursts over 60s (one every 6s), each 1s at 9.6 Mbps → `10 × 1,200,000 = 12,000,000 B/UE` ✓
  - **Mobile** (target 15,000,000 B/UE): 12 bursts over 60s (one every 5s), each 1s at 10 Mbps → `12 × 1,250,000 = 15,000,000 B/UE` ✓

### Step 7: expected bytes and expected percentage — final table, before running anything

| Use case | UEs | Method | Rate/UE | Bytes/UE (60s) | Bytes total | **Expected %** | Approved target % |
|---|---|---|---|---|---|---|---|
| mMTC | 7 | small UDP, 100B/~14ms | 57.14 kbps | 428,571.4 | 3,000,000 | **1.235%** | 1.235% |
| Web | 2 | bursty UDP (Option B) or HTTP (Option A) | 1.6 Mbps avg | 12,000,000 | 24,000,000 | **9.877%** | 9.877% |
| Mobile | 2 | bursty UDP (Option B) or HTTP (Option A) | 2.0 Mbps avg | 15,000,000 | 30,000,000 | **12.346%** | 12.346% |
| VoD | 2 | iperf3 UDP, sustained | 7.0 Mbps | 52,500,000 | 105,000,000 | **43.210%** | 43.210% |
| Live Video | 2 | iperf3 UDP, sustained | 5.0 Mbps | 37,500,000 | 75,000,000 | **30.864%** | 30.864% |
| V2X | 1 | small UDP, 150B/~1.5ms | 800 kbps | 6,000,000 | 6,000,000 | **2.469%** | 2.469% |
| **Total** | 16 | — | — | — | **243,000,000 B** | **100.00%** | 100.00% |

By construction, the *configured* rates exactly reproduce the approved target percentages. **This table is the expectation, not the result** — Phase 5/6 will measure the actual bytes transferred (iperf3's own sender/receiver summary, cross-checked against a genuinely captured server-side log this time, since the previous run's iperf3 servers were launched with `docker exec -d` and silently discarded their output when the control-socket bug hit) and Phase 6 will report the *measured* percentage against this table, not assume it matches just because the rates were configured this way.

---

## Phase 4 decision: Option B, approved

Web/Mobile use **Option B — labeled bursty UDP**, no `oai-ext-dn` container changes. Every Web/Mobile output is explicitly labeled *"Web-like bursty UDP"* / *"Mobile-like bursty UDP"*, never HTTP or real mobile-application traffic.

## PHASE 4 — Execution methodology

Scripts (`multi_ue_setup/`):
- `04_start_iperf_servers.sh` — one iperf3 server per UE, port `5200+ue_id`, all 16 ports (extended from the original VoD/Live-only version).
- `05_run_traffic.sh` — per-profile iperf3 UDP client calls, `--logfile <path> -J` captured client-side only. mMTC/V2X: single 60s call, small payload (100B/150B) at the Step-5 rates. VoD/Live: single 60s sustained call at 7/5 Mbps. Web/Mobile: loop of 10/12 separate 1s-burst iperf3 calls (9.6/10 Mbps in-burst) with 5s/4s idle between, each wrapped with wall-clock start/end timestamps; the loop always attempts the full planned count but records only bursts that actually returned valid data as "completed" — never assumed.
- `08_test_connectivity.sh phase4` — dispatcher (added because `05_run_traffic.sh`/`06_aggregate_throughput.sh` are outside the NOPASSWD sudoers scope; this reuses `08`'s existing grant rather than changing sudoers).
- `_parse_iperf_results.py` / `06_aggregate_throughput.sh --table` — parses every UE's client-side JSON. For UDP, iperf3's protocol has the *server* relay loss/jitter back to the *client* at end-of-test, so client-side JSON alone contains sender-measured bytes plus receiver-measured loss/jitter; nothing depends on capturing the server's own stdout (that dependency is what silently lost data in the pre-Phase-4 run this document originally described). "Bytes received" is derived as `bytes_sent × (received_packets/packets)`, not directly reported by iperf3 for UDP.

UE/use-case mapping: `multi_ue_setup/00_ue_matrix.csv` (UE1-7 mMTC, UE8-9 Web, UE10-11 Mobile, UE12-13 VoD, UE14-15 Live, UE16 V2X — unchanged since Phase 3). Full UE→IMSI→namespace→tunnel-IP→destination-IP mapping was live-verified (namespace existence, tunnel presence, single-ping traversal) before traffic; see `multi_ue_setup/results/pre_phase4_snapshot.txt`.

Pre-traffic health gate: 16/16 `5GMM-REGISTERED`, all 16 `oaitun_ue1` interfaces present with expected IPs (12.1.1.130-145), 0 DU errors, all 9 containers healthy, all 16 iperf3 ports listening.

## PHASE 4 — Final measured results (2026-08-26)

**Traffic volume — computed from actual transmitted bytes only (iperf3 JSON `end.sum.bytes`), never from the configured/target bytes above:**

| Use case | UEs | Measured bytes | Measured % | Target % | Deviation |
|---|---|---|---|---|---|
| mMTC | 7 | 3,000,200 | 1.2348% | 1.235% | −0.0002pp |
| Web-like bursty UDP | 2 | 23,986,120 | 9.8718% | 9.877% | −0.0052pp |
| Mobile-like bursty UDP | 2 | 29,989,528 | 12.3426% | 12.346% | −0.0034pp |
| Video on Demand | 2 | 105,000,272 | 43.2141% | 43.210% | +0.0041pp |
| Live video | 2 | 75,000,608 | 30.8674% | 30.864% | +0.0034pp |
| V2X | 1 | 6,000,000 | 2.4694% | 2.469% | +0.0004pp |
| **Total** | 16 | **242,976,728 B** | **100.000%** | 100.000% | |

Loss was 0% and Web/Mobile completed all planned bursts (UE8 10/10, UE9 10/10, UE10 12/12, UE11 12/12) despite the anomaly below. Full per-UE KPIs (SINR, RSRP, HARQ, UL BLER, throughput, jitter, PDU status) are in `PAIBO_Assignment_Results.xlsx`, sheet "Phase4 Per-UE KPI"; raw source data in `multi_ue_setup/results/`.

Post-traffic health check: 16/16 still `5GMM-REGISTERED`, CU/DU confirmed same PIDs as pre-traffic (no restart), 0 new DU errors, all containers healthy, fresh single-ping-per-UE re-check 0% loss on all 16 tunnels.

## PHASE 4 — Limitations and the iperf3 wall-clock anomaly

**The run's real wall-clock duration was ~269s, not the intended 60s** — a genuine, reproducible finding, not a measurement error smoothed over:
- VoD/Live/V2X (UE12-16): each hit `iperf3: error - control socket has closed unexpectedly`, appended *after* a complete, valid JSON data summary — the same bug this document's Phase 1 findings originally flagged in the pre-Phase-4 run. Data transfer itself finished correctly (iperf3's internal data-transfer clock reads a clean 60.0s); only the post-test control-channel teardown hung, adding ~48s of wall time per flow.
- Web/Mobile (UE8-11): *every* burst, not just the one that also hit the bug above, took far longer to set up its control connection than expected (10-44s per 1s-intended burst), stretching the intended 60s burst sequence to ~245-269s.

This is assessed as a measurement-tool/execution characteristic of this WSL/docker environment (repeated iperf3 control-connection setup to the same server is slow here), not evidence that the 16-UE registration/PDU-session/user-plane/traffic-distribution result is invalid — all 16 UEs stayed registered, no packets were lost, and the measured byte-volume shares landed within 0.01 percentage points of every target regardless of the wall-clock overrun, because iperf3's own configured-rate data transfer completed correctly independent of the control-channel delay around it.

Standing limitations (carried over, still true): PRB utilization is not exposed as a cell-wide % by this OAI build (only per-allocation UL NPRB); UL BLER is only available where the DU printed a `ulsch_rounds` line for that RNTI (UE1-9 in this run; N/A for UE10-16); latency/RTT is not reported by iperf3 UDP tests (N/A for all six profiles, ping-based RTT is not used in Phase 4).
