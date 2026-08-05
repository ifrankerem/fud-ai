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
    /// Identity that survives the round trip through the model, so a follow-up
    /// analysis can update this exact component instead of returning a new list
    /// that has to be re-matched by name. `id` stays the local, UI-stable key.
    var stableID: String
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
    /// Where `grams` came from. Drives whether the app asks about this component's
    /// weight, and whether a later pass may overwrite it.
    var quantitySource: QuantitySource
    /// "grilled", "deep-fried", "steamed". Often worth more calories than the
    /// portion size, which is why it is worth a question of its own.
    var preparationMethod: String?
    /// Plausible bounds for this component alone. Meal totals are summed from
    /// these rather than estimated separately.
    var calorieRange: CalorieRange?
    /// What is specifically unknown here, e.g. "cooked weight not visible".
    /// Distinct from `note`, which states what was assumed.
    var uncertainties: [String]

    init(
        id: UUID = UUID(),
        stableID: String? = nil,
        name: String,
        grams: Double,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        confidence: ConfidenceScore? = nil,
        isHidden: Bool = false,
        note: String? = nil,
        quantitySource: QuantitySource = .visualEstimate,
        preparationMethod: String? = nil,
        calorieRange: CalorieRange? = nil,
        uncertainties: [String] = []
    ) {
        self.id = id
        self.stableID = stableID ?? id.uuidString
        self.name = name
        self.grams = max(0, grams)
        self.calories = max(0, calories)
        self.protein = max(0, protein)
        self.carbs = max(0, carbs)
        self.fat = max(0, fat)
        self.confidence = confidence
        self.isHidden = isHidden
        self.note = note
        self.quantitySource = quantitySource
        self.preparationMethod = preparationMethod
        self.calorieRange = calorieRange
        self.uncertainties = uncertainties
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, grams, calories, protein, carbs, fat, confidence, isHidden, note
        case stableID, quantitySource, preparationMethod, calorieRange, uncertainties
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        grams = try container.decodeIfPresent(Double.self, forKey: .grams) ?? 0
        calories = try container.decodeIfPresent(Int.self, forKey: .calories) ?? 0
        protein = try container.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        carbs = try container.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
        fat = try container.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        confidence = try container.decodeIfPresent(ConfidenceScore.self, forKey: .confidence)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        note = try container.decodeIfPresent(String.self, forKey: .note)
        stableID = try container.decodeIfPresent(String.self, forKey: .stableID) ?? id.uuidString
        // Components stored before provenance existed were all visual estimates —
        // claiming .unknown would be equally wrong and would start asking about
        // weights the analysis had in fact estimated.
        quantitySource = try container.decodeIfPresent(QuantitySource.self, forKey: .quantitySource) ?? .visualEstimate
        preparationMethod = try container.decodeIfPresent(String.self, forKey: .preparationMethod)
        calorieRange = try container.decodeIfPresent(CalorieRange.self, forKey: .calorieRange)
        uncertainties = try container.decodeIfPresent([String].self, forKey: .uncertainties) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(grams, forKey: .grams)
        try container.encode(calories, forKey: .calories)
        try container.encode(protein, forKey: .protein)
        try container.encode(carbs, forKey: .carbs)
        try container.encode(fat, forKey: .fat)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encodeIfPresent(note, forKey: .note)
        if stableID != id.uuidString { try container.encode(stableID, forKey: .stableID) }
        if quantitySource != .visualEstimate { try container.encode(quantitySource, forKey: .quantitySource) }
        try container.encodeIfPresent(preparationMethod, forKey: .preparationMethod)
        try container.encodeIfPresent(calorieRange, forKey: .calorieRange)
        if !uncertainties.isEmpty { try container.encode(uncertainties, forKey: .uncertainties) }
    }

    /// Whether the app already knows this component's amount well enough that
    /// asking about it would waste one of the three available questions.
    var hasExactQuantity: Bool { quantitySource.isExact }

    /// Quantity plus provenance, e.g. "185 g · Measured".
    var quantityDisplay: String {
        let amount = grams >= 10 || grams == grams.rounded()
            ? String(Int(grams.rounded()))
            : String(format: "%.1f", grams)
        return "\(amount) g · \(quantitySource.displayLabel)"
    }

    func scaled(by factor: Double) -> MealComponent {
        guard factor.isFinite, factor > 0 else { return self }
        var copy = self
        copy.grams = grams * factor
        copy.calories = Int((Double(calories) * factor).rounded())
        copy.protein = protein * factor
        copy.carbs = carbs * factor
        copy.fat = fat * factor
        copy.calorieRange = calorieRange?.scaled(by: factor)
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

/// What kind of control answers a question.
///
/// A weight cannot be answered by tapping a chip, and "grilled or fried" should
/// not require typing. Matching the control to the question is most of what makes
/// answering fast enough that people bother.
enum ClarifyingQuestionKind: String, Codable, CaseIterable, Hashable {
    /// A number plus a unit — the highest-value answer, since it converts a guess
    /// into a measurement.
    case numericMeasurement
    case singleChoice
    case yesNo
    case freeText
    /// Asks for another photo rather than an answer.
    case requestAdditionalPhoto

    static func parse(_ raw: Any?, optionCount: Int) -> ClarifyingQuestionKind {
        guard let string = raw as? String else {
            // No declared kind: infer from shape. Options mean a choice; nothing
            // to tap means free text.
            return optionCount >= 2 ? .singleChoice : .freeText
        }
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        for candidate in ClarifyingQuestionKind.allCases where candidate.rawValue.lowercased() == normalized {
            return candidate
        }
        switch normalized {
        case "numeric", "number", "measurement", "weight", "quantity":
            return .numericMeasurement
        case "choice", "select", "multiplechoice", "options", "singleselect":
            return .singleChoice
        case "boolean", "bool", "yesno", "confirm":
            return .yesNo
        case "text", "open", "openended", "input":
            return .freeText
        case "photo", "image", "addphoto", "requestphoto":
            return .requestAdditionalPhoto
        default:
            return optionCount >= 2 ? .singleChoice : .freeText
        }
    }
}

/// A short question the model wants answered before it commits to a number,
/// e.g. "Grilled or fried?". Pre-log only — never persisted on a logged entry.
///
/// `id` is a string rather than a generated UUID because it has to survive the
/// round trip through the model: the follow-up analysis is given the first pass's
/// JSON back, and answers are matched to questions by this id.
struct ClarifyingQuestion: Identifiable, Codable, Hashable {
    var id: String
    var kind: ClarifyingQuestionKind
    var question: String
    /// Choices for `singleChoice`. Empty for every other kind.
    var options: [String]
    /// Why this is being asked, e.g. "Oil is the largest source of uncertainty."
    /// Shown to the user: a question that explains itself gets answered more often
    /// than one that just interrogates.
    var reason: String?
    /// Components this question would change, by their stable ids.
    var relatedItemIDs: [String]
    /// Suggested unit for `numericMeasurement`, e.g. "g" or "ml".
    var suggestedUnit: String?
    /// For `requestAdditionalPhoto`: what the photo should show.
    var requestedPhotoKind: PhotoEvidenceKind?

    init(
        id: String = UUID().uuidString,
        kind: ClarifyingQuestionKind = .singleChoice,
        question: String,
        options: [String] = [],
        reason: String? = nil,
        relatedItemIDs: [String] = [],
        suggestedUnit: String? = nil,
        requestedPhotoKind: PhotoEvidenceKind? = nil
    ) {
        self.id = id
        self.kind = kind
        self.question = question
        self.options = options
        self.reason = reason
        self.relatedItemIDs = relatedItemIDs
        self.suggestedUnit = suggestedUnit
        self.requestedPhotoKind = requestedPhotoKind
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, question, options, reason, relatedItemIDs, suggestedUnit, requestedPhotoKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Entries written before ids were stable stored a UUID; either decodes as
        // a string here, so no migration is needed.
        if let string = try? container.decode(String.self, forKey: .id) {
            id = string
        } else if let uuid = try? container.decode(UUID.self, forKey: .id) {
            id = uuid.uuidString
        } else {
            id = UUID().uuidString
        }
        question = try container.decodeIfPresent(String.self, forKey: .question) ?? ""
        options = try container.decodeIfPresent([String].self, forKey: .options) ?? []
        kind = try container.decodeIfPresent(ClarifyingQuestionKind.self, forKey: .kind)
            ?? (options.count >= 2 ? .singleChoice : .freeText)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        relatedItemIDs = try container.decodeIfPresent([String].self, forKey: .relatedItemIDs) ?? []
        suggestedUnit = try container.decodeIfPresent(String.self, forKey: .suggestedUnit)
        requestedPhotoKind = try container.decodeIfPresent(PhotoEvidenceKind.self, forKey: .requestedPhotoKind)
    }

    /// Whether the question is answerable as presented. A choice question with
    /// nothing to choose between is a dead end and should never reach the UI.
    var isRenderable: Bool {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch kind {
        case .singleChoice: return options.count >= 2
        case .yesNo, .numericMeasurement, .freeText, .requestAdditionalPhoto: return true
        }
    }

    /// An empty answer shell, so the UI can bind to something before the user acts.
    func emptyAnswer() -> ClarificationAnswer {
        ClarificationAnswer(questionID: id, kind: kind, questionText: question, unit: suggestedUnit)
    }
}

/// Everything the analysis knows beyond a single flat number: what the plate is
/// made of, how wide the real answer could be, and what it had to assume.
/// Where an analysis sits in the two-stage flow.
enum MealAnalysisStatus: String, Codable, CaseIterable, Hashable {
    /// A first estimate the model is content with.
    case provisional
    /// A first estimate with questions outstanding that would materially improve it.
    case needsClarification
    /// Settled — either the questions were answered, or the user chose to skip them.
    case final
}

struct MealAnalysisDetail: Codable, Hashable {
    var status: MealAnalysisStatus
    /// The dish as a whole, e.g. "Chicken, rice and yogurt". The components name
    /// the parts; this names the meal.
    var mealName: String?
    var components: [MealComponent]
    var calorieRange: CalorieRange?
    var confidence: ConfidenceScore?
    var assumptions: [String]
    var questions: [ClarifyingQuestion]
    /// Answers the user gave. Kept after logging — they explain why the numbers
    /// are what they are, and they are the record of what the user actually knew.
    var answers: [ClarificationAnswer]
    /// The one or two things that would most change the answer if known. Shown
    /// instead of a bare confidence percentage, which tells the user nothing
    /// actionable.
    var majorUncertainties: [String]
    var provenance: AnalysisProvenance?

    init(
        status: MealAnalysisStatus = .provisional,
        mealName: String? = nil,
        components: [MealComponent] = [],
        calorieRange: CalorieRange? = nil,
        confidence: ConfidenceScore? = nil,
        assumptions: [String] = [],
        questions: [ClarifyingQuestion] = [],
        answers: [ClarificationAnswer] = [],
        majorUncertainties: [String] = [],
        provenance: AnalysisProvenance? = nil
    ) {
        self.status = status
        self.mealName = mealName
        self.components = components
        self.calorieRange = calorieRange
        self.confidence = confidence
        self.assumptions = assumptions
        self.questions = questions
        self.answers = answers
        self.majorUncertainties = majorUncertainties
        self.provenance = provenance
    }

    /// Questions worth putting in front of the user: renderable, not already
    /// answered, and not asking about something the app already knows exactly.
    func pendingQuestions() -> [ClarifyingQuestion] {
        let answered = Set(answers.filter(\.isAnswered).map(\.questionID))
        let exactComponentIDs = Set(components.filter(\.hasExactQuantity).map(\.stableID))
        return questions.filter { question in
            guard question.isRenderable, !answered.contains(question.id) else { return false }
            // A weight question about a component that was weighed is noise.
            if question.kind == .numericMeasurement,
               !question.relatedItemIDs.isEmpty,
               question.relatedItemIDs.allSatisfy({ exactComponentIDs.contains($0) }) {
                return false
            }
            return true
        }
    }

    var needsClarification: Bool { !pendingQuestions().isEmpty }

    /// Calorie bounds summed from the components, which is more defensible than a
    /// separately invented meal-level range: the parts are where the uncertainty
    /// actually lives. Falls back to the model's own range when the components do
    /// not carry one.
    var derivedCalorieRange: CalorieRange? {
        let ranges = components.compactMap(\.calorieRange)
        guard !ranges.isEmpty, ranges.count == components.count else { return calorieRange }
        let low = ranges.reduce(0) { $0 + $1.low }
        let high = ranges.reduce(0) { $0 + $1.high }
        let summed = CalorieRange(low: low, high: high)
        return summed.isMeaningful ? summed : calorieRange
    }

    static let empty = MealAnalysisDetail()

    var isEmpty: Bool {
        components.isEmpty
            && calorieRange == nil
            && confidence == nil
            && assumptions.isEmpty
            && questions.isEmpty
            && answers.isEmpty
            && majorUncertainties.isEmpty
            && provenance == nil
            && (mealName ?? "").isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case components, calorieRange, confidence, assumptions, questions
        case status, mealName, answers, majorUncertainties, provenance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        components = try container.decodeIfPresent([MealComponent].self, forKey: .components) ?? []
        calorieRange = try container.decodeIfPresent(CalorieRange.self, forKey: .calorieRange)
        confidence = try container.decodeIfPresent(ConfidenceScore.self, forKey: .confidence)
        assumptions = try container.decodeIfPresent([String].self, forKey: .assumptions) ?? []
        questions = try container.decodeIfPresent([ClarifyingQuestion].self, forKey: .questions) ?? []
        // Anything already in the diary was settled by the act of logging it.
        status = try container.decodeIfPresent(MealAnalysisStatus.self, forKey: .status) ?? .final
        mealName = try container.decodeIfPresent(String.self, forKey: .mealName)
        answers = try container.decodeIfPresent([ClarificationAnswer].self, forKey: .answers) ?? []
        majorUncertainties = try container.decodeIfPresent([String].self, forKey: .majorUncertainties) ?? []
        provenance = try container.decodeIfPresent(AnalysisProvenance.self, forKey: .provenance)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !components.isEmpty { try container.encode(components, forKey: .components) }
        try container.encodeIfPresent(calorieRange, forKey: .calorieRange)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        if !assumptions.isEmpty { try container.encode(assumptions, forKey: .assumptions) }
        if !questions.isEmpty { try container.encode(questions, forKey: .questions) }
        if status != .final { try container.encode(status, forKey: .status) }
        try container.encodeIfPresent(mealName, forKey: .mealName)
        if !answers.isEmpty { try container.encode(answers, forKey: .answers) }
        if !majorUncertainties.isEmpty { try container.encode(majorUncertainties, forKey: .majorUncertainties) }
        try container.encodeIfPresent(provenance, forKey: .provenance)
    }

    var componentGrams: Double { components.reduce(0) { $0 + $1.grams } }
    var componentCalories: Int { components.reduce(0) { $0 + $1.calories } }

    func scaled(by factor: Double) -> MealAnalysisDetail {
        guard factor.isFinite, factor > 0, factor != 1 else { return self }
        var copy = self
        copy.components = components.map { $0.scaled(by: factor) }
        copy.calorieRange = calorieRange?.scaled(by: factor)
        return copy
    }

    /// Drops the pre-log question prompt and marks the analysis settled. Questions
    /// describe a decision the user has already made by the time the meal is in the
    /// diary; the answers are kept, because they explain the numbers.
    var withoutQuestions: MealAnalysisDetail {
        var copy = self
        copy.questions = []
        copy.status = .final
        return copy
    }

    /// Records that the user changed a value by hand. Weak evidence the estimate
    /// was wrong, and the counterpart to leaving it untouched — together these are
    /// what later makes per-model accuracy measurable.
    func markingUserEdited() -> MealAnalysisDetail {
        guard var existing = provenance else { return self }
        guard !existing.userEdited else { return self }
        existing.userEdited = true
        var copy = self
        copy.provenance = existing
        return copy
    }

    /// Attaches the answers the user gave and settles the status.
    func applying(answers newAnswers: [ClarificationAnswer]) -> MealAnalysisDetail {
        var copy = self
        let answered = newAnswers.filter(\.isAnswered)
        var merged = answers.filter { existing in !answered.contains { $0.questionID == existing.questionID } }
        merged.append(contentsOf: answered)
        copy.answers = merged
        copy.provenance?.answeredQuestionCount = merged.count
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
