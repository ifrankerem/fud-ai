import Foundation
import Testing
@testable import calorietracker

struct ConfidenceScoreTests {

    @Test func parsesBucketNames() {
        #expect(ConfidenceScore.parse("high")?.level == .high)
        #expect(ConfidenceScore.parse("  Medium ")?.level == .medium)
        #expect(ConfidenceScore.parse("LOW")?.level == .low)
    }

    @Test func bucketNameCarriesNoFakePercent() {
        #expect(ConfidenceScore.parse("high")?.percent == nil)
        #expect(ConfidenceScore.parse("high")?.displayText == AnalysisConfidence.high.displayName)
    }

    @Test func parsesFractionAsPercent() {
        let score = ConfidenceScore.parse(0.72)
        #expect(score?.percent == 72)
        #expect(score?.level == .medium)
    }

    @Test func parsesWholePercent() {
        #expect(ConfidenceScore.parse(85)?.percent == 85)
        #expect(ConfidenceScore.parse(85)?.level == .high)
        #expect(ConfidenceScore.parse(45)?.level == .low)
    }

    /// 1 is ambiguous between "100%" and "1%". A 1% confidence is not a real answer.
    @Test func treatsOneAsFullConfidence() {
        #expect(ConfidenceScore.parse(1)?.percent == 100)
    }

    @Test func parsesPercentString() {
        #expect(ConfidenceScore.parse("72%")?.percent == 72)
    }

    @Test func parsesDictionaryShape() {
        #expect(ConfidenceScore.parse(["level": "medium", "percent": 65])?.percent == 65)
        #expect(ConfidenceScore.parse(["level": "low"])?.level == .low)
    }

    @Test func rejectsGarbage() {
        #expect(ConfidenceScore.parse("pretty sure") == nil)
        #expect(ConfidenceScore.parse(nil) == nil)
        #expect(ConfidenceScore.parse([1, 2, 3]) == nil)
    }

    @Test func clampsOutOfRangePercent() {
        #expect(ConfidenceScore(percent: 140).percent == 100)
        #expect(ConfidenceScore(percent: -20).percent == 0)
    }
}

struct CalorieRangeTests {

    @Test func normalizesReversedBounds() {
        let range = CalorieRange(low: 760, high: 620)
        #expect(range.low == 620)
        #expect(range.high == 760)
    }

    @Test func zeroWidthRangeIsNotMeaningful() {
        #expect(CalorieRange(low: 700, high: 700).isMeaningful == false)
        #expect(CalorieRange(low: 620, high: 760).isMeaningful)
    }

    @Test func scalesWithPortion() {
        let doubled = CalorieRange(low: 620, high: 760).scaled(by: 2)
        #expect(doubled.low == 1240)
        #expect(doubled.high == 1520)
    }

    @Test func ignoresNonsenseScaleFactors() {
        let range = CalorieRange(low: 620, high: 760)
        #expect(range.scaled(by: 0) == range)
        #expect(range.scaled(by: -1) == range)
    }

    /// After a manual correction the original bounds can fall entirely on one side of
    /// the number on screen; the range has to stretch to keep containing it.
    @Test func stretchesToContainPointEstimate() {
        let range = CalorieRange(low: 800, high: 900).containing(700)
        #expect(range.low == 700)
        #expect(range.high == 900)
    }

    @Test func containingLeavesRangeAloneWhenAlreadyInside() {
        let range = CalorieRange(low: 620, high: 760).containing(700)
        #expect(range == CalorieRange(low: 620, high: 760))
    }
}

struct MealComponentTests {

    @Test func scalingMovesEveryAxis() {
        let component = MealComponent(name: "Rice", grams: 180, calories: 234, protein: 4.3, carbs: 51, fat: 0.5)
        let scaled = component.scaled(by: 0.5)
        #expect(scaled.grams == 90)
        #expect(scaled.calories == 117)
        #expect(scaled.protein == 2.15)
        #expect(scaled.id == component.id)
    }

    @Test func negativeInputIsClampedAtInit() {
        let component = MealComponent(name: "Oil", grams: -10, calories: -5, protein: -1, carbs: 0, fat: 0)
        #expect(component.grams == 0)
        #expect(component.calories == 0)
        #expect(component.protein == 0)
    }

