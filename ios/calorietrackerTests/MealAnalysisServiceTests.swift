import Foundation
import Testing
import UIKit
@testable import calorietracker

/// Canned provider replies. Nothing here touches the network or a Keychain entry.
private enum Fixture {

    static func response(
        calories: Int = 500,
        items: String,
        questions: String = "[]",
        status: String = "provisional",
        extra: String = ""
    ) -> String {
        """
        {"name":"Chicken and rice","calories":\(calories),"protein":45.0,"carbs":50.0,"fat":15.0,
         "serving_size_grams":400.0,"emoji":"🍗","status":"\(status)","meal_name":"Chicken and rice",
         "items":\(items),"questions":\(questions)\(extra)}
        """
    }

    static let chickenAndRice = """
    [{"id":"chicken","name":"Grilled chicken","estimated_quantity":200,"unit":"g",
      "quantity_source":"visual_estimate","calories":250,"protein":40,"carbs":0,"fat":11,
      "calorie_min":220,"calorie_max":300},
     {"id":"rice","name":"Rice","estimated_quantity":200,"unit":"g",
      "quantity_source":"visual_estimate","calories":250,"protein":5,"carbs":50,"fat":4,
      "calorie_min":210,"calorie_max":330}]
    """

    static let oilQuestion = """
    [{"id":"rice_oil","type":"single_choice","question":"How oily was the rice?",
      "reason":"Oil is the largest source of uncertainty.",
      "options":["No added oil","Lightly oiled","Normal","Very oily"],
      "related_item_ids":["rice"]}]
    """

    static let weightQuestion = """
    [{"id":"chicken_weight","type":"numeric_measurement","question":"How much chicken?",
      "unit":"g","related_item_ids":["chicken"]}]
    """

    static func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}

struct MealAnalysisServiceStageOneTests {

    @Test func producesComponentsAndQuestions() async throws {
        let stub = StubAIRequestDispatcher(
            response: Fixture.response(items: Fixture.chickenAndRice, questions: Fixture.oilQuestion, status: "needs_clarification")
        )
        let outcome = try await MealAnalysisService(dispatcher: stub)
            .analyze(images: [LabelledImage(image: Fixture.image())])

        #expect(outcome.analysis.calories == 500)
        #expect(outcome.detail.components.count == 2)
        #expect(outcome.detail.questions.count == 1)
        #expect(outcome.needsClarification)
        #expect(outcome.detail.status == .needsClarification)
    }

    /// Meal bounds are summed from the parts rather than taken on trust.
    @Test func mealRangeComesFromTheComponents() async throws {
        let stub = StubAIRequestDispatcher(response: Fixture.response(items: Fixture.chickenAndRice))
        let outcome = try await MealAnalysisService(dispatcher: stub)
            .analyze(images: [LabelledImage(image: Fixture.image())])
        #expect(outcome.detail.calorieRange == CalorieRange(low: 430, high: 630))
    }

    @Test func recordsWhichProviderAnswered() async throws {
        let stub = StubAIRequestDispatcher(
            responses: [.success(Fixture.response(items: Fixture.chickenAndRice))],
            providerName: "Anthropic Claude",
            model: "claude-sonnet-5"
        )
        let outcome = try await MealAnalysisService(dispatcher: stub)
            .analyze(images: [LabelledImage(image: Fixture.image())])

        #expect(outcome.detail.provenance?.providerName == "Anthropic Claude")
        #expect(outcome.detail.provenance?.model == "claude-sonnet-5")
        #expect(outcome.detail.provenance?.stage == .initial)
        #expect(outcome.detail.provenance?.userEdited == false)
    }

    // MARK: - Measurements from the note

    /// The headline rule: a weight the user already gave must not be asked for again.
    @Test func statedWeightSuppressesItsOwnQuestion() async throws {
        let stub = StubAIRequestDispatcher(
            response: Fixture.response(items: Fixture.chickenAndRice, questions: Fixture.weightQuestion, status: "needs_clarification")
        )
        let outcome = try await MealAnalysisService(dispatcher: stub).analyze(
            images: [LabelledImage(image: Fixture.image())],
            note: "Chicken 220 g, rice 200 g"
        )

        let chicken = outcome.detail.components.first { $0.stableID == "chicken" }
        #expect(chicken?.quantitySource == .userMeasured)
        #expect(chicken?.grams == 220)
        #expect(outcome.detail.pendingQuestions().isEmpty)
        #expect(!outcome.needsClarification)
    }

