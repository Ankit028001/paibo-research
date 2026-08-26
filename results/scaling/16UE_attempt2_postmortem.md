# 16-UE Attempt 2 — Post-mortem (read-only analysis)

**Scope correction up front:** the live report issued immediately after this
attempt concluded "DU stalled, log went silent, cause unclear." This
post-mortem's deeper log analysis overturns that framing. The actual root
cause is fully identified and is **not** a DU/RF-simulator processing stall.

## 1. Confirmed observations

### 1.1 The exact root cause: SMF IP-pool exhaustion, not a DU stall

Direct log evidence, SMF stdout, identical for all four rejected UEs
(imsi ...043/044/045/046 = UE13/14/15/16):

```
[smf_app] [debug] PDU Session Type IPv4
[smf_app] [warning] Could not get PAA PDU_SESSION_TYPE_E_IPV4 for DNN oai
[smf_n1 ] [info] Create N1 SM Container, PDU Session Establishment Reject
[smf_n1 ] [debug] PDU Session Establishment Reject,, 5GSM Cause: 0x1a
```

PAA = PDU Address Allocation. SMF's address pool for DNN "oai" is
`12.1.1.144/28` (16 addresses total, ~13-14 usable) — this is the exact
subnet substituted during the earlier 4-UE SEID-collision investigation
(originally `12.1.1.128/25`, 128 addresses, narrowed to avoid an IP
collision with a stale UPF session at the time). That narrower pool was
never widened back before this 16-UE attempt. UE1-12 consumed 12 addresses
(`12.1.1.146`-`12.1.1.157`); the pool had nothing left for UE13-16.

Every one of the four rejections happened **within 2-8 seconds of that UE's
request being received by SMF** (e.g., UE13's request at 15:21:54.242,
reject encoded and sent essentially immediately in the same log burst). This
is fast, decisive, correct SMF behavior — not a hang.

**5GSM Cause `0x1a` (26 decimal) = "Insufficient resources"**, distinct from
the `0x26` (38 decimal) cause seen in the earlier SEID-collision bug — these
are two different SMF rejection paths, not the same bug recurring.

### 1.2 The DU "silence" is very likely a redirection/buffering artifact, not a stall

- DU's redirected log file stopped growing at `13:44:19.220657` (last line:
  "Adding new UE context with RNTI 0x2b47", RA success for the final UE that
  attempted RA).
- **But CU's log — also newly captured this run — continued for a further
  ~800ms**, actively processing that same UE (CU-side "UE ID 16", RNTI
  `2b47`): Security Mode Complete, UE Capability exchange,
  `NGAP_UE_CAPABILITIES_IND`, `NGAP_InitialContextSetupResponse`, and two
  RRC UL Information Transfer messages received at `13:44:20.030` and
  `13:44:20.039`. Those RRC UL Information Transfers physically carry NAS
  messages (Registration Complete, then the PDU Session Establishment
  Request) and can only reach CU by transiting DU's F1 interface — proving
  DU was still functionally alive and relaying traffic after its own log
  file stopped growing.
- DU's process state at the time of investigation was `SLl` (interruptible
  sleep, memory-locked, multi-threaded) — not `D` (uninterruptible/hung).
  CPU remained active (141% of 1000% available on 10 cores).
- This is the **first stage in this entire project where DU/CU stdout was
  redirected to a plain file** (`> file 2>&1`) rather than an interactive
  terminal (pty). glibc defaults to full block-buffering (typically 4-8KB)
  for non-tty stdout, versus line-buffering for a tty. Every prior stage
  used a pty and never exhibited this symptom.
- **This has not been proven** (no strace, no forced flush, no signal sent
  — all of which would have required touching the running process, out of
  scope for a read-only investigation). It is the best-supported hypothesis,
  not a confirmed fact.

### 1.3 RA/RRC layer: fully successful, no failures, no degradation trend

