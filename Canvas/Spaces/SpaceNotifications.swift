// CosmoOS/Canvas/Spaces/SpaceNotifications.swift
// The two notifications behind the one creation grammar for spaces: any
// surface asks MainView to present the composer sheet; the composer tells
// the sidebar what it made so the parent row can open.

import Foundation

extension CosmoNotification.Navigation {
    /// Present the Space composer sheet (create or settings).
    /// userInfo: `"mode"` = `"create"` | `"edit"`; `"parentId"` (create,
    /// optional); `"thinkspaceId"` (edit). Decode with `SpaceComposerRequest(from:)`.
    static let presentSpaceComposer = Notification.Name("com.cosmo.navigation.presentSpaceComposer")

    /// A space was created through the composer.
    /// userInfo: `"thinkspaceId"`; `"parentId"` when it was nested.
    /// Decode with `SpaceComposerCreated(from:)`.
    static let spaceComposerDidCreate = Notification.Name("com.cosmo.navigation.spaceComposerDidCreate")
}

/// What a caller wants from the composer. `Identifiable` so MainView can
/// drive `.sheet(item:)` straight from a decoded notification.
struct SpaceComposerRequest: Equatable, Identifiable {
    enum Mode: Equatable {
        case create(parentId: String?)
        case edit(thinkspaceId: String)
    }

    let id = UUID()
    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    init?(from notification: Notification) {
        guard let info = notification.userInfo,
              let modeRaw = info["mode"] as? String else { return nil }
        switch modeRaw {
        case "create":
            mode = .create(parentId: info["parentId"] as? String)
        case "edit":
            guard let thinkspaceId = info["thinkspaceId"] as? String else { return nil }
            mode = .edit(thinkspaceId: thinkspaceId)
        default:
            return nil
        }
    }

    var userInfo: [AnyHashable: Any] {
        switch mode {
        case .create(let parentId):
            var info: [AnyHashable: Any] = ["mode": "create"]
            if let parentId { info["parentId"] = parentId }
            return info
        case .edit(let thinkspaceId):
            return ["mode": "edit", "thinkspaceId": thinkspaceId]
        }
    }

    func post() {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.presentSpaceComposer,
            object: nil,
            userInfo: userInfo
        )
    }

    /// One-liner for call sites: `SpaceComposerRequest.post(.create(parentId: nil))`.
    static func post(_ mode: Mode) {
        SpaceComposerRequest(mode: mode).post()
    }
}

extension SpaceComposerRequest: NotificationPayload {}

/// The composer's receipt for a creation — posted by `SpaceComposerModel.commit()`
/// (never by the presenter, so it fires exactly once).
struct SpaceComposerCreated: Equatable {
    let thinkspaceId: String
    let parentId: String?

    init(thinkspaceId: String, parentId: String?) {
        self.thinkspaceId = thinkspaceId
        self.parentId = parentId
    }

    init?(from notification: Notification) {
        guard let thinkspaceId = notification.userInfo?["thinkspaceId"] as? String else { return nil }
        self.thinkspaceId = thinkspaceId
        self.parentId = notification.userInfo?["parentId"] as? String
    }

    var userInfo: [AnyHashable: Any] {
        var info: [AnyHashable: Any] = ["thinkspaceId": thinkspaceId]
        if let parentId { info["parentId"] = parentId }
        return info
    }

    func post() {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.spaceComposerDidCreate,
            object: nil,
            userInfo: userInfo
        )
    }
}

extension SpaceComposerCreated: NotificationPayload {}
