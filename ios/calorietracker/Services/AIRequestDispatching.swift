import Foundation
import UIKit

/// What a single AI round-trip produced, plus who produced it.
///
/// The provider identity travels with the text because a two-stage analysis needs
/// to record which model actually answered — including when the primary failed and
/// the configured fallback stepped in, which the caller otherwise cannot see.
struct AIRequestOutcome: Equatable {
    let text: String
    /// Display name of the provider that answered, e.g. "Google Gemini".
    let providerName: String
    let model: String
    /// True when the primary provider failed and the fallback answered instead.
    let usedFallback: Bool

    init(text: String, providerName: String, model: String, usedFallback: Bool = false) {
        self.text = text
        self.providerName = providerName
        self.model = model
        self.usedFallback = usedFallback
    }
}

/// The one thing meal analysis needs from the networking layer: turn a prompt and
/// some images into text.
///
/// Everything above this protocol — prompt building, parsing, validation, the
/// two-stage flow — is pure logic and can be unit-tested against a stub. That is
/// the point: the existing analysis code reaches straight into a private static
/// method, so no test can exercise it without a live API key and a real network
/// call. Provider selection, key storage, base URLs, timeouts and fallback all
/// stay exactly where they are; this only names the seam.
protocol AIRequestDispatching: Sendable {
    func send(prompt: String, images: [UIImage]) async throws -> AIRequestOutcome
}

extension AIRequestDispatching {
    func send(prompt: String) async throws -> AIRequestOutcome {
        try await send(prompt: prompt, images: [])
    }
}
