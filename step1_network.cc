

#include "ns3/applications-module.h"
#include "ns3/core-module.h"
#include "ns3/flow-monitor-module.h"
#include "ns3/internet-module.h"
#include "ns3/mobility-module.h"
#include "ns3/network-module.h"
#include "ns3/nr-module.h"
#include "ns3/point-to-point-module.h"

#include <fstream>
#include <iomanip>

using namespace ns3;
NS_LOG_COMPONENT_DEFINE("Step1Network");

static std::ofstream g_attachLog;

// Called every time a UE completes RRC connection (= bearer established)
void
NotifyConnectionEstablishedUe(std::string context,
                               uint64_t imsi,
                               uint16_t cellid,
                               uint16_t rnti)
{
    double now = Simulator::Now().GetSeconds();
    NS_LOG_INFO("[ATTACH] t=" << now << "s  IMSI=" << imsi
                              << "  cell=" << cellid
                              << "  rnti=" << rnti);
    if (g_attachLog.is_open())
        g_attachLog << std::fixed << std::setprecision(3)
                    << now << "," << imsi << ","
                    << cellid << "," << rnti << "\n";
}

int
main(int argc, char* argv[])
{
    // ── Simulation parameters ───────────────────────────────────
    uint32_t    numUes     = 50;
    double      simTime    = 10.0;   // seconds
    double      cellRadius = 500.0;  // metres
    double      freq       = 3.5e9;  // Hz  (n78 band)
    double      bw         = 20e6;   // Hz
    double      txPower    = 43.0;   // dBm
    std::string outDir     = "step1_out/";

    CommandLine cmd(__FILE__);
    cmd.AddValue("numUes",     "Number of UEs",        numUes);
    cmd.AddValue("simTime",    "Simulation time (s)",  simTime);
    cmd.AddValue("cellRadius", "Cell radius (m)",      cellRadius);
    cmd.Parse(argc, argv);

    LogComponentEnable("Step1Network", LOG_LEVEL_INFO);

    // SrsPeriodicity caps the number of simultaneously connected UEs
    // (each holds an SRS slot for the whole time it stays attached).
    // Default is 40ms/40 UEs, too low for numUes UEs that all stay
    // connected for the whole simulation; raise it accordingly.
    Config::SetDefault("ns3::LteEnbRrc::SrsPeriodicity", UintegerValue(160));

    // ── Output directory ────────────────────────────────────────
    int r = system(("mkdir -p " + outDir).c_str()); (void)r;
    g_attachLog.open(outDir + "attachments.csv");
    g_attachLog << "time_s,imsi,cellId,rnti\n";

    // ── Nodes ───────────────────────────────────────────────────
    NodeContainer gnbNodes; gnbNodes.Create(1);
    NodeContainer ueNodes;  ueNodes.Create(numUes);

    // ── Mobility ────────────────────────────────────────────────
    // gNB fixed at origin, 30m pole
    MobilityHelper gnbMob;
    gnbMob.SetMobilityModel("ns3::ConstantPositionMobilityModel");
    Ptr<ListPositionAllocator> gnbPos =
        CreateObject<ListPositionAllocator>();
    gnbPos->Add(Vector(0.0, 0.0, 30.0));
    gnbMob.SetPositionAllocator(gnbPos);
    gnbMob.Install(gnbNodes);

    // UEs: uniform random in disk, pedestrian random walk
    MobilityHelper ueMob;
    ueMob.SetPositionAllocator(
        "ns3::UniformDiscPositionAllocator",
        "rho", DoubleValue(cellRadius),
        "X",   DoubleValue(0.0),
        "Y",   DoubleValue(0.0),
        "Z",   DoubleValue(1.5));
    ueMob.SetMobilityModel(
        "ns3::RandomWalk2dMobilityModel",
        "Bounds",   RectangleValue(Rectangle(-cellRadius, cellRadius,
                                             -cellRadius, cellRadius)),
        "Speed",    StringValue(
                        "ns3::UniformRandomVariable[Min=0.5|Max=2.0]"),
        "Distance", DoubleValue(20.0));
    ueMob.Install(ueNodes);

    // ── NR Helper + EPC (exactly as in cttc-nr-demo.cc) ────────
    Ptr<NrPointToPointEpcHelper> epcHelper =
        CreateObject<NrPointToPointEpcHelper>();
    Ptr<NrHelper> nrHelper = CreateObject<NrHelper>();
    nrHelper->SetEpcHelper(epcHelper);

    // ── Band / BWP configuration ────────────────────────────────
    CcBwpCreator ccBwpCreator;
    CcBwpCreator::SimpleOperationBandConf bandConf(
        freq, bw, 1,                          // freq, BW, 1 BWP
        BandwidthPartInfo::UMi_StreetCanyon); // path loss model

    OperationBandInfo band =
        ccBwpCreator.CreateOperationBandContiguousCc(bandConf);
    nrHelper->InitializeOperationBand(&band);
    BandwidthPartInfoPtrVector allBwps =
        CcBwpCreator::GetAllBwps({band});

    // ── PHY attributes ──────────────────────────────────────────
    const uint16_t numerology = 1; // 30kHz SCS
    nrHelper->SetGnbPhyAttribute("TxPower",    DoubleValue(txPower));
    nrHelper->SetUePhyAttribute ("NoiseFigure",DoubleValue(9.0));
    nrHelper->SetGnbPhyAttribute("Numerology", UintegerValue(numerology));

    // Proportional Fair scheduler
    nrHelper->SetSchedulerTypeId(
        TypeId::LookupByName("ns3::NrMacSchedulerTdmaPF"));

    // ── Install devices ─────────────────────────────────────────
    NetDeviceContainer gnbDev =
        nrHelper->InstallGnbDevice(gnbNodes, allBwps);
    NetDeviceContainer ueDev =
        nrHelper->InstallUeDevice(ueNodes, allBwps);
    for (auto it = gnbDev.Begin(); it != gnbDev.End(); ++it)
    {
        DynamicCast<NrGnbNetDevice>(*it)->UpdateConfig();
    }
    for (auto it = ueDev.Begin(); it != ueDev.End(); ++it)
    {
        Ptr<NrUeNetDevice> ueNetDev = DynamicCast<NrUeNetDevice>(*it);
        ueNetDev->UpdateConfig();
        // Attach() normally sets this, but Attach is staggered below (see
        // comment there); set it here so the PHY's slot event loop, which
        // starts at t=0 regardless of when Attach runs, has a valid
        // subcarrier spacing to fall back on.
        ueNetDev->GetPhy(0)->SetNumerology(numerology);
    }

    // ── Internet stack on UEs ───────────────────────────────────
    InternetStackHelper inet;
    inet.Install(ueNodes);
    Ipv4InterfaceContainer ueIpIface =
        epcHelper->AssignUeIpv4Address(NetDeviceContainer(ueDev));

    for (uint32_t i = 0; i < ueNodes.GetN(); i++)
    {
        Ptr<Ipv4StaticRouting> rt =
            Ipv4StaticRoutingHelper().GetStaticRouting(
                ueNodes.Get(i)->GetObject<Ipv4>());
        rt->SetDefaultRoute(epcHelper->GetUeDefaultGatewayAddress(), 1);
    }

    // ── Attach UEs (v3.0 uses AttachToClosestEnb) ───────────────
    // Stagger attach so UEs don't attempt random access on the same
    // PRACH occasion at t=0 (simultaneous RA causes preamble collisions
    // that can trigger a spurious duplicate RA-success callback and an
    // NS_FATAL in the RRC state machine). The interval must be wide
    // enough for one UE's full RA -> RRC -> S1AP bearer-setup handshake
    // to finish before the next UE starts, or their connection
    // procedures at the eNB can race.
    const uint32_t attachIntervalMs = 100;
    for (uint32_t i = 0; i < ueNodes.GetN(); i++)
    {
        NetDeviceContainer thisUeDev(ueDev.Get(i));
        Simulator::Schedule(MilliSeconds(attachIntervalMs * i), [nrHelper, thisUeDev, gnbDev]() {
            nrHelper->AttachToClosestEnb(thisUeDev, gnbDev);
        });
    }

    // ── RRC trace — fires when bearer is established ─────────────
    Config::Connect(
        "/NodeList/*/DeviceList/*/LteUeRrc/ConnectionEstablished",
        MakeCallback(&NotifyConnectionEstablishedUe));

    // ── Remote host ─────────────────────────────────────────────
    NodeContainer remoteHostContainer;
    remoteHostContainer.Create(1);
    Ptr<Node> remoteHost = remoteHostContainer.Get(0);
    InternetStackHelper inetR; inetR.Install(remoteHostContainer);

    PointToPointHelper p2ph;
    p2ph.SetDeviceAttribute ("DataRate", StringValue("10Gbps"));
    p2ph.SetChannelAttribute("Delay",    StringValue("1ms"));
    NetDeviceContainer netDev =
        p2ph.Install(epcHelper->GetPgwNode(), remoteHost);

    Ipv4AddressHelper ipv4h;
    ipv4h.SetBase("1.0.0.0", "255.0.0.0");
    Ipv4InterfaceContainer ifaces = ipv4h.Assign(netDev);
    Ipv4Address remoteAddr = ifaces.GetAddress(1);

    Ipv4StaticRoutingHelper().GetStaticRouting(
        remoteHost->GetObject<Ipv4>())
        ->AddNetworkRouteTo(
            Ipv4Address("7.0.0.0"), Ipv4Mask("255.0.0.0"), 1);

    // ── Applications: UDP keepalive per UE ──────────────────────
    // Purpose: establish one default bearer per UE
    // We measure: how long does bearer setup take? (attachments.csv)
    uint16_t port = 1234;
    UdpServerHelper server(port);
    server.Install(remoteHost).Start(Seconds(0.5));

    for (uint32_t i = 0; i < ueNodes.GetN(); i++)
    {
        UdpClientHelper client(remoteAddr, port);
        client.SetAttribute("MaxPackets", UintegerValue(0));
        client.SetAttribute("Interval",   TimeValue(Seconds(1.0)));
        client.SetAttribute("PacketSize", UintegerValue(256));
        ApplicationContainer app = client.Install(ueNodes.Get(i));
        // Start after this UE's own attach completes (attach is staggered
        // above by attachIntervalMs per UE), plus a buffer for the bearer
        // to be ready.
        app.Start(MilliSeconds(attachIntervalMs * i) + Seconds(0.5));
        app.Stop(Seconds(simTime));
    }

    // ── Flow Monitor ─────────────────────────────────────────────
    FlowMonitorHelper fmHelper;
    Ptr<FlowMonitor>  fm = fmHelper.InstallAll();

    // ── Write initial topology ───────────────────────────────────
    std::ofstream topoLog(outDir + "topology.csv");
    topoLog << "node_type,id,x_m,y_m,z_m\n";
    Vector gp =
        gnbNodes.Get(0)->GetObject<MobilityModel>()->GetPosition();
    topoLog << "gNB,0," << gp.x << "," << gp.y << "," << gp.z << "\n";
    for (uint32_t i = 0; i < ueNodes.GetN(); i++)
    {
        Vector p =
            ueNodes.Get(i)->GetObject<MobilityModel>()->GetPosition();
        topoLog << "UE," << (i+1) << ","
                << std::fixed << std::setprecision(1)
                << p.x << "," << p.y << "," << p.z << "\n";
    }
    topoLog.close();

    // ── Run ──────────────────────────────────────────────────────
    Simulator::Stop(Seconds(simTime + 1.0));
    NS_LOG_INFO("=== Step 1: 5G Network ===");
    NS_LOG_INFO("gNBs=" << gnbNodes.GetN()
                        << "  UEs=" << numUes
                        << "  Freq=" << freq/1e9 << "GHz"
                        << "  BW=" << bw/1e6 << "MHz"
                        << "  Time=" << simTime << "s");
    Simulator::Run();

    // ── Collect and write flow stats ─────────────────────────────
    fm->CheckForLostPackets();
    Ptr<Ipv4FlowClassifier> clf =
        DynamicCast<Ipv4FlowClassifier>(fmHelper.GetClassifier());

    std::ofstream flowLog(outDir + "flow_stats.csv");
    flowLog << "flow_id,src,dst,proto,"
            << "tx_pkts,rx_pkts,lost_pkts,loss_pct,"
            << "throughput_kbps,mean_delay_ms,jitter_ms\n";

    for (auto& [id, s] : fm->GetFlowStats())
    {
        auto t   = clf->FindFlow(id);
        double dur  = simTime - 1.0;
        double tput = (s.rxBytes * 8.0) / (dur * 1e3);
        double loss = s.txPackets > 0
                      ? 100.0 * s.lostPackets / s.txPackets : 0.0;
        double dlay = s.rxPackets > 0
                      ? s.delaySum.GetMilliSeconds() / s.rxPackets : 0.0;
        double jit  = s.rxPackets > 1
                      ? s.jitterSum.GetMilliSeconds() /
                            (s.rxPackets - 1) : 0.0;

        flowLog << std::fixed << std::setprecision(3)
                << id << ","
                << t.sourceAddress << "," << t.destinationAddress << ","
                << (t.protocol == 6 ? "TCP" : "UDP") << ","
                << s.txPackets << "," << s.rxPackets << ","
                << s.lostPackets << "," << loss << ","
                << tput << "," << dlay << "," << jit << "\n";
    }
    flowLog.close();

    NS_LOG_INFO("=== Done ===");
    NS_LOG_INFO("  " << outDir << "topology.csv    — positions");
    NS_LOG_INFO("  " << outDir << "attachments.csv — bearer events");
    NS_LOG_INFO("  " << outDir << "flow_stats.csv  — KPIs");

    g_attachLog.close();
    Simulator::Destroy();
    return 0;
}
