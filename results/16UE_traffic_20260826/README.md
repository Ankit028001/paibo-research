# 16-UE Six-Use-Case Differentiated Traffic Experiment

Timestamp: 2026-08-25 ~19:58-20:01 UTC (wall-clock span of the concurrent test: 71.3s; see `raw/*.txt.time`)

## Pre-conditions (verified before traffic)
- 16/16 UEs registered, 16/16 PDU sessions established (clean health-gate result carried over from `16UE_clean_20260826/`)
- All 16 UE tunnel IPs re-verified: UE1=12.1.1.130 (native netns), UE2-16=12.1.1.131-145 (one per `ueN` netns)
- ext-dn container IP re-verified at traffic time: `192.168.70.130` (had changed from `.131` used at an earlier stage -- containers are not statically pinned in this compose file, so this is re-checked every stage, not assumed)
- 4 iperf3 UDP servers started on ext-dn for the VoD/LiveVideo profiles: ports 5207/5214 (VoD, UE7/UE14), 5208/5215 (LiveVideo, UE8/UE15)
- Pre-traffic CPU/mem snapshot recorded in `pre_traffic_snapshot.txt`

## UE-to-use-case mapping (supervisor's rounded 16-UE realization)
- mMTC: UE1,2,3,4,9,10,11 (7 UEs)
- Web: UE5,12 (2 UEs)
- Mobile: UE6,13 (2 UEs)
- VoD: UE7,14 (2 UEs)
- Live Video: UE8,15 (2 UEs)
- V2X: UE16 (1 UE)

## Traffic methods actually used (exact, not idealized)
| Use case | Method | Params |
|---|---|---|
| mMTC | ICMP ping | 50-byte payload, 1s interval, 50 packets |
| Web | **FALLBACK: ICMP ping** | 56-byte default payload, 20 packets, default 1s interval |
| Mobile | **FALLBACK: ICMP ping** | 56-byte default payload, 20 packets, default 1s interval |
| VoD | iperf3 UDP client | `-b 8M -t 30`, per-UE source-bound |
| Live Video | iperf3 UDP client | `-b 4M -t 30`, per-UE source-bound |
| V2X | ICMP ping | 128-byte payload, 10ms requested interval, 100 packets |

**Web and Mobile were not real HTTP/application-layer traffic.** No HTTP or other application server was ever stood up on `oai-ext-dn` in this project (confirmed limitation carried over from the 1-UE baseline methodology). Ping was used as an explicitly-labeled fallback so that Web/Mobile UEs still generated some differentiated traffic pattern (short burst, default packet size) rather than being skipped. This is a methodological limitation, not a hidden substitution.

## Result 1: UE health post-traffic
**All 16 UEs remained healthy.** Post-traffic AMF UE table shows 16/16 in `5GMM-REGISTERED` state. Zero new error/fail/reject log lines appeared in the AMF, SMF, or UPF containers during or after the traffic window. All 36 `nr-uesoftmodem` processes (UE1 native + UE2-16 namespaced, including per-UE child threads) were still running after the test. No UE or core component failure occurred; no restart of CU/DU/5GC/UEs was necessary or performed.

