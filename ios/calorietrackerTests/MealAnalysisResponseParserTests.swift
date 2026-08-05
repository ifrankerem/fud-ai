import Foundation
import Testing
@testable import calorietracker

struct MealAnalysisResponseParserTests {

    private func parse(
        _ json: [String: Any],
        calories: Int = 500,
        protein: Double = 40,
        carbs: Double = 50,
        fat: Double = 15,
        grams: Double = 400
    ) -> MealAnalysisDetail {
        MealAnalysisResponseParser.parseDetail(
            from: json,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            servingSizeGrams: grams
        )
    }

    private func twoItems(_ extra: [String: Any] = [:]) -> [[String: Any]] {
        var first: [String: Any] = [
            "id": "chicken", "name": "Grilled chicken", "estimated_quantity": 200, "unit": "g",
            "calories": 250, "protein": 35, "carbs": 0, "fat": 11
        ]
        first.merge(extra) { _, new in new }
        let second: [String: Any] = [
            "id": "rice", "name": "Rice", "estimated_quantity": 200, "unit": "g",
            "calories": 250, "protein": 5, "carbs": 50, "fat": 4
        ]
        return [first, second]
    }

    // MARK: - The spec's shape

    @Test func parsesTheDocumentedSchema() {
        let detail = parse([
            "status": "needs_clarification",
            "meal_name": "Chicken, rice and yogurt",
            "items": twoItems([
                "quantity_source": "visual_estimate",
                "preparation_method": "grilled",
                "calorie_min": 220,
                "calorie_max": 300,
                "confidence": 0.86,
                "assumptions": ["Skinless chicken breast"],
                "uncertainties": ["Exact cooked weight is unknown"]
            ]),
            "calorie_range": ["low": 450, "high": 620],
            "overall_confidence": 0.72,
            "major_uncertainties": ["Rice oil quantity"],
            "questions": [[
                "id": "rice_oil",
                "type": "single_choice",
                "question": "How oily was the rice?",
                "reason": "Oil is the largest source of uncertainty.",
                "options": ["No added oil", "Lightly oiled", "Normal", "Very oily"],
                "related_item_ids": ["rice"]
            ]]
        ])

        #expect(detail.mealName == "Chicken, rice and yogurt")
        #expect(detail.components.count == 2)
        #expect(detail.confidence?.percent == 72)
        #expect(detail.majorUncertainties == ["Rice oil quantity"])
        #expect(detail.status == .needsClarification)

        let chicken = detail.components.first { $0.stableID == "chicken" }
        #expect(chicken?.preparationMethod == "grilled")
        #expect(chicken?.quantitySource == .visualEstimate)
        #expect(chicken?.confidence?.percent == 86)
        #expect(chicken?.uncertainties == ["Exact cooked weight is unknown"])

        let question = detail.questions.first
        #expect(question?.id == "rice_oil")
        #expect(question?.kind == .singleChoice)
        #expect(question?.reason == "Oil is the largest source of uncertainty.")
        #expect(question?.relatedItemIDs == ["rice"])
        #expect(question?.options.count == 4)
    }

    // MARK: - Quantities

    @Test func convertsStatedUnitsToGrams() {
        let detail = parse([
            "items": [
                ["id": "beef", "name": "Beef", "estimated_quantity": 0.5, "unit": "kg", "calories": 250],
                ["id": "oil", "name": "Oil", "estimated_quantity": 1, "unit": "oz", "calories": 250]
            ]
        ], grams: 528)
        let beef = detail.components.first { $0.stableID == "beef" }
        #expect(abs((beef?.grams ?? 0) - 500) < 1)
    }

    /// A unit whose weight depends on the food is left alone rather than converted
    /// with an invented density.
    @Test func foodDependentUnitsPassThroughUnconverted() {
        let detail = parse([
            "items": [
                ["id": "bread", "name": "Bread", "estimated_quantity": 2, "unit": "slice", "calories": 160],
                ["id": "jam", "name": "Jam", "estimated_quantity": 1, "unit": "tbsp", "calories": 60]
            ]
        ], calories: 220, grams: 3)
        #expect(detail.components.count == 2)
    }

    @Test func readsQuantitySourceInAnyCasing() {
        let detail = parse(["items": twoItems(["quantity_source": "KITCHEN-SCALE"])])
        #expect(detail.components.first { $0.stableID == "chicken" }?.quantitySource == .kitchenScale)
        #expect(detail.components.first { $0.stableID == "chicken" }?.hasExactQuantity == true)
    }

    /// An unreadable provenance must not become a claim of measurement.
    @Test func unknownQuantitySourceIsNotExact() {
        let detail = parse(["items": twoItems(["quantity_source": "vibes"])])
        #expect(detail.components.first { $0.stableID == "chicken" }?.quantitySource == .unknown)
        #expect(detail.components.first { $0.stableID == "chicken" }?.hasExactQuantity == false)
    }

    // MARK: - Ranges

    @Test func readsPerItemBounds() {
        let detail = parse([
            "items": [
                ["id": "a", "name": "A", "estimated_quantity": 200, "calories": 250, "calorie_min": 220, "calorie_max": 300],
                ["id": "b", "name": "B", "estimated_quantity": 200, "calories": 250, "calorie_min": 200, "calorie_max": 320]
            ]
        ])
        #expect(detail.components.allSatisfy { $0.calorieRange != nil })
        // Meal bounds are summed from the parts, not taken from the model.
        #expect(detail.calorieRange == CalorieRange(low: 420, high: 620))
    }

    @Test func fallsBackToMealBoundsWhenPartsHaveNone() {
        let detail = parse(["items": twoItems(), "calorie_range": "450–620 kcal"])
        #expect(detail.calorieRange == CalorieRange(low: 450, high: 620))
    }

