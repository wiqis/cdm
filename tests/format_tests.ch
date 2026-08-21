// ChemicalDM — tests for formatting helpers (bytes, speed, eta, state, category).

using std::string;
using std::string_view;

@test
public func CDM_format_bytes(env : &mut TestEnv) {
    var b1 = cdm::format_bytes(0)
    if(!b1.equals_view("0 B")) { env.error("0 B"); return }

    var b2 = cdm::format_bytes(512)
    if(!b2.equals_view("512 B")) { env.error("512 B"); return }

    var b3 = cdm::format_bytes(1024)
    if(!b3.equals_view("1.0 KB")) { env.error("1024 -> 1.0 KB"); return }

    var b4 = cdm::format_bytes(1048576)
    if(!b4.equals_view("1.0 MB")) { env.error("1MB"); return }

    var b5 = cdm::format_bytes(1073741824)
    if(!b5.equals_view("1.0 GB")) { env.error("1GB"); return }

    // Negative bytes (unknown).
    var b6 = cdm::format_bytes(-1)
    if(!b6.equals_view("-1 B")) { env.error("-1 B"); return }
}

@test
public func CDM_format_speed(env : &mut TestEnv) {
    var s1 = cdm::format_speed(0)
    if(!s1.equals_view("0 B/s")) { env.error("0 B/s"); return }

    var s2 = cdm::format_speed(1024)
    if(!s2.equals_view("1.0 KB/s")) { env.error("1KB/s"); return }

    var s3 = cdm::format_speed(1048576)
    if(!s3.equals_view("1.0 MB/s")) { env.error("1MB/s"); return }
}

@test
public func CDM_format_eta(env : &mut TestEnv) {
    // Zero speed → empty.
    var e1 = cdm::format_eta(1000, 0)
    if(!e1.empty()) { env.error("zero speed -> empty"); return }

    // Zero remaining → empty.
    var e2 = cdm::format_eta(0, 1000)
    if(!e2.empty()) { env.error("zero remaining -> empty"); return }

    // 10 seconds at 100 bytes/sec.
    var e3 = cdm::format_eta(1000, 100)
    if(!e3.equals_view("10s")) { env.error("10s ETA"); return }

    // 90 seconds → 1m 30s.
    var e4 = cdm::format_eta(9000, 100)
    if(!e4.equals_view("1m 30s")) { env.error("1m30s ETA"); return }

    // 3661 seconds → 1h 1m.
    var e5 = cdm::format_eta(366100, 100)
    if(!e5.equals_view("1h 1m")) { env.error("1h1m ETA"); return }
}

@test
public func CDM_format_state(env : &mut TestEnv) {
    if(!cdm::format_state(cdm::STATE_QUEUED).equals_view("Queued")) { env.error("Queued"); return }
    if(!cdm::format_state(cdm::STATE_DOWNLOADING).equals_view("Downloading")) { env.error("Downloading"); return }
    if(!cdm::format_state(cdm::STATE_PAUSED).equals_view("Paused")) { env.error("Paused"); return }
    if(!cdm::format_state(cdm::STATE_DONE).equals_view("Done")) { env.error("Done"); return }
    if(!cdm::format_state(cdm::STATE_FAILED).equals_view("Failed")) { env.error("Failed"); return }
    if(!cdm::format_state(cdm::STATE_CANCELLED).equals_view("Cancelled")) { env.error("Cancelled"); return }
    if(!cdm::format_state(99).equals_view("Unknown")) { env.error("Unknown"); return }
}

@test
public func CDM_format_category(env : &mut TestEnv) {
    if(!cdm::format_category(cdm::Category.Other as int).equals_view("Other")) { env.error("Other"); return }
    if(!cdm::format_category(cdm::Category.Documents as int).equals_view("Documents")) { env.error("Documents"); return }
    if(!cdm::format_category(cdm::Category.Programs as int).equals_view("Programs")) { env.error("Programs"); return }
    if(!cdm::format_category(cdm::Category.Video as int).equals_view("Video")) { env.error("Video"); return }
    if(!cdm::format_category(cdm::Category.Music as int).equals_view("Music")) { env.error("Music"); return }
    if(!cdm::format_category(cdm::Category.Compressed as int).equals_view("Compressed")) { env.error("Compressed"); return }
}

@test
public func CDM_format_seconds(env : &mut TestEnv) {
    var s1 = cdm::format_seconds(0)
    if(!s1.equals_view("0s")) { env.error("0s"); return }

    var s2 = cdm::format_seconds(45)
    if(!s2.equals_view("45s")) { env.error("45s"); return }

    var s3 = cdm::format_seconds(120)
    if(!s3.equals_view("2m 0s")) { env.error("2m0s"); return }

    var s4 = cdm::format_seconds(3600)
    if(!s4.equals_view("1h 0m")) { env.error("1h0m"); return }

    var s5 = cdm::format_seconds(7384)
    if(!s5.equals_view("2h 3m")) { env.error("2h3m"); return }
}
