import Foundation
import UIKit

/// A photo plus what it is meant to prove.
struct LabelledImage {
    var image: UIImage
    var kind: PhotoEvidenceKind

    init(image: UIImage, kind: PhotoEvidenceKind = .other) {
        self.image = image
        self.kind = kind
    }
}

/// One pass of the analysis, ready for the review screen.
struct MealAnalysisOutcome {
    /// Flat nutrition plus the component breakdown, in the shape the existing
    /// review and logging path already understands.
    var analysis: GeminiService.FoodAnalysis
    /// Non-blocking notices, currently only "we kept your measurement".
    var warnings: [String]

    var detail: MealAnalysisDetail { analysis.analysisDetail }
    var needsClarification: Bool { !detail.pendingQuestions().isEmpty }
}

/// Runs the two-pass meal analysis.
///
/// The first pass produces a component-level estimate and, when it would help,
/// up to three questions. The second folds the user's answers back in. Both go
/// through the user's configured provider — this owns no networking of its own,
/// only the shape of the conversation.
///
/// Every failure path degrades rather than dies. A reply that will not parse gets
/// one repair attempt, and if that fails too the caller can fall back to the
/// existing single-pass analysis. A meal estimate is worth more to the user than
/// a correct component breakdown.
struct MealAnalysisService {

    private let dispatcher: AIRequestDispatching

    init(dispatcher: AIRequestDispatching = LiveAIRequestDispatcher()) {
        self.dispatcher = dispatcher
    }

    // MARK: - Stage one

    func analyze(
        images: [LabelledImage],
        note: String? = nil,
        userContext: String? = nil
    ) async throws -> MealAnalysisOutcome {
        let measurements = MeasurementExtractor.extract(from: note)
        let prompt = MealAnalysisPromptBuilder.initialAnalysisPrompt(
            note: note,
            measurements: measurements,
            photoLabels: images.map(\.kind),
            userContext: userContext
        )

        let (analysis, outcome) = try await requestAnalysis(prompt: prompt, images: images.map(\.image))
        var detail = analysis.analysisDetail
        detail.provenance = AnalysisProvenance(outcome: outcome, stage: .initial)
        detail = applyingExtractedMeasurements(measurements, to: detail)

        var result = analysis
        result.analysisDetail = MealAnalysisValidator.validate(
            detail,
            mealCalories: analysis.calories,
            protein: analysis.protein,
            carbs: analysis.carbs,
            fat: analysis.fat,
            servingSizeGrams: analysis.servingSizeGrams
        ).detail

        return MealAnalysisOutcome(analysis: result, warnings: [])
    }

    // MARK: - Stage two

    /// Re-runs with the user's answers folded in.
    ///
    /// Returns the previous outcome untouched when there is nothing new to say —
    /// spending an API call to tell the model "the user skipped everything" buys
    /// nothing but latency and cost.
    func refine(
        previous: MealAnalysisOutcome,
        answers: [ClarificationAnswer],
        images: [LabelledImage],
        additionalImages: [LabelledImage] = [],
        note: String? = nil
    ) async throws -> MealAnalysisOutcome {
        let answered = answers.filter(\.isAnswered)
        guard !answered.isEmpty || !additionalImages.isEmpty else {
            return skipping(previous, answers: answers)
        }

        let measurements = MeasurementExtractor.extract(from: note)
        let previousDetail = previous.analysis.analysisDetail
        let prompt = MealAnalysisPromptBuilder.refinementPrompt(
            previous: previousDetail,
            previousTotals: MealTotalsSnapshot(analysis: previous.analysis),
            answers: answered,
            note: note,
            measurements: measurements,
            newPhotoLabels: additionalImages.map(\.kind)
        )

        let allImages = images + additionalImages
        let (analysis, outcome) = try await requestAnalysis(prompt: prompt, images: allImages.map(\.image))

        var revised = analysis.analysisDetail
        revised.provenance = AnalysisProvenance(outcome: outcome, stage: .refined)

        // The user's own numbers are stamped on before the merge, so the merge sees
        // them as measurements and protects them like any other.
        revised = MealAnalysisValidator.applyingMeasuredAnswers(
            to: revised,
            questions: previousDetail.questions,
            answers: answered
        )

        let merged = MealAnalysisValidator.merge(
            stageOne: previousDetail,
            stageTwo: revised,
            answers: answered,
            mealCalories: analysis.calories,
            protein: analysis.protein,
            carbs: analysis.carbs,
            fat: analysis.fat,
            servingSizeGrams: analysis.servingSizeGrams
        )

        var result = analysis
        result.analysisDetail = merged.detail
        return MealAnalysisOutcome(analysis: result, warnings: merged.warnings)
    }

