import DevKeeperCore
import Foundation

public final class FileSystemWatcher: @unchecked Sendable {
    public static let shared = FileSystemWatcher()
    
    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounceTimer: Timer?
    private var onChangeCallback: (@Sendable () -> Void)?
    
    public func startWatching(onChange: @escaping @Sendable () -> Void) {
        self.onChangeCallback = onChange
        stopWatching()
        
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pathsToWatch = [
            "/Applications",
            "\(home)/Applications",
            "/opt/homebrew/Cellar",
            "/opt/homebrew/Caskroom",
            "/opt/homebrew/lib/node_modules",
            "\(home)/.local/bin"
        ]
        
        for path in pathsToWatch {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .delete, .rename, .attrib],
                queue: DispatchQueue.global(qos: .utility)
            )
            
            source.setEventHandler { [weak self] in
                self?.handleFileSystemEvent()
            }
            
            source.setCancelHandler {
                close(fd)
            }
            
            source.resume()
            sources.append(source)
        }
    }
    
    public func stopWatching() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
    }
    
    private func handleFileSystemEvent() {
        DispatchQueue.main.async { [weak self] in
            self?.debounceTimer?.invalidate()
            self?.debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.onChangeCallback?()
            }
        }
    }
}