    @Test func reconcileMatchesCalorieTotalExactly() {
        let components = [
            MealComponent(name: "A", grams: 100, calories: 100, protein: 10, carbs: 0, fat: 0),
            MealComponent(name: "B", grams: 100, calories: 100, protein: 10, carbs: 0, fat: 0),
            MealComponent(name: "C", grams: 100, calories: 100, protein: 10, carbs: 0, fat: 0)
        ]
        // 350/3 does not divide evenly — rounding drift has to land somewhere.
        let reconciled = MealAnalysisDetail.reconcile(components, toCalories: 350, protein: 30, carbs: 0, fat: 0)
        #expect(reconciled.reduce(0) { $0 + $1.calories } == 350)
    }

    @Test func reconcileMatchesMacroTotals() {
        let components = [
            MealComponent(name: "Chicken", grams: 150, calories: 250, protein: 40, carbs: 0, fat: 9),
            MealComponent(name: "Rice", grams: 200, calories: 260, protein: 5, carbs: 56, fat: 1)
        ]
        let reconciled = MealAnalysisDetail.reconcile(components, toCalories: 510, protein: 50, carbs: 60, fat: 12)
        let protein = reconciled.reduce(0.0) { $0 + $1.protein }
        let carbs = reconciled.reduce(0.0) { $0 + $1.carbs }
        let fat = reconciled.reduce(0.0) { $0 + $1.fat }
        #expect(abs(protein - 50) < 0.001)
        #expect(abs(carbs - 60) < 0.001)
        #expect(abs(fat - 12) < 0.001)
    }

    /// A macro that is zero across every part has no distribution to preserve; the
    /// rescale must leave it alone instead of dividing by zero.
    @Test func reconcileSkipsAllZeroMacro() {
        let components = [
            MealComponent(name: "A", grams: 100, calories: 100, protein: 0, carbs: 20, fat: 0),
            MealComponent(name: "B", grams: 100, calories: 100, protein: 0, carbs: 20, fat: 0)
        ]
        let reconciled = MealAnalysisDetail.reconcile(components, toCalories: 200, protein: 10, carbs: 40, fat: 0)
        #expect(reconciled.allSatisfy { $0.protein == 0 })
        #expect(reconciled.reduce(0.0) { $0 + $1.carbs } == 40)
    }
}

struct MealDetailParsingTests {

    private func parse(_ json: [String: Any], calories: Int = 500, grams: Double = 400) -> MealAnalysisDetail {
        GeminiService.parseMealDetail(
            from: json,
            calories: calories,
            protein: 40,
            carbs: 50,
            fat: 15,
            servingSizeGrams: grams
        )
    }

    @Test func parsesFullPayload() {
        let detail = parse([
            "components": [
                ["name": "Grilled chicken", "grams": 150, "calories": 250, "protein": 35, "carbs": 0, "fat": 11, "confidence": "high"],
                ["name": "Rice", "grams": 200, "calories": 230, "protein": 5, "carbs": 50, "fat": 1, "confidence": "medium"],
                ["name": "Olive oil", "grams": 5, "calories": 45, "protein": 0, "carbs": 0, "fat": 5, "hidden": true, "note": "assumed 1 tsp"]
            ],
            "calorie_range": ["low": 450, "high": 600],
            "confidence": "medium",
            "assumptions": ["Assumed grilled, not fried", "Assumed 1 tsp of oil"],
            "questions": [["question": "Grilled or fried?", "options": ["Grilled", "Fried"]]]
        ])

        #expect(detail.components.count == 3)
        #expect(detail.calorieRange == CalorieRange(low: 450, high: 600))
        #expect(detail.confidence?.level == .medium)
        #expect(detail.assumptions.count == 2)
        #expect(detail.questions.count == 1)
        #expect(detail.components[2].isHidden)
        #expect(detail.components[2].note == "assumed 1 tsp")
        #expect(detail.components[0].confidence?.level == .high)
    }

