
// Exercises the production adapter with a fake Security boundary. Never reads
// the developer's keychain or contacts Supabase.
final class FakeKeychain: @unchecked Sendable {
    var modern: Data?
    var legacy: Data? = Data("refresh-token".utf8)
    var modernStatus: OSStatus?
    var legacyStatus: OSStatus?
    var writeStatus: OSStatus?
    var legacyReads = 0
    var additions = 0

    func validate(_ query: [String: Any]) {
        precondition(query[kSecAttrService as String] as? String == "supabase.gotrue.swift")
        precondition(query[kSecAttrAccount as String] as? String == "test-session")
        precondition(query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIFail as String,
                     "No operation may display Keychain UI")
    }

    func storage() -> SupabaseSessionKeychainStorage {
        SupabaseSessionKeychainStorage(read: { query in
            self.validate(query)
            if query[kSecUseDataProtectionKeychain as String] as? Bool == true {
                return (self.modernStatus ?? (self.modern == nil ? errSecItemNotFound : errSecSuccess), self.modern)
            }
            self.legacyReads += 1
            return (self.legacyStatus ?? (self.legacy == nil ? errSecItemNotFound : errSecSuccess), self.legacy)
        }, add: { query in
            self.validate(query)
            precondition(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
            precondition(query[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
            self.additions += 1
            if let status = self.writeStatus { return status }
            self.modern = query[kSecValueData as String] as? Data
            return errSecSuccess
        }, update: { query, attributes in
            self.validate(query)
            precondition(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
            if let status = self.writeStatus { return status }
            guard self.modern != nil else { return errSecItemNotFound }
            self.modern = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        })
    }
}

func expectError(_ operation: () throws -> Void) {
    do { try operation(); fatalError("Expected storage failure") } catch { }
}
let key = "test-session"
let fake = FakeKeychain()
let storage = fake.storage()
for _ in 0..<5 {
    let absent = try storage.retrieve(key: key)
    precondition(absent == nil, "Legacy sessions must require sign-in, never automatic migration")
}
precondition(fake.legacyReads == 0 && fake.additions == 0)
fake.modern = Data("modern-refresh-token".utf8)
let restored = try storage.retrieve(key: key)
precondition(restored == fake.modern && fake.legacyReads == 0)
let refreshed = Data("new-refresh-token".utf8)
try storage.store(key: key, value: refreshed)
precondition(fake.modern == refreshed && fake.additions == 0)
try storage.remove(key: key)
let signedOut = try storage.retrieve(key: key)
precondition(signedOut == nil && fake.legacyReads == 0, "Sign out must not resurrect legacy sessions")

let denied = FakeKeychain()
denied.legacyStatus = errSecInteractionNotAllowed
for _ in 0..<5 {
    let absent = try denied.storage().retrieve(key: key)
    precondition(absent == nil)
}
precondition(denied.legacyReads == 0)
precondition(denied.modern == nil && denied.additions == 0)
let locked = FakeKeychain()
locked.modernStatus = errSecInteractionNotAllowed
expectError { _ = try locked.storage().retrieve(key: key) }
precondition(locked.legacyReads == 0)
let failed = FakeKeychain()
failed.modern = refreshed
failed.writeStatus = errSecAuthFailed
expectError { try failed.storage().store(key: key, value: Data("replacement".utf8)) }
precondition(failed.modern == refreshed, "Failed refresh writes must preserve existing credentials")
let missing = FakeKeychain()
missing.legacy = nil
let absent = try missing.storage().retrieve(key: key)
precondition(absent == nil)
print("PASS: no legacy access on repeated launches, modern restore, refresh, sign-out, repeated ACL denial, locked keychain, failed write preservation, missing session")
