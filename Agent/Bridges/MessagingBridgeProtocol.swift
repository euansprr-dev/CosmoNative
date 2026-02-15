// CosmoOS/Agent/Bridges/MessagingBridgeProtocol.swift
// Protocol for messaging platform bridges

import Foundation

/// Protocol that all messaging bridges must implement
protocol MessagingBridge: AnyObject {
    /// Start the bridge (begin listening for messages)
    func start() async

    /// Stop the bridge
    func stop()

    /// Whether the bridge is currently connected
    var isConnected: Bool { get }

    /// Callback for received messages
    var onMessageReceived: ((IncomingMessage) -> Void)? { get set }
}

/// A message received from an external messaging platform
struct IncomingMessage: Sendable {
    let source: MessageSource
    let text: String?
    let voiceData: Data?
    let chatId: String
    let messageId: Int?
    let senderName: String?

    var hasVoice: Bool { voiceData != nil }
    var hasText: Bool { text != nil && !text!.isEmpty }
}
