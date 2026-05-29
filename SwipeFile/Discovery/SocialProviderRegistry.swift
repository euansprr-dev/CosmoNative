import Foundation

struct SocialProviderRegistry: Sendable {
    private let providers: [any SocialDiscoveryProvider]

    init(providers: [any SocialDiscoveryProvider]) {
        self.providers = providers
    }

    func provider(
        for platform: SocialPlatform,
        requiring requiredCapabilities: Set<SocialProviderCapability>
    ) -> (any SocialDiscoveryProvider)? {
        providers.first { provider in
            provider.supports(platform: platform)
                && requiredCapabilities.isSubset(of: provider.capabilities)
        }
    }
}
