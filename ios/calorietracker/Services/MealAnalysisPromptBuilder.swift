import Foundation

/// Builds the prompts for both analysis passes.
///
/// Provider-independent by construction: it emits text and asks for JSON, which
/// every provider the app supports can do. Nothing here depends on a structured
/// output mode, because the app routes to thirteen providers whose support for
/// one differs — and a feature that only works on Gemini is not a feature.
///
/// The prompts are deliberately explicit about what counts as a measurement.
/// That distinction is the difference between an app that admits it is guessing
/// and one that launders a guess into a number.
enum MealAnalysisPromptBuilder {

    // MARK: - Shared schema

    /// The flat nutrition block, unchanged from the existing analysis so the same
    /// parser reads both. Extended with the component and uncertainty fields.
    private static let responseSchema = """
    {"name":"...","calories":0,"protein":0.0,"carbs":0.0,"fat":0.0,"serving_size_grams":0.0,"emoji":"🍽️","sugar":0.0,"added_sugar":0.0,"fiber":0.0,"saturated_fat":0.0,"monounsaturated_fat":0.0,"polyunsaturated_fat":0.0,"trans_fat":0.0,"cholesterol":0.0,"sodium":0.0,"potassium":0.0,"calcium":0.0,"iron":0.0,"magnesium":0.0,"zinc":0.0,"vitamin_a":0.0,"vitamin_c":0.0,"vitamin_d":0.0,"vitamin_b12":0.0,"vitamin_e":0.0,"vitamin_k":0.0,"folate":0.0,"omega_3":0.0,"unit_options":[],"status":"needs_clarification","meal_name":"...","items":[{"id":"rice","name":"Oil-cooked rice","estimated_quantity":220,"unit":"g","quantity_source":"visual_estimate","preparation_method":"boiled with oil","calories":286,"calorie_min":250,"calorie_max":340,"protein":5.0,"carbs":62.0,"fat":4.0,"confidence":0.7,"hidden":false,"note":"assumed 1 tbsp oil","assumptions":["..."],"uncertainties":["..."]}],"calorie_range":{"low":620,"high":850},"overall_confidence":0.72,"assumptions":["..."],"major_uncertainties":["..."],"questions":[{"id":"rice_oil","type":"single_choice","question":"How oily was the rice?","reason":"Oil is the largest source of uncertainty.","options":["No added oil","Lightly oiled","Normal","Very oily"],"related_item_ids":["rice"]}]}
    """

    private static let nutrientUnits = """
    Calories are integers. Protein/carbs/fat are decimal grams. serving_size_grams is the estimated total weight. sugar/fiber/fats/omega_3 are grams; cholesterol/sodium/potassium/calcium/iron/magnesium/zinc/vitamin_c/vitamin_e are milligrams; vitamin_a/vitamin_d/vitamin_b12/vitamin_k/folate are micrograms. Use null for any nutrient you cannot estimate — do not invent detailed nutrients to fill the shape.
    """

    private static let outputRules = """
    Return ONLY the JSON object. No markdown fences, no commentary before or after.
    The example values above show the shape only — replace every one of them.
    """

    /// What the app is allowed to call a measurement. Stated as a closed list
    /// because the whole clarification design keys off it.
    private static let measurementRules = """
    A quantity is EXACT only when it comes from one of these:
    - a number the user stated
    - a kitchen-scale reading visible in a photo
    - a nutrition label visible in a photo
    - a known barcode or packaged serving
    - an explicit weight or volume in the user's note

    These are NOT exact: "a normal portion", "one plate", "a small bowl", "a little rice", "the usual amount", "about one serving". Neither is your own read of how full a plate looks.

    Set each item's quantity_source honestly: user_measured, kitchen_scale, nutrition_label, barcode, known_serving, visual_estimate, or inferred. Never describe an estimated value as a measured one. Never ask for a quantity that is already exact.
    """

    private static let componentRules = """
    Split the meal into the parts you can see or must infer — grilled chicken, rice, salad, sauce, the oil it was cooked in. A plated meal normally has 2-6 parts; use one only when the food genuinely is one item, like an apple. Keep a mixed dish as one part when separating it would be guesswork, but still say what is likely in it and what is uncertain.

    Give every part its own id, a short stable slug like "rice" or "chicken". You will be shown these ids again if the user answers a question, and you must reuse them.

    The parts' quantities must add up to serving_size_grams, and their calories and macros must add up to the meal totals.

    Set "hidden": true for calories the photo does not show — cooking oil, butter, dressing, sauce, syrup, frying fat, sugar in a drink. List them as their own part even when you are only inferring them.
    """

    private static let rangeRules = """
    Give every part a calorie_min and calorie_max, and the meal a calorie_range. Widen them when the cooking method, the amount of oil, or the depth of a portion is unclear; tighten them when a label, a scale reading, or a packaged item pins something down. Do not return a token range like the estimate plus or minus one — an honest wide range is more useful than a false narrow one.

    overall_confidence is 0 to 1. Use a low value when identification or portion is a guess, a high one only when both are clear.

    In assumptions, name what you assumed, most calorie-moving first: "Assumed about 10 g of oil in the rice", "Assumed grilled rather than fried", "Assumed a standard 26 cm dinner plate". In major_uncertainties, name the one or two things that would most change the answer if known.
    """

