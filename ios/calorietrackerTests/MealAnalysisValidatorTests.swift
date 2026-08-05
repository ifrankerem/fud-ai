import Foundation
import Testing
@testable import calorietracker

private func makeComponent(
    id: String,
    name: String = "Part",
    grams: Double = 100,
    calories: Int = 200,
    protein: Double = 10,
    carbs: Double = 20,
    fat: Double = 8,
    source: QuantitySource = .visualEstimate,
    range: CalorieRange? = nil
) -> MealComponent {
    MealComponent(
        stableID: id,
        name: name,
        grams: grams,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        quantitySource: source,
        calorieRange: range
    )
}

struct MealAnalysisValidatorRuleTests {

    private func validate(_ detail: MealAnalysisDetail, calories: Int = 400, grams: Double = 200) -> MealAnalysisDetail {
        MealAnalysisValidator.validate(
            detail,
            mealCalories: calories,
            protein: 20,
            carbs: 40,
            fat: 16,
            servingSizeGrams: grams
        ).detail
    }

    /// The model does not get to assert that it is confident: status is a
    /// conclusion drawn from whether it left answerable questions.
    @Test func statusIsDerivedNotTrusted() {
        let claimingFinal = MealAnalysisDetail(
            status: .final,
            components: [makeComponent(id: "a"), makeComponent(id: "b")],
            questions: [ClarifyingQuestion(id: "q", kind: .yesNo, question: "Any oil?")]
        )
        #expect(validate(claimingFinal).status == .needsClarification)

        let claimingUnsure = MealAnalysisDetail(
            status: .needsClarification,
            components: [makeComponent(id: "a"), makeComponent(id: "b")]
        )
        #expect(validate(claimingUnsure).status == .provisional)
    }

    @Test func questionsAreCappedAtThree() {
        let questions = (1...6).map {
            ClarifyingQuestion(id: "q\($0)", kind: .yesNo, question: "Question \($0)?")
        }
        #expect(validate(MealAnalysisDetail(questions: questions)).questions.count == 3)
    }

    @Test func duplicateQuestionsAreDropped() {
        let detail = MealAnalysisDetail(questions: [
            ClarifyingQuestion(id: "a", kind: .yesNo, question: "Any oil?"),
            ClarifyingQuestion(id: "b", kind: .yesNo, question: "ANY OIL?"),
            ClarifyingQuestion(id: "a", kind: .yesNo, question: "Different text")
        ])
        #expect(validate(detail).questions.count == 1)
    }

    @Test func unanswerableQuestionsAreDropped() {
        let detail = MealAnalysisDetail(questions: [
            ClarifyingQuestion(id: "a", kind: .singleChoice, question: "Pick", options: ["Only"]),
            ClarifyingQuestion(id: "b", kind: .yesNo, question: "   "),
            ClarifyingQuestion(id: "c", kind: .yesNo, question: "Real question?")
        ])
        #expect(validate(detail).questions.map(\.id) == ["c"])
    }

    /// A dangling component reference would make the "already measured" check
    /// silently pass on nothing, so a redundant question would survive.
    @Test func referencesToMissingComponentsAreStripped() {
        let detail = MealAnalysisDetail(
            components: [makeComponent(id: "rice"), makeComponent(id: "chicken")],
            questions: [
                ClarifyingQuestion(
                    id: "q",
                    kind: .numericMeasurement,
                    question: "How much?",
                    relatedItemIDs: ["rice", "ghost"]
                )
            ]
        )
        #expect(validate(detail).questions.first?.relatedItemIDs == ["rice"])
    }

    @Test func duplicateComponentIDsAreMadeUnique() {
        let detail = MealAnalysisDetail(components: [
            makeComponent(id: "same", name: "A"),
            makeComponent(id: "same", name: "B")
        ])
        let ids = validate(detail).components.map(\.stableID)
        #expect(Set(ids).count == 2)
    }

    @Test func optionsAreDroppedForNonChoiceQuestions() {
        let detail = MealAnalysisDetail(questions: [
            ClarifyingQuestion(id: "q", kind: .numericMeasurement, question: "How much rice?", options: [])
        ])
        #expect(validate(detail).questions.first?.options.isEmpty == true)
    }

    @Test func componentRangeIsWidenedToContainItsOwnEstimate() {
        let detail = MealAnalysisDetail(components: [
            makeComponent(id: "a", calories: 200, range: CalorieRange(low: 300, high: 400)),
            makeComponent(id: "b", calories: 200, range: CalorieRange(low: 150, high: 260))
        ])
        let first = validate(detail).components.first
        #expect(first?.calorieRange?.low == 200)
    }