## Result 2: Per-UE KPIs
See `per_ue_kpis.csv`. Highlights:
- SINR 42.6-45.1 dB, RSRP -42 dBm for all 16 UEs (ideal RF-simulator channel, as in every prior stage)
- HARQ error counts are 0 for every UE (format logged is `attempts/errors`) -- but these are **cumulative since UE launch**, not isolated to the 71s traffic window; window-isolated HARQ delta is NOT_MEASURABLE without pre/post timestamped log diffing, which was not performed
- BLER is derived as 0% from the same cumulative HARQ counters (0 errors / N attempts) -- same cumulative-not-windowed caveat applies
- MCS is not logged anywhere in this OAI build's UE stdout, consistent with every prior stage -- recorded as NOT_LOGGED, not fabricated
- Bearer/PDU-session setup latency was not re-measured in this traffic run (all 16 sessions were already established from the pre-traffic health gate; no new establishment events occurred)
- **V2X anomaly, reported as observed:** the V2X profile (128B/10ms, intended to be the lowest-latency profile) actually showed the *highest* average RTT (300.4 ms) and RTT variability (143.4 ms mdev) of any ping-based profile, versus ~85-114 ms average RTT for mMTC/Web/Mobile. ping itself flagged `pipe 34` (34 unacknowledged probes in flight), meaning the requested 10ms send interval was faster than the round-trip time actually being achieved under 16-UE concurrent-flow contention on the shared RF-simulator/DU. This is reported as-is; it was not smoothed over or excluded.
- **VoD/LiveVideo (4 UEs) delivered-side metrics are NOT_MEASURABLE.** Each of the 4 iperf3 UDP clients printed `iperf3: error - control socket has closed unexpectedly` after completing its 30-second data send. The client-side "receiver" summary line came back as `0.00 Bytes / 0.00 bits/sec / 0.000 ms jitter / 0/0 datagrams` -- this is an **empty placeholder**, not a measured zero, because the server never returned its final report over the control channel before the socket closed. The iperf3 servers were started with `docker exec -d`, which discards their stdout, so no independent server-side confirmation could be recovered after the fact either. Only the **sender-side offered** rate/bytes are confirmed measurements for these 4 UEs; true delivered throughput, delivered packet loss, and delivered jitter for VoD/LiveVideo are NOT_MEASURABLE with this run's setup.
- Each VoD/LiveVideo iperf3 client process ran for ~71s wall-clock (not the intended ~30s) because it hung waiting on the failed control-channel handshake after finishing its 30s of actual data transfer -- confirmed via the `.time` sidecars in `raw/`. The 30 seconds of actual UDP data transfer itself is not in question (visible in each file's 6 interval reports); only the post-transfer control exchange failed.

## Result 3: Aggregate cell-level KPIs
See `cell_kpis.csv`. Highlights:
- 16/16 UEs connected; F1, NGAP, and PFCP all confirmed UP throughout
- Aggregate offered throughput across all 16 concurrent flows: **~24.13 Mbps** (~99.97% of this contributed by the 4 VoD/LiveVideo iperf3 flows)
- Ping-based profiles (mMTC/Web/Mobile/V2X, 12 UEs): 0% loss confirmed at the ICMP layer for every one of them
- iperf3-based profiles (VoD/LiveVideo, 4 UEs): loss NOT_MEASURABLE (see above)
- PRB utilization: NOT_AVAILABLE (not exposed in this OAI build's log output, consistent with every prior stage of this project)
- **DU/CU CPU: a script bug was found and is being reported, not hidden.** `08_test_connectivity.sh`'s `sixprofile` mode auto-detects the DU/CU PIDs via `pgrep -f ... | sort -n | sed -n '3p'`, which in this run's process tree picked the `sudo` wrapper PID (0% CPU) instead of the real worker PID -- so the automated BEFORE/DURING/AFTER CPU readings in `raw/cpu_timeline.txt` are all incorrectly 0.0% for both DU and CU. A corrected, manually-verified point-in-time reading taken shortly after the test (against the confirmed real worker PIDs) showed **DU 148% / CU 5.4%** (of 1000% max on this 10-core host), consistent with every other DU/CU CPU measurement across this entire project. The DURING/AFTER-specific values from the actual 71-second traffic window itself were not recaptured and are recorded as NOT_CAPTURED rather than backfilled with an assumption. Memory readings in the same timeline file are unaffected by this bug and are valid (8353 -> 8349 -> 8190 MB free of 24033 MB total).
- **This script bug has not yet been fixed in `08_test_connectivity.sh`** (left unmodified for this run; flagging for a future stage).

## Result 4: Actual vs target traffic-volume percentages
See `traffic_volume_summary.csv` for full numbers. **The measured traffic-volume-by-bytes percentages do not match the supervisor's target percentages, and this is expected, not a fabrication:**

| Use case | UE-share target | UE-share actual | Volume target | Volume actual (offered bytes) |
|---|---|---|---|---|
| mMTC | 40% | 43.75% | <1% | 0.030% |
| Web | 15% | 12.5% | ~8% | 0.004% |
| Mobile | 15% | 12.5% | ~10% | 0.004% |
| VoD | 12% | 12.5% | ~35% | 66.62% |
| Live Video | 13% | 12.5% | ~25% | 33.32% |
| V2X | 5% | 6.25% | ~2% | 0.017% |

The UE-share (count) percentages track the supervisor's target reasonably closely (they are the rounded 16-UE realization, as instructed). **The traffic-volume-by-bytes percentages do not**, because the actual byte volume generated by each profile in this run was driven entirely by the traffic-generation parameters chosen (ping packet count/size vs iperf3 duration/bitrate), not by any attempt to hit the target volume shares:
- mMTC/Web/Mobile/V2X (ping-based, 12 UEs total) generated a combined ~50 KB across the whole test -- negligible next to two 30-second, multi-Mbps iperf3 streams
- VoD+LiveVideo (4 UEs, iperf3) generated ~90 MB combined and dominate the volume distribution (99.95% of total offered bytes) simply because they ran a sustained high-bitrate stream for the full window while the other profiles sent a handful of small packets

Matching the target volume percentages exactly would have required either much longer/higher-rate ping-based flows for Web/Mobile/mMTC/V2X, or a shorter/lower-rate VoD/LiveVideo flow -- neither was done, since the instruction was to run the differentiated methods as specified (low-rate periodic for mMTC/V2X, bursty small-request for Web/Mobile, sustained 8/4 Mbps for VoD/Live) rather than to reverse-engineer parameters to hit a volume target. This gap is reported directly rather than being closed by adjusting the numbers.

## Result 5: Limitations and fallback methods used (consolidated)
1. Web and Mobile traffic used an ICMP ping fallback, not real HTTP/application-layer traffic -- no HTTP server exists on `oai-ext-dn` in this testbed.
2. VoD and LiveVideo delivered-side throughput, loss, and jitter are NOT_MEASURABLE for this run: the iperf3 control channel closed before the server's final report reached the client, and the server (run via `docker exec -d`) had no captured stdout to recover after the fact. Only sender-side offered throughput/bytes are confirmed.
3. End-to-end bearer/PDU-session establishment latency was not applicable to this run (no new sessions were established during traffic; all 16 were already up from the health gate).
4. MCS is not logged anywhere in this OAI build and is recorded as NOT_LOGGED throughout.
5. BLER/HARQ-error counts are cumulative since each UE's process launch, not isolated to the 71-second traffic window.
6. PRB utilization is not exposed in this build's DU/CU log output.
7. The `08_test_connectivity.sh` sixprofile mode's automated DU/CU CPU PID-detection has a bug (picks a `sudo` wrapper PID instead of the real worker PID), producing incorrect 0.0% CPU readings in `raw/cpu_timeline.txt`. A corrected manual reading is reported separately in `cell_kpis.csv`; the script itself was left unmodified for this run.
8. The V2X profile's requested 10ms ping interval was not actually achievable given the measured ~300ms RTT under 16-UE concurrent load; actual inter-packet spacing was effectively RTT-bound, not 10ms.
9. Traffic-volume-by-bytes percentages do not match the supervisor's target distribution (see Result 4) -- this is a direct consequence of the chosen per-profile traffic parameters, not an error to be corrected by adjusting reported figures.

No CU/DU/5GC/UE component was restarted or modified during this experiment. The Excel workbook was not modified and nothing was pushed to GitHub, per instruction.
