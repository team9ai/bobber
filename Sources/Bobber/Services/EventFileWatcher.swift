import Foundation

enum BobberError: Error {
    case cannotWatchDirectory(String)
}

class EventFileWatcher {
    private let eventsDir: URL
    private let onChange: (BobberEvent) -> Void
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fallbackTimer: Timer?
    private var processedFiles: Set<String> = []

    init(eventsDir: URL = defaultEventsDir, onChange: @escaping (BobberEvent) -> Void) {
        self.eventsDir = eventsDir
        self.onChange = onChange
    }

    static var defaultEventsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bobber/events")
    }

    func start() throws {
        // Ensure directory exists
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)

        // Primary: DispatchSource file system watcher
        let fd = open(eventsDir.path, O_EVTONLY)
        guard fd >= 0 else { throw BobberError.cannotWatchDirectory(eventsDir.path) }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scanForNewEvents() }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        self.dispatchSource = source

        // Fallback: 2-second polling timer
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.scanForNewEvents()
        }

        // Process any existing files
        scanForNewEvents()
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func scanForNewEvents() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: eventsDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in jsonFiles {
            let name = file.lastPathComponent
            guard !processedFiles.contains(name) else { continue }
            processedFiles.insert(name)

            do {
                let event = try Self.parseEventFile(at: file)
                onChange(event)
                // Delete processed file
                try? FileManager.default.removeItem(at: file)
            } catch {
                // Skip malformed files, remove after 1 minute
            }
        }
    }

    static func parseEventFile(at url: URL) throws -> BobberEvent {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.bobber.decode(BobberEvent.self, from: data)
    }
}
