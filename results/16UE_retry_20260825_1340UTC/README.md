# 16-UE retry (23GiB/10 CPU) — health gate FAILED, different failure mode than before

## Pre-launch verification
- WSL memory confirmed: **23GiB** (`free -h`)
- WSL CPU confirmed: **10 cores** (`nproc`)
- Environment was fully clean before this retry: the entire previous stack
  (CU/DU/5GC/all UEs) had been wiped by an unplanned full WSL2 VM restart
  after the prior 16-UE attempt (not caused by any action taken here).

## Bring-up (all via previously-validated commands/configs, nothing changed)
- 5GC: `docker-compose -f docker-compose-basic-nrf.yaml up -d` — all 9
  healthy within 15s.
- CU/DU: same `nr-softmodem` commands and config files as every prior stage.
  F1 Setup confirmed in ~67 microseconds (CU log: Request received
  13:42:14.571970 -> Response sent 13:42:14.572037).
- UE1: same validated command, succeeded (IP 12.1.1.146).
- UE2-16: launched via `multi_ue_setup/01_create_namespaces.sh` +
  `02_launch_ues.sh`, same RF parameters as every prior stage.

## Outcome: 16/16 registered, 12/16 PDU sessions -- health gate FAILED

- All 16 UEs reached RRC_CONNECTED (DU log: "CBRA procedure succeeded (UE
  Connected)" for every one) and all 16 show 5GMM-REGISTERED in AMF's table.
- **UE1-12 established PDU sessions successfully** (IPs 12.1.1.146-157) --
  already a clear improvement over the previous attempt's 9/16, consistent
  with the added RAM/CPU headroom.
- **UE13-16 stalled.** DU's own log (now directly captured, since CU/DU were
  started with stdout redirected to a file this retry -- an improvement over
  prior stages where DU's output was inaccessible) shows its last line at
  13:44:19.220657, immediately after connecting the last UE it processed
  (RNTI 0x2b47). No further log output was produced for 4+ minutes of
  observation.

## Root cause: distinct from the prior attempt -- NOT memory pressure this time

| Signal | Prior attempt (15.9GB) | This retry (23GB) |
|---|---|---|
| Free memory at failure | 761MB | 8.1GB |
| Available memory at failure | 2.3GB | 10GB |
| Stalled component | SMF (received requests, never dispatched) | DU (log silent, CPU still active) |
| DU/CU CPU | unchanged, not implicated | DU 141%/10-core, CPU-ACTIVE but not progressing |
| Already-connected UEs | unaffected | UE1 still pingable (0% loss) but RTT elevated ~114-129ms vs typical ~40-90ms |

This is a **different failure signature**: memory is no longer the binding
constraint (confirmed healthy: 8.1GB free, 10GB available). This time DU
itself stops producing log output while continuing to consume CPU -- it is
not blocked/idle, but also not advancing new UEs past the point already
reached, and is applying some scheduling degradation to already-connected
UEs (elevated RTT). This points to something in DU's own onboarding/logging
pipeline for additional UEs beyond ~12 concurrent connections on this
single-DU, single-cell (106 PRB) configuration, distinct from the SMF/UPF
control-plane bugs found in earlier investigation.

**Not root-caused at the source level** (no strace/core dump taken, per the
instruction not to modify or debug the RAN/core beyond observation). This is
reported as a strong, reproducible correlation (2 attempts, 2 different
constraints hit near the same ~12-13 UE mark), not a proven mechanism.

## What was NOT done, per instructions
- CU, DU, AMF, SMF, UPF were not restarted or modified after the stall.
- Traffic phase was not started (health gate requires 16/16, only 12/16 passed).
- Excel workbook not touched, nothing pushed to GitHub.
- Previous 1/4/8/9-UE results and the original 16UE failure evidence
  (`results/16UE/`) are untouched -- this retry's evidence lives entirely
  under `results/16UE_retry_20260825_1340UTC/`.

## Known limitations carried over
- End-to-end bearer establishment latency and AMF->SMF SM-context latency
  were NOT computed for this stage -- the health gate failed, so per the
  established methodology latency computation was deferred (would need to
  be done separately for the 12 successful UEs if useful, but is not
  fabricated here for the 4 stalled ones).
- PRB utilization: still no aggregate percentage field available in this
  OAI build (same gap as every prior stage).