- All 16 UEs completed CBRA ("Received Ack of Msg4. CBRA procedure
  succeeded (UE Connected)") — zero RA failures, zero contention-resolution
  timeouts, zero PBCH/sync errors anywhere in the DU log.
- Inter-connection timing across all 16 RA completions: 2.0-2.7 seconds
  apart, consistently — matching the launch script's own 2-second stagger
  between UEs. **No progressive slowdown** is visible as UE count grew from
  1 to 16; the 15th and 16th connections completed just as fast as the 2nd.
- All `dlsch_errors`/`ulsch_errors` counters found in the log are `0` --
  no HARQ failures logged for any UE.
- No F1AP failure/error lines in either CU or DU log; only the expected
  Setup Request/Response at startup.
- No "cannot allocate resources for ..., rejecting UE" lines (the PUCCH/SRS
  exhaustion pattern seen in earlier, unrelated investigation) appear
  anywhere in this run's DU log.

**Conclusion on the explicit failure-mode checklist requested:**

| Failure mode | Evidence found? |
|---|---|
| Missed real-time deadlines | None found in logs; cannot fully rule out silently (see buffering caveat) |
| Scheduling delays | None visible in RA timing; UE1's ping RTT (~120ms vs typical ~40-90ms) is the one soft signal, but not tied to a specific log event |
| Frame drops | None found |
| Synchronization problems | None found (no PBCH/sync error strings) |
| RACH/RA failures | **Zero** -- all 16 UEs succeeded |
| F1AP failures | **Zero** -- only normal setup messages |
| UE-context/resource exhaustion | **Yes, but at SMF's IP pool, not at DU's UE-context table** |
| CPU starvation | Not supported -- DU at 141% of 1000% available (10 cores), i.e. ~14% aggregate utilization |

## 2. Strong correlation (not fully proven)

- The DU log's stdio-buffering-artifact explanation is strongly, but not
  conclusively, supported: it is consistent with every piece of available
  evidence (CU's continued activity, DU's healthy process state, the fast
  correct SMF-side rejections, no error strings anywhere), and no
  alternative explanation in the evidence points to an actual DU processing
  fault.
- UE1's elevated ping RTT (~120ms vs the ~40-90ms typical range seen in
  earlier stages) correlates with the period of heaviest onboarding activity
  (12-16 UEs attempting RA/RRC in quick succession) but was not isolated to
  a specific cause (could be scheduler contention, could be measurement
  timing, only 3 samples were taken).

## 3. Hypotheses (explicitly unproven)

- That DU's internal PHY/MAC real-time loop itself never missed a deadline
  is *not* something the logs can fully confirm one way or the other,
  because if the logging subsystem is genuinely the only thing affected by
  buffering, deadline-miss counters (if any exist in this codebase) would
  also be sitting in the same unflushed buffer.
