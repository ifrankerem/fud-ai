import Foundation
import Testing
@testable import calorietracker

struct MealAnalysisPendingQuestionTests {

    private func component(
        id: String,
        name: String,
        grams: Double = 200,
        source: QuantitySource = .visualEstimate
    ) -> MealComponent {
        MealComponent(
            stableID: id,
            name: name,
            grams: grams,
            calories: 250,
            protein: 10,
            carbs: 30,
            fat: 8,
            quantitySource: source
        )
    }

    /// The headline rule: if the user already said "chicken is 185 g", one of the
    /// three available questions must not be spent asking for it again.
    @Test func weightQuestionIsSuppressedForAlreadyMeasuredComponent() {
        let detail = MealAnalysisDetail(
            components: [component(id: "chicken", name: "Chicken", grams: 185, source: .userMeasured)],
            questions: [
                ClarifyingQuestion(
                    id: "chicken_weight",
                    kind: .numericMeasurement,
                    question: "How much chicken?",
                    relatedItemIDs: ["chicken"]
                )
            ]
        )
        #expect(detail.pendingQuestions().isEmpty)
        #expect(!detail.needsClarification)
    }

    @Test func weightQuestionSurvivesForAnEstimatedComponent() {
        let detail = MealAnalysisDetail(
            components: [component(id: "rice", name: "Rice")],
            questions: [
                ClarifyingQuestion(
                    id: "rice_weight",
                    kind: .numericMeasurement,
                    question: "How much rice?",
                    relatedItemIDs: ["rice"]
                )
            ]
        )
        #expect(detail.pendingQuestions().count == 1)
        #expect(detail.needsClarification)
    }

    /// Only weight questions are suppressed by an exact quantity. Knowing the
    /// chicken weighed 185 g says nothing about whether it was fried.
    @Test func nonWeightQuestionSurvivesEvenWhenComponentIsMeasured() {
        let detail = MealAnalysisDetail(
            components: [component(id: "chicken", name: "Chicken", grams: 185, source: .userMeasured)],
            questions: [
                ClarifyingQuestion(
                    id: "chicken_method",
                    kind: .singleChoice,
                    question: "Grilled or fried?",
                    options: ["Grilled", "Fried"],
                    relatedItemIDs: ["chicken"]
                )
            ]
        )
        #expect(detail.pendingQuestions().count == 1)
    }

    /// A weight question covering several components is only pointless when every
    /// one of them is already known.
    @Test func multiComponentWeightQuestionSurvivesIfAnyIsStillEstimated() {
        let detail = MealAnalysisDetail(
            components: [
                component(id: "chicken", name: "Chicken", grams: 185, source: .userMeasured),
                component(id: "rice", name: "Rice")
            ],
            questions: [
                ClarifyingQuestion(
                    id: "weights",
                    kind: .numericMeasurement,
                    question: "Weights?",
                    relatedItemIDs: ["chicken", "rice"]
                )
            ]
        )
        #expect(detail.pendingQuestions().count == 1)
    }

    @Test func answeredQuestionsDropOut() {
        let question = ClarifyingQuestion(
            id: "rice_oil",
            kind: .singleChoice,
            question: "Oily?",
            options: ["Yes", "No"]
        )
        let detail = MealAnalysisDetail(components: [component(id: "rice", name: "Rice")], questions: [question])
        #expect(detail.pendingQuestions().count == 1)

        let answered = detail.applying(answers: [
            ClarificationAnswer(questionID: "rice_oil", kind: .singleChoice, choice: "Yes")
        ])
        #expect(answered.pendingQuestions().isEmpty)
    }

    @Test func unanswerableQuestionsNeverReachTheUser() {
        let detail = MealAnalysisDetail(
            questions: [
                ClarifyingQuestion(id: "broken", kind: .singleChoice, question: "Pick one", options: ["Only"]),
                ClarifyingQuestion(id: "blank", kind: .yesNo, question: "  ")
            ]
        )
        #expect(detail.pendingQuestions().isEmpty)
    }
}

struct MealAnalysisRangeTests {

    private func component(calories: Int, low: Int, high: Int) -> MealComponent {
        MealComponent(
            name: "Part",
            grams: 100,
            calories: calories,
            protein: 5,
            carbs: 10,
            fat: 4,
            calorieRange: CalorieRange(low: low, high: high)
        )
    }

    /// The uncertainty lives in the parts, so the meal range is summed from them
    /// rather than invented separately at the meal level.
    @Test func mealRangeIsSummedFromComponents() {
        let detail = MealAnalysisDetail(
            components: [
                component(calories: 250, low: 220, high: 300),
                component(calories: 300, low: 260, high: 400)
            ],
            calorieRange: CalorieRange(low: 1, high: 9_999)
        )
        #expect(detail.derivedCalorieRange == CalorieRange(low: 480, high: 700))
    }

    /// When the model gave no per-part bounds there is nothing to sum, so its own
    /// meal-level range is the best available answer.
    @Test func fallsBackToMealRangeWhenComponentsHaveNone() {
        let detail = MealAnalysisDetail(
            components: [
                MealComponent(name: "A", grams: 100, calories: 250, protein: 5, carbs: 10, fat: 4)
            ],
            calorieRange: CalorieRange(low: 200, high: 320)
        )
        #expect(detail.derivedCalorieRange == CalorieRange(low: 200, high: 320))
    }

