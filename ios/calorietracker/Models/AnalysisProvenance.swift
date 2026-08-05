import Foundation

/// Which pass of the analysis produced a result.
enum AnalysisStage: String, Codable, CaseIterable, Hashable {
    /// First look at the photos, before the user has clarified anything.
    case initial
    /// Re-run after the user answered clarification questions.
    case refined
    /// Typed by hand; no model involved.
    case manual

    var displayName: String {
        switch self {
        case .initial: return LocalizedDisplayText.text("First estimate", polish: "Pierwszy szacunek")
        case .refined: return LocalizedDisplayText.text("Refined", polish: "Doprecyzowany")
        case .manual: return LocalizedDisplayText.text("Entered manually", polish: "Wprowadzone ręcznie")
        }
    }
}

/// Who produced an analysis and what happened to it afterwards.
///
/// Recorded per entry because "which model is actually good at *my* food" is not
/// answerable after the fact — the provider can be switched at any time, and a
/// silent fallback means the model that answered may not even be the one that was
/// selected. Capturing it at log time is the only chance.
///
/// `userEdited` is the other half: an estimate the user corrected is evidence the
/// model got it wrong, and an untouched one is weak evidence it got it right.
/// Together these are the raw material for per-model accuracy and for calibrating
/// future estimates from past corrections.
struct AnalysisProvenance: Codable, Hashable {
    /// Display name of the provider that answered, e.g. "Google Gemini".
    var providerName: String
    var model: String
    /// True when the selected provider failed and the configured fallback answered.
    /// Without this the recorded provider would be a lie in exactly the cases that
    /// matter most for judging reliability.
    var usedFallback: Bool
    var stage: AnalysisStage
    /// Set once the user changes any nutrition value before logging.
    var userEdited: Bool
    /// Number of clarification questions the user actually answered.
    var answeredQuestionCount: Int

    init(
        providerName: String,
        model: String,
        usedFallback: Bool = false,
        stage: AnalysisStage = .initial,
        userEdited: Bool = false,
        answeredQuestionCount: Int = 0
    ) {
        self.providerName = providerName
        self.model = model
        self.usedFallback = usedFallback
        self.stage = stage
        self.userEdited = userEdited
        self.answeredQuestionCount = answeredQuestionCount
    }

    private enum CodingKeys: String, CodingKey {
        case providerName, model, usedFallback, stage, userEdited, answeredQuestionCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        usedFallback = try container.decodeIfPresent(Bool.self, forKey: .usedFallback) ?? false
        stage = try container.decodeIfPresent(AnalysisStage.self, forKey: .stage) ?? .initial
        userEdited = try container.decodeIfPresent(Bool.self, forKey: .userEdited) ?? false
        answeredQuestionCount = try container.decodeIfPresent(Int.self, forKey: .answeredQuestionCount) ?? 0
    }

    /// Built from a transport outcome so the fallback provider is recorded rather
    /// than the one that was merely selected.
    init(outcome: AIRequestOutcome, stage: AnalysisStage) {
        self.init(
            providerName: outcome.providerName,
            model: outcome.model,
            usedFallback: outcome.usedFallback,
            stage: stage
        )
    }

    /// e.g. "Google Gemini · gemini-3.6-flash · Refined"
    var displaySummary: String {
        var parts = [providerName, model].filter { !$0.isEmpty }
        parts.append(stage.displayName)
        if usedFallback {
            parts.append(LocalizedDisplayText.text("Fallback", polish: "Zapasowy"))
        }
        return parts.joined(separator: " · ")
    }
}
