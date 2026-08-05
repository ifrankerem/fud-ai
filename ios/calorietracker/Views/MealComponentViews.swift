import SwiftUI

// MARK: - Confidence

extension AnalysisConfidence {
    var tint: Color {
        switch self {
        case .low: return .orange
        case .medium: return .yellow
        case .high: return .green
        }
    }

    var symbolName: String {
        switch self {
        case .low: return "questionmark.circle.fill"
        case .medium: return "circle.lefthalf.filled"
        case .high: return "checkmark.circle.fill"
        }
    }
}

/// Compact "how sure is this" pill. Shows the exact score when the model gave one,
/// otherwise the bucket name.
struct ConfidenceBadge: View {
    let score: ConfidenceScore
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: score.level.symbolName)
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
            if !compact {
                Text(score.displayText)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(score.level.tint)
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(score.level.tint.opacity(0.14), in: Capsule())
        .accessibilityLabel(
            "\(LocalizedDisplayText.text("Confidence", polish: "Pewność")): \(score.displayText)"
        )
    }
}

// MARK: - Calorie range

/// Shows the honest bounds around the point estimate, e.g. "620–760 kcal".
struct CalorieRangeRow: View {
    let range: CalorieRange
    let confidence: ConfidenceScore?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedDisplayText.text("Likely range", polish: "Prawdopodobny zakres"))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Text("\(range.displayText) kcal")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            Spacer()
            if let confidence {
                ConfidenceBadge(score: confidence)
            }
        }
    }
}

// MARK: - Components

/// One part of the plate. Collapsed it is a summary line; expanded it exposes grams,
/// calories and macros so a wrong rice estimate can be fixed without touching the rest.
struct MealComponentRow: View {
    /// Values already scaled to the portion the user selected.
    let component: MealComponent
    let onEditGrams: (String) -> Void
    let onEditCalories: (String) -> Void
    let onEditProtein: (String) -> Void
    let onEditCarbs: (String) -> Void
    let onEditFat: (String) -> Void
    let onRemove: () -> Void

    @State private var isExpanded = false

    private var summary: String {
        "\(MealComponentFormat.grams(component.grams)) g · \(component.calories) kcal"
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ReviewNutritionValueRow(
                label: "Amount",
                displayValue: MealComponentFormat.grams(component.grams),
                editValue: MealComponentFormat.grams(component.grams),
                unit: "g",
                isUnlocked: true,
                onEdit: onEditGrams
            )
            ReviewNutritionValueRow(
                label: "Calories",
                displayValue: "\(component.calories)",
                editValue: "\(component.calories)",
                unit: "kcal",
                isUnlocked: true,
                onEdit: onEditCalories
            )
            ReviewNutritionValueRow(
                label: "Protein",
                displayValue: MacroValueFormatter.string(component.protein),
                editValue: MacroValueFormatter.string(component.protein),
                unit: "g",
                isUnlocked: true,
                dim: true,
                onEdit: onEditProtein
            )
            ReviewNutritionValueRow(
                label: "Carbs",
                displayValue: MacroValueFormatter.string(component.carbs),
                editValue: MacroValueFormatter.string(component.carbs),
                unit: "g",
                isUnlocked: true,
                dim: true,
                onEdit: onEditCarbs
            )
            ReviewNutritionValueRow(
                label: "Fat",
                displayValue: MacroValueFormatter.string(component.fat),
                editValue: MacroValueFormatter.string(component.fat),
                unit: "g",
                isUnlocked: true,
                dim: true,
                onEdit: onEditFat
            )
            if let note = component.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive, action: onRemove) {
                Label(
                    LocalizedDisplayText.text("Remove from meal", polish: "Usuń z posiłku"),
                    systemImage: "trash"
                )
                .font(.subheadline)
            }
            .buttonStyle(.borderless)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(component.name)
                            .lineLimit(1)
                        if component.isHidden {
                            // Oil, butter, dressing: calories the photo never showed.
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .accessibilityLabel(
                                    LocalizedDisplayText.text("Hidden calories", polish: "Ukryte kalorie")
                                )
                        }
                    }
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let confidence = component.confidence {
                    ConfidenceBadge(score: confidence, compact: true)
                }
            }
        }
        .tint(AppColors.calorie)
    }
}

enum MealComponentFormat {
    static func grams(_ value: Double) -> String {
        if value >= 10 || value == value.rounded() {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Assumptions

/// What the model had to guess. Surfacing this is the difference between a number
/// the user can sanity-check and one they have to take on faith.
struct AssumptionsSection: View {
    let assumptions: [String]

    var body: some View {
        ForEach(Array(assumptions.enumerated()), id: \.offset) { _, assumption in
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                Text(assumption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Clarifying questions

/// Short multiple-choice questions the model wants answered before it commits.
/// Answering re-runs the analysis with the answers folded into the context.
struct ClarifyingQuestionsView: View {
    let questions: [ClarifyingQuestion]
    @Binding var answers: [UUID: String]
    let isRefining: Bool
    let onRefine: () -> Void

    private var answeredCount: Int {
        questions.filter { answers[$0.id] != nil }.count
    }

    var body: some View {
        ForEach(questions) { question in
            VStack(alignment: .leading, spacing: 8) {
                Text(question.question)
                    .font(.subheadline.weight(.medium))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(question.options, id: \.self) { option in
                            let isSelected = answers[question.id] == option
                            Button {
                                // Tapping the chosen answer again clears it, so a
                                // mis-tap doesn't force a pointless re-analysis.
                                answers[question.id] = isSelected ? nil : option
                            } label: {
                                Text(option)
                                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        isSelected ? AppColors.calorie.opacity(0.18) : Color.secondary.opacity(0.10),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(isSelected ? AppColors.calorie : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.vertical, 2)
        }

        Button(action: onRefine) {
            HStack {
                if isRefining {
                    ProgressView().controlSize(.small)
                }
                Text(
                    isRefining
                        ? LocalizedDisplayText.text("Re-analyzing…", polish: "Ponowna analiza…")
                        : LocalizedDisplayText.text("Update estimate", polish: "Zaktualizuj szacunek")
                )
                .font(.system(.body, design: .rounded, weight: .semibold))
            }
        }
        .disabled(answeredCount == 0 || isRefining)
        .tint(AppColors.calorie)
    }
}
