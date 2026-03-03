import XCTest
@testable import Bobber

final class PermissionServerTests: XCTestCase {
    func testServerStartsAndAcceptsConnection() throws {
        let socketPath = "/tmp/bobber-test-\(UUID().uuidString).sock"
        defer { unlink(socketPath) }

        let server = PermissionServer(socketPath: socketPath)
        try server.start()

        // Connect as a client
        let clientFd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThan(clientFd, 0)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                _ = strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(clientFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(connectResult, 0, "Client should connect to server")

        Darwin.close(clientFd)
        server.stop()
    }
}
