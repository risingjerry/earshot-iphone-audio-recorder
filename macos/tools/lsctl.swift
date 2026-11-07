import Foundation
let cmd = CommandLine.arguments.dropFirst().joined(separator: " ")
// CICADA_DEBUG_CHANNEL picks one running copy (see DevBuild.debugChannel).
let channel = ProcessInfo.processInfo.environment["CICADA_DEBUG_CHANNEL"].map { $0.isEmpty ? "" : "." + $0 } ?? ""
DistributedNotificationCenter.default().postNotificationName(Notification.Name("dev.earshot.mac.debug" + channel), object: cmd, userInfo: nil, deliverImmediately: true)
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