    @Test func degenerateComponentRangeIsDropped() {
        let detail = MealAnalysisDetail(components: [
            makeComponent(id: "a", calories: 200, range: CalorieRange(low: 200, high: 200)),
            makeComponent(id: "b", calories: 200)
        ])
        #expect(validate(detail).components.first?.calorieRange == nil)
    }

    /// Grams are their own axis; the parts have to add up to the plate weight.
    @Test func componentGramsAreScaledToTheServingWeight() {
        let detail = MealAnalysisDetail(components: [
            makeComponent(id: "a", grams: 50),
            makeComponent(id: "b", grams: 50)
        ])
        let result = validate(detail, grams: 400)
        #expect(abs(result.componentGrams - 400) < 0.01)
    }

    /// A weight the user measured is not the thing that is wrong. Scaling it to
    /// make a guessed total add up would destroy the only hard number present.
    @Test func measuredComponentIsExemptFromGramNormalisation() {
        let detail = MealAnalysisDetail(components: [
            makeComponent(id: "chicken", grams: 185, source: .userMeasured),
            makeComponent(id: "rice", grams: 100)
        ])
        let result = validate(detail, grams: 385)
        let chicken = result.components.first { $0.stableID == "chicken" }
        let rice = result.components.first { $0.stableID == "rice" }
        #expect(chicken?.grams == 185)
        #expect(abs((rice?.grams ?? 0) - 200) < 0.01)
    }

    /// When measured parts alone exceed the stated plate weight, the plate weight
    /// is what is wrong. Shrinking a measurement to fit a guess would be backwards.
    @Test func nothingIsScaledWhenMeasurementsExceedTheStatedWeight() {
        let detail = MealAnalysisDetail(components: [
            makeComponent(id: "chicken", grams: 400, source: .userMeasured),
            makeComponent(id: "rice", grams: 100, source: .kitchenScale)
        ])
        let result = validate(detail, grams: 200)
        #expect(result.components.map(\.grams) == [400, 100])
    }

    @Test func singleComponentIsDropped() {
        #expect(validate(MealAnalysisDetail(components: [makeComponent(id: "a")])).components.isEmpty)
    }

    @Test func namelessComponentsAreDropped() {
        let detail = MealAnalysisDetail(components: [
            makeComponent(id: "a", name: "  "),
            makeComponent(id: "b", name: "Rice"),
            makeComponent(id: "c", name: "Chicken")
        ])
        #expect(validate(detail).components.map(\.name) == ["Rice", "Chicken"])
    }

    @Test func assumptionsAndUncertaintiesAreBounded() {
        let detail = MealAnalysisDetail(
            assumptions: (1...9).map { "assumption \($0)" },
            majorUncertainties: (1...9).map { "uncertainty \($0)" }
        )
        let result = validate(detail)
        #expect(result.assumptions.count == MealAnalysisValidator.maxAssumptions)
        #expect(result.majorUncertainties.count == MealAnalysisValidator.maxMajorUncertainties)
    }
}

struct MealAnalysisMergeTests {

    private func merge(
        stageOne: MealAnalysisDetail,
        stageTwo: MealAnalysisDetail,
        answers: [ClarificationAnswer] = []
    ) -> MealAnalysisValidator.Outcome {
        MealAnalysisValidator.merge(
            stageOne: stageOne,
            stageTwo: stageTwo,
            answers: answers,
            mealCalories: 400,
            protein: 20,
            carbs: 40,
            fat: 16,
            servingSizeGrams: 300
        )
    }

    /// The rule the whole two-stage design rests on: a follow-up analysis may
    /// revise its own guesses, but it may not quietly replace a weight the user
    /// measured with one it estimated.
    @Test func stageTwoCannotOverwriteAMeasuredQuantity() {
        let stageOne = MealAnalysisDetail(components: [
            makeComponent(id: "chicken", grams: 185, source: .userMeasured),
            makeComponent(id: "rice", grams: 115)
        ])
        let stageTwo = MealAnalysisDetail(components: [
            makeComponent(id: "chicken", grams: 250, source: .visualEstimate),
            makeComponent(id: "rice", grams: 115)
        ])
        let outcome = merge(stageOne: stageOne, stageTwo: stageTwo)
        let chicken = outcome.detail.components.first { $0.stableID == "chicken" }
        #expect(chicken?.grams == 185)
        #expect(chicken?.quantitySource == .userMeasured)
    }

