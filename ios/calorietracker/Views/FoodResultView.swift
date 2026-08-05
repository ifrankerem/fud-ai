import SwiftUI

struct FoodResultView: View {
    private enum ScrollTarget: Hashable {
        case quantity
    }

    let images: [UIImage]
    let emoji: String?
    let source: FoodSource

    /// Grams the unscaled nutrition numbers refer to. Not a `let`: editing a component
    /// changes how much food the meal actually is, and the portion scale the user
    /// picked has to stay pinned across that change.
    @State private var baseServingSizeGrams: Double
    /// The model's own calorie figure, kept so the calorie range can follow a manual
    /// correction instead of drifting away from the number on screen.
    private let originalAnalysisCalories: Int
    let servingUnitOptions: [ServingUnitOption]

    @State var name: String
    @State var servingSizeGrams: Double
    @State private var servingSizeText: String
    @State private var selectedServingUnitID: String
    @State private var quantityFocusRequest = 0
    @State private var isQuantityEditing = false
    @State private var nutritionUnlocked = false
    @State private var editableCalories: Int
    @State private var editableProtein: Double
    @State private var editableCarbs: Double
    @State private var editableFat: Double
    @State private var editableSugar: Double?
    @State private var editableAddedSugar: Double?
    @State private var editableFiber: Double?
    @State private var editableSaturatedFat: Double?
    @State private var editableMonounsaturatedFat: Double?
    @State private var editablePolyunsaturatedFat: Double?
    @State private var editableCholesterol: Double?
    @State private var editableSodium: Double?
    @State private var editablePotassium: Double?
    @State private var editableTransFat: Double?
    @State private var editableCalcium: Double?
    @State private var editableIron: Double?
    @State private var editableMagnesium: Double?
    @State private var editableZinc: Double?
    @State private var editableVitaminA: Double?
    @State private var editableVitaminC: Double?
    @State private var editableVitaminD: Double?
    @State private var editableVitaminB12: Double?
    @State private var editableVitaminE: Double?
    @State private var editableVitaminK: Double?
    @State private var editableFolate: Double?
    @State private var editableOmega3: Double?
    @State private var showWhatIfSheet = false
    @State var mealType: MealType = .currentMeal

    // Component breakdown + uncertainty. Components hold unscaled values, same as
    // the `editable*` fields above; the portion scale is applied at render time.
    @State private var editableComponents: [MealComponent]
    /// Per-component snapshot used to derive calories-per-gram. The editor fires on
    /// every keystroke, so scaling relative to the *previous* keystroke compounds
    /// ("300" would apply the factor three times). Everything is recomputed from this
    /// fixed reference instead, which stays correct no matter how the text is typed.
    @State private var componentReference: [UUID: MealComponent]
    @State private var baseCalorieRange: CalorieRange?
    @State private var mealConfidence: ConfidenceScore?
    @State private var assumptions: [String]
    @State private var clarifyingQuestions: [ClarifyingQuestion]
    @State private var questionAnswers: [String: String] = [:]
    @State private var isRefining = false

    let logDate: Date
    let profile: UserProfile
    let dayEntries: [FoodEntry]
    let weightMetric: Bool
    var onLog: (FoodEntry) -> Void
    /// Re-runs the analysis with the user's answers folded into the context. Nil when
    /// the caller has nothing to re-analyze (a barcode hit, a saved meal).
    var onRefine: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    // Scaling factor based on user-adjusted serving size
    private var scale: Double {
        guard baseServingSizeGrams > 0 else { return 1 }
        return servingSizeGrams / baseServingSizeGrams
    }

    // Computed scaled nutrition values
    private var scaledCalories: Int { Int(round(Double(editableCalories) * scale)) }
    private var scaledProtein: Double { editableProtein * scale }
    private var scaledCarbs: Double { editableCarbs * scale }
    private var scaledFat: Double { editableFat * scale }
    private var scaledSugar: Double? { editableSugar.map { round($0 * scale * 10) / 10 } }
    private var scaledAddedSugar: Double? { editableAddedSugar.map { round($0 * scale * 10) / 10 } }
    private var scaledFiber: Double? { editableFiber.map { round($0 * scale * 10) / 10 } }
    private var scaledSaturatedFat: Double? { editableSaturatedFat.map { round($0 * scale * 10) / 10 } }
    private var scaledMonounsaturatedFat: Double? { editableMonounsaturatedFat.map { round($0 * scale * 10) / 10 } }
    private var scaledPolyunsaturatedFat: Double? { editablePolyunsaturatedFat.map { round($0 * scale * 10) / 10 } }
    private var scaledCholesterol: Double? { editableCholesterol.map { round($0 * scale * 10) / 10 } }
    private var scaledSodium: Double? { editableSodium.map { round($0 * scale * 10) / 10 } }
    private var scaledPotassium: Double? { editablePotassium.map { round($0 * scale * 10) / 10 } }
    private var scaledTransFat: Double? { editableTransFat.map { round($0 * scale * 10) / 10 } }
    private var scaledCalcium: Double? { editableCalcium.map { round($0 * scale * 10) / 10 } }
    private var scaledIron: Double? { editableIron.map { round($0 * scale * 10) / 10 } }
    private var scaledMagnesium: Double? { editableMagnesium.map { round($0 * scale * 10) / 10 } }
    private var scaledZinc: Double? { editableZinc.map { round($0 * scale * 10) / 10 } }
    private var scaledVitaminA: Double? { editableVitaminA.map { round($0 * scale * 10) / 10 } }
    private var scaledVitaminC: Double? { editableVitaminC.map { round($0 * scale * 10) / 10 } }
    private var scaledVitaminD: Double? { editableVitaminD.map { round($0 * scale * 10) / 10 } }
    private var scaledVitaminB12: Double? { editableVitaminB12.map { round($0 * scale * 10) / 10 } }
    private var scaledVitaminE: Double? { editableVitaminE.map { round($0 * scale * 10) / 10 } }
    private var scaledVitaminK: Double? { editableVitaminK.map { round($0 * scale * 10) / 10 } }
    private var scaledFolate: Double? { editableFolate.map { round($0 * scale * 10) / 10 } }
    private var scaledOmega3: Double? { editableOmega3.map { round($0 * scale * 10) / 10 } }
    private var selectedServingOption: ServingUnitOption {
        ServingUnitOption.option(matching: selectedServingUnitID, in: servingUnitOptions)
    }
    private var selectedServingQuantity: Double? {
        ServingUnitEditor.parseDecimal(servingSizeText)
    }

