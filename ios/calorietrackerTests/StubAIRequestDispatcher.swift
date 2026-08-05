import Foundation
import UIKit
@testable import calorietracker

/// Test double for the AI transport.
///
/// Exists so meal-analysis tests can run in CI with no API key, no network and no
/// provider configuration — feed it canned provider responses and assert on what
/// the parsing, validation and two-stage logic do with them.
final class StubAIRequestDispatcher: AIRequestDispatching, @unchecked Sendable {

    /// Responses handed out in order, one per `send` call. The last one repeats
    /// once exhausted so a test does not have to count retries exactly.
    private var responses: [Result<String, Error>]
    private let providerName: String
    private let model: String
    private let lock = NSLock()

    /// Every prompt this dispatcher was asked to send, in order. Lets a test assert
    /// that stage two actually received the user's answers.
    private(set) var sentPrompts: [String] = []
    private(set) var sentImageCounts: [Int] = []

    init(
        responses: [Result<String, Error>],
        providerName: String = "Stub Provider",
        model: String = "stub-model"
    ) {
        precondition(!responses.isEmpty, "StubAIRequestDispatcher needs at least one response")
        self.responses = responses
        self.providerName = providerName
        self.model = model
    }

    convenience init(response: String, providerName: String = "Stub Provider", model: String = "stub-model") {
        self.init(responses: [.success(response)], providerName: providerName, model: model)
    }

    convenience init(error: Error) {
        self.init(responses: [.failure(error)])
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sentPrompts.count
    }

    func send(prompt: String, images: [UIImage]) async throws -> AIRequestOutcome {
        lock.lock()
        sentPrompts.append(prompt)
        sentImageCounts.append(images.count)
        let index = min(sentPrompts.count - 1, responses.count - 1)
        let response = responses[index]
        lock.unlock()

        switch response {
        case let .success(text):
            return AIRequestOutcome(text: text, providerName: providerName, model: model)
        case let .failure(error):
            throw error
        }
    }
}