    @Test func statedMeasurementsReachThePrompt() async throws {
        let stub = StubAIRequestDispatcher(response: Fixture.response(items: Fixture.chickenAndRice))
        _ = try await MealAnalysisService(dispatcher: stub).analyze(
            images: [LabelledImage(image: Fixture.image())],
            note: "Chicken 185 g"
        )
        let prompt = stub.sentPrompts.first ?? ""
        #expect(prompt.contains("185"))
        #expect(prompt.contains("EXACT"))
    }

    /// A hedged number is a hint, not a measurement, so the question stays.
    @Test func hedgedAmountDoesNotSuppressTheQuestion() async throws {
        let stub = StubAIRequestDispatcher(
            response: Fixture.response(items: Fixture.chickenAndRice, questions: Fixture.weightQuestion, status: "needs_clarification")
        )
        let outcome = try await MealAnalysisService(dispatcher: stub).analyze(
            images: [LabelledImage(image: Fixture.image())],
            note: "about 220 g chicken"
        )
        #expect(outcome.detail.components.first { $0.stableID == "chicken" }?.quantitySource != .userMeasured)
        #expect(outcome.needsClarification)
    }

    /// A wild mismatch more likely means the names collided than that the user
    /// weighed something four times heavier than it looks.
    @Test func implausibleNameMatchIsNotClaimed() async throws {
        let stub = StubAIRequestDispatcher(response: Fixture.response(items: Fixture.chickenAndRice))
        let outcome = try await MealAnalysisService(dispatcher: stub).analyze(
            images: [LabelledImage(image: Fixture.image())],
            note: "rice 5000 g"
        )
        #expect(outcome.detail.components.first { $0.stableID == "rice" }?.quantitySource == .visualEstimate)
    }

    // MARK: - Photo labels

    @Test func photoLabelsReachThePrompt() async throws {
        let stub = StubAIRequestDispatcher(response: Fixture.response(items: Fixture.chickenAndRice))
        _ = try await MealAnalysisService(dispatcher: stub).analyze(images: [
            LabelledImage(image: Fixture.image(), kind: .beforeEating),
            LabelledImage(image: Fixture.image(), kind: .kitchenScale)
        ])
        let prompt = stub.sentPrompts.first ?? ""
        #expect(prompt.contains("kitchen scale"))
        #expect(prompt.contains("overrides any visual portion estimate"))
    }

    /// Multiple angles of one plate must not be added up.
    @Test func repeatViewsCarryADoNotDoubleCountInstruction() async throws {
        let stub = StubAIRequestDispatcher(response: Fixture.response(items: Fixture.chickenAndRice))
        _ = try await MealAnalysisService(dispatcher: stub).analyze(images: [
            LabelledImage(image: Fixture.image(), kind: .anotherAngle),
            LabelledImage(image: Fixture.image(), kind: .anotherAngle)
        ])
        #expect(stub.sentPrompts.first?.contains("Do not count the same food twice") == true)
        #expect(stub.sentImageCounts.first == 2)
    }
}

struct MealAnalysisServiceStageTwoTests {

    private func stageOne(
        questions: String = Fixture.oilQuestion
    ) async throws -> (MealAnalysisOutcome, StubAIRequestDispatcher) {
        let stub = StubAIRequestDispatcher(
            response: Fixture.response(items: Fixture.chickenAndRice, questions: questions, status: "needs_clarification")
        )
        let outcome = try await MealAnalysisService(dispatcher: stub)
            .analyze(images: [LabelledImage(image: Fixture.image())])
        return (outcome, stub)
    }

