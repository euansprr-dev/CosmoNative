// CosmoOS/Daemon/main.swift
// Entry point for CosmoVoiceDaemon XPC service
// Keeps ML models hot in RAM for instant voice response

import Foundation

/// Shared state for daemon readiness
nonisolated(unsafe) var daemonIsReady = false

/// XPC Service Delegate
final class DaemonServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Configure the connection
        connection.exportedInterface = NSXPCInterface(with: CosmoVoiceDaemonProtocol.self)
        connection.exportedObject = CosmoVoiceDaemon.shared

        // Set up invalidation handler
        connection.invalidationHandler = {
            print("CosmoVoiceDaemon: Connection invalidated")
        }

        connection.interruptionHandler = {
            print("CosmoVoiceDaemon: Connection interrupted")
        }

        // Resume the connection
        connection.resume()

        print("CosmoVoiceDaemon: Accepted new connection (models ready: \(daemonIsReady))")
        return true
    }
}

// MARK: - Main Entry Point

print("CosmoVoiceDaemon: Starting...")
print("CosmoVoiceDaemon: Models will be downloaded to ~/Library/Caches/huggingface/hub/")

// Initialize the daemon (load models) - this runs async
let daemon = CosmoVoiceDaemon.shared
Task {
    await daemon.initialize()
    daemonIsReady = true
    print("CosmoVoiceDaemon: All models loaded - ready for requests")
}

// Create the XPC listener
let delegate = DaemonServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate

print("CosmoVoiceDaemon: Listening for XPC connections (model loading in background)...")

// Start the service (blocks forever)
listener.resume()
RunLoop.main.run()