    /// Overriding silently would be worse than not overriding at all, so the user
    /// is told what was kept.
    @Test func keepingAMeasurementProducesAVisibleWarning() {
        let stageOne = MealAnalysisDetail(components: [
            makeComponent(id: "chicken", name: "Chicken", grams: 185, source: .userMeasured),
            makeComponent(id: "rice", grams: 115)
        ])
        let stageTwo = MealAnalysisDetail(components: [
            makeComponent(id: "chicken", name: "Chicken", grams: 250),
            makeComponent(id: "rice", grams: 115)
        ])
        let outcome = merge(stageOne: stageOne, stageTwo: stageTwo)
        #expect(outcome.warnings.count == 1)
        #expect(outcome.warnings.first?.contains("Chicken") == true)
        #expect(outcome.warnings.first?.contains("185") == true)
    }

    /// Restoring the weight without restoring the nutrition would leave the
    /// component describing 185 g with calories computed for 250 g.
    @Test func restoringAMeasurementRescalesItsNutrition() {
        let stageOne = MealAnalysisDetail(components: [
            makeComponent(id: "chicken", grams: 100, source: .userMeasured),
            makeComponent(id: "rice", grams: 200)
        ])
        let stageTwo = MealAnalysisDetail(components: [
            makeComponent(id: "chicken", grams: 200, calories: 400, protein: 40, source: .visualEstimate),
            makeComponent(id: "rice", grams: 200, calories: 200, protein: 10)
        ])
        let outcome = merge(stageOne: stageOne, stageTwo: stageTwo)
        let chicken = outcome.detail.components.first { $0.stableID == "chicken" }
        #expect(chicken?.grams == 100)
        // Halved weight means halved nutrition, then reconciled to the meal totals.
        #expect((chicken?.protein ?? 0) < (outcome.detail.components.first { $0.stableID == "rice" }?.protein ?? 0) * 3)
    }

    /// A guess has no authority to protect; the second pass is exactly the point.
    @Test func stageTwoFreelyRevisesAnEstimate() {
        let stageOne = MealAnalysisDetail(components: [
            makeComponent(id: "rice", grams: 100),
            makeComponent(id: "chicken", grams: 100)
        ])
        let stageTwo = MealAnalysisDetail(components: [
            makeComponent(id: "rice", grams: 200),
            makeComponent(id: "chicken", grams: 100)
        ])
        let outcome = merge(stageOne: stageOne, stageTwo: stageTwo)
        #expect(outcome.warnings.isEmpty)
        let rice = outcome.detail.components.first { $0.stableID == "rice" }
        #expect((rice?.grams ?? 0) > 100)
    }

    /// Models rename things between passes; matching by id rather than name is
    /// what stops a rename from duplicating or dropping a component.
    @Test func componentsMatchByIDNotName() {
        let stageOne = MealAnalysisDetail(components: [
            makeComponent(id: "rice", name: "Rice", grams: 150, source: .userMeasured),
            makeComponent(id: "chicken", name: "Chicken", grams: 150)
        ])
        let stageTwo = MealAnalysisDetail(components: [
            makeComponent(id: "rice", name: "Oil-cooked rice", grams: 250),
            makeComponent(id: "chicken", name: "Chicken", grams: 150)
        ])
        let outcome = merge(stageOne: stageOne, stageTwo: stageTwo)
        #expect(outcome.detail.components.count == 2)
        let rice = outcome.detail.components.first { $0.stableID == "rice" }
        #expect(rice?.name == "Oil-cooked rice")
        #expect(rice?.grams == 150)
    }

    /// A part the follow-up forgot to mention is not a part that vanished.
    @Test func componentsMissingFromStageTwoAreCarriedForward() {
        let stageOne = MealAnalysisDetail(components: [
            makeComponent(id: "rice", grams: 100),
            makeComponent(id: "chicken", grams: 100),
            makeComponent(id: "salad", grams: 100)
        ])
        let stageTwo = MealAnalysisDetail(components: [
            makeComponent(id: "rice", grams: 100),
            makeComponent(id: "chicken", grams: 100)
        ])
        let outcome = merge(stageOne: stageOne, stageTwo: stageTwo)
        #expect(Set(outcome.detail.components.map(\.stableID)) == ["rice", "chicken", "salad"])
    }

    @Test func mergedResultIsFinalOnceNoQuestionsRemain() {
        let stageOne = MealAnalysisDetail(components: [makeComponent(id: "a"), makeComponent(id: "b")])
        let stageTwo = MealAnalysisDetail(components: [makeComponent(id: "a"), makeComponent(id: "b")])
        let answers = [ClarificationAnswer(questionID: "q", kind: .yesNo, boolValue: true)]
        let outcome = merge(stageOne: stageOne, stageTwo: stageTwo, answers: answers)
        #expect(outcome.detail.status == .final)
        #expect(outcome.detail.answers.count == 1)
    }
}

