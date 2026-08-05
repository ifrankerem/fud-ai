import Foundation

/// Turns a provider's reply into a `MealAnalysisDetail`.
///
/// Every field is optional by design. Providers differ in how well they follow a
/// schema, and a model that ignores half the instruction should still produce a
/// usable meal estimate — just one with less to show. The alternative, failing the
/// analysis because `major_uncertainties` was missing, would trade a real feature
/// for a cosmetic one.
///
/// Nothing here trusts the input: quantities can arrive negative, confidence as
/// a sentence, a range as a string, `components` as an object instead of an array.
/// Each is handled or dropped. Validation of the *relationships* between fields —
/// parts summing to the meal, ranges containing their estimate — is
/// `MealAnalysisValidator`'s job, not this one's.
enum MealAnalysisResponseParser {

    /// Reads the component / uncertainty block out of an already-decoded JSON
    /// object. Totals are passed in because the meal's own calories and weight are
    /// parsed elsewhere, and the components have to be reconciled against them.
    static func parseDetail(
        from json: [String: Any],
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        servingSizeGrams: Double
    ) -> MealAnalysisDetail {
        let detail = MealAnalysisDetail(
            status: parseStatus(json["status"]),
            mealName: string(json["meal_name"] ?? json["mealName"]),
            components: parseComponents(json["components"] ?? json["items"]),
            calorieRange: parseCalorieRange(from: json["calorie_range"] ?? json["calorieRange"]),
            confidence: ConfidenceScore.parse(json["confidence"] ?? json["overall_confidence"] ?? json["overallConfidence"]),
            assumptions: parseStringList(json["assumptions"], keys: ["text", "assumption", "note"]),
            questions: parseQuestions(json["questions"] ?? json["clarifying_questions"] ?? json["clarifyingQuestions"]),
            majorUncertainties: parseStringList(
                json["major_uncertainties"] ?? json["majorUncertainties"] ?? json["uncertainties"],
                keys: ["text", "uncertainty", "note"]
            )
        )

        return MealAnalysisValidator.validate(
            detail,
            mealCalories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            servingSizeGrams: servingSizeGrams
        ).detail
    }

    // MARK: - Status

