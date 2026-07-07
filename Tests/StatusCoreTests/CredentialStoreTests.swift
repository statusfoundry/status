import Foundation
import Testing
@testable import StatusCore

@Test func credentialReferenceUsesKeychainReferenceShape() throws {
    let reference = try CredentialReference.make()

    #expect(reference.hasPrefix("kc_"))
    #expect(reference.count == 29)
    try CredentialReference.validate(reference)
}

@Test func invalidCredentialReferencesAreRejected() {
    #expect(throws: CredentialStoreError.invalidReference("token_123")) {
        try CredentialReference.validate("token_123")
    }
}

@Test func inMemoryCredentialStoreRoundTripsAndDeletesSecretsByReference() throws {
    let store = InMemoryCredentialStore()
    let secret = try #require("github_pat_example".data(using: .utf8))

    let reference = try store.store(secret, label: "GitHub token")

    #expect(try store.read(reference: reference) == secret)

    try store.delete(reference: reference)

    #expect(try store.read(reference: reference) == nil)
}