    @Test func answeringUpdatesTheEstimate() async throws {
        let (first, _) = try await stageOne()
        let oilier = """
        [{"id":"chicken","name":"Grilled chicken","estimated_quantity":200,"unit":"g","calories":250,"protein":40,"carbs":0,"fat":11},
         {"id":"rice","name":"Oil-cooked rice","estimated_quantity":200,"unit":"g","calories":400,"protein":5,"carbs":50,"fat":20}]
        """
        let stub = StubAIRequestDispatcher(
            response: Fixture.response(calories: 650, items: oilier, status: "final")
        )
        let refined = try await MealAnalysisService(dispatcher: stub).refine(
            previous: first,
            answers: [ClarificationAnswer(questionID: "rice_oil", kind: .singleChoice, choice: "Very oily")],
            images: [LabelledImage(image: Fixture.image())]
        )

        #expect(refined.analysis.calories == 650)
        #expect(refined.detail.status == .final)
        #expect(refined.detail.provenance?.stage == .refined)
        #expect(refined.detail.answers.count == 1)
    }

    @Test func theAnswerReachesTheFollowUpPrompt() async throws {
        let (first, _) = try await stageOne()
        let stub = StubAIRequestDispatcher(response: Fixture.response(items: Fixture.chickenAndRice, status: "final"))
        _ = try await MealAnalysisService(dispatcher: stub).refine(
            previous: first,
            answers: [ClarificationAnswer(
                questionID: "rice_oil",
                kind: .singleChoice,
                questionText: "How oily was the rice?",
                choice: "Very oily"
            )],
            images: [LabelledImage(image: Fixture.image())]
        )
        let prompt = stub.sentPrompts.first ?? ""
        #expect(prompt.contains("Very oily"))
        // The previous pass travels as validated JSON so the ids survive.
        #expect(prompt.contains("\"id\":\"rice\""))
    }

    /// The rule the two-stage design rests on.
    @Test func stageTwoCannotOverwriteAMeasuredWeight() async throws {
        let stub = StubAIRequestDispatcher(
            response: Fixture.response(items: Fixture.chickenAndRice, questions: Fixture.weightQuestion, status: "needs_clarification")
        )
        let first = try await MealAnalysisService(dispatcher: stub).analyze(
            images: [LabelledImage(image: Fixture.image())],
            note: "chicken 220 g"
        )
        #expect(first.detail.components.first { $0.stableID == "chicken" }?.grams == 220)

        let disagreeing = """
        [{"id":"chicken","name":"Grilled chicken","estimated_quantity":320,"unit":"g","quantity_source":"visual_estimate","calories":400,"protein":60,"carbs":0,"fat":16},
         {"id":"rice","name":"Rice","estimated_quantity":200,"unit":"g","calories":250,"protein":5,"carbs":50,"fat":4}]
        """
        let second = StubAIRequestDispatcher(response: Fixture.response(calories: 650, items: disagreeing, status: "final"))
        let refined = try await MealAnalysisService(dispatcher: second).refine(
            previous: first,
            answers: [ClarificationAnswer(questionID: "q", kind: .yesNo, boolValue: true)],
            images: [LabelledImage(image: Fixture.image())]
        )

        let chicken = refined.detail.components.first { $0.stableID == "chicken" }
        #expect(chicken?.grams == 220)
        #expect(chicken?.quantitySource == .userMeasured)
        #expect(!refined.warnings.isEmpty)
    }

    /// A number typed in answer to "how much chicken?" is a measurement.
    @Test func numericAnswerBecomesAMeasurement() async throws {
        let (first, _) = try await stageOne(questions: Fixture.weightQuestion)
        let stub = StubAIRequestDispatcher(response: Fixture.response(items: Fixture.chickenAndRice, status: "final"))
        let refined = try await MealAnalysisService(dispatcher: stub).refine(
            previous: first,
            answers: [ClarificationAnswer(
                questionID: "chicken_weight",
                kind: .numericMeasurement,
                numericValue: 300,
                unit: "g"
            )],
            images: [LabelledImage(image: Fixture.image())]
        )
        let chicken = refined.detail.components.first { $0.stableID == "chicken" }
        #expect(chicken?.quantitySource == .userMeasured)
        #expect(chicken?.grams == 300)
    }

    /// Spending an API call to say "the user skipped everything" buys latency and
    /// cost and nothing else.
    @Test func skippingEveryQuestionMakesNoSecondCall() async throws {
        let (first, _) = try await stageOne()
        let stub = StubAIRequestDispatcher(response: Fixture.response(items: Fixture.chickenAndRice))
        let refined = try await MealAnalysisService(dispatcher: stub).refine(
            previous: first,
            answers: [],
            images: [LabelledImage(image: Fixture.image())]
        )
        #expect(stub.callCount == 0)
        #expect(refined.detail.status == .final)
        #expect(refined.detail.questions.isEmpty)
    }

