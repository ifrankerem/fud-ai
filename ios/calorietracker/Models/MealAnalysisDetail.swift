import Foundation

/// How sure the model is about an estimate. Stored as a bucket so old entries keep
/// rendering even if a provider starts returning something we don't recognise.
enum AnalysisConfidence: String, Codable, CaseIterable, Hashable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: return LocalizedDisplayText.text("Low", polish: "Niska")
        case .medium: return LocalizedDisplayText.text("Medium", polish: "Średnia")
        case .high: return LocalizedDisplayText.text("High", polish: "Wysoka")
        }
    }

    /// Bucket for a 0-100 score. Boundaries match the wording above: below half is a
    /// guess, 80+ is something the photo actually showed.
    static func bucket(forPercent percent: Int) -> AnalysisConfidence {
        switch percent {
        case ..<50: return .low
        case ..<80: return .medium
        default: return .high
        }
    }
}

/// A confidence bucket plus the exact score when the model gave one. Keeping both
/// means "72%" renders as "72%" and a bare "medium" still renders as "Medium".
struct ConfidenceScore: Codable, Hashable {
    var level: AnalysisConfidence
    var percent: Int?

    init(level: AnalysisConfidence, percent: Int? = nil) {
        self.level = level
        self.percent = percent.map { min(100, max(0, $0)) }
    }

    init(percent: Int) {
        let clamped = min(100, max(0, percent))
        self.level = AnalysisConfidence.bucket(forPercent: clamped)
        self.percent = clamped
    }

    var displayText: String {
        if let percent { return "\(percent)%" }
        return level.displayName
    }

    /// Accepts `"high"`, `0.72`, `72`, or `{"level":"medium","percent":65}` — providers
    /// disagree on shape and a dropped confidence would silently read as "no opinion".
    static func parse(_ value: Any?) -> ConfidenceScore? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let level = AnalysisConfidence(rawValue: trimmed) {
                return ConfidenceScore(level: level)
            }
            // "72", "72%", "0.72"
            let stripped = trimmed.replacingOccurrences(of: "%", with: "")
            if let number = Double(stripped) { return parse(number) }
            return nil
        case let number as NSNumber:
            let raw = number.doubleValue
            guard raw.isFinite, raw >= 0 else { return nil }
            // A fraction (0-1) and a percentage (0-100) are both common. 1.0 is
            // ambiguous; treat it as 100% since a 1% confidence is not a real answer.
            let percent = raw <= 1 ? raw * 100 : raw
            return ConfidenceScore(percent: Int(percent.rounded()))
        case let dictionary as [String: Any]:
            if let percent = parse(dictionary["percent"] ?? dictionary["score"]) {
                return percent
            }
            return parse(dictionary["level"] ?? dictionary["value"])
        default:
            return nil
        }
    }
}

/// Low/high calorie bounds for a meal. Shown instead of pretending a photo can
/// produce a single exact number.
struct CalorieRange: Codable, Hashable {
    var low: Int
    var high: Int

    init(low: Int, high: Int) {
        self.low = max(0, min(low, high))
        self.high = max(0, max(low, high))
    }

    /// A range is only worth showing when it actually spans something. Providers
    /// occasionally echo `calories ± 0`, which is noise, not information.
    var isMeaningful: Bool { high > low }

    var displayText: String { "\(low)–\(high)" }

    func scaled(by factor: Double) -> CalorieRange {
        guard factor.isFinite, factor > 0 else { return self }
        return CalorieRange(
            low: Int((Double(low) * factor).rounded()),
            high: Int((Double(high) * factor).rounded())
        )
    }

    /// Keeps the point estimate inside its own range. Once the user edits calories
    /// by hand the original bounds can fall entirely on one side of the new number.
    func containing(_ value: Int) -> CalorieRange {
        CalorieRange(low: min(low, value), high: max(high, value))
    }
}

/// One part of a plate — grilled chicken, rice, salad, the oil it was cooked in.
struct MealComponent: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var grams: Double
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var confidence: ConfidenceScore?
    /// Calories the photo does not show directly — cooking oil, butter, dressing,
    /// syrup. Flagged so the row can be marked rather than silently folded in.
    var isHidden: Bool
    /// Why this component looks the way it does, e.g. "assumed 1 tbsp olive oil".
    var note: String?

    init(
        id: UUID = UUID(),
        name: String,
        grams: Double,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        confidence: ConfidenceScore? = nil,
        isHidden: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.grams = max(0, grams)
        self.calories = max(0, calories)
        self.protein = max(0, protein)
        self.carbs = max(0, carbs)
        self.fat = max(0, fat)
        self.confidence = confidence
        self.isHidden = isHidden
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, grams, calories, protein, carbs, fat, confidence, isHidden, note
    }

    func scaled(by factor: Double) -> MealComponent {
        guard factor.isFinite, factor > 0 else { return self }
        var copy = self
        copy.grams = grams * factor
        copy.calories = Int((Double(calories) * factor).rounded())
        copy.protein = protein * factor
        copy.carbs = carbs * factor
        copy.fat = fat * factor
        return copy
    }

    mutating func clampToNonNegative() {
        grams = max(0, grams)
        calories = max(0, calories)
        protein = max(0, protein)
        carbs = max(0, carbs)
        fat = max(0, fat)
    }
}

