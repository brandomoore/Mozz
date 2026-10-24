import Foundation

/// Platform shells supply interface data; every client uses the same heuristic.
public struct NetworkInterfaceSnapshot: Codable, Sendable, Equatable {
    public var name: String
    public var isUp: Bool
    public var isLoopback: Bool
    public var addresses: [String]

    public init(name: String, isUp: Bool, isLoopback: Bool, addresses: [String]) {
        self.name = name
        self.isUp = isUp
        self.isLoopback = isLoopback
        self.addresses = addresses
    }
}

public struct TailscaleNetwork: Codable, Sendable, Equatable {
    /// A tunnel address is evidence, not proof of Tailscale or peer reachability.
    public let detected: Bool

    public init(interfaces: [NetworkInterfaceSnapshot]) {
        detected = interfaces.contains { interface in
            let name = interface.name.lowercased()
            let tunnel = name.contains("tailscale") || name.hasPrefix("utun") || name.hasPrefix("tun")
            return interface.isUp && !interface.isLoopback && tunnel
                && interface.addresses.contains(where: Self.isTunnelAddress)
        }
    }

    public static func isTunnelAddress(_ address: String) -> Bool {
        let host = address.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: "%", maxSplits: 1).first.map(String.init) ?? ""
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }),
           let first = UInt8(parts[0]), let second = UInt8(parts[1]),
           UInt8(parts[2]) != nil, UInt8(parts[3]) != nil {
            return first == 100 && (64...127).contains(second)
        }
        // Interface APIs return numeric IPv6 addresses. Validate the spelling
        // before checking Tailscale's fd7a:115c:a1e0::/48 allocation.
        let compressed = host.components(separatedBy: "::")
        guard compressed.count <= 2, !host.contains(":::"),
              !host.hasSuffix(":") || host.hasSuffix("::") else { return false }
        let words = host.split(separator: ":", omittingEmptySubsequences: true)
        guard words.allSatisfy({
            $0.count <= 4 && $0.allSatisfy { $0.isASCIIDigit || ($0 >= "a" && $0 <= "f") }
        }),
              compressed.count == 2 ? words.count < 8 : words.count == 8 else { return false }
        return host.hasPrefix("fd7a:115c:a1e0:")
    }
}

private extension Character {
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