- That reverting the DNN "oai" pool back to a wider subnet (e.g. the
  original `/25`) would allow all 16 UEs to obtain PDU sessions is a
  reasonable inference from the PAA-failure evidence, but has not been
  tested in this attempt (doing so would require a config change, out of
  scope for this read-only investigation and for the "do not modify
  CU/DU/core configuration" instruction already in force this session).

## 4. 8-UE vs 16-UE (attempt 2) comparison

**Important limitation:** DU/CU stdout was not captured for the 8-UE stage
(it ran in an interactive pty session, not redirected to a file) — so the
DU-side log analysis available for 16-UE attempt 2 (RA timing, F1AP
content, per-event detail) has no 8-UE equivalent to compare against
line-for-line. Only process-level metrics (`ps`, `free`) were captured for
the 8-UE stage, and are compared below.

| Metric | 8-UE run | 16-UE attempt 2 | Notes |
|---|---|---|---|
| DU CPU | 183% (unchanged before/during/after traffic) | 141% (at the point of the PDU-address failures) | Core count differs (10 cores confirmed for attempt 2; not explicitly recorded for the 8-UE run, so this is not a normalized apples-to-apples comparison) |
| CU CPU | 5.0% | 4.9% | Effectively unchanged |
| Host memory used | ~7.9-8.0GB (of 15.9GB) | ~12GB (of 23GB) | Both comfortable; attempt 2 had 8.1GB free vs 8-UE's ~7.7GB free -- similar headroom fraction despite 2x the UE count, due to the larger VM |
| DU log event volume | Not captured (pty, not redirected) | 1234 lines captured, all 16 RA sequences fully logged before the file stopped growing | N/A for comparison |
| RA/RRC failures | 0 | 0 | Identical |
| Registration success | 8/8 | 16/16 | |
| PDU session success | 8/8 | 12/16 (4 rejected for IP-pool exhaustion, a config limit, not a capacity failure) | |

## 5. Does the evidence support a DU/RF-simulator scaling limitation?

**No.** Every specific failure-mode check requested (RA failures, F1AP
failures, sync problems, frame drops, CPU starvation) came back negative.
The one anomaly (DU's log file going silent) has a well-supported, mundane
explanation (stdio buffering from a redirection method never used in prior
stages) that is not itself a functional defect, and is contradicted by
CU's continued, successful processing of the same UE's traffic afterward.
The actual, fully-evidenced failure is a **configuration artifact**: an
IP pool sized for a 4-UE experiment was never widened before a 16-UE
attempt. This is fixable without touching DU/CU/RAN code or config, and
without evidence of any underlying RAN capacity ceiling below 16 UEs on
this hardware.

## 6. Consolidated comparison — 1 / 4 / 8 / 9 / 16 (attempt 1) / 16 (attempt 2)

| Stage | UEs registered | PDU sessions established | Health gate result | DU CPU | CU CPU | Host mem used / total | Mem free | WSL RAM/CPU | Failure point (if any) |
|---|---|---|---|---|---|---|---|---|---|
| 1 UE (original baseline) | 1/1 | 1/1 | N/A (single-UE) | not recorded in this format | not recorded | not recorded | not recorded | not recorded | none |
| 4 UE | 4/4 | 4/4 (after SEID-collision fix) | PASS | 184% | 5.0% | ~4.9-5.0GB / 15.9GB | ~10.6GB | ~15.9GB / not recorded | none (post-fix) |
| 8 UE | 8/8 | 8/8 | PASS | 183% | 5.0% | ~7.8-8.0GB / 15.9GB | ~7.7-7.8GB | ~15.9GB / not recorded | none |
| 9 UE (first new UE of 16-attempt-1 batch) | 9/9 | 9/9 | PASS (partial batch) | 181-184% | 5.0% | included in 16-attempt-1 figures below | -- | ~15.9GB | none -- sole success before UE10-16 stalled in the same batch |
| 16 UE, attempt 1 | 16/16 | 9/16 | **FAIL** | 181% (unchanged) | 5.0% (unchanged) | 13.3GB / 15.9GB | 761MB | ~15.9GB | SMF received all 7 remaining PDU requests but only progressed 1; strongly correlated with severe memory pressure (761MB free) |
| 16 UE, attempt 2 | 16/16 | 12/16 | **FAIL** | 141% (10-core) | 4.9% | ~12GB / 23GB | ~8.1GB | 23GiB / 10 CPU (confirmed) | **Root-caused**: SMF's DNN "oai" IP pool (narrowed to /28 = 16 addrs during the 4-UE fix) exhausted after 12 sessions -- "Could not get PAA" -> reject cause 0x1a for UE13-16. Not a DU/RF-sim capacity limit. |

### Interpretation

- Radio/RRC/F1/NGAP layers have shown **zero failures at any UE count
  tested, up to and including all 16 UEs simultaneously attempting RA**.
- The two 16-UE failures had **two different, unrelated causes**:
  attempt 1 = host memory exhaustion at the 15.9GB WSL limit (SMF received
  requests but stalled progressing them); attempt 2 = an SMF IP-pool
  configuration left over from an earlier, unrelated fix, unconnected to
  the memory/CPU upgrade.
- Neither attempt's evidence supports a DU or RF-simulator processing
  ceiling below 16 UEs on this hardware. The practical blocker each time
  was configuration/resource-sizing, not RAN software or real-time
  performance.
- A genuinely conclusive 16-UE health-gate result would require: (a) the
  DNN "oai" pool widened back to accommodate at least 16 addresses (a
  config change, not yet made, out of scope for this read-only analysis),
  and (b) a re-run under the current 23GiB/10-CPU allocation to confirm
  clean 16/16 PDU session establishment.
