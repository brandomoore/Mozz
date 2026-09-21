import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Bionic)
import Bionic
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// BSD socket constants whose Swift *type* differs between platforms.
///
/// The values agree everywhere; the types do not, and that is enough to stop a
/// build. `socket(_:_:_:)` takes three `Int32`, and on Darwin, Bionic and Musl
/// `SOCK_DGRAM` already is one — but Glibc imports it as a member of the
/// `__socket_type` enum, so the same line that compiles on a Mac fails on Linux
/// with "cannot convert value of type '__socket_type' to expected argument type
/// 'Int32'".
///
/// Both LAN discoveries hit this, and neither noticed for a fortnight: the
/// desktop workflow had been red since before they landed, so "the shared core
/// is portable" was being asserted by a job that had stopped checking. The
/// constant lives here rather than in each of them because a portability shim
/// written twice is one that will be fixed once.
public enum PortableSocket {
    // Glibc only, and explicitly not Android or Bionic. The condition is about
    // which C library actually provides the symbol, not which ones happen to be
    // importable: Android's toolchain has been known to satisfy
    // `canImport(Glibc)` while its `SOCK_DGRAM` is a plain `Int32`, and taking
    // the `.rawValue` path there would break the platform this shim was written
    // to protect.

    /// `SOCK_DGRAM` as the `Int32` that `socket(_:_:_:)` wants.
    public static var datagram: Int32 {
        #if canImport(Glibc) && !canImport(Android) && !canImport(Bionic)
        return Int32(SOCK_DGRAM.rawValue)
        #else
        return SOCK_DGRAM
        #endif
    }

    /// `SOCK_STREAM`, same reasoning.
    public static var stream: Int32 {
        #if canImport(Glibc) && !canImport(Android) && !canImport(Bionic)
        return Int32(SOCK_STREAM.rawValue)
        #else
        return SOCK_STREAM
        #endif
    }
}