    /// A partial set would sum to a total that silently omits some of the meal.
    @Test func partialComponentRangesDoNotProduceAMisleadingSum() {
        let detail = MealAnalysisDetail(
            components: [
                component(calories: 250, low: 220, high: 300),
                MealComponent(name: "B", grams: 100, calories: 300, protein: 5, carbs: 10, fat: 4)
            ],
            calorieRange: CalorieRange(low: 480, high: 700)
        )
        #expect(detail.derivedCalorieRange == CalorieRange(low: 480, high: 700))
    }

    @Test func scalingCarriesComponentRanges() {
        let detail = MealAnalysisDetail(components: [component(calories: 250, low: 200, high: 300)])
        let scaled = detail.scaled(by: 2)
        #expect(scaled.components.first?.calorieRange == CalorieRange(low: 400, high: 600))
        #expect(scaled.components.first?.calories == 500)
    }
}

struct MealAnalysisProvenanceIntegrationTests {

    @Test func loggingSettlesStatusButKeepsAnswers() {
        let detail = MealAnalysisDetail(
            status: .needsClarification,
            questions: [ClarifyingQuestion(id: "q", kind: .yesNo, question: "Oil?")],
            answers: [ClarificationAnswer(questionID: "q", kind: .yesNo, boolValue: true)]
        )
        let logged = detail.withoutQuestions
        #expect(logged.questions.isEmpty)
        #expect(logged.status == .final)
        #expect(logged.answers.count == 1)
    }

    @Test func userEditFlagIsRecordedOnce() {
        let detail = MealAnalysisDetail(
            provenance: AnalysisProvenance(providerName: "Google Gemini", model: "gemini-3.6-flash")
        )
        #expect(detail.provenance?.userEdited == false)
        let edited = detail.markingUserEdited()
        #expect(edited.provenance?.userEdited == true)
        #expect(edited.markingUserEdited().provenance?.userEdited == true)
    }

    @Test func userEditFlagIsSafeWithoutProvenance() {
        #expect(MealAnalysisDetail().markingUserEdited().provenance == nil)
    }

    @Test func applyingAnswersReplacesRatherThanDuplicates() {
        let detail = MealAnalysisDetail(
            answers: [ClarificationAnswer(questionID: "q", kind: .singleChoice, choice: "Old")]
        )
        let updated = detail.applying(answers: [
            ClarificationAnswer(questionID: "q", kind: .singleChoice, choice: "New")
        ])
        #expect(updated.answers.count == 1)
        #expect(updated.answers.first?.choice == "New")
    }

    @Test func applyingIgnoresBlankAnswers() {
        let updated = MealAnalysisDetail().applying(answers: [
            ClarificationAnswer(questionID: "q", kind: .freeText, text: "   ")
        ])
        #expect(updated.answers.isEmpty)
    }
}

struct MealAnalysisBackwardCompatibilityTests {

    /// Anything already sitting in the diary was settled by the act of logging it,
    /// so it must not decode as still needing clarification.
    @Test func detailWrittenBeforeStatusExistedDecodesAsFinal() throws {
        let legacy = #"{"assumptions":["Assumed grilled"]}"#
        let decoded = try JSONDecoder().decode(MealAnalysisDetail.self, from: Data(legacy.utf8))
        #expect(decoded.status == .final)
        #expect(decoded.assumptions == ["Assumed grilled"])
        #expect(decoded.provenance == nil)
    }

    /// Components stored before provenance existed really were visual estimates.
    /// Decoding them as .unknown would be equally wrong and would start asking
    /// about weights the analysis had in fact estimated.
    @Test func componentWrittenBeforeProvenanceDecodesAsVisualEstimate() throws {
        let legacy = #"{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Rice","grams":200,"calories":260,"protein":5,"carbs":56,"fat":1,"isHidden":false}"#
        let decoded = try JSONDecoder().decode(MealComponent.self, from: Data(legacy.utf8))
        #expect(decoded.quantitySource == .visualEstimate)
        #expect(!decoded.hasExactQuantity)
        #expect(decoded.stableID == decoded.id.uuidString)
        #expect(decoded.uncertainties.isEmpty)
        #expect(decoded.calorieRange == nil)
    }

    @Test func newFieldsSurviveRoundTrip() throws {
        let component = MealComponent(
            stableID: "rice",
            name: "Rice",
            grams: 220,
            calories: 286,
            protein: 5,
            carbs: 62,
            fat: 1,
            quantitySource: .userMeasured,
            preparationMethod: "boiled",
            calorieRange: CalorieRange(low: 260, high: 320),
            uncertainties: ["oil content unknown"]
        )
        let decoded = try JSONDecoder().decode(
            MealComponent.self,
            from: try JSONEncoder().encode(component)
        )
        #expect(decoded.stableID == "rice")
        #expect(decoded.quantitySource == .userMeasured)
        #expect(decoded.preparationMethod == "boiled")
        #expect(decoded.calorieRange == CalorieRange(low: 260, high: 320))
        #expect(decoded.uncertainties == ["oil content unknown"])
    }

    @Test func defaultsAreStillOmittedFromStorage() throws {
        let detail = MealAnalysisDetail(status: .final, assumptions: ["kept"])
        let json = String(decoding: try JSONEncoder().encode(detail), as: UTF8.self)
        #expect(!json.contains("status"))
        #expect(!json.contains("provenance"))
        #expect(json.contains("kept"))
    }

    @Test func emptyDetailStaysEmptyWithNewFields() {
        #expect(MealAnalysisDetail().isEmpty)
        #expect(!MealAnalysisDetail(mealName: "Chicken and rice").isEmpty)
        #expect(!MealAnalysisDetail(majorUncertainties: ["oil"]).isEmpty)
    }
}