    private static let questionRules = """
    Ask at most THREE questions, and only where the answer would meaningfully move the calorie number. Skip anything nutritionally trivial — do not ask about a garnish.

    Priority order: exact weight or volume; cooking oil, butter, frying fat, dressing, cream or sauce; cooking method; whether the whole visible portion was eaten; plate or bowl size; hidden ingredients in mixed dishes; brand or product; a second-angle photo; a nutrition-label or scale photo.

    Every question needs a "type", because it decides what control the user is given:
    - "numeric_measurement" for an amount. Include "unit" (usually g or ml) and the related_item_ids it would fix.
    - "single_choice" with 2-4 short options.
    - "yes_no".
    - "free_text" only when no shorter form works.
    - "request_additional_photo" with "photo_kind" of another_angle, kitchen_scale, nutrition_label, packaging, before_eating or after_eating.

    Give each question a stable id and a one-line "reason" the user can read. Set related_item_ids to the part ids it would change. Return [] when you are genuinely confident, and set status to "provisional" rather than "needs_clarification".
    """

    // MARK: - Stage one

    static func initialAnalysisPrompt(
        note: String?,
        measurements: [ExtractedMeasurement],
        photoLabels: [PhotoEvidenceKind],
        userContext: String?
    ) -> String {
        var sections: [String] = []

        sections.append("""
        Analyze this meal from the photos and produce a component-level estimate.

        Respond ONLY with JSON in this exact shape:
        \(responseSchema)

        \(outputRules)
        \(nutrientUnits)
        """)

        sections.append("EXACTNESS\n\(measurementRules)")
        sections.append("COMPONENTS\n\(componentRules)")
        sections.append("RANGES AND CONFIDENCE\n\(rangeRules)")
        sections.append("QUESTIONS\n\(questionRules)")

        if let photoSection = photoEvidenceSection(photoLabels) {
            sections.append(photoSection)
        }
        if let measurementSection = measurementSection(measurements) {
            sections.append(measurementSection)
        }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            sections.append("""
            USER'S NOTE — read this before estimating anything. Any number in it outranks what the photo suggests.
            \(note)
            """)
        }
        if let context = userContext?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            sections.append("STANDING CONTEXT FROM THE USER (applies to every meal)\n\(context)")
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Stage two