struct MeasuredAnswerApplicationTests {

    /// A number the user typed in answer to "how much rice?" is a measurement, and
    /// nothing the model returns outranks it.
    @Test func numericAnswerBecomesTheComponentQuantity() {
        let detail = MealAnalysisDetail(components: [
            makeComponent(id: "rice", grams: 150, calories: 200),
            makeComponent(id: "chicken", grams: 150)
        ])
        let question = ClarifyingQuestion(
            id: "rice_weight",
            kind: .numericMeasurement,
            question: "How much rice?",
            relatedItemIDs: ["rice"]
        )
        let answer = ClarificationAnswer(
            questionID: "rice_weight",
            kind: .numericMeasurement,
            numericValue: 300,
            unit: "g"
        )

        let result = MealAnalysisValidator.applyingMeasuredAnswers(
            to: detail,
            questions: [question],
            answers: [answer]
        )
        let rice = result.components.first { $0.stableID == "rice" }
        #expect(rice?.grams == 300)
        #expect(rice?.quantitySource == .userMeasured)
        #expect(rice?.calories == 400)
    }

    @Test func unitsAreConvertedToGrams() {
        let detail = MealAnalysisDetail(components: [
            makeComponent(id: "beef", grams: 100),
            makeComponent(id: "rice", grams: 100)
        ])
        let question = ClarifyingQuestion(
            id: "beef_weight",
            kind: .numericMeasurement,
            question: "How much beef?",
            relatedItemIDs: ["beef"]
        )
        let answer = ClarificationAnswer(
            questionID: "beef_weight",
            kind: .numericMeasurement,
            numericValue: 1,
            unit: "kg"
        )
        let result = MealAnalysisValidator.applyingMeasuredAnswers(
            to: detail,
            questions: [question],
            answers: [answer]
        )
        #expect(result.components.first { $0.stableID == "beef" }?.grams == 1000)
    }

    /// "2 slices" cannot be converted here — a slice of bread and of cake are not
    /// the same weight. The model is told the amount instead.
    @Test func foodDependentUnitsAreNotGuessed() {
        let detail = MealAnalysisDetail(components: [
            makeComponent(id: "bread", grams: 100),
            makeComponent(id: "cheese", grams: 100)
        ])
        let question = ClarifyingQuestion(
            id: "bread_amount",
            kind: .numericMeasurement,
            question: "How much bread?",
            relatedItemIDs: ["bread"]
        )
        let answer = ClarificationAnswer(
            questionID: "bread_amount",
            kind: .numericMeasurement,
            numericValue: 2,
            unit: "slice"
        )
        let result = MealAnalysisValidator.applyingMeasuredAnswers(
            to: detail,
            questions: [question],
            answers: [answer]
        )
        #expect(result.components.first { $0.stableID == "bread" }?.grams == 100)
    }

    @Test func answersWithoutASingleTargetAreIgnored() {
        let detail = MealAnalysisDetail(components: [
            makeComponent(id: "a", grams: 100),
            makeComponent(id: "b", grams: 100)
        ])
        let ambiguous = ClarifyingQuestion(
            id: "weights",
            kind: .numericMeasurement,
            question: "Weights?",
            relatedItemIDs: ["a", "b"]
        )
        let answer = ClarificationAnswer(questionID: "weights", kind: .numericMeasurement, numericValue: 500, unit: "g")
        let result = MealAnalysisValidator.applyingMeasuredAnswers(
            to: detail,
            questions: [ambiguous],
            answers: [answer]
        )
        #expect(result.components.map(\.grams) == [100, 100])
    }

    @Test func dontKnowChangesNothing() {
        let detail = MealAnalysisDetail(components: [
            makeComponent(id: "rice", grams: 150),
            makeComponent(id: "chicken", grams: 150)
        ])
        let question = ClarifyingQuestion(
            id: "rice_weight",
            kind: .numericMeasurement,
            question: "How much rice?",
            relatedItemIDs: ["rice"]
        )
        let answer = ClarificationAnswer(questionID: "rice_weight", kind: .numericMeasurement, isDontKnow: true)
        let result = MealAnalysisValidator.applyingMeasuredAnswers(
            to: detail,
            questions: [question],
            answers: [answer]
        )
        #expect(result.components.first { $0.stableID == "rice" }?.quantitySource == .visualEstimate)
    }
}
