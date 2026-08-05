import Foundation

/// Enforces the rules a model's answer has to obey before it is allowed to become
/// application state.
///
/// Two jobs. First, coherence: a component whose range excludes its own estimate,
/// parts that do not add up to the meal, four questions when three were asked for,
/// a negative gram count. None of these should reach the UI, and none of them are
/// worth a retry — they are fixable in Swift, deterministically.
///
/// Second, and more important: protecting what the user told us. A follow-up
/// analysis is free to revise its own guesses, but it may not quietly replace a
/// weight the user measured with one it estimated. That rule lives here rather
/// than in the prompt, because a prompt is a request and this is a guarantee.
enum MealAnalysisValidator {

    static let maxQuestions = 3
    static let maxAssumptions = 4
    static let maxUncertaintiesPerComponent = 3
    static let maxMajorUncertainties = 3
    static let maxComponents = 12

    struct Outcome {
        var detail: MealAnalysisDetail
        /// Shown to the user without blocking them. Reserved for the case where a
        /// stated measurement was kept but looks wrong — silently overriding it
        /// would be worse, and silently accepting it hides a probable typo.
        var warnings: [String]

        init(detail: MealAnalysisDetail, warnings: [String] = []) {
            self.detail = detail
            self.warnings = warnings
        }
    }

    // MARK: - Single-pass validation

    /// Cleans one analysis against the meal totals it claims to describe.
    static func validate(
        _ detail: MealAnalysisDetail,
        mealCalories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        servingSizeGrams: Double
    ) -> Outcome {
        var result = detail

        result.components = normalizedComponents(
            detail.components,
            mealCalories: mealCalories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            servingSizeGrams: servingSizeGrams
        )
        result.questions = normalizedQuestions(detail.questions, components: result.components)
        result.assumptions = trimmedStrings(detail.assumptions, limit: maxAssumptions, maxLength: 140)
        result.majorUncertainties = trimmedStrings(detail.majorUncertainties, limit: maxMajorUncertainties, maxLength: 140)
        result.calorieRange = normalizedMealRange(detail, components: result.components, calories: mealCalories)
        result.mealName = detail.mealName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        // Status is a conclusion, not something the model gets to assert: it either
        // left answerable questions or it did not.
        result.status = result.pendingQuestions().isEmpty ? .provisional : .needsClarification

        return Outcome(detail: result)
    }

    // MARK: - Two-pass merge