    /// Sends the first pass back with the user's answers.
    ///
    /// The previous result travels as validated JSON rather than as the model's
    /// original text, so the follow-up revises what the app actually holds —
    /// including the ids it assigned and any correction already applied.
    static func refinementPrompt(
        previous: MealAnalysisDetail,
        previousTotals: MealTotalsSnapshot,
        answers: [ClarificationAnswer],
        note: String?,
        measurements: [ExtractedMeasurement],
        newPhotoLabels: [PhotoEvidenceKind]
    ) -> String {
        var sections: [String] = []

        sections.append("""
        You previously analyzed this meal. The user has now answered your questions. Produce a revised estimate.

        Respond ONLY with JSON in the same shape as before:
        \(responseSchema)

        \(outputRules)
        \(nutrientUnits)
        """)

        sections.append("""
        YOUR PREVIOUS ESTIMATE
        \(previousJSON(previous: previous, totals: previousTotals))
        """)

        let answered = answers.filter(\.isAnswered)
        if answered.isEmpty {
            sections.append("""
            THE USER'S ANSWERS
            The user skipped the questions. Do not ask them again. Keep your previous estimate unless the photos support a change, and widen the ranges for anything you asked about and did not learn.
            """)
        } else {
            sections.append("""
            THE USER'S ANSWERS
            \(answered.map { "- \($0.promptLine)" }.joined(separator: "\n"))
            """)
        }

        sections.append("""
        HOW TO REVISE
        - Reuse the same item ids. A part you are updating keeps its id; only add an id for food that was genuinely missed.
        - Any amount the user stated is a measurement. Set that item's quantity_source to "user_measured" and build the nutrition around it. Do not replace it with your own estimate.
        - If a stated amount is physically impossible or contradicts another answer, keep it anyway and say so in that item's uncertainties. Do not silently correct the user.
        - Narrow the ranges for what you now know. Leave them wide for what you still do not.
        - Update assumptions to reflect what is now known rather than assumed.
        - Ask a question again ONLY if an answer revealed a genuinely new and larger uncertainty. Otherwise return [] and set status to "final".
        """)

        sections.append("EXACTNESS\n\(measurementRules)")
        sections.append("COMPONENTS\n\(componentRules)")
        sections.append("RANGES AND CONFIDENCE\n\(rangeRules)")

        if let photoSection = photoEvidenceSection(newPhotoLabels, isFollowUp: true) {
            sections.append(photoSection)
        }
        if let measurementSection = measurementSection(measurements) {
            sections.append(measurementSection)
        }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            sections.append("THE USER'S ORIGINAL NOTE\n\(note)")
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Repair

    /// Asks the model to return just the JSON from a reply that was not parseable.
    ///
    /// Cheaper and far more likely to succeed than re-running the whole analysis:
    /// the content is usually right and only the wrapper is wrong.
    static func repairPrompt(malformed: String) -> String {
        """
        The following was supposed to be a single JSON object but could not be parsed. Return the SAME data as valid JSON.

        Do not re-analyze anything, do not change any value, and do not add or remove fields. Fix only the syntax: remove any prose or markdown around it, close unclosed brackets and strings, remove trailing commas, and replace non-standard values such as NaN with null.

        Return ONLY the JSON object.

        \(String(malformed.prefix(12_000)))
        """
    }

    // MARK: - Sections

    private static func photoEvidenceSection(_ labels: [PhotoEvidenceKind], isFollowUp: Bool = false) -> String? {
        let meaningful = labels.filter { $0 != .other }
        guard !meaningful.isEmpty else { return nil }

        var lines = meaningful.enumerated().map { index, kind in
            "- Photo \(index + 1) is \(kind.promptDescription)"
        }
        if meaningful.contains(where: \.depictsAlreadyCountedFood) {
            lines.append("- Do not count the same food twice across photos.")
        }
        let heading = isFollowUp ? "NEW PHOTOS THE USER ADDED" : "WHAT THE PHOTOS SHOW"
        return "\(heading)\n\(lines.joined(separator: "\n"))"
    }

    private static func measurementSection(_ measurements: [ExtractedMeasurement]) -> String? {
        guard !measurements.isEmpty else { return nil }
        let exact = measurements.filter { !$0.isApproximate }
        let approximate = measurements.filter(\.isApproximate)

        var lines: [String] = []
        if !exact.isEmpty {
            lines.append("These amounts came from the user and are EXACT. Use them as given, set quantity_source to \"user_measured\", and do not ask about them:")
            lines.append(contentsOf: exact.map { "- \($0.promptLine)" })
        }
        if !approximate.isEmpty {
            lines.append("These amounts were hedged by the user, so treat them as a strong hint rather than a measurement:")
            lines.append(contentsOf: approximate.map { "- \($0.promptLine)" })
        }
        return "AMOUNTS THE USER ALREADY GAVE\n\(lines.joined(separator: "\n"))"
    }

    /// Compact JSON of the previous pass. Micronutrients are left out on purpose:
    /// they are not what a follow-up revises, and including twenty-odd fields per
    /// item would crowd out the parts of the prompt that matter.
    private static func previousJSON(previous: MealAnalysisDetail, totals: MealTotalsSnapshot) -> String {
        var root: [String: Any] = [
            "name": totals.name,
            "calories": totals.calories,
            "protein": rounded(totals.protein),
            "carbs": rounded(totals.carbs),
            "fat": rounded(totals.fat),
            "serving_size_grams": rounded(totals.servingSizeGrams)
        ]
        if let mealName = previous.mealName { root["meal_name"] = mealName }
        if let range = previous.derivedCalorieRange {
            root["calorie_range"] = ["low": range.low, "high": range.high]
        }
        if let confidence = previous.confidence {
            root["overall_confidence"] = Double(confidence.percent ?? 50) / 100
        }
        if !previous.assumptions.isEmpty { root["assumptions"] = previous.assumptions }
        if !previous.majorUncertainties.isEmpty { root["major_uncertainties"] = previous.majorUncertainties }

        root["items"] = previous.components.map { component -> [String: Any] in
            var item: [String: Any] = [
                "id": component.stableID,
                "name": component.name,
                "estimated_quantity": rounded(component.grams),
                "unit": "g",
                "quantity_source": component.quantitySource.rawValue,
                "calories": component.calories,
                "protein": rounded(component.protein),
                "carbs": rounded(component.carbs),
                "fat": rounded(component.fat),
                "hidden": component.isHidden
            ]
            if let method = component.preparationMethod { item["preparation_method"] = method }
            if let range = component.calorieRange {
                item["calorie_min"] = range.low
                item["calorie_max"] = range.high
            }
            if let note = component.note { item["note"] = note }
            if !component.uncertainties.isEmpty { item["uncertainties"] = component.uncertainties }
            return item
        }

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            // Serialization cannot realistically fail on this shape, but a prompt
            // that silently omits the previous pass would be worse than one that
            // says so — the model would invent a fresh analysis and lose the ids.
            return "{\"error\":\"previous estimate unavailable\"}"
        }
        return text
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

/// The flat meal totals that sit alongside a `MealAnalysisDetail`.
struct MealTotalsSnapshot {
    var name: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var servingSizeGrams: Double

    init(name: String, calories: Int, protein: Double, carbs: Double, fat: Double, servingSizeGrams: Double) {
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingSizeGrams = servingSizeGrams
    }

    init(analysis: GeminiService.FoodAnalysis) {
        self.init(
            name: analysis.name,
            calories: analysis.calories,
            protein: analysis.protein,
            carbs: analysis.carbs,
            fat: analysis.fat,
            servingSizeGrams: analysis.servingSizeGrams
        )
    }
}