    @Test func componentCaloriesAreForcedToMatchMealTotal() {
        let detail = parse([
            "components": [
                ["name": "A", "grams": 200, "calories": 200, "protein": 20, "carbs": 25, "fat": 7],
                ["name": "B", "grams": 200, "calories": 200, "protein": 20, "carbs": 25, "fat": 8]
            ]
        ], calories: 500)
        #expect(detail.componentCalories == 500)
    }

    @Test func componentGramsAreForcedToMatchServingWeight() {
        let detail = parse([
            "components": [
                ["name": "A", "grams": 100, "calories": 250, "protein": 20, "carbs": 25, "fat": 7],
                ["name": "B", "grams": 100, "calories": 250, "protein": 20, "carbs": 25, "fat": 8]
            ]
        ], grams: 400)
        #expect(abs(detail.componentGrams - 400) < 0.001)
    }

    /// A lone component just restates the meal — it costs a row and adds nothing.
    @Test func singleComponentIsDropped() {
        let detail = parse([
            "components": [["name": "Apple", "grams": 180, "calories": 95, "protein": 0.5, "carbs": 25, "fat": 0.3]]
        ])
        #expect(detail.components.isEmpty)
    }

    @Test func unnamedComponentsAreSkipped() {
        let detail = parse([
            "components": [
                ["name": "A", "grams": 100, "calories": 250, "protein": 20, "carbs": 25, "fat": 7],
                ["grams": 100, "calories": 250],
                ["name": "  ", "grams": 50, "calories": 100],
                ["name": "B", "grams": 100, "calories": 250, "protein": 20, "carbs": 25, "fat": 8]
            ]
        ])
        #expect(detail.components.map(\.name) == ["A", "B"])
    }

    @Test func degenerateRangeIsDropped() {
        let detail = parse(["calorie_range": ["low": 500, "high": 500]])
        #expect(detail.calorieRange == nil)
    }

    @Test func rangeIsWidenedToContainTheCalorieFigure() {
        let detail = parse(["calorie_range": ["low": 600, "high": 700]], calories: 500)
        #expect(detail.calorieRange == CalorieRange(low: 500, high: 700))
    }

    @Test func parsesRangeFromArrayAndString() {
        #expect(parse(["calorie_range": [450, 600]]).calorieRange == CalorieRange(low: 450, high: 600))
        #expect(parse(["calorie_range": "450–600 kcal"]).calorieRange == CalorieRange(low: 450, high: 600))
    }

    /// A question with nothing to tap is just noise next to the context field.
    @Test func questionsNeedAtLeastTwoOptions() {
        let detail = parse([
            "questions": [
                ["question": "Grilled?", "options": ["Yes"]],
                ["question": "Sauce?", "options": ["Yes", "No"]],
                ["question": "Oily?"]
            ]
        ])
        #expect(detail.questions.map(\.question) == ["Sauce?"])
    }

    @Test func duplicateOptionsAreCollapsed() {
        let detail = parse([
            "questions": [["question": "Sauce?", "options": ["Yes", "yes", "No"]]]
        ])
        #expect(detail.questions.first?.options == ["Yes", "No"])
    }

    @Test func questionsAreCappedAtThree() {
        let questions = (1...6).map { ["question": "Q\($0)", "options": ["A", "B"]] }
        #expect(parse(["questions": questions]).questions.count == 3)
    }

    @Test func assumptionsAreCappedAtFour() {
        let detail = parse(["assumptions": ["a", "b", "c", "d", "e", "f"]])
        #expect(detail.assumptions.count == 4)
    }

    @Test func missingPayloadYieldsEmptyDetail() {
        #expect(parse([:]).isEmpty)
    }

    /// Providers that ignore the instruction must not break the analysis.
    @Test func malformedPayloadIsIgnoredNotFatal() {
        let detail = parse([
            "components": "not an array",
            "calorie_range": "nonsense",
            "confidence": ["unexpected": true],
            "assumptions": [42, ["text": "kept"]],
            "questions": "also not an array"
        ])
        #expect(detail.components.isEmpty)
        #expect(detail.calorieRange == nil)
        #expect(detail.questions.isEmpty)
        #expect(detail.assumptions == ["kept"])
    }
}