    init(
        images: [UIImage] = [],
        emoji: String? = nil,
        source: FoodSource,
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        servingSizeGrams: Double = 100,
        sugar: Double? = nil,
        addedSugar: Double? = nil,
        fiber: Double? = nil,
        saturatedFat: Double? = nil,
        monounsaturatedFat: Double? = nil,
        polyunsaturatedFat: Double? = nil,
        cholesterol: Double? = nil,
        sodium: Double? = nil,
        potassium: Double? = nil,
        transFat: Double? = nil,
        calcium: Double? = nil,
        iron: Double? = nil,
        magnesium: Double? = nil,
        zinc: Double? = nil,
        vitaminA: Double? = nil,
        vitaminC: Double? = nil,
        vitaminD: Double? = nil,
        vitaminB12: Double? = nil,
        vitaminE: Double? = nil,
        vitaminK: Double? = nil,
        folate: Double? = nil,
        omega3: Double? = nil,
        servingUnitOptions: [ServingUnitOption] = [],
        selectedServingUnit: String? = nil,
        selectedServingQuantity: Double? = nil,
        analysisDetail: MealAnalysisDetail = .empty,
        logDate: Date = .now,
        profile: UserProfile,
        dayEntries: [FoodEntry],
        weightMetric: Bool,
        onLog: @escaping (FoodEntry) -> Void,
        onRefine: ((String) -> Void)? = nil
    ) {
        let normalizedServingUnitOptions = ServingUnitOption.normalizedOptions(servingUnitOptions, totalGrams: servingSizeGrams)
        let preferredServingUnit = FoodMeasurementSettings.preferGramsByDefault ? nil : selectedServingUnit
        let initialServingUnitID = ServingUnitOption.initialUnitID(
            preferredUnit: preferredServingUnit,
            options: normalizedServingUnitOptions,
            defaultToGrams: FoodMeasurementSettings.preferGramsByDefault
        )
        self.images = images
        self.emoji = emoji
        self.source = source
        self._baseServingSizeGrams = State(initialValue: servingSizeGrams)
        self.originalAnalysisCalories = calories
        self.servingUnitOptions = normalizedServingUnitOptions
        self._name = State(initialValue: name)
        self._servingSizeGrams = State(initialValue: servingSizeGrams)
        self._servingSizeText = State(initialValue: ServingUnitOption.initialQuantityText(
            totalGrams: servingSizeGrams,
            selectedUnitID: initialServingUnitID,
            selectedQuantity: selectedServingQuantity,
            options: normalizedServingUnitOptions
        ))
        self._selectedServingUnitID = State(initialValue: initialServingUnitID)
        self._editableCalories = State(initialValue: calories)
        self._editableProtein = State(initialValue: protein)
        self._editableCarbs = State(initialValue: carbs)
        self._editableFat = State(initialValue: fat)
        self._editableSugar = State(initialValue: sugar)
        self._editableAddedSugar = State(initialValue: addedSugar)
        self._editableFiber = State(initialValue: fiber)
        self._editableSaturatedFat = State(initialValue: saturatedFat)
        self._editableMonounsaturatedFat = State(initialValue: monounsaturatedFat)
        self._editablePolyunsaturatedFat = State(initialValue: polyunsaturatedFat)
        self._editableCholesterol = State(initialValue: cholesterol)
        self._editableSodium = State(initialValue: sodium)
        self._editablePotassium = State(initialValue: potassium)
        self._editableTransFat = State(initialValue: transFat)
        self._editableCalcium = State(initialValue: calcium)
        self._editableIron = State(initialValue: iron)
        self._editableMagnesium = State(initialValue: magnesium)
        self._editableZinc = State(initialValue: zinc)
        self._editableVitaminA = State(initialValue: vitaminA)
        self._editableVitaminC = State(initialValue: vitaminC)
        self._editableVitaminD = State(initialValue: vitaminD)
        self._editableVitaminB12 = State(initialValue: vitaminB12)
        self._editableVitaminE = State(initialValue: vitaminE)
        self._editableVitaminK = State(initialValue: vitaminK)
        self._editableFolate = State(initialValue: folate)
        self._editableOmega3 = State(initialValue: omega3)
        // Parts the model returned must already add up to the totals it returned;
        // the parser reconciles them, so no second pass is needed here.
        self._editableComponents = State(initialValue: analysisDetail.components)
        self._componentReference = State(
            initialValue: Dictionary(uniqueKeysWithValues: analysisDetail.components.map { ($0.id, $0) })
        )
        self._baseCalorieRange = State(initialValue: analysisDetail.calorieRange)
        self._mealConfidence = State(initialValue: analysisDetail.confidence)
        self._assumptions = State(initialValue: analysisDetail.assumptions)
        self._clarifyingQuestions = State(initialValue: analysisDetail.questions)
        self.logDate = logDate
        self.profile = profile
        self.dayEntries = dayEntries
        self.weightMetric = weightMetric
        self.onLog = onLog
        self.onRefine = onRefine
    }

    private static func formatGrams(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private var safeInverseScale: Double {
        scale > 0 ? scale : 1
    }

    private func decimalValue(from text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized) else {
            return nil
        }
        return max(0, value)
    }