    @Test func readsRangeFromAnArray() {
        let detail = parse(["items": twoItems(), "calorie_range": [450, 620]])
        #expect(detail.calorieRange == CalorieRange(low: 450, high: 620))
    }

    // MARK: - Questions

    /// Options without a declared type mean a choice — that is what options are for.
    @Test func optionsImplyAChoiceWhenTypeIsMissing() {
        let detail = parse([
            "questions": [["id": "a", "question": "Grilled or fried?", "options": ["Grilled", "Fried"]]]
        ])
        #expect(detail.questions.first?.kind == .singleChoice)
    }

    /// A single option is a malformed choice, not a free-text question. Silently
    /// reclassifying it would turn "Grilled?" into a typing prompt.
    @Test func malformedChoiceIsDroppedRatherThanReclassified() {
        let detail = parse([
            "questions": [
                ["id": "broken", "question": "Grilled?", "options": ["Yes"]],
                ["id": "ok", "question": "Sauce?", "options": ["Yes", "No"]]
            ]
        ])
        #expect(detail.questions.map(\.id) == ["ok"])
    }

    /// Neither a type nor options means the control to show is unknowable.
    /// Offering a free-text box hands the user a chore they will not do.
    @Test func underSpecifiedQuestionIsDropped() {
        #expect(parse(["questions": [["id": "a", "question": "Describe the sauce"]]]).questions.isEmpty)
    }

    @Test func explicitFreeTextIsHonoured() {
        let detail = parse([
            "questions": [["id": "a", "type": "free_text", "question": "Describe the sauce"]]
        ])
        #expect(detail.questions.first?.kind == .freeText)
    }

    @Test func readsNumericQuestionUnit() {
        let detail = parse([
            "questions": [[
                "id": "rice_weight",
                "type": "numeric_measurement",
                "question": "How much rice?",
                "unit": "g"
            ]]
        ])
        let question = detail.questions.first
        #expect(question?.kind == .numericMeasurement)
        #expect(question?.suggestedUnit == "g")
        #expect(question?.options.isEmpty == true)
    }

    @Test func readsPhotoRequestKind() {
        let detail = parse([
            "questions": [[
                "id": "scale_photo",
                "type": "request_additional_photo",
                "question": "Can you photograph the scale?",
                "photo_kind": "kitchen_scale"
            ]]
        ])
        #expect(detail.questions.first?.kind == .requestAdditionalPhoto)
        #expect(detail.questions.first?.requestedPhotoKind == .kitchenScale)
    }

    /// Ids matter: they are how answers get matched back. A model that omits them
    /// must still produce addressable questions and components.
    @Test func missingIDsFallBackToPositions() {
        let detail = parse([
            "items": [
                ["name": "A", "estimated_quantity": 200, "calories": 250],
                ["name": "B", "estimated_quantity": 200, "calories": 250]
            ],
            "questions": [["question": "Any oil?", "type": "yes_no"]]
        ])
        #expect(detail.components.map(\.stableID) == ["item-1", "item-2"])
        #expect(detail.questions.first?.id == "question-1")
    }

    // MARK: - Robustness

    /// A model asked for a list sometimes sends one string; treating that as
    /// "nothing" would discard a real answer.
    @Test func acceptsASingleStringWhereAListWasAsked() {
        let detail = parse(["assumptions": "Assumed grilled, not fried"])
        #expect(detail.assumptions == ["Assumed grilled, not fried"])
    }

    @Test func acceptsNumbersSentAsStrings() {
        let detail = parse([
            "items": [
                ["id": "a", "name": "A", "estimated_quantity": "200", "calories": "250"],
                ["id": "b", "name": "B", "estimated_quantity": "200", "calories": "250"]
            ]
        ])
        #expect(detail.components.first?.calories == 250)
        #expect(detail.components.first?.grams == 200)
    }

    @Test func malformedPayloadDegradesInsteadOfFailing() {
        let detail = parse([
            "status": 42,
            "items": "not an array",
            "calorie_range": "nonsense",
            "confidence": ["unexpected": true],
            "questions": ["also not an object"],
            "major_uncertainties": [17, ["text": "kept"]]
        ])
        #expect(detail.components.isEmpty)
        #expect(detail.calorieRange == nil)
        #expect(detail.questions.isEmpty)
        #expect(detail.majorUncertainties == ["kept"])
        #expect(detail.status == .provisional)
    }

    @Test func emptyPayloadYieldsEmptyDetail() {
        #expect(parse([:]).isEmpty)
    }

    @Test func negativeValuesAreClampedNotPropagated() {
        let detail = parse([
            "items": [
                ["id": "a", "name": "A", "estimated_quantity": -50, "calories": -100, "protein": -5],
                ["id": "b", "name": "B", "estimated_quantity": 200, "calories": 500, "protein": 40]
            ]
        ])
        #expect(detail.components.allSatisfy { $0.grams >= 0 && $0.calories >= 0 && $0.protein >= 0 })
    }

    /// Confidence is a 0...1 concept however it arrives; a nonsense figure must not
    /// reach the UI as "3200% sure".
    @Test func confidenceIsClamped() {
        #expect(parse(["confidence": 32]).confidence?.percent == 32)
        #expect(parse(["confidence": 320]).confidence?.percent == 100)
        #expect(parse(["confidence": -5]).confidence == nil)
    }

    @Test func acceptsBothComponentsAndItemsKeys() {
        #expect(parse(["components": twoItems()]).components.count == 2)
        #expect(parse(["items": twoItems()]).components.count == 2)
    }
}
