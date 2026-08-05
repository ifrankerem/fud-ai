import Foundation

/// The user's reply to one clarification question.
///
/// Stored flat rather than as an enum with associated values: it has to survive a
/// `Codable` round-trip inside a diary entry, and it has to render into a prompt
/// line for the follow-up analysis. A flat shape does both without hand-written
/// coding machinery that would be one more thing to get wrong.
///
/// Only one of the value fields is meaningful, chosen by `kind`.
struct ClarificationAnswer: Codable, Hashable, Identifiable {
    var questionID: String
    var kind: ClarifyingQuestionKind
    /// The question text, kept so a stored answer still reads sensibly after the
    /// questions themselves are discarded at log time.
    var questionText: String

    var choice: String?
    var boolValue: Bool?
    var numericValue: Double?
    var unit: String?
    var text: String?
    var photoKind: PhotoEvidenceKind?
    /// The user explicitly declined. Distinct from an unanswered question: it tells
    /// the follow-up analysis not to keep leaning on that detail.
    var isDontKnow: Bool

    var id: String { questionID }

    init(
        questionID: String,
        kind: ClarifyingQuestionKind,
        questionText: String = "",
        choice: String? = nil,
        boolValue: Bool? = nil,
        numericValue: Double? = nil,
        unit: String? = nil,
        text: String? = nil,
        photoKind: PhotoEvidenceKind? = nil,
        isDontKnow: Bool = false
    ) {
        self.questionID = questionID
        self.kind = kind
        self.questionText = questionText
        self.choice = choice
        self.boolValue = boolValue
        self.numericValue = numericValue
        self.unit = unit
        self.text = text
        self.photoKind = photoKind
        self.isDontKnow = isDontKnow
    }

    private enum CodingKeys: String, CodingKey {
        case questionID, kind, questionText
        case choice, boolValue, numericValue, unit, text, photoKind, isDontKnow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        questionID = try container.decodeIfPresent(String.self, forKey: .questionID) ?? ""
        kind = try container.decodeIfPresent(ClarifyingQuestionKind.self, forKey: .kind) ?? .freeText
        questionText = try container.decodeIfPresent(String.self, forKey: .questionText) ?? ""
        choice = try container.decodeIfPresent(String.self, forKey: .choice)
        boolValue = try container.decodeIfPresent(Bool.self, forKey: .boolValue)
        numericValue = try container.decodeIfPresent(Double.self, forKey: .numericValue)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        photoKind = try container.decodeIfPresent(PhotoEvidenceKind.self, forKey: .photoKind)
        isDontKnow = try container.decodeIfPresent(Bool.self, forKey: .isDontKnow) ?? false
    }

    /// Whether this carries information worth sending back to the model.
    /// "I don't know" does — it rules something out. An empty answer does not.
    var isAnswered: Bool {
        if isDontKnow { return true }
        switch kind {
        case .singleChoice:
            return !(choice ?? "").isEmpty
        case .yesNo:
            return boolValue != nil
        case .numericMeasurement:
            return (numericValue ?? 0) > 0
        case .freeText:
            return !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .requestAdditionalPhoto:
            return photoKind != nil
        }
    }

    /// A numeric answer is the user stating a measurement, which is the strongest
    /// provenance there is. Everything else describes the food without measuring it.
    var impliedQuantitySource: QuantitySource? {
        guard !isDontKnow, kind == .numericMeasurement, (numericValue ?? 0) > 0 else { return nil }
        return .userMeasured
    }

    /// One line for the follow-up prompt, e.g. `How oily was the rice? — Very oily`.
    var promptLine: String {
        let question = questionText.isEmpty ? questionID : questionText
        return "\(question) — \(answerText)"
    }

    var answerText: String {
        if isDontKnow { return "user does not know" }
        switch kind {
        case .singleChoice:
            return choice ?? "no answer"
        case .yesNo:
            guard let boolValue else { return "no answer" }
            return boolValue ? "yes" : "no"
        case .numericMeasurement:
            guard let numericValue, numericValue > 0 else { return "no answer" }
            let formatted = numericValue == numericValue.rounded()
                ? String(Int(numericValue))
                : String(format: "%.1f", numericValue)
            return "\(formatted) \(unit ?? "g") (measured by the user)"
        case .freeText:
            return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "no answer"
        case .requestAdditionalPhoto:
            guard let photoKind else { return "no photo added" }
            return "user added a photo: \(photoKind.promptDescription)"
        }
    }
}