    private func editText(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? ""
    }

    private func displayText(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "—"
    }

    private func updateBaseCalories(from text: String) {
        let newValue = Int(round((decimalValue(from: text) ?? 0) / safeInverseScale))
        // Correcting the total has to move the parts too, or the breakdown below
        // would stop adding up to the number the user just typed.
        distributeCalories(to: newValue)
        editableCalories = newValue
    }

    private func updateBaseProtein(from text: String) {
        let newValue = (decimalValue(from: text) ?? 0) / safeInverseScale
        distributeMacro(\.protein, from: editableProtein, to: newValue)
        editableProtein = newValue
    }

    private func updateBaseCarbs(from text: String) {
        let newValue = (decimalValue(from: text) ?? 0) / safeInverseScale
        distributeMacro(\.carbs, from: editableCarbs, to: newValue)
        editableCarbs = newValue
    }

    private func updateBaseFat(from text: String) {
        let newValue = (decimalValue(from: text) ?? 0) / safeInverseScale
        distributeMacro(\.fat, from: editableFat, to: newValue)
        editableFat = newValue
    }

    private func updateBaseDouble(from text: String, set: (Double) -> Void) {
        set((decimalValue(from: text) ?? 0) / safeInverseScale)
    }

    // MARK: - Component breakdown

    /// Components rendered at the portion the user selected.
    private var scaledComponents: [MealComponent] {
        editableComponents.map { $0.scaled(by: scale) }
    }

    /// The bounds were drawn around the model's original figure, so they follow both
    /// the portion scale and any manual correction — otherwise the range would stop
    /// bracketing the calorie number sitting right above it.
    private var displayedCalorieRange: CalorieRange? {
        guard let baseCalorieRange, baseCalorieRange.isMeaningful else { return nil }
        let correction = originalAnalysisCalories > 0
            ? Double(editableCalories) / Double(originalAnalysisCalories)
            : 1
        return baseCalorieRange.scaled(by: correction * scale).containing(scaledCalories)
    }

    private func componentBaseValue(from text: String) -> Double {
        max(0, (decimalValue(from: text) ?? 0) / safeInverseScale)
    }

    private func editComponent(_ id: UUID, _ transform: (inout MealComponent) -> Void) {
        guard let index = editableComponents.firstIndex(where: { $0.id == id }) else { return }
        let previousScale = scale
        let previousBaseGrams = baseServingSizeGrams
        transform(&editableComponents[index])
        editableComponents[index].clampToNonNegative()
        syncTotalsFromComponents(previousScale: previousScale, previousBaseGrams: previousBaseGrams)
    }

    /// Changing how much of something there was has to change its calories too —
    /// "that was 300 g of rice, not 200" is a statement about energy, not just weight.
    /// Nutrition is re-derived from the reference snapshot's density.
    private func editComponentGrams(_ id: UUID, text: String) {
        let newGrams = componentBaseValue(from: text)
        editComponent(id) { part in
            guard let reference = componentReference[id], reference.grams > 0 else {
                part.grams = newGrams
                return
            }
            let factor = newGrams / reference.grams
            part.grams = newGrams
            part.calories = Int((Double(reference.calories) * factor).rounded())
            part.protein = reference.protein * factor
            part.carbs = reference.carbs * factor
            part.fat = reference.fat * factor
        }
    }

    /// A direct nutrition edit redefines the component's density, so it becomes the
    /// new reference for any later gram change.
    private func editComponentValue(_ id: UUID, _ apply: (inout MealComponent) -> Void) {
        editComponent(id, apply)
        if let updated = editableComponents.first(where: { $0.id == id }) {
            componentReference[id] = updated
        }
    }

    /// Correcting a meal total rewrites every component, which invalidates the density
    /// snapshots the gram editor derives from.
    private func refreshComponentReferences() {
        for component in editableComponents {
            componentReference[component.id] = component
        }
    }

    private func removeComponent(_ id: UUID) {
        // Dropping to zero components would leave the meal with no breakdown and no
        // way to get one back, so the last one stays.
        guard editableComponents.count > 1,
              let index = editableComponents.firstIndex(where: { $0.id == id })
        else { return }
        let previousScale = scale
        let previousBaseGrams = baseServingSizeGrams
        editableComponents.remove(at: index)
        componentReference[id] = nil
        syncTotalsFromComponents(previousScale: previousScale, previousBaseGrams: previousBaseGrams)
    }

    /// Components are the source of truth once the user touches one: totals become
    /// their sum, and the meal's weight becomes their combined grams.
    private func syncTotalsFromComponents(previousScale: Double, previousBaseGrams: Double) {
        guard !editableComponents.isEmpty else { return }
        editableCalories = editableComponents.reduce(0) { $0 + $1.calories }
        editableProtein = editableComponents.reduce(0) { $0 + $1.protein }
        editableCarbs = editableComponents.reduce(0) { $0 + $1.carbs }
        editableFat = editableComponents.reduce(0) { $0 + $1.fat }

        let newBaseGrams = editableComponents.reduce(0) { $0 + $1.grams }
        guard newBaseGrams > 0 else { return }

        // Micronutrients are estimated for the meal as a whole rather than per
        // component, so the only consistent response to "there was more rice" is to
        // scale them with the new food amount.
        if previousBaseGrams > 0, abs(newBaseGrams - previousBaseGrams) > 0.01 {
            scaleOptionalNutrients(by: newBaseGrams / previousBaseGrams)
        }

        baseServingSizeGrams = newBaseGrams
        servingSizeGrams = newBaseGrams * previousScale
        servingSizeText = ServingUnitOption.initialQuantityText(
            totalGrams: servingSizeGrams,
            selectedUnitID: selectedServingUnitID,
            selectedQuantity: nil,
            options: servingUnitOptions
        )
    }