    /// Skipping must still leave a loggable estimate — that is the whole promise.
    @Test func skippedEstimateIsStillComplete() async throws {
        let (first, _) = try await stageOne()
        let skipped = MealAnalysisService(dispatcher: StubAIRequestDispatcher(response: "{}")).skipping(first)
        #expect(skipped.analysis.calories == 500)
        #expect(skipped.detail.components.count == 2)
        #expect(skipped.detail.status == .final)
        #expect(skipped.detail.questions.isEmpty)
    }
}

struct MealAnalysisServiceRobustnessTests {

    /// The content is usually right and only the wrapper is wrong, so one repair
    /// attempt is worth far more than re-running the analysis.
    @Test func malformedJSONGetsOneRepairAttempt() async throws {
        let stub = StubAIRequestDispatcher(responses: [
            .success("Here is the meal!\n```json\n{\"name\": broken,,}\n```"),
            .success(Fixture.response(items: Fixture.chickenAndRice))
        ])
        let outcome = try await MealAnalysisService(dispatcher: stub)
            .analyze(images: [LabelledImage(image: Fixture.image())])

        #expect(stub.callCount == 2)
        #expect(stub.sentPrompts[1].contains("could not be parsed"))
        #expect(outcome.analysis.calories == 500)
    }

    /// The repair call fixes punctuation; crediting it with the analysis would
    /// blame the wrong model in accuracy stats.
    @Test func repairDoesNotStealProvenance() async throws {
        let stub = StubAIRequestDispatcher(
            responses: [.success("not json"), .success(Fixture.response(items: Fixture.chickenAndRice))],
            providerName: "Groq",
            model: "llama-4"
        )
        let outcome = try await MealAnalysisService(dispatcher: stub)
            .analyze(images: [LabelledImage(image: Fixture.image())])
        #expect(outcome.detail.provenance?.providerName == "Groq")
    }

    /// Two failures in a row is a real failure; the caller falls back to the
    /// existing single-pass analysis rather than the app pretending.
    @Test func repeatedFailureThrowsRatherThanFabricating() async {
        let stub = StubAIRequestDispatcher(responses: [.success("not json"), .success("still not json")])
        await #expect(throws: (any Error).self) {
            try await MealAnalysisService(dispatcher: stub)
                .analyze(images: [LabelledImage(image: Fixture.image())])
        }
    }

    @Test func transportErrorsPropagate() async {
        struct Offline: Error {}
        let stub = StubAIRequestDispatcher(error: Offline())
        await #expect(throws: Offline.self) {
            try await MealAnalysisService(dispatcher: stub)
                .analyze(images: [LabelledImage(image: Fixture.image())])
        }
    }

    /// A provider that ignores the component instruction still has to produce a
    /// usable meal — a breakdown is a bonus, not a precondition.
    @Test func replyWithoutComponentsStillProducesAnEstimate() async throws {
        let stub = StubAIRequestDispatcher(response: """
        {"name":"Soup","calories":320,"protein":12.0,"carbs":30.0,"fat":14.0,"serving_size_grams":350.0}
        """)
        let outcome = try await MealAnalysisService(dispatcher: stub)
            .analyze(images: [LabelledImage(image: Fixture.image())])

        #expect(outcome.analysis.calories == 320)
        #expect(outcome.detail.components.isEmpty)
        #expect(!outcome.needsClarification)
    }

    @Test func missingOptionalNutrientsParseFine() async throws {
        let stub = StubAIRequestDispatcher(response: """
        {"name":"Soup","calories":320,"protein":12.0,"carbs":30.0,"fat":14.0,
         "serving_size_grams":350.0,"sodium":null,"vitamin_a":null,"iron":null}
        """)
        let outcome = try await MealAnalysisService(dispatcher: stub)
            .analyze(images: [LabelledImage(image: Fixture.image())])
        #expect(outcome.analysis.sodium == nil)
        #expect(outcome.analysis.calories == 320)
    }
}