    /// Folds a follow-up analysis into the first one.
    ///
    /// Components are matched by stable id so a revision updates the part it meant
    /// to, rather than being re-matched by name — models rename things between
    /// passes ("rice" becoming "oil-cooked rice") and name matching would either
    /// duplicate the component or drop the revision.
    static func merge(
        stageOne: MealAnalysisDetail,
        stageTwo: MealAnalysisDetail,
        answers: [ClarificationAnswer],
        mealCalories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        servingSizeGrams: Double
    ) -> Outcome {
        var warnings: [String] = []
        let originals = Dictionary(
            stageOne.components.map { ($0.stableID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var merged: [MealComponent] = []
        for var revised in stageTwo.components {
            guard let original = originals[revised.stableID] else {
                merged.append(revised)
                continue
            }
            // Keep the local identity so SwiftUI does not tear down and rebuild the
            // row — and with it any edit in progress.
            revised.id = original.id

            if original.quantitySource.authority > revised.quantitySource.authority,
               abs(original.grams - revised.grams) > 0.5 {
                // The first pass knew something the second pass does not. Restore
                // the measured amount and scale the nutrition it implied, so the
                // component stays internally consistent rather than pairing a
                // measured weight with calories computed for a different one.
                let factor = revised.grams > 0 ? original.grams / revised.grams : 1
                warnings.append(keptMeasurementWarning(for: original))
                revised.grams = original.grams
                revised.quantitySource = original.quantitySource
                if factor.isFinite, factor > 0, factor != 1 {
                    revised.calories = Int((Double(revised.calories) * factor).rounded())
                    revised.protein *= factor
                    revised.carbs *= factor
                    revised.fat *= factor
                    revised.calorieRange = revised.calorieRange?.scaled(by: factor)
                }
            }
            merged.append(revised)
        }

        // A part the follow-up forgot to mention is not a part that vanished.
        let revisedIDs = Set(merged.map(\.stableID))
        for original in stageOne.components where !revisedIDs.contains(original.stableID) {
            merged.append(original)
        }

        var result = stageTwo
        result.components = merged
        result.answers = stageOne.answers
        // A refinement that produced no questions of its own should not resurrect
        // the ones the user just answered.
        result.questions = stageTwo.questions

        let validated = validate(
            result,
            mealCalories: mealCalories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            servingSizeGrams: servingSizeGrams
        )
        var settled = validated.detail.applying(answers: answers)
        settled.status = settled.pendingQuestions().isEmpty ? .final : .needsClarification

        return Outcome(detail: settled, warnings: warnings + validated.warnings)
    }

    /// Stamps quantities the user gave in their answers onto the components those
    /// questions were about. The answer is a measurement; nothing the model
    /// returns outranks it.
    static func applyingMeasuredAnswers(
        to detail: MealAnalysisDetail,
        questions: [ClarifyingQuestion],
        answers: [ClarificationAnswer]
    ) -> MealAnalysisDetail {
        let questionsByID = Dictionary(questions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var components = detail.components

        for answer in answers where answer.impliedQuantitySource != nil {
            guard let grams = gramsValue(of: answer),
                  grams > 0,
                  let question = questionsByID[answer.questionID],
                  question.relatedItemIDs.count == 1,
                  let index = components.firstIndex(where: { $0.stableID == question.relatedItemIDs[0] })
            else { continue }

            let previous = components[index].grams
            let factor = previous > 0 ? grams / previous : 1
            components[index].grams = grams
            components[index].quantitySource = .userMeasured
            if factor.isFinite, factor > 0, factor != 1 {
                components[index].calories = Int((Double(components[index].calories) * factor).rounded())
                components[index].protein *= factor
                components[index].carbs *= factor
                components[index].fat *= factor
                components[index].calorieRange = components[index].calorieRange?.scaled(by: factor)
            }
        }

        var result = detail
        result.components = components
        return result
    }

    // MARK: - Component rules

    private static func normalizedComponents(
        _ components: [MealComponent],
        mealCalories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        servingSizeGrams: Double
    ) -> [MealComponent] {
        var cleaned: [MealComponent] = []
        var usedIDs = Set<String>()

        for var component in components.prefix(maxComponents) {
            component.name = component.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !component.name.isEmpty else { continue }
            component.clampToNonNegative()
            component.note = component.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            component.preparationMethod = component.preparationMethod?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            component.uncertainties = trimmedStrings(
                component.uncertainties,
                limit: maxUncertaintiesPerComponent,
                maxLength: 120
            )
            component.calorieRange = normalizedRange(component.calorieRange, around: component.calories)

            // Duplicate ids would make a follow-up analysis update the wrong part.
            if !usedIDs.insert(component.stableID).inserted {
                component.stableID = "\(component.stableID)-\(usedIDs.count)"
                usedIDs.insert(component.stableID)
            }
            cleaned.append(component)
        }

        // A lone component restates the meal and adds nothing but a row.
        guard cleaned.count > 1 else { return [] }

        var reconciled = MealAnalysisDetail.reconcile(
            cleaned,
            toCalories: mealCalories,
            protein: protein,
            carbs: carbs,
            fat: fat
        )

        // Reconciling moved the calories, so a range validated against the old
        // figure may no longer contain the new one. Re-check after, not before.
        for index in reconciled.indices {
            reconciled[index].calorieRange = normalizedRange(
                reconciled[index].calorieRange,
                around: reconciled[index].calories
            )
        }

        // Grams are their own axis: a model can get the calories right and still
        // hand back parts that do not add up to the plate weight. Components the
        // user actually measured are excluded from the correction — they are not
        // the ones that are wrong.
        reconciled = normalizedGrams(reconciled, to: servingSizeGrams)
        return reconciled
    }

    private static func normalizedGrams(_ components: [MealComponent], to servingSizeGrams: Double) -> [MealComponent] {
        guard servingSizeGrams > 0 else { return components }
        let total = components.reduce(0.0) { $0 + $1.grams }
        guard total > 0 else { return components }
        guard abs(total / servingSizeGrams - 1) > 0.02 else { return components }

        let fixedTotal = components.filter(\.hasExactQuantity).reduce(0.0) { $0 + $1.grams }
        let adjustableTotal = total - fixedTotal
        let adjustableTarget = servingSizeGrams - fixedTotal

        // Measured parts alone already exceed the plate weight, so the plate weight
        // is what is wrong. Leave every component alone rather than shrinking a
        // measurement to fit a guess.
        guard adjustableTotal > 0, adjustableTarget > 0 else { return components }

        let factor = adjustableTarget / adjustableTotal
        guard factor.isFinite, factor > 0 else { return components }

        return components.map { component in
            guard !component.hasExactQuantity else { return component }
            var copy = component
            copy.grams = component.grams * factor
            return copy
        }
    }

    // MARK: - Range rules

    /// A range that excludes its own point estimate is incoherent, and one with no
    /// width is not a range. Neither is worth showing.
    static func normalizedRange(_ range: CalorieRange?, around calories: Int) -> CalorieRange? {
        guard let range else { return nil }
        let widened = calories > 0 ? range.containing(calories) : range
        return widened.isMeaningful ? widened : nil
    }

    private static func normalizedMealRange(
        _ detail: MealAnalysisDetail,
        components: [MealComponent],
        calories: Int
    ) -> CalorieRange? {
        var candidate = detail
        candidate.components = components
        // Prefer bounds summed from the parts: that is where the uncertainty is.
        return normalizedRange(candidate.derivedCalorieRange, around: calories)
    }

    // MARK: - Question rules

    private static func normalizedQuestions(
        _ questions: [ClarifyingQuestion],
        components: [MealComponent]
    ) -> [ClarifyingQuestion] {
        let componentIDs = Set(components.map(\.stableID))
        var cleaned: [ClarifyingQuestion] = []
        var usedIDs = Set<String>()
        var usedText = Set<String>()

        for var question in questions {
            question.question = question.question.trimmingCharacters(in: .whitespacesAndNewlines)
            question.reason = question.reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            question.options = trimmedStrings(question.options, limit: 4, maxLength: 40, deduplicate: true)
            // A reference to a component that does not exist would make the
            // "already measured" check silently pass on nothing.
            question.relatedItemIDs = question.relatedItemIDs.filter { componentIDs.contains($0) }

            guard question.isRenderable else { continue }
            guard usedIDs.insert(question.id).inserted else { continue }
            guard usedText.insert(question.question.lowercased()).inserted else { continue }

            cleaned.append(question)
            if cleaned.count >= maxQuestions { break }
        }
        return cleaned
    }

    // MARK: - Helpers

    private static func gramsValue(of answer: ClarificationAnswer) -> Double? {
        guard let value = answer.numericValue, value > 0 else { return nil }
        let unit = (answer.unit ?? "g").lowercased()
        switch unit {
        case "g", "gram", "grams", "ml": return value
        case "kg": return value * 1000
        case "oz": return value * 28.3495
        case "lb", "lbs": return value * 453.592
        case "l": return value * 1000
        // Anything whose weight depends on the food cannot be converted here; the
        // model is told the amount instead and can price it properly.
        default: return nil
        }
    }

    private static func keptMeasurementWarning(for component: MealComponent) -> String {
        let amount = component.grams == component.grams.rounded()
            ? String(Int(component.grams))
            : String(format: "%.1f", component.grams)
        return "Kept your \(amount) g for \(component.name) instead of the new estimate."
    }

    private static func trimmedStrings(
        _ values: [String],
        limit: Int,
        maxLength: Int,
        deduplicate: Bool = true
    ) -> [String] {
        var results: [String] = []
        var seen = Set<String>()
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let capped = String(trimmed.prefix(maxLength))
            if deduplicate, !seen.insert(capped.lowercased()).inserted { continue }
            results.append(capped)
            if results.count >= limit { break }
        }
        return results
    }
}

// File-private, matching the convention already used in ExerciseLibraryItem.swift.
// An internal one would be ambiguous against that file's private copy.
private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