    private func scaleOptionalNutrients(by factor: Double) {
        guard factor.isFinite, factor > 0, factor != 1 else { return }
        func scaled(_ value: Double?) -> Double? { value.map { $0 * factor } }
        editableSugar = scaled(editableSugar)
        editableAddedSugar = scaled(editableAddedSugar)
        editableFiber = scaled(editableFiber)
        editableSaturatedFat = scaled(editableSaturatedFat)
        editableMonounsaturatedFat = scaled(editableMonounsaturatedFat)
        editablePolyunsaturatedFat = scaled(editablePolyunsaturatedFat)
        editableCholesterol = scaled(editableCholesterol)
        editableSodium = scaled(editableSodium)
        editablePotassium = scaled(editablePotassium)
        editableTransFat = scaled(editableTransFat)
        editableCalcium = scaled(editableCalcium)
        editableIron = scaled(editableIron)
        editableMagnesium = scaled(editableMagnesium)
        editableZinc = scaled(editableZinc)
        editableVitaminA = scaled(editableVitaminA)
        editableVitaminC = scaled(editableVitaminC)
        editableVitaminD = scaled(editableVitaminD)
        editableVitaminB12 = scaled(editableVitaminB12)
        editableVitaminE = scaled(editableVitaminE)
        editableVitaminK = scaled(editableVitaminK)
        editableFolate = scaled(editableFolate)
        editableOmega3 = scaled(editableOmega3)
    }

    private func distributeCalories(to newTotal: Int) {
        guard !editableComponents.isEmpty else { return }
        defer { refreshComponentReferences() }
        let current = editableComponents.reduce(0) { $0 + $1.calories }
        guard current > 0 else {
            let share = Int((Double(newTotal) / Double(editableComponents.count)).rounded())
            for index in editableComponents.indices {
                editableComponents[index].calories = max(0, share)
            }
            return
        }
        let factor = Double(newTotal) / Double(current)
        for index in editableComponents.indices {
            editableComponents[index].calories = max(0, Int((Double(editableComponents[index].calories) * factor).rounded()))
        }
        // Per-component rounding leaves a few kcal unaccounted for; park them on the
        // largest part so the sum still equals what the user typed.
        let drift = newTotal - editableComponents.reduce(0) { $0 + $1.calories }
        if drift != 0,
           let target = editableComponents.indices.max(by: { editableComponents[$0].calories < editableComponents[$1].calories }) {
            editableComponents[target].calories = max(0, editableComponents[target].calories + drift)
        }
    }

    private func distributeMacro(
        _ keyPath: WritableKeyPath<MealComponent, Double>,
        from oldTotal: Double,
        to newTotal: Double
    ) {
        guard !editableComponents.isEmpty else { return }
        defer { refreshComponentReferences() }
        guard oldTotal > 0 else {
            let share = newTotal / Double(editableComponents.count)
            for index in editableComponents.indices {
                editableComponents[index][keyPath: keyPath] = max(0, share)
            }
            return
        }
        let factor = newTotal / oldTotal
        for index in editableComponents.indices {
            editableComponents[index][keyPath: keyPath] = max(0, editableComponents[index][keyPath: keyPath] * factor)
        }
    }

    private var refinementSummary: String {
        clarifyingQuestions
            .compactMap { question in
                guard let answer = questionAnswers[question.id] else { return nil }
                return "\(question.question) \(answer)"
            }
            .joined(separator: " ")
    }

    private func submitRefinement() {
        guard let onRefine else { return }
        let summary = refinementSummary
        guard !summary.isEmpty else { return }
        isRefining = true
        onRefine(summary)
    }

    // MARK: - Sections
    //
    // Extracted rather than inlined: `List` takes at most 10 direct children in a
    // ViewBuilder, and the body was already at six before any of this was added.

    /// The honest-estimate header: how wide the answer really is, and the questions
    /// that would narrow it. Placed above the numbers because answering one changes
    /// everything below it.
    @ViewBuilder
    private var uncertaintySections: some View {
        if displayedCalorieRange != nil || mealConfidence != nil {
            Section {
                if let range = displayedCalorieRange {
                    CalorieRangeRow(range: range, confidence: mealConfidence)
                } else if let confidence = mealConfidence {
                    HStack {
                        Text(LocalizedDisplayText.text("Confidence", polish: "Pewność"))
                        Spacer()
                        ConfidenceBadge(score: confidence)
                    }
                }
            } header: {
                Text(LocalizedDisplayText.text("Estimate", polish: "Szacunek"))
            }
        }

        if !clarifyingQuestions.isEmpty, onRefine != nil {
            Section {
                ClarifyingQuestionsView(
                    questions: clarifyingQuestions,
                    answers: $questionAnswers,
                    isRefining: isRefining,
                    onRefine: submitRefinement
                )
            } header: {
                Text(LocalizedDisplayText.text("Help the estimate", polish: "Pomóż w szacunku"))
            } footer: {
                Text(LocalizedDisplayText.text(
                    "Answering runs the analysis again with your answers.",
                    polish: "Odpowiedzi uruchamiają analizę ponownie."
                ))
            }
        }
    }

