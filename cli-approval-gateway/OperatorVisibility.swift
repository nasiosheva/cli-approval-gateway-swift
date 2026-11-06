// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

func idleHeartbeatIfDue(lastHeartbeat: inout Date, now: Date = Date(), interval: TimeInterval) -> String? {
    guard interval > 0, now.timeIntervalSince(lastHeartbeat) >= interval else { return nil }
    lastHeartbeat = now
    return "[idle] menunggu request... (\(ISO8601DateFormatter().string(from: now)))"
}
