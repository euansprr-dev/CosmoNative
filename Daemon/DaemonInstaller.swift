// CosmoOS/Daemon/DaemonInstaller.swift
// Utility for installing and managing the CosmoVoiceDaemon LaunchAgent
// macOS 26+ optimized

import Foundation

// MARK: - Daemon Installer

public struct DaemonInstaller {
    // MARK: - Constants

    private static let daemonServiceName = "com.cosmo.voicedaemon"
    private static let plistFileName = "com.cosmo.voicedaemon.plist"

    private static var launchAgentsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    private static var installedPlistPath: URL {
        launchAgentsPath.appendingPathComponent(plistFileName)
    }

    // MARK: - Installation Status

    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installedPlistPath.path)
    }

    public static var isRunning: Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list", daemonServiceName]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Installation

    /// Install the daemon LaunchAgent plist
    public static func install() throws {
        // 1. Ensure LaunchAgents directory exists
        try FileManager.default.createDirectory(
            at: launchAgentsPath,
            withIntermediateDirectories: true
        )

        // 2. Get the plist from the app bundle
        guard let bundlePlistURL = Bundle.main.url(
            forResource: "com.cosmo.voicedaemon",
            withExtension: "plist"
        ) else {
            throw DaemonInstallerError.plistNotFound
        }

        // 3. Read and modify the plist to use correct paths
        var plistContent = try String(contentsOf: bundlePlistURL, encoding: .utf8)

        // Update the daemon executable path to current app location
        let appPath = Bundle.main.bundlePath
        let daemonPath = "\(appPath)/Contents/XPCServices/CosmoVoiceDaemon.xpc/Contents/MacOS/CosmoVoiceDaemon"
        plistContent = plistContent.replacingOccurrences(
            of: "/Applications/CosmoOS.app/Contents/XPCServices/CosmoVoiceDaemon.xpc/Contents/MacOS/CosmoVoiceDaemon",
            with: daemonPath
        )

        // Expand ~ in cache path
        let expandedCachePath = NSString(string: "~/Library/Caches/com.cosmo.voicedaemon/mlx").expandingTildeInPath
        plistContent = plistContent.replacingOccurrences(
            of: "~/Library/Caches/com.cosmo.voicedaemon/mlx",
            with: expandedCachePath
        )

        // 4. Write the modified plist
        try plistContent.write(to: installedPlistPath, atomically: true, encoding: .utf8)

        // 5. Set correct permissions (644)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: installedPlistPath.path
        )

        print("DaemonInstaller: Installed LaunchAgent at \(installedPlistPath.path)")
    }

    /// Uninstall the daemon LaunchAgent
    public static func uninstall() throws {
        // 1. Stop the daemon first
        try? stop()

        // 2. Remove the plist
        if FileManager.default.fileExists(atPath: installedPlistPath.path) {
            try FileManager.default.removeItem(at: installedPlistPath)
            print("DaemonInstaller: Uninstalled LaunchAgent")
        }
    }

    // MARK: - Lifecycle Management

    /// Load and start the daemon
    public static func start() throws {
        guard isInstalled else {
            throw DaemonInstallerError.notInstalled
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["load", installedPlistPath.path]

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            throw DaemonInstallerError.loadFailed(task.terminationStatus)
        }

        print("DaemonInstaller: Daemon started")
    }

    /// Stop and unload the daemon
    public static func stop() throws {
        guard isInstalled else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["unload", installedPlistPath.path]

        try task.run()
        task.waitUntilExit()

        // Don't throw on error - daemon might not be loaded
        print("DaemonInstaller: Daemon stopped")
    }

    /// Restart the daemon (stop then start)
    public static func restart() throws {
        try? stop()
        try start()
    }

    /// Bootstrap (kickstart) the daemon immediately
    public static func bootstrap() throws {
        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootstrap", "gui/\(uid)", installedPlistPath.path]

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            // Try legacy load command as fallback
            try start()
        }

        print("DaemonInstaller: Daemon bootstrapped")
    }

    /// Kickstart (force immediate start) the daemon
    public static func kickstart() throws {
        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["kickstart", "-k", "gui/\(uid)/\(daemonServiceName)"]

        try task.run()
        task.waitUntilExit()

        print("DaemonInstaller: Daemon kickstarted")
    }

    // MARK: - Setup (Install + Start)

    /// Full setup: install plist and start daemon
    public static func setup() async throws {
        // 1. Install if needed
        if !isInstalled {
            try install()
        }

        // 2. Ensure daemon cache directory exists
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.cosmo.voicedaemon/mlx")
        try FileManager.default.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true
        )

        // 3. Start the daemon
        if !isRunning {
            try bootstrap()
        }

        // 4. Wait for daemon to be ready
        let client = await DaemonXPCClient.shared
        let ready = await client.waitForReady(timeout: .seconds(30))

        if !ready {
            throw DaemonInstallerError.daemonNotReady
        }

        print("DaemonInstaller: Setup complete, daemon ready")
    }

    // MARK: - Status

    public struct Status {
        public let isInstalled: Bool
        public let isRunning: Bool
        public let plistPath: String?
        public let daemonRAM: Int64?
    }

    public static func getStatus() async -> Status {
        var ramUsage: Int64? = nil

        if isRunning {
            let client = await DaemonXPCClient.shared
            let (alive, ram) = await client.healthCheck()
            if alive {
                ramUsage = ram
            }
        }

        return Status(
            isInstalled: isInstalled,
            isRunning: isRunning,
            plistPath: isInstalled ? installedPlistPath.path : nil,
            daemonRAM: ramUsage
        )
    }
}

// MARK: - Errors

public enum DaemonInstallerError: LocalizedError {
    case plistNotFound
    case notInstalled
    case loadFailed(Int32)
    case daemonNotReady

    public var errorDescription: String? {
        switch self {
        case .plistNotFound:
            return "LaunchAgent plist not found in app bundle"
        case .notInstalled:
            return "Daemon is not installed"
        case .loadFailed(let code):
            return "Failed to load daemon (exit code: \(code))"
        case .daemonNotReady:
            return "Daemon failed to become ready within timeout"
        }
    }
}

// MARK: - App Lifecycle Integration

extension DaemonInstaller {
    /// Call this from AppDelegate applicationDidFinishLaunching
    public static func onAppLaunch() {
        Task {
            do {
                try await setup()
            } catch {
                print("DaemonInstaller: Failed to setup daemon: \(error)")
                // Post notification for UI to show error
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .daemonSetupFailed,
                        object: nil,
                        userInfo: ["error": error]
                    )
                }
            }
        }
    }

    /// Call this from AppDelegate applicationWillTerminate
    public static func onAppTerminate() {
        // Don't stop the daemon - it should keep running for quick restarts
        // Only stop if user explicitly quits via menu with Option held
        print("DaemonInstaller: App terminating, daemon will continue running")
    }

    /// Force-stop daemon (Option+Quit)
    public static func forceStopDaemon() {
        try? stop()
        print("DaemonInstaller: Daemon force-stopped")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let daemonSetupFailed = Notification.Name("com.cosmo.daemonSetupFailed")
    static let daemonSetupComplete = Notification.Name("com.cosmo.daemonSetupComplete")
}