    @ViewBuilder
    private var componentsSection: some View {
        if !editableComponents.isEmpty {
            Section {
                ForEach(scaledComponents) { component in
                    MealComponentRow(
                        component: component,
                        onEditGrams: { text in
                            editComponentGrams(component.id, text: text)
                        },
                        onEditCalories: { text in
                            let value = componentBaseValue(from: text)
                            editComponentValue(component.id) { $0.calories = Int(value.rounded()) }
                        },
                        onEditProtein: { text in
                            let value = componentBaseValue(from: text)
                            editComponentValue(component.id) { $0.protein = value }
                        },
                        onEditCarbs: { text in
                            let value = componentBaseValue(from: text)
                            editComponentValue(component.id) { $0.carbs = value }
                        },
                        onEditFat: { text in
                            let value = componentBaseValue(from: text)
                            editComponentValue(component.id) { $0.fat = value }
                        },
                        onRemove: { removeComponent(component.id) }
                    )
                }
            } header: {
                Text(LocalizedDisplayText.text("What's on the plate", polish: "Co jest na talerzu"))
            } footer: {
                Text(LocalizedDisplayText.text(
                    "Editing a part updates the meal totals above.",
                    polish: "Edycja części aktualizuje sumy powyżej."
                ))
            }
        }
    }

    @ViewBuilder
    private var assumptionsSection: some View {
        if !assumptions.isEmpty {
            Section {
                AssumptionsSection(assumptions: assumptions)
            } header: {
                Text(LocalizedDisplayText.text("Assumptions", polish: "Założenia"))
            }
        }
    }

    private func updateOptionalBaseDouble(from text: String, set: (Double?) -> Void) {
        set(decimalValue(from: text).map { $0 / safeInverseScale })
    }

