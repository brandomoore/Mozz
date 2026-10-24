import XCTest
@testable import MozzCore

final class TailscaleNetworkTests: XCTestCase {
    func testTailscaleRangesAndBoundaries() {
        for address in ["100.64.0.0", "100.127.255.255", "fd7a:115c:a1e0::1",
                        "FD7A:115C:A1E0:0:0:0:0:1", "[fd7a:115c:a1e0::2]", "fd7a:115c:a1e0::2%tun0"] {
            XCTAssertTrue(TailscaleNetwork.isTunnelAddress(address), address)
        }
        for address in ["100.63.255.255", "100.128.0.0", "100.64.0.256", "100.64.0",
                        "100.+64.0.1", "fd7a:115c:a1e1::1", "fd7a:115c:a1e00::1",
                        "fd7a:115c:a1e0:::1", "fd7a:115c:a1e0:zz::1",
                        "fd7a:115c:a1e0::+1", "fd7a:115c:a1e0:: 1", "192.168.1.1"] {
            XCTAssertFalse(TailscaleNetwork.isTunnelAddress(address), address)
        }
    }

    func testEveryShellUsesTheSameTunnelHeuristic() {
        for name in ["utun4", "tun0", "tailscale0", "Ethernet Tailscale Tunnel"] {
            XCTAssertTrue(status(name: name).detected, name)
        }
        XCTAssertTrue(status(name: "utun4", address: "fd7a:115c:a1e0::1").detected)
    }

    func testCarrierNATAndInactiveInterfacesDoNotImplyTailscale() {
        for name in ["pdp_ip0", "rmnet_data0", "en0", "eth0"] {
            XCTAssertFalse(status(name: name).detected, name)
        }
        XCTAssertFalse(status(name: "utun4", address: "10.0.0.1").detected)
        XCTAssertFalse(status(name: "utun4", isUp: false).detected)
        XCTAssertFalse(status(name: "tailscale0", isLoopback: true).detected)
        XCTAssertFalse(TailscaleNetwork(interfaces: []).detected)
    }

    private func status(
        name: String, address: String = "100.100.10.20",
        isUp: Bool = true, isLoopback: Bool = false
    ) -> TailscaleNetwork {
        TailscaleNetwork(interfaces: [
            NetworkInterfaceSnapshot(name: name, isUp: isUp, isLoopback: isLoopback, addresses: [address])
        ])
    }
}