/// A short question the model wants answered before it commits to a number,
/// e.g. "Grilled or fried?". Pre-log only — never persisted on a logged entry.
struct ClarifyingQuestion: Identifiable, Codable, Hashable {
    var id: UUID
    var question: String
    var options: [String]

    init(id: UUID = UUID(), question: String, options: [String]) {
        self.id = id
        self.question = question
        self.options = options
    }
}

/// Everything the analysis knows beyond a single flat number: what the plate is
/// made of, how wide the real answer could be, and what it had to assume.
struct MealAnalysisDetail: Codable, Hashable {
    var components: [MealComponent]
    var calorieRange: CalorieRange?
    var confidence: ConfidenceScore?
    var assumptions: [String]
    var questions: [ClarifyingQuestion]

    init(
        components: [MealComponent] = [],
        calorieRange: CalorieRange? = nil,
        confidence: ConfidenceScore? = nil,
        assumptions: [String] = [],
        questions: [ClarifyingQuestion] = []
    ) {
        self.components = components
        self.calorieRange = calorieRange
        self.confidence = confidence
        self.assumptions = assumptions
        self.questions = questions
    }

    static let empty = MealAnalysisDetail()

    var isEmpty: Bool {
        components.isEmpty
            && calorieRange == nil
            && confidence == nil
            && assumptions.isEmpty
            && questions.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case components, calorieRange, confidence, assumptions, questions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        components = try container.decodeIfPresent([MealComponent].self, forKey: .components) ?? []
        calorieRange = try container.decodeIfPresent(CalorieRange.self, forKey: .calorieRange)
        confidence = try container.decodeIfPresent(ConfidenceScore.self, forKey: .confidence)
        assumptions = try container.decodeIfPresent([String].self, forKey: .assumptions) ?? []
        questions = try container.decodeIfPresent([ClarifyingQuestion].self, forKey: .questions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !components.isEmpty { try container.encode(components, forKey: .components) }
        try container.encodeIfPresent(calorieRange, forKey: .calorieRange)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        if !assumptions.isEmpty { try container.encode(assumptions, forKey: .assumptions) }
        if !questions.isEmpty { try container.encode(questions, forKey: .questions) }
    }

    var componentGrams: Double { components.reduce(0) { $0 + $1.grams } }
    var componentCalories: Int { components.reduce(0) { $0 + $1.calories } }

    func scaled(by factor: Double) -> MealAnalysisDetail {
        guard factor.isFinite, factor > 0, factor != 1 else { return self }
        return MealAnalysisDetail(
            components: components.map { $0.scaled(by: factor) },
            calorieRange: calorieRange?.scaled(by: factor),
            confidence: confidence,
            assumptions: assumptions,
            questions: questions
        )
    }

    /// Drops the pre-log question prompt. Questions describe a decision the user has
    /// already made by the time the meal is in the diary.
    var withoutQuestions: MealAnalysisDetail {
        var copy = self
        copy.questions = []
        return copy
    }

    /// Rebalances components so their sums match the meal totals the user settled on.
    /// Models routinely return parts that miss the total by a few percent; the diary
    /// shows the total, so the parts are what must move.
    func reconciled(toCalories calories: Int, protein: Double, carbs: Double, fat: Double) -> MealAnalysisDetail {
        guard !components.isEmpty else { return self }
        var copy = self
        copy.components = MealAnalysisDetail.reconcile(components, toCalories: calories, protein: protein, carbs: carbs, fat: fat)
        return copy
    }

    static func reconcile(
        _ components: [MealComponent],
        toCalories calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double
    ) -> [MealComponent] {
        guard !components.isEmpty else { return components }
        var adjusted = components

        let currentCalories = adjusted.reduce(0) { $0 + $1.calories }
        if currentCalories > 0, calories > 0 {
            let factor = Double(calories) / Double(currentCalories)
            for index in adjusted.indices {
                adjusted[index].calories = Int((Double(adjusted[index].calories) * factor).rounded())
            }
            // Rounding leaves a few kcal on the table; put them on the biggest part.
            let drift = calories - adjusted.reduce(0) { $0 + $1.calories }
            if drift != 0, let target = adjusted.indices.max(by: { adjusted[$0].calories < adjusted[$1].calories }) {
                adjusted[target].calories = max(0, adjusted[target].calories + drift)
            }
        }

        func rescale(_ keyPath: WritableKeyPath<MealComponent, Double>, to total: Double) {
            let current = adjusted.reduce(0.0) { $0 + $1[keyPath: keyPath] }
            guard current > 0, total > 0 else { return }
            let factor = total / current
            for index in adjusted.indices {
                adjusted[index][keyPath: keyPath] *= factor
            }
        }
        rescale(\.protein, to: protein)
        rescale(\.carbs, to: carbs)
        rescale(\.fat, to: fat)

        return adjusted
    }
}