    private func toggleNutritionLock() {
        nutritionUnlocked.toggle()
        if !nutritionUnlocked {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                List {
                    if !images.isEmpty {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 220, height: 200)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                            .overlay(alignment: .bottomTrailing) {
                                                if images.count > 1 {
                                                    Text("\(index + 1)/\(images.count)")
                                                        .font(.caption2.weight(.semibold))
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 5)
                                                        .background(.ultraThinMaterial, in: Capsule())
                                                        .padding(8)
                                                }
                                            }
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.viewAligned)
                            .listRowBackground(Color.clear)
                        }
                    } else if let emoji {
                        Section {
                            HStack {
                                Spacer()
                                Text(emoji)
                                    .font(.system(size: 80))
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                        }
                    }

                    Section("Food Details") {
                        HStack {
                            Text("Name")
                            Spacer()
                            TextField("Food name", text: $name)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    uncertaintySections

                    Section("Serving") {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            ServingUnitEditor(
                                quantityText: $servingSizeText,
                                servingSizeGrams: $servingSizeGrams,
                                selectedUnitID: $selectedServingUnitID,
                                unitOptions: servingUnitOptions,
                                focusRequest: quantityFocusRequest,
                                onEditingChanged: { editing in
                                    isQuantityEditing = editing
                                },
                                onClear: {
                                    servingSizeText = ""
                                    quantityFocusRequest += 1
                                }
                            )
                        }
                        .id(ScrollTarget.quantity)
                        if !selectedServingOption.isGramUnit {
                            HStack {
                                Text("Total")
                                Spacer()
                                Text("~\(Self.formatGrams(servingSizeGrams)) g")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section {
                        ReviewNutritionValueRow(
                            label: "Calories",
                            displayValue: "\(scaledCalories)",
                            editValue: "\(scaledCalories)",
                            unit: "kcal",
                            isUnlocked: nutritionUnlocked,
                            onEdit: updateBaseCalories
                        )
                        ReviewNutritionValueRow(
                            label: "Protein",
                            displayValue: MacroValueFormatter.string(scaledProtein),
                            editValue: MacroValueFormatter.string(scaledProtein),
                            unit: "g",
                            isUnlocked: nutritionUnlocked,
                            onEdit: updateBaseProtein
                        )
                        ReviewNutritionValueRow(
                            label: "Carbs",
                            displayValue: MacroValueFormatter.string(scaledCarbs),
                            editValue: MacroValueFormatter.string(scaledCarbs),
                            unit: "g",
                            isUnlocked: nutritionUnlocked,
                            onEdit: updateBaseCarbs
                        )
                        ReviewNutritionValueRow(
                            label: "Fat",
                            displayValue: MacroValueFormatter.string(scaledFat),
                            editValue: MacroValueFormatter.string(scaledFat),
                            unit: "g",
                            isUnlocked: nutritionUnlocked,
                            onEdit: updateBaseFat
                        )
                    } header: {
                        HStack {
                            Text("Nutrition")
                            Spacer()
                            Button(action: toggleNutritionLock) {
                                Image(systemName: nutritionUnlocked ? "lock.open.fill" : "lock.fill")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(nutritionUnlocked ? AppColors.calorie : .secondary)
                            .accessibilityLabel(nutritionUnlocked ? "Lock nutrition editing" : "Unlock nutrition editing")
                        }
                    }

                    componentsSection

                    Section {
                        DisclosureGroup("More Nutrition") {
                            ReviewNutritionValueRow(label: "Sugar", displayValue: displayText(scaledSugar), editValue: editText(scaledSugar), unit: "g", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableSugar = $0 } })
                            ReviewNutritionValueRow(label: "Added Sugar", displayValue: displayText(scaledAddedSugar), editValue: editText(scaledAddedSugar), unit: "g", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableAddedSugar = $0 } })
                            ReviewNutritionValueRow(label: "Fiber", displayValue: displayText(scaledFiber), editValue: editText(scaledFiber), unit: "g", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableFiber = $0 } })
                            ReviewNutritionValueRow(label: "Saturated Fat", displayValue: displayText(scaledSaturatedFat), editValue: editText(scaledSaturatedFat), unit: "g", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableSaturatedFat = $0 } })
                            ReviewNutritionValueRow(label: "Mono Fat", displayValue: displayText(scaledMonounsaturatedFat), editValue: editText(scaledMonounsaturatedFat), unit: "g", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableMonounsaturatedFat = $0 } })
                            ReviewNutritionValueRow(label: "Poly Fat", displayValue: displayText(scaledPolyunsaturatedFat), editValue: editText(scaledPolyunsaturatedFat), unit: "g", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editablePolyunsaturatedFat = $0 } })
                            ReviewNutritionValueRow(label: "Cholesterol", displayValue: displayText(scaledCholesterol), editValue: editText(scaledCholesterol), unit: "mg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableCholesterol = $0 } })
                            ReviewNutritionValueRow(label: "Sodium", displayValue: displayText(scaledSodium), editValue: editText(scaledSodium), unit: "mg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableSodium = $0 } })
                            ReviewNutritionValueRow(label: "Potassium", displayValue: displayText(scaledPotassium), editValue: editText(scaledPotassium), unit: "mg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editablePotassium = $0 } })
                            ReviewNutritionValueRow(label: "Trans Fat", displayValue: displayText(scaledTransFat), editValue: editText(scaledTransFat), unit: "g", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableTransFat = $0 } })
                            ReviewNutritionValueRow(label: "Calcium", displayValue: displayText(scaledCalcium), editValue: editText(scaledCalcium), unit: "mg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableCalcium = $0 } })
                            ReviewNutritionValueRow(label: "Iron", displayValue: displayText(scaledIron), editValue: editText(scaledIron), unit: "mg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableIron = $0 } })
                            ReviewNutritionValueRow(label: "Magnesium", displayValue: displayText(scaledMagnesium), editValue: editText(scaledMagnesium), unit: "mg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableMagnesium = $0 } })
                            ReviewNutritionValueRow(label: "Zinc", displayValue: displayText(scaledZinc), editValue: editText(scaledZinc), unit: "mg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableZinc = $0 } })
                            ReviewNutritionValueRow(label: "Vitamin A", displayValue: displayText(scaledVitaminA), editValue: editText(scaledVitaminA), unit: "mcg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableVitaminA = $0 } })
                            ReviewNutritionValueRow(label: "Vitamin C", displayValue: displayText(scaledVitaminC), editValue: editText(scaledVitaminC), unit: "mg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableVitaminC = $0 } })
                            ReviewNutritionValueRow(label: "Vitamin D", displayValue: displayText(scaledVitaminD), editValue: editText(scaledVitaminD), unit: "mcg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableVitaminD = $0 } })
                            ReviewNutritionValueRow(label: "Vitamin B12", displayValue: displayText(scaledVitaminB12), editValue: editText(scaledVitaminB12), unit: "mcg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableVitaminB12 = $0 } })
                            ReviewNutritionValueRow(label: "Vitamin E", displayValue: displayText(scaledVitaminE), editValue: editText(scaledVitaminE), unit: "mg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableVitaminE = $0 } })
                            ReviewNutritionValueRow(label: "Vitamin K", displayValue: displayText(scaledVitaminK), editValue: editText(scaledVitaminK), unit: "mcg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableVitaminK = $0 } })
                            ReviewNutritionValueRow(label: "Folate", displayValue: displayText(scaledFolate), editValue: editText(scaledFolate), unit: "mcg", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableFolate = $0 } })
                            ReviewNutritionValueRow(label: "Omega-3", displayValue: displayText(scaledOmega3), editValue: editText(scaledOmega3), unit: "g", isUnlocked: nutritionUnlocked, dim: true, onEdit: { updateOptionalBaseDouble(from: $0) { editableOmega3 = $0 } })
                        }
                        .tint(AppColors.calorie)
                    }

                    assumptionsSection

                    Section("Meal") {
                        Picker("Meal Type", selection: $mealType) {
                            ForEach(MealType.allCases, id: \.self) { meal in
                                Label(meal.displayName, systemImage: meal.icon)
                                    .tag(meal)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.calorie)
                    }

                }
                .scrollContentBackground(.hidden)
                .background(AppColors.appBackground)
                .background(KeyboardDismissTapInstaller())
                .safeAreaInset(edge: .bottom) {
                    if isQuantityEditing {
                        Color.clear.frame(height: 12)
                    }
                }
                .onChange(of: isQuantityEditing) { _, editing in
                    guard editing else { return }
                    scrollQuantityIntoView(scrollProxy)
                }
                .navigationTitle("Review Food")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .confirmationAction) {
                        Button("What if?") { showWhatIfSheet = true }
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .tint(AppColors.protein)

                        Button("Log", action: logFood)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .tint(AppColors.calorie)
                    }
                }
                .sheet(isPresented: $showWhatIfSheet) {
                    WhatIfMealImpactSheet(
                        entry: makeFoodEntry(includeImage: false),
                        dayEntries: dayEntries,
                        profile: profile,
                        weightMetric: weightMetric
                    )
                }
            }
        }
    }

    private func scrollQuantityIntoView(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(ScrollTarget.quantity, anchor: .bottom)
            }
        }
    }

    private func logFood() {
        let entry = makeFoodEntry(includeImage: true)
        onLog(entry)
        dismiss()
    }

    private func makeFoodEntry(includeImage: Bool) -> FoodEntry {
        FoodEntry(
            name: name,
            calories: scaledCalories,
            protein: scaledProtein,
            carbs: scaledCarbs,
            fat: scaledFat,
            timestamp: logDate,
            imageData: includeImage ? images.first?.jpegData(compressionQuality: 0.5) : nil,
            additionalImageData: includeImage ? images.dropFirst().compactMap { $0.jpegData(compressionQuality: 0.5) } : [],
            emoji: emoji,
            source: source,
            mealType: mealType,
            sugar: scaledSugar,
            addedSugar: scaledAddedSugar,
            fiber: scaledFiber,
            saturatedFat: scaledSaturatedFat,
            monounsaturatedFat: scaledMonounsaturatedFat,
            polyunsaturatedFat: scaledPolyunsaturatedFat,
            cholesterol: scaledCholesterol,
            sodium: scaledSodium,
            potassium: scaledPotassium,
            transFat: scaledTransFat,
            calcium: scaledCalcium,
            iron: scaledIron,
            magnesium: scaledMagnesium,
            zinc: scaledZinc,
            vitaminA: scaledVitaminA,
            vitaminC: scaledVitaminC,
            vitaminD: scaledVitaminD,
            vitaminB12: scaledVitaminB12,
            vitaminE: scaledVitaminE,
            vitaminK: scaledVitaminK,
            folate: scaledFolate,
            omega3: scaledOmega3,
            servingSizeGrams: servingSizeGrams,
            servingUnitOptions: servingUnitOptions,
            selectedServingUnit: servingUnitOptions.isEmpty ? nil : selectedServingOption.unit,
            selectedServingQuantity: servingUnitOptions.isEmpty ? nil : selectedServingQuantity,
            analysisDetail: loggedAnalysisDetail
        )
    }

    /// What gets stored with the diary entry. Questions are dropped — by this point the
    /// user has answered them or decided not to — and the parts are reconciled against
    /// the totals actually being saved so the stored breakdown always adds up.
    private var loggedAnalysisDetail: MealAnalysisDetail {
        MealAnalysisDetail(
            components: scaledComponents,
            calorieRange: displayedCalorieRange,
            confidence: mealConfidence,
            assumptions: assumptions
        )
        .reconciled(
            toCalories: scaledCalories,
            protein: scaledProtein,
            carbs: scaledCarbs,
            fat: scaledFat
        )
    }

}