struct FoodEntryAnalysisDetailPersistenceTests {

    private func makeEntry(detail: MealAnalysisDetail) -> FoodEntry {
        FoodEntry(
            name: "Chicken and rice",
            calories: 500,
            protein: 40,
            carbs: 50,
            fat: 15,
            source: .snapFood,
            servingSizeGrams: 400,
            analysisDetail: detail
        )
    }

    private func roundTrip(_ entry: FoodEntry) throws -> FoodEntry {
        let data = try JSONEncoder().encode(entry)
        return try JSONDecoder().decode(FoodEntry.self, from: data)
    }

    @Test func detailSurvivesRoundTrip() throws {
        let detail = MealAnalysisDetail(
            components: [
                MealComponent(name: "Chicken", grams: 150, calories: 250, protein: 35, carbs: 0, fat: 11, confidence: ConfidenceScore(level: .high)),
                MealComponent(name: "Oil", grams: 5, calories: 45, protein: 0, carbs: 0, fat: 5, isHidden: true, note: "1 tsp")
            ],
            calorieRange: CalorieRange(low: 450, high: 600),
            confidence: ConfidenceScore(percent: 65),
            assumptions: ["Assumed grilled"]
        )
        let decoded = try roundTrip(makeEntry(detail: detail))

        #expect(decoded.analysisDetail.components.count == 2)
        #expect(decoded.analysisDetail.components[1].isHidden)
        #expect(decoded.analysisDetail.components[1].note == "1 tsp")
        #expect(decoded.analysisDetail.calorieRange == CalorieRange(low: 450, high: 600))
        #expect(decoded.analysisDetail.confidence?.percent == 65)
        #expect(decoded.analysisDetail.assumptions == ["Assumed grilled"])
    }

    /// Entries logged before this feature carry no detail key at all.
    @Test func entryWithoutDetailDecodesToEmpty() throws {
        let decoded = try roundTrip(makeEntry(detail: .empty))
        #expect(decoded.analysisDetail.isEmpty)
    }

    @Test func emptyDetailIsNotWrittenToDisk() throws {
        let data = try JSONEncoder().encode(makeEntry(detail: .empty))
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("analysisDetail"))
    }

    @Test func questionsAreStrippedForStorage() {
        let detail = MealAnalysisDetail(
            assumptions: ["kept"],
            questions: [ClarifyingQuestion(question: "Grilled?", options: ["Yes", "No"])]
        )
        #expect(detail.withoutQuestions.questions.isEmpty)
        #expect(detail.withoutQuestions.assumptions == ["kept"])
    }

    /// The edit screen changes meal totals without touching individual parts, so it
    /// rescales the stored breakdown and pins it back to the new totals.
    @Test func scaleThenReconcileKeepsPartsAddingUp() {
        let detail = MealAnalysisDetail(components: [
            MealComponent(name: "Chicken", grams: 150, calories: 250, protein: 35, carbs: 0, fat: 11),
            MealComponent(name: "Rice", grams: 200, calories: 250, protein: 5, carbs: 55, fat: 1)
        ])
        let adjusted = detail
            .scaled(by: 1.5)
            .reconciled(toCalories: 750, protein: 60, carbs: 82.5, fat: 18)

        #expect(adjusted.componentCalories == 750)
        #expect(abs(adjusted.componentGrams - 525) < 0.001)
        #expect(abs(adjusted.components.reduce(0.0) { $0 + $1.protein } - 60) < 0.001)
    }

    @Test func detailFollowsADuplicatedEntry() throws {
        let entry = makeEntry(detail: MealAnalysisDetail(
            components: [
                MealComponent(name: "A", grams: 100, calories: 250, protein: 20, carbs: 25, fat: 7),
                MealComponent(name: "B", grams: 100, calories: 250, protein: 20, carbs: 25, fat: 8)
            ],
            confidence: ConfidenceScore(level: .medium)
        ))
        let copy = entry.duplicatedForLogging(at: .now)
        #expect(copy.analysisDetail.components.count == 2)
        #expect(copy.analysisDetail.confidence?.level == .medium)
    }
}
