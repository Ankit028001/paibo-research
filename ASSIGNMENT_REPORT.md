# OAI 5G SA Testbed — Assignment Report

## Task 1 — CU-DU Architecture

```
  UE                DU               CU            AMF / SMF / UPF          Internet
(nr-uesoftmodem) (nr-softmodem)  (nr-softmodem)      (OAI 5G Core)
      |                |                |                   |                    |
      |--- RF (rfsim) ->|                |                   |                    |
      |                |--- F1 (SCTP) -->|                   |                    |
      |                |                |--- NGAP (SCTP) --->|                   |
      |                |                |                   |--- N6 / GTP-U ---->|
      |<====================== PDU Session (UE IP 12.1.1.130) ======================>|
```

- **F1 interface**: confirmed — DU log recorded `received F1 Setup Response from CU cu-rfsim`.
- **NGAP/SCTP**: confirmed — SCTP association `ESTABLISHED` between CU (192.168.70.129) and AMF (192.168.70.134:38412); `NGSetupResponse` received from AMF; AMF's own gNB table shows `cu-rfsim` as **Connected**.
- **PDU session**: confirmed — `PDU Session Establishment Accept` received; AMF's own UE table shows IMSI `208950000000031` in state `5GMM-REGISTERED`.
- **UE IP**: `12.1.1.130` (assigned on the `oaitun_ue1` interface).

## Task 2 — Traffic Profiles

Eight heterogeneous traffic profiles were evaluated over the OAI 5G SA testbed, including UDP/TCP application workloads and ICMP-based representative profiles.

| Traffic Type | Test Method | Packets/Data | Loss | Throughput (Mbps) | Jitter (ms) | Notes |
|---|---|---|---|---|---|---|
| URLLC | ICMP representative profile (ping) | 100 sent / 100 recv | 0.00% | 0.078 | 2.482 | avg RTT 11.548 ms |
| eMTC/eMBB\* | ICMP representative profile (ping) | 50 sent / 50 recv | 0.00% | 0.819 | 1.886 | avg RTT 14.901 ms |
| mMTC | ICMP representative profile (ping) | 50 sent / 50 recv | 0.00% | 0.0003 | 2.516 | avg RTT 13.634 ms |
| V2X | ICMP representative profile (ping) | 100 sent / 100 recv | 0.00% | 0.039 | 3.040 | avg RTT 13.035 ms |
| Live Video | Actual UDP workload (iperf3) | 12500 sent / 12499 recv | 0.00% | 4.00 | 2.687 | 4 Mbps target, 30s sustained |
| VoD | Actual UDP workload (iperf3) | 21428 sent / 21428 recv | 0.00% | 8.00 | 1.776 | 8 Mbps target, 30s sustained |
| File Transfer | Actual TCP workload (iperf3) | N/A (TCP, byte-oriented) | 0.00%\*\* | 46.8 | N/A | 493 retransmits in one 5s interval, otherwise clean |
| Web/Mobile | Ping fallback — no HTTP server on ext-dn | 20 sent / 20 recv | 0.00% | 0.004 | 1.988 | avg RTT 14.326 ms |

\* Tested as eMBB profile; eMTC would use lower rate and longer intervals.

\*\* TCP guarantees application-level delivery, so 0% reflects no data loss visible to the application. The 493 retransmits are the more meaningful link-quality signal for this test and are reported as a note rather than folded into loss_pct.

iperf3 tests used `ext-dn` (192.168.70.131) as the server, reached through `oaitun_ue1`. min/avg/max RTT are not reported for the iperf3 rows because iperf3 does not measure round-trip latency (UDP mode reports jitter; TCP mode reports retransmits) — those cells are intentionally left blank rather than estimated.

## Task 3 — KPI Availability

OAI does not expose bearer setup time as a single directly available KPI in the current logging configuration; it must be derived from timestamped RRC/NGAP/F1AP events.

| KPI Name | OAI Source | Status | Value Observed | PAIBO Relevance |
|---|---|---|---|---|
| DL SINR | DU logs (nrMAC_stats.log) | Available | 16.2 dB (MAC-layer SNR estimate; RRC-level SINR field reports "not provided" in nrRRC_stats.log) | Core |
| UL SINR | DU logs (nrMAC_stats.log) | Available | 22.1 dB | Core |
| DL RSSI | DU logs (nrMAC_stats.log) | Available | -37.3 dBm | Core |
| UL RSSI | DU logs (nrMAC_stats.log) | Available | -41.7 dBm | Core |
| DL BLER | MAC stats (nrMAC_stats.log) | Available | 0.00000 | Core |
| UL BLER | MAC stats (nrMAC_stats.log) | Available | 0.00000 | Core |
| MCS DL | MAC stats (nrMAC_stats.log) | Available | MCS index 0 (Qm 2, low modulation order given light traffic load) | Secondary |
| PRB utilization | MAC stats (nrMAC_stats.log) | Partial | UL NPRB 5 reported per allocation; no DL PRB count and no utilization percentage (allocated/total) field exists in this log | Core |
| HARQ errors | MAC stats (nrMAC_stats.log) | Available | 0 errors (dlsch_errors 0, ulsch_errors 0; retransmission rounds 2-4 all 0/0) | Core |
| RRC state | RRC stats (nrRRC_stats.log) | Available | PDU session ID 1 status established (implies RRC_CONNECTED); literal "RRC_CONNECTED" string not printed in this file | Secondary |
| Bearer setup time | RRC stats (nrRRC_stats.log) | Available (derived) | 157.75ms total (RRC: 0.33ms + NGAP/Core: 147.63ms), derived by enabling utc_time logging and correlating CU+DU+AMF timestamps | Core |
| F1 setup time | CU logs (/tmp/cu.log) | Partial | F1 Setup Response is logged as a timestamped event, not a duration; must be derived manually by diffing log timestamps | Secondary |
| PDU session time | AMF logs (docker logs oai-amf) | Partial | PDU session establishment messages are individually timestamped; no explicit duration field, must be derived manually | Core |
| E2E latency | ping tests (kpi_summary.csv) | Available | avg RTT 11.5-14.9 ms across URLLC/eMBB/mMTC/V2X tests | Core |
| Throughput | ping tests (kpi_summary.csv) | Available | 0.0003-46.8 Mbps (iperf3 TCP: 46.8 Mbps; iperf3 UDP: 4-8 Mbps; ICMP estimated: 0.0003-0.82 Mbps) | Core |
| Packet loss | ping tests (kpi_summary.csv) | Available | 0.00% across all 4 traffic tests (300 packets total, 0 lost) | Core |
| Jitter | ping tests (kpi_summary.csv) | Available | 1.9-3.0 ms (RTT mdev) across the 4 tests | Core |

**Bearer Setup Latency Baseline (Derived):** By enabling UTC timestamp logging in OAI (utc_time option in CU and DU config) and correlating events across CU, DU, and AMF logs, bearer setup latency was derived as 157.75ms — dominated by Core-side NGAP signaling (147.63ms) rather than the radio interface (0.33ms). Full derivation methodology is in kpi_results/bearer_setup_latency.txt.

## Limitations

- Single UE only — simultaneous multi-UE not yet demonstrated.
- Web/Mobile fell back to ping — ext-dn has no HTTP server.
- Bearer setup time requires manual log timestamp derivation.
- ICMP profiles represent traffic characteristics, not actual application protocols.