private struct WhatIfMealImpactSheet: View {
    let entry: FoodEntry
    let dayEntries: [FoodEntry]
    let profile: UserProfile
    let weightMetric: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingSuggestion = true
    @State private var suggestion: String?
    @State private var suggestionError: String?

    private var currentTotals: WhatIfMacroTotals {
        WhatIfMacroTotals(entries: dayEntries)
    }

    private var mealTotals: WhatIfMacroTotals {
        WhatIfMacroTotals(entry: entry)
    }

    private var afterTotals: WhatIfMacroTotals {
        currentTotals + mealTotals
    }

    private var goals: WhatIfMacroTotals {
        WhatIfMacroTotals(
            calories: profile.effectiveCalories,
            protein: Double(profile.effectiveProtein),
            carbs: Double(profile.effectiveCarbs),
            fat: Double(profile.effectiveFat)
        )
    }

    private var suggestionTaskID: String {
        [
            entry.name,
            "\(entry.calories)",
            MacroValueFormatter.string(entry.protein),
            MacroValueFormatter.string(entry.carbs),
            MacroValueFormatter.string(entry.fat),
            "\(dayEntries.count)",
            "\(profile.effectiveCalories)",
            "\(profile.effectiveProtein)",
            "\(profile.effectiveCarbs)",
            "\(profile.effectiveFat)"
        ].joined(separator: "|")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WhatIfImpactRow(
                        label: "Calories",
                        added: "+\(entry.calories) kcal",
                        after: "\(afterTotals.calories) / \(goals.calories) kcal",
                        remaining: remainingCaloriesText,
                        isOver: afterTotals.calories > goals.calories,
                        tint: AppColors.calorie
                    )
                    WhatIfImpactRow(
                        label: "Protein",
                        added: "+\(MacroValueFormatter.withUnit(entry.protein))",
                        after: "\(MacroValueFormatter.string(afterTotals.protein)) / \(profile.effectiveProtein)g",
                        remaining: remainingMacroText(afterTotals.protein, goal: Double(profile.effectiveProtein)),
                        isOver: false,
                        tint: AppColors.protein
                    )
                    WhatIfImpactRow(
                        label: "Carbs",
                        added: "+\(MacroValueFormatter.withUnit(entry.carbs))",
                        after: "\(MacroValueFormatter.string(afterTotals.carbs)) / \(profile.effectiveCarbs)g",
                        remaining: remainingMacroText(afterTotals.carbs, goal: Double(profile.effectiveCarbs)),
                        isOver: afterTotals.carbs > Double(profile.effectiveCarbs),
                        tint: AppColors.carbs
                    )
                    WhatIfImpactRow(
                        label: "Fat",
                        added: "+\(MacroValueFormatter.withUnit(entry.fat))",
                        after: "\(MacroValueFormatter.string(afterTotals.fat)) / \(profile.effectiveFat)g",
                        remaining: remainingMacroText(afterTotals.fat, goal: Double(profile.effectiveFat)),
                        isOver: afterTotals.fat > Double(profile.effectiveFat),
                        tint: AppColors.fat
                    )
                } header: {
                    Text("Impact on Today")
                } footer: {
                    Text("This does not log the meal. It shows what today would look like if you logged \(entry.name).")
                }

                Section("AI Suggestion") {
                    if isLoadingSuggestion {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Checking fit with your goals...")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else if let suggestion {
                        Text(suggestion)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    } else if let suggestionError {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(suggestionError)
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task { await loadSuggestion() }
                            }
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .tint(AppColors.calorie)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.appBackground)
            .navigationTitle("What if?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .tint(AppColors.calorie)
                }
            }
            .task(id: suggestionTaskID) {
                await loadSuggestion()
            }
        }
    }

    private var remainingCaloriesText: String {
        let remaining = goals.calories - afterTotals.calories
        if remaining >= 0 {
            return "\(remaining) kcal left"
        }
        return "\(abs(remaining)) kcal over"
    }

    private func remainingMacroText(_ value: Double, goal: Double) -> String {
        let remaining = goal - value
        if remaining >= 0 {
            return "\(MacroValueFormatter.string(remaining))g left"
        }
        return "\(MacroValueFormatter.string(abs(remaining)))g over"
    }

    @MainActor
    private func loadSuggestion() async {
        isLoadingSuggestion = true
        suggestion = nil
        suggestionError = nil

        do {
            let text = try await GeminiService.suggestMealWhatIf(
                entry: entry,
                dayEntries: dayEntries,
                profile: profile,
                weightMetric: weightMetric
            )
            suggestion = text.isEmpty ? "No suggestion returned. You can still review the numbers above before logging." : text
        } catch {
            suggestionError = error.localizedDescription
        }

        isLoadingSuggestion = false
    }
}

