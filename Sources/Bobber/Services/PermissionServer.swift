import Foundation

class PermissionServer {
    let socketPath: String
    private var serverFd: Int32 = -1
    private var dispatchSource: DispatchSourceRead?
    private var pendingClients: [String: Int32] = [:]  // sessionId -> fd
    var onPermissionRequest: ((String, BobberEvent) -> Void)?  // (sessionId, event)

    init(socketPath: String = "/tmp/bobber.sock") {
        self.socketPath = socketPath
    }

    func start() throws {
        // Remove stale socket
        unlink(socketPath)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else { throw BobberError.cannotWatchDirectory("socket creation failed") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                _ = strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(serverFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw BobberError.cannotWatchDirectory("socket bind failed") }
        guard Darwin.listen(serverFd, 5) == 0 else { throw BobberError.cannotWatchDirectory("socket listen failed") }

        // Non-blocking accept via GCD
        let source = DispatchSource.makeReadSource(fileDescriptor: serverFd, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptClient() }
        source.setCancelHandler { [weak self] in
            if let fd = self?.serverFd, fd >= 0 { Darwin.close(fd) }
        }
        source.resume()
        self.dispatchSource = source
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
        for (_, fd) in pendingClients { Darwin.close(fd) }
        pendingClients.removeAll()
        unlink(socketPath)
    }

    func respond(sessionId: String, decision: PermissionDecision) {
        guard let fd = pendingClients.removeValue(forKey: sessionId) else { return }
        let json: String
        switch decision {
        case .allow:
            json = #"{"behavior":"allow"}"#
        case .allowForProject:
            json = #"{"behavior":"allow","remember":"project"}"#
        case .deny:
            json = #"{"behavior":"deny","message":"Denied from Bobber"}"#
        case .custom(let message):
            let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
            json = #"{"behavior":"deny","message":"\#(escaped)"}"#
        }
        let data = json.data(using: .utf8)!
        data.withUnsafeBytes { buffer in
            _ = Darwin.write(fd, buffer.baseAddress!, buffer.count)
        }
        Darwin.close(fd)
    }

    private func acceptClient() {
        let clientFd = Darwin.accept(serverFd, nil, nil)
        guard clientFd >= 0 else { return }

        // Read data from client on background queue
        DispatchQueue.global().async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 65536)
            let bytesRead = Darwin.read(clientFd, &buffer, buffer.count)
            guard bytesRead > 0 else {
                Darwin.close(clientFd)
                return
            }

            let data = Data(bytes: buffer, count: bytesRead)
            guard let event = try? JSONDecoder.bobber.decode(BobberEvent.self, from: data) else {
                Darwin.close(clientFd)
                return
            }

            DispatchQueue.main.async {
                self?.pendingClients[event.sessionId] = clientFd
                self?.onPermissionRequest?(event.sessionId, event)
            }
        }
    }
}

enum PermissionDecision {
    case allow
    case allowForProject
    case deny
    case custom(String)
}
