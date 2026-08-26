# Channel Model — OAI 5G SA Testbed (RF Simulator)

Documents the actual RF-simulator channel behavior used for the single-UE baseline and the 16-UE six-use-case experiment (`results/16UE_traffic_model_proposal.md`), referenced from that document's Phase 1 findings. Written strictly from configuration files and measurements already captured — no new simulation runs, no configuration changes were made to produce this document.

## Actual model: none active (ideal/lossless passthrough)

The gNB DU config actually launched for every stage of this project —
`~/oai/openairinterface5g/targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb-du.sa.band78.106prb.rfsim.pci0.conf`
— contains **no `channelmod` section and no `@include` of any channel-model file.** Verified by direct grep of the file: zero matches for `channelmod`.

Transport is OAI's RF simulator (`--rfsim`), which by default relays IQ samples between the DU and each UE process without applying a channel model unless one is explicitly configured. Since the DU config carries no channel-model configuration, no fading, pathloss, or noise model is applied to any UE's radio link in this testbed — every UE communicates with the gNB over what is effectively an ideal, lossless simulated channel.

## Available but unused configuration

`~/oai/openairinterface5g/targets/PROJECTS/GENERIC-NR-5GC/CONF/ue.conf` (the UE-side config) contains this line:

```
@include "channelmod_rfsimu_LEO_satellite.conf"
```

That included file exists at `~/oai/openairinterface5g/targets/PROJECTS/GENERIC-NR-5GC/CONF/channelmod_rfsimu_LEO_satellite.conf` and specifies:

```
channelmod = {
  max_chan=10;
  modellist="modellist_rfsimu_1";
  modellist_rfsimu_1 = (
    { model_name = "rfsimu_channel_enB0"; type = "SAT_LEO_TRANS"; noise_power_dB = -100; },
    { model_name = "rfsimu_channel_ue0";  type = "SAT_LEO_TRANS"; noise_power_dB = -100; }
  );
};
```

This is a **LEO-satellite transparent-transponder channel model** (`SAT_LEO_TRANS`) with a defined noise floor (`noise_power_dB = -100`) for both the gNB-side and UE-side simulated legs — i.e., a config exists on disk for simulating a satellite RF path, but:

- it is only `@include`d from `ue.conf`, not from the DU config that was actually launched in every run (single-UE baseline through the 16-UE experiment), and
- the observed measurements (below) are consistent with no channel model being in effect at all.

**Conclusion: this LEO-satellite channel model is present in the repo/config tree but was never active in any run documented in this project.** It should not be read as describing the channel actually used.

## Observed SINR/RSRP behavior (evidence for "no model active")

Per-UE DL channel measurements, read directly from each UE process's own log (`DL Chan: SSB 0 SINR ... dB RSRP ... dBm` lines):

| Run | UEs | SINR range | RSRP |
|---|---|---|---|
| Single-UE baseline (`ASSIGNMENT_REPORT.md`) | 1 | 16.2 dB (DL, one measurement) / 22.1 dB (UL) | −37.3 dBm (DL) / −41.7 dBm (UL) |
| 16-UE clean baseline (`results/16UE_clean_20260826/`) | 16 | 42.6–45.1 dB | −42 dBm (all 16) |
| Phase 4 traffic run (`multi_ue_setup/results/phase4_ran_kpis.txt`) | 16 | 42.1–45.1 dB | −42 dBm (all 16) |

In the 16-UE runs, **every UE reports the same RSRP (−42 dBm) and a tightly clustered SINR (42–45 dB) regardless of which UE it is** — there is no per-UE spread that a real or simulated propagation/fading/pathloss difference would produce. DL BLER and UL HARQ errors were 0 across all 16 UEs in every run (`0/N` attempts/errors in `phase4_ran_kpis.txt`), and post-traffic DU-side UL BLER readings (`multi_ue_setup/results/phase4_ue_rnti_bler.txt`, available for UE1–9 only — the DU did not print a `ulsch_rounds` line for UE10–16 in that run) show near-zero instantaneous BLER (0.0–0.066) with SNR clustered at 21.8–23.5 dB. All of this is the expected signature of an ideal/lossless RF-simulator link with no channel impairment applied, not of a satellite or fading channel.

## RF simulator transport parameters (actually used)

Common to CU, DU, and every UE (native UE1 and namespaced UE2–16) across the single-UE baseline and the 16-UE experiment:

- Band 78, 106 PRB, numerology 1, center frequency `-C 3450720000` (3.45072 GHz), `--ssb 516`
- gNB: CU-DU split over F1 (`gnb-cu.sa.f1.conf` / `gnb-du.sa.band78.106prb.rfsim.pci0.conf`), DU launched with `--rfsim --device.name rfsimulator`
- UEs: `nr-uesoftmodem -O ue.conf --rfsim -C 3450720000 -r 106 --numerology 1 --band 78 --ssb 516`, each namespaced UE (2–16) additionally passing `--uicc0.imsi <IMSI>` and `--rfsimulator.[0].serveraddr 10.<200+ue_id>.1.100` (the RF-simulator's own DU-connection address per UE — a transport/session parameter, not a channel-model setting)

None of these parameters configure a channel model; they configure which simulated RF carrier/PRB grid and which DU the RF simulator connects each UE to.

## Limitations

- No fading, pathloss, shadowing, or mobility model was active in any run in this project. All results (single-UE, 4/8/16-UE stages, and the Phase 4 six-use-case experiment) reflect an ideal/lossless simulated radio link, not a realistic propagation environment.
- The `SAT_LEO_TRANS` config on disk was never exercised or validated — its presence in `ue.conf` should not be read as evidence that a satellite channel was tested.
- Because no channel model differentiates UEs, per-UE SINR/RSRP spread in this project's results reflects RF-simulator/measurement-timing noise only, not real or simulated position/distance/mobility effects — any conclusions drawn from small SINR variations between UEs (e.g., 42.1 dB vs 45.1 dB) should not be attributed to channel conditions.
- Activating a real channel model (either the existing `SAT_LEO_TRANS` config, wired into the DU config it's currently absent from, or a terrestrial fading/pathloss model) would be required before any result in this project could be read as representative of a non-ideal RF environment. That has not been done and is out of scope for this document.