private struct WhatIfImpactRow: View {
    let label: String
    let added: String
    let after: String
    let remaining: String
    let isOver: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 30, height: 30)
                .overlay {
                    Circle()
                        .fill(tint)
                        .frame(width: 10, height: 10)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedDisplayText.text(label))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Text(after)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(added)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Text(remaining)
                    .font(.caption)
                    .foregroundStyle(isOver ? Color.red : .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct WhatIfMacroTotals {
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = WhatIfMacroTotals(calories: 0, protein: 0, carbs: 0, fat: 0)

    init(calories: Int, protein: Double, carbs: Double, fat: Double) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    init(entry: FoodEntry) {
        self.init(
            calories: entry.calories,
            protein: entry.protein,
            carbs: entry.carbs,
            fat: entry.fat
        )
    }

    init(entries: [FoodEntry]) {
        self = entries.reduce(.zero) { totals, entry in
            totals + WhatIfMacroTotals(entry: entry)
        }
    }

    static func + (lhs: WhatIfMacroTotals, rhs: WhatIfMacroTotals) -> WhatIfMacroTotals {
        WhatIfMacroTotals(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat
        )
    }
}

struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissTapView {
        KeyboardDismissTapView()
    }

    func updateUIView(_ uiView: KeyboardDismissTapView, context: Context) {
        uiView.installIfNeeded()
    }

    static func dismantleUIView(_ uiView: KeyboardDismissTapView, coordinator: ()) {
        uiView.removeGesture()
    }
}

final class KeyboardDismissTapView: UIView, UIGestureRecognizerDelegate {
    private weak var installedWindow: UIWindow?
    private var tapGesture: UITapGestureRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    func installIfNeeded() {
        guard let window, installedWindow !== window else { return }
        removeGesture()

        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        window.addGestureRecognizer(gesture)

        installedWindow = window
        tapGesture = gesture
    }

    func removeGesture() {
        if let tapGesture, let installedWindow {
            installedWindow.removeGestureRecognizer(tapGesture)
        }
        tapGesture = nil
        installedWindow = nil
    }

    @objc private func handleTap() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !touch.viewContainsInputOrControl
    }
}

struct EndEditingDecimalTextField: UIViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    var onEditingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.keyboardType = .decimalPad
        textField.textAlignment = .right
        textField.placeholder = "0"
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.inputAccessoryView = context.coordinator.makeToolbar()
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                textField.becomeFirstResponder()
                Self.moveCaretToEnd(in: textField)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, focusRequest: focusRequest, onEditingChanged: onEditingChanged)
    }

    private static func moveCaretToEnd(in textField: UITextField) {
        let end = textField.endOfDocument
        textField.selectedTextRange = textField.textRange(from: end, to: end)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        var lastFocusRequest: Int
        private let onEditingChanged: (Bool) -> Void

        init(text: Binding<String>, focusRequest: Int, onEditingChanged: @escaping (Bool) -> Void) {
            self._text = text
            self.lastFocusRequest = focusRequest
            self.onEditingChanged = onEditingChanged
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func makeToolbar() -> UIToolbar {
            let doneItem = UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(doneTapped))
            doneItem.tintColor = Self.calorieTint

            let toolbar = UIToolbar()
            toolbar.items = [
                UIBarButtonItem(systemItem: .flexibleSpace),
                doneItem
            ]
            toolbar.sizeToFit()
            return toolbar
        }

        @objc func doneTapped() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            onEditingChanged(true)
            DispatchQueue.main.async {
                EndEditingDecimalTextField.moveCaretToEnd(in: textField)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            onEditingChanged(false)
        }

        private static let calorieTint = UIColor(red: 1.0, green: 55.0 / 255.0, blue: 95.0 / 255.0, alpha: 1.0)
    }
}

private extension UITouch {
    var viewContainsInputOrControl: Bool {
        var currentView = view
        while let view = currentView {
            if view is UITextField || view is UITextView || view is UIControl {
                return true
            }
            currentView = view.superview
        }
        return false
    }
}

struct ReviewNutritionValueRow: View {
    let label: String
    let displayValue: String
    let editValue: String
    let unit: String
    let isUnlocked: Bool
    var dim = false
    let onEdit: (String) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(LocalizedDisplayText.text(label))
                .foregroundStyle(dim ? .secondary : .primary)
            Spacer()
            if isUnlocked {
                TextField("0", text: Binding(
                    get: { isFocused ? draft : editValue },
                    set: { newValue in
                        draft = newValue
                        onEdit(newValue)
                    }
                ))
                .focused($isFocused)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .fontWeight(.medium)
                .frame(minWidth: 76, maxWidth: 118)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.calorie.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                .onAppear { draft = editValue }
                .onChange(of: editValue) { _, newValue in
                    if !isFocused {
                        draft = newValue
                    }
                }
                .onChange(of: isUnlocked) { _, unlocked in
                    if unlocked {
                        draft = editValue
                    } else {
                        isFocused = false
                    }
                }
            } else {
                Text(displayValue)
                    .fontWeight(.medium)
            }
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
}

struct NutritionDisplayRow: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        HStack {
            Text(LocalizedDisplayText.text(label))
            Spacer()
            Text(value)
                .fontWeight(.medium)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
}

struct OptionalNutritionDisplayRow: View {
    let label: String
    let value: Double?
    let unit: String

    var body: some View {
        HStack {
            Text(LocalizedDisplayText.text(label))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.map { String(format: "%.1f", $0) } ?? "—")
                .fontWeight(.medium)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
}