    /// The user chose to log the provisional estimate as-is. Settle it without
    /// another round trip, keeping whatever they did answer.
    func skipping(_ previous: MealAnalysisOutcome, answers: [ClarificationAnswer] = []) -> MealAnalysisOutcome {
        var result = previous.analysis
        var detail = previous.analysis.analysisDetail.applying(answers: answers)
        detail.questions = []
        detail.status = .final
        result.analysisDetail = detail
        return MealAnalysisOutcome(analysis: result, warnings: previous.warnings)
    }

    // MARK: - Transport

    /// Sends a prompt and parses the reply, with one repair attempt.
    private func requestAnalysis(
        prompt: String,
        images: [UIImage]
    ) async throws -> (GeminiService.FoodAnalysis, AIRequestOutcome) {
        let outcome = try await dispatcher.send(prompt: prompt, images: images)

        do {
            return (try GeminiService.parseFoodAnalysis(from: outcome.text), outcome)
        } catch {
            // The content is usually right and only the wrapper is wrong — a stray
            // sentence, an unclosed bracket. Asking for the same data back as valid
            // JSON is cheaper and likelier to work than re-running the analysis.
            let repair = try await dispatcher.send(
                prompt: MealAnalysisPromptBuilder.repairPrompt(malformed: outcome.text),
                images: []
            )
            let repaired = try GeminiService.parseFoodAnalysis(from: repair.text)
            // Credit the provider that did the analysis, not the one that fixed the
            // punctuation — otherwise accuracy stats would blame the wrong model.
            return (repaired, outcome)
        }
    }

    /// Marks components whose amount the user already stated, so the app stops
    /// asking about them and a later pass cannot overwrite them.
    ///
    /// Matching is by name because at this point there is nothing else to match on:
    /// the note said "chicken", the model called a part "Grilled chicken breast".
    /// A miss costs a redundant question, not a wrong number, so the containment
    /// test is deliberately loose.
    private func applyingExtractedMeasurements(
        _ measurements: [ExtractedMeasurement],
        to detail: MealAnalysisDetail
    ) -> MealAnalysisDetail {
        let exact = measurements.filter { !$0.isApproximate && $0.grams != nil }
        guard !exact.isEmpty, !detail.components.isEmpty else { return detail }

        var components = detail.components
        var claimed = Set<Int>()

        for measurement in exact {
            guard let foodName = measurement.foodName?.lowercased(), foodName.count > 2 else { continue }
            guard let grams = measurement.grams, grams > 0 else { continue }

            let match = components.indices.first { index in
                guard !claimed.contains(index) else { return false }
                let componentName = components[index].name.lowercased()
                return componentName.contains(foodName) || foodName.contains(componentName)
            }
            guard let index = match else { continue }
            claimed.insert(index)

            // Only claim the measurement when the model landed somewhere near it.
            // A wild mismatch more likely means the names collided than that the
            // user weighed something four times heavier than it looks.
            let modelled = components[index].grams
            guard modelled <= 0 || (grams / modelled > 0.25 && grams / modelled < 4) else { continue }

            components[index].quantitySource = .userMeasured
            components[index].grams = grams
        }

        var result = detail
        result.components = components
        return result
    }
}

/// Sends through the app's existing provider routing.
///
/// A thin adapter on purpose: provider selection, Keychain storage, base URLs,
/// timeouts, image encoding and fallback all stay in `GeminiService`, which is
/// where they are already tested and working.
struct LiveAIRequestDispatcher: AIRequestDispatching {
    func send(prompt: String, images: [UIImage]) async throws -> AIRequestOutcome {
        try await GeminiService.callAIReportingProvider(prompt: prompt, images: images)
    }
}