    private static func parseStatus(_ raw: Any?) -> MealAnalysisStatus {
        guard let string = raw as? String else { return .provisional }
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "needsclarification", "clarify", "incomplete", "unsure": return .needsClarification
        case "final", "complete", "done", "confident": return .final
        default: return .provisional
        }
    }

    // MARK: - Components

    private static func parseComponents(_ raw: Any?) -> [MealComponent] {
        guard let list = raw as? [Any] else { return [] }

        var components: [MealComponent] = []
        for (index, element) in list.enumerated() {
            guard let item = element as? [String: Any] else { continue }
            guard let name = string(item["name"] ?? item["food"] ?? item["label"]) else { continue }

            let calories = Int((double(item["calories"] ?? item["kcal"]) ?? 0).rounded())
            let quantity = double(item["estimated_quantity"] ?? item["estimatedQuantity"] ?? item["grams"] ?? item["quantity"]) ?? 0

            components.append(
                MealComponent(
                    // Fall back to a positional id so a model that omits ids still
                    // produces components a follow-up pass can address.
                    stableID: string(item["id"] ?? item["item_id"] ?? item["itemId"]) ?? "item-\(index + 1)",
                    name: name,
                    grams: gramsValue(quantity: quantity, unit: string(item["unit"])),
                    calories: calories,
                    protein: double(item["protein"]) ?? 0,
                    carbs: double(item["carbs"] ?? item["carbohydrates"]) ?? 0,
                    fat: double(item["fat"]) ?? 0,
                    confidence: ConfidenceScore.parse(item["confidence"]),
                    isHidden: bool(item["hidden"] ?? item["is_hidden"] ?? item["isHidden"]) ?? false,
                    note: string(item["note"], maxLength: 80),
                    quantitySource: QuantitySource.parse(item["quantity_source"] ?? item["quantitySource"]),
                    preparationMethod: string(item["preparation_method"] ?? item["preparationMethod"], maxLength: 40),
                    calorieRange: parseComponentRange(item, calories: calories),
                    uncertainties: parseStringList(item["uncertainties"], keys: ["text", "uncertainty"])
                )
            )
        }
        return components
    }

    /// Converts a stated amount to grams when the unit allows it. Units whose
    /// weight depends on the food are left as-is: pretending a "slice" is a fixed
    /// number of grams would invent precision that is not there.
    private static func gramsValue(quantity: Double, unit: String?) -> Double {
        guard quantity > 0 else { return 0 }
        guard let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !unit.isEmpty else {
            return quantity
        }
        switch unit {
        case "g", "gr", "gram", "grams", "ml", "milliliter", "millilitre": return quantity
        case "kg", "kilogram", "kilograms": return quantity * 1000
        case "mg": return quantity * 0.001
        case "l", "liter", "litre": return quantity * 1000
        case "oz", "ounce", "ounces": return quantity * 28.3495
        case "lb", "lbs", "pound", "pounds": return quantity * 453.592
        default: return quantity
        }
    }

    private static func parseComponentRange(_ item: [String: Any], calories: Int) -> CalorieRange? {
        if let low = double(item["calorie_min"] ?? item["calorieMin"] ?? item["min_calories"]),
           let high = double(item["calorie_max"] ?? item["calorieMax"] ?? item["max_calories"]) {
            return MealAnalysisValidator.normalizedRange(
                CalorieRange(low: Int(low.rounded()), high: Int(high.rounded())),
                around: calories
            )
        }
        return MealAnalysisValidator.normalizedRange(
            parseCalorieRange(from: item["calorie_range"] ?? item["calorieRange"]),
            around: calories
        )
    }

    // MARK: - Ranges

    static func parseCalorieRange(from raw: Any?) -> CalorieRange? {
        if let dictionary = raw as? [String: Any] {
            guard let low = double(dictionary["low"] ?? dictionary["min"]),
                  let high = double(dictionary["high"] ?? dictionary["max"])
            else { return nil }
            return CalorieRange(low: Int(low.rounded()), high: Int(high.rounded()))
        }
        if let pair = raw as? [Any], pair.count == 2,
           let low = double(pair[0]), let high = double(pair[1]) {
            return CalorieRange(low: Int(low.rounded()), high: Int(high.rounded()))
        }
        // "620-760", "620–760 kcal"
        if let text = raw as? String {
            let parts = text
                .replacingOccurrences(of: "–", with: "-")
                .replacingOccurrences(of: "—", with: "-")
                .replacingOccurrences(of: "kcal", with: "")
                .split(separator: "-")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 {
                return CalorieRange(low: Int(parts[0].rounded()), high: Int(parts[1].rounded()))
            }
        }
        return nil
    }

    // MARK: - Questions

    private static func parseQuestions(_ raw: Any?) -> [ClarifyingQuestion] {
        guard let list = raw as? [Any] else { return [] }

        var questions: [ClarifyingQuestion] = []
        for (index, element) in list.enumerated() {
            guard let item = element as? [String: Any] else { continue }
            guard let text = string(item["question"] ?? item["text"] ?? item["prompt"]) else { continue }

            let options = parseStringList(item["options"] ?? item["answers"] ?? item["choices"], keys: ["text", "label"])
            let kind = ClarifyingQuestionKind.parse(item["type"] ?? item["kind"], optionCount: options.count)

            questions.append(
                ClarifyingQuestion(
                    id: string(item["id"] ?? item["question_id"] ?? item["questionId"]) ?? "question-\(index + 1)",
                    kind: kind,
                    question: text,
                    // Options only mean anything for a choice; carrying them on a
                    // numeric question would render chips next to a number pad.
                    options: kind == .singleChoice ? options : [],
                    reason: string(item["reason"] ?? item["why"] ?? item["rationale"], maxLength: 140),
                    relatedItemIDs: parseStringList(
                        item["related_item_ids"] ?? item["relatedItemIds"] ?? item["related_items"],
                        keys: ["id"]
                    ),
                    suggestedUnit: string(item["unit"] ?? item["suggested_unit"] ?? item["suggestedUnit"], maxLength: 12),
                    requestedPhotoKind: kind == .requestAdditionalPhoto
                        ? PhotoEvidenceKind.parse(item["photo_kind"] ?? item["photoKind"] ?? item["photo_type"])
                        : nil
                )
            )
        }
        return questions
    }

    // MARK: - Primitives

    private static func parseStringList(_ raw: Any?, keys: [String]) -> [String] {
        // A model asked for a list sometimes sends one string. Treating that as
        // "nothing" would throw away a real answer.
        if let single = raw as? String {
            let trimmed = single.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        guard let list = raw as? [Any] else { return [] }

        var results: [String] = []
        for element in list {
            var candidate: String?
            if let text = element as? String {
                candidate = text
            } else if let dictionary = element as? [String: Any] {
                candidate = keys.compactMap { dictionary[$0] as? String }.first
            }
            guard let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
            results.append(text)
            // Generous cap here; the validator applies the real per-field limits.
            if results.count >= 16 { break }
        }
        return results
    }

    private static func string(_ raw: Any?, maxLength: Int = 120) -> String? {
        guard let text = raw as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    private static func double(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber {
            let value = number.doubleValue
            return value.isFinite ? value : nil
        }
        if let text = raw as? String {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            guard let value = Double(normalized), value.isFinite else { return nil }
            return value
        }
        return nil
    }

    private static func bool(_ raw: Any?) -> Bool? {
        if let flag = raw as? Bool { return flag }
        if let number = raw as? NSNumber { return number.boolValue }
        if let text = raw as? String {
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }
}
