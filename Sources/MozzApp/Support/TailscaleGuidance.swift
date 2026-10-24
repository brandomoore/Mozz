import SwiftUI
import MozzCore
import Darwin

struct TailscaleGuidance: View {
    let status: TailscaleGuidanceState

    @ViewBuilder
    var body: some View {
        if status.detected {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tailscale appears connected").font(.headline)
                    Text("Enter your server's Tailscale IP or MagicDNS name. Saved servers reconnect at their saved address; LAN search won't find new tailnet servers.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } else if status.failed {
            Section {
                Text("Couldn't check VPN interfaces. You can still enter your server address.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct TailscaleGuidanceState {
    private(set) var detected = false
    private(set) var failed = false

    mutating func refresh() {
        do {
            detected = TailscaleNetwork(interfaces: try appleNetworkInterfaces()).detected
            failed = false
        } catch {
            detected = false
            failed = true
            NSLog("Mozz VPN interface inspection failed: code=%ld", (error as NSError).code)
        }
    }
}

/// Only OS enumeration lives in the shell; tunnel classification is shared.
private func appleNetworkInterfaces() throws -> [NetworkInterfaceSnapshot] {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer { freeifaddrs(head) }
    var result: [NetworkInterfaceSnapshot] = []
    var cursor = head
    while let current = cursor {
        defer { cursor = current.pointee.ifa_next }
        guard let address = current.pointee.ifa_addr,
              address.pointee.sa_family == AF_INET || address.pointee.sa_family == AF_INET6 else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(address, socklen_t(address.pointee.sa_len),
                                 &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        guard status == 0 else {
            throw NSError(domain: "MozzNetworkInterface", code: Int(status))
        }
        let flags = Int32(current.pointee.ifa_flags)
        result.append(NetworkInterfaceSnapshot(
            name: String(cString: current.pointee.ifa_name),
            isUp: flags & IFF_UP != 0,
            isLoopback: flags & IFF_LOOPBACK != 0,
            addresses: [String(cString: host)]
        ))
    }
    return result
}
