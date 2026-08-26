# 16-UE stage — health gate FAILED, traffic phase not started

## Outcome summary

- **16/16 UEs achieved RRC/NAS registration** (5GMM-REGISTERED), at the exact
  `MAX_MOBILES_PER_GNB=16` ceiling. Radio layer (RA, RRC), F1, and NGAP were
  not the constraint -- zero failures observed at any of those layers.
- **Only 9/16 UEs achieved PDU session establishment** (UE1-8, preserved from
  prior stages, plus UE9, newly launched). **UE10-16 stalled**: SMF's own log
  confirms it received all 8 new `PDU Session Create SM Context Request`
  messages from AMF, but only progressed 1 of them (UE9's) through to an
  actual N4 Session Establishment sent to UPF. UE10-16's requests were never
  answered -- not accepted, not rejected, just never progressed, for 2.5+
  minutes of observation.
- **Per instructions, the traffic phase was never started** -- the health
  gate explicitly requires 16/16 PDU sessions established before any
  application traffic, and that condition was not met.
- **Nothing was restarted or modified.** CU, DU, AMF, SMF, UPF, and UE1-9
  were left exactly as they were at the moment of the stall. All logs and
  process state were captured at that exact point (`failure_snapshot.txt`,
  `failure_timestamp.txt`, full raw logs for AMF/SMF/UPF/NRF and all 16 UEs).

## Root cause identified: host memory exhaustion, not a code defect

This is a different failure mode from the earlier SMF-hang and SEID-collision
bugs found in the 4-UE recovery work -- SMF remained alive throughout (NRF
heartbeats continued firing normally every 10s, confirmed via `docker top`
and log timestamps), so this is not the same freeze.

Direct measurement via `ps` RSS at the moment of the stall:

| Component | RSS per instance | Count | Subtotal |
|---|---|---|---|
| `nr-uesoftmodem` (per UE) | ~692-704 MB | 16 | ~11.2 GB |
| DU (`nr-softmodem`) | 1073 MB | 1 | 1.07 GB |
| CU (`nr-softmodem`) | 159 MB | 1 | 0.16 GB |
| 5GC (9 containers, `docker stats`) | -- | 9 | ~0.59 GB (mysql dominates at 476MB) |
| **Total** | | | **~13.0 GB**, matching the observed 13.3GB `used` almost exactly |

Host total is 15.9GB (this WSL2 VM). At the moment of the stall: **761MB
free, 2331MB "available"**. At the 8-UE stage, used memory was ~7.9GB with
~7.7GB available -- comfortable headroom. Doubling to 16 UEs did not double
UE count proportionally in cost (DU/CU/5GC stayed fixed), but the 16x~700MB
UE-process cost alone pushed total usage to the edge of the VM's ceiling.

**Correlation, not yet proven as strict causation:** the PDU-session stall
began exactly when free memory dropped into the sub-1GB range. Low free
memory can plausibly cause exactly this symptom (a specific SMF internal
task/queue starved of a resource -- likely a new memory allocation, or an
HTTP/socket buffer under system-wide memory pressure -- while other,
already-established code paths like the heartbeat timer keep running fine).
This has not been root-caused at the source-code level (no core dump or
strace taken), so it should be described as strongly correlated, not
definitively proven.

## Practical capacity conclusion for this testbed

- **8 UEs: fully stable** (confirmed in the prior stage -- 8/8 registered,
  8/8 PDU sessions, 0 rejections, full traffic test completed cleanly).
- **9 UEs: registration + PDU session both succeeded** for the single
  additional UE tested at that point in the sequence.
- **16 UEs: registration succeeded for all, but PDU session establishment
  failed for 7 of the 8 newly-added UEs.** The MAX_MOBILES_PER_GNB=16
  *software* ceiling is not actually the binding constraint reached here --
  *host memory* is. On a host with more RAM, the RAN/core software stack
  shows no reason (via CPU, F1, NGAP, or RF-sim evidence) it couldn't
  support the full 16.
- This is reported as the practical scaling limit for the **current
  single-host WSL2 environment**, not a limitation of OAI's RAN/5GC software
  design itself.

## Methodology (unchanged from 4-UE/8-UE stages, for continuity)

- Same validated RF parameters throughout: `--rfsim -C 3450720000 -r 106
  --numerology 1 --band 78 --ssb 516`.
- UE5-16 launched via `multi_ue_setup/01_create_namespaces.sh` +
  `02_launch_ues.sh`, each in its own network namespace.
- UE distribution target (mMTC 7 / Web 2 / Mobile 2 / VoD 2 / Live 2 / V2X 1)
  reconciled against the already-running UE5-8 assignments from the 8-UE
  stage (Web/Mobile/VoD/Live respectively): UE9-11=mMTC (completing 7),
  UE12=Web, UE13=Mobile, UE14=VoD, UE15=Live, UE16=V2X.
- Health gate checked: 5GMM state (AMF table), PDU session state (UE + SMF
  + UPF logs), IP/SEID uniqueness, PFCP rejection count, RA/RRC/NGAP/F1
  error greps, RF-sim sync, CPU (`ps`), memory (`free -m`, per-process RSS).

## Known limitations, carried over from prior stages

- End-to-end bearer establishment latency (RRC/RA initiation -> session
  ready) is not measurable in this setup for any UE, in any stage: UE-side
  logs carry no timestamps, and DU's stdout is not accessible (permission
  denied, not redirected to a readable file). Only the narrower AMF-received
  PDU-Session-Establishment-Request -> SMF-Accept-dispatched leg is
  measurable, and that is reported separately, never conflated with the
  broader figure.
- PRB utilization has no directly-logged aggregate percentage field in this
  OAI build (only per-allocation NPRB counts) -- same gap noted in every
  prior stage, not fabricated here either.
- No traffic-level KPIs (offered load, throughput, jitter under load) exist
  for the 16-UE stage since the traffic phase never started.
