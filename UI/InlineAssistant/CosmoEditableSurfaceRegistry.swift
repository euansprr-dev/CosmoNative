import Foundation

@MainActor
final class CosmoEditableSurfaceRegistry {
    static let shared = CosmoEditableSurfaceRegistry()

    private var providers: [String: WeakEditableSurfaceProvider] = [:]
    private var activationOrder: [String] = []

    var activeSurface: (any CosmoEditableSurfaceProvider)? {
        cleanupReleasedProviders()
        return activationOrder.reversed().compactMap { providers[$0]?.provider }.first
    }

    func provider(surfaceID: String) -> (any CosmoEditableSurfaceProvider)? {
        cleanupReleasedProviders()
        return providers[surfaceID]?.provider
    }

    func register(_ provider: any CosmoEditableSurfaceProvider) {
        providers[provider.surfaceID] = WeakEditableSurfaceProvider(provider)
        activationOrder.removeAll { $0 == provider.surfaceID }
        activationOrder.append(provider.surfaceID)
    }

    func activate(surfaceID: String) {
        guard providers[surfaceID]?.provider != nil else { return }
        activationOrder.removeAll { $0 == surfaceID }
        activationOrder.append(surfaceID)
    }

    func unregister(surfaceID: String) {
        providers.removeValue(forKey: surfaceID)
        activationOrder.removeAll { $0 == surfaceID }
    }

    private func cleanupReleasedProviders() {
        let released = providers.compactMap { key, value in
            value.provider == nil ? key : nil
        }
        for key in released {
            providers.removeValue(forKey: key)
            activationOrder.removeAll { $0 == key }
        }
    }
}

private final class WeakEditableSurfaceProvider {
    weak var provider: (any CosmoEditableSurfaceProvider)?

    init(_ provider: any CosmoEditableSurfaceProvider) {
        self.provider = provider
    }
}
