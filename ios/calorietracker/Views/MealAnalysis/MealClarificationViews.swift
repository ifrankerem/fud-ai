import SwiftUI

/// The controls the user answers a clarification question with.
///
/// The kind decides the control, which is most of what makes answering fast
/// enough that people bother: a weight gets a number pad, "grilled or fried" gets
/// two taps, and nothing gets a typing task unless nothing shorter will do.
struct ClarificationQuestionRow: View {
    let question: ClarifyingQuestion
    @Binding var answer: ClarificationAnswer
    /// Called when the user accepts a request for another photo.
    var onRequestPhoto: ((PhotoEvidenceKind) -> Void)?

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(question.question)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                // A question that explains itself gets answered far more often than
                // one that just interrogates.
                if let reason = question.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            control

            // Not knowing is a real answer: it tells the follow-up analysis to stop
            // leaning on that detail instead of asking again.
            if question.kind != .requestAdditionalPhoto {
                Button {
                    answer.isDontKnow.toggle()
                    if answer.isDontKnow { isFieldFocused = false }
                } label: {
                    Label(
                        LocalizedDisplayText.text("I don't know", polish: "Nie wiem"),
                        systemImage: answer.isDontKnow ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(answer.isDontKnow ? AppColors.calorie : .secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(answer.isDontKnow ? 0.55 : 1)
    }

    @ViewBuilder
    private var control: some View {
        switch question.kind {
        case .singleChoice:
            choiceChips
        case .yesNo:
            yesNoButtons
        case .numericMeasurement:
            measurementField
        case .freeText:
            freeTextField
        case .requestAdditionalPhoto:
            photoButton
        }
    }

    // MARK: - Controls

    private var choiceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(question.options, id: \.self) { option in
                    chip(option, isSelected: answer.choice == option) {
                        // Tapping the chosen answer again clears it, so a mis-tap
                        // does not force a pointless re-analysis.
                        answer.choice = answer.choice == option ? nil : option
                        answer.isDontKnow = false
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var yesNoButtons: some View {
        HStack(spacing: 8) {
            chip(LocalizedDisplayText.text("Yes", polish: "Tak"), isSelected: answer.boolValue == true) {
                answer.boolValue = answer.boolValue == true ? nil : true
                answer.isDontKnow = false
            }
            chip(LocalizedDisplayText.text("No", polish: "Nie"), isSelected: answer.boolValue == false) {
                answer.boolValue = answer.boolValue == false ? nil : false
                answer.isDontKnow = false
            }
        }
    }

    private var measurementField: some View {
        HStack(spacing: 10) {
            TextField(
                "0",
                text: Binding(
                    get: {
                        guard let value = answer.numericValue, value > 0 else { return "" }
                        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
                    },
                    set: { text in
                        answer.numericValue = ServingUnitEditor.parseDecimal(text)
                        if answer.numericValue != nil { answer.isDontKnow = false }
                    }
                )
            )
            .focused($isFieldFocused)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .fontWeight(.medium)
            .frame(minWidth: 80, maxWidth: 130)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColors.calorie.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))

            Menu {
                ForEach(ClarificationUnits.options, id: \.self) { unit in
                    Button(unit) { answer.unit = unit }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(answer.unit ?? question.suggestedUnit ?? "g")
                        .fontWeight(.medium)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(AppColors.calorie)
            }
            Spacer(minLength: 0)
        }
    }

    private var freeTextField: some View {
        TextField(
            LocalizedDisplayText.text("Your answer", polish: "Twoja odpowiedź"),
            text: Binding(
                get: { answer.text ?? "" },
                set: { newValue in
                    answer.text = newValue
                    if !newValue.isEmpty { answer.isDontKnow = false }
                }
            ),
            axis: .vertical
        )
        .focused($isFieldFocused)
        .lineLimit(1...3)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppColors.calorie.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private var photoButton: some View {
        let kind = question.requestedPhotoKind ?? .anotherAngle
        return Button {
            answer.photoKind = kind
            onRequestPhoto?(kind)
        } label: {
            Label(kind.displayName, systemImage: kind.symbolName)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.calorie.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppColors.calorie)
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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

enum ClarificationUnits {
    /// Deliberately short. A long unit list turns a two-tap answer into a scroll,
    /// and the analysis can price an unusual unit from a free-text answer instead.
    static let options = ["g", "ml", "oz", "cup", "tbsp", "tsp", "slice", "piece", "serving"]
}

/// The banner that says an estimate is not settled yet, and offers the two ways
/// forward. Skipping is always available — the user is never trapped behind a
/// question they cannot answer.
struct ProvisionalEstimateBanner: View {
    let questionCount: Int
    let isRefining: Bool
    let onAnswer: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                Text(
                    questionCount == 1
                        ? LocalizedDisplayText.text("One answer would sharpen this estimate", polish: "Jedna odpowiedź poprawi szacunek")
                        : String(
                            format: LocalizedDisplayText.text("%d answers would sharpen this estimate", polish: "%d odpowiedzi poprawi szacunek"),
                            questionCount
                        )
                )
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(action: onAnswer) {
                    Text(LocalizedDisplayText.text("Answer", polish: "Odpowiedz"))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppColors.calorie.opacity(0.18), in: Capsule())
                        .foregroundStyle(AppColors.calorie)
                }
                .buttonStyle(.plain)
                .disabled(isRefining)

                Button(action: onSkip) {
                    Text(LocalizedDisplayText.text("Use this estimate", polish: "Użyj tego szacunku"))
                        .font(.system(.subheadline, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRefining)

                if isRefining {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }
}

/// What would most change the answer if it were known. Shown instead of a bare
/// percentage, which tells the user nothing they can act on.
struct MajorUncertaintiesView: View {
    let confidence: ConfidenceScore?
    let uncertainties: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let confidence {
                HStack {
                    Text(LocalizedDisplayText.text("Confidence", polish: "Pewność"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ConfidenceBadge(score: confidence)
                }
            }
            if !uncertainties.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        uncertainties.count == 1
                            ? LocalizedDisplayText.text("Main uncertainty", polish: "Główna niepewność")
                            : LocalizedDisplayText.text("Main uncertainties", polish: "Główne niepewności")
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach(Array(uncertainties.enumerated()), id: \.offset) { _, uncertainty in
                        Text("• \(uncertainty)")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Amounts pulled out of the user's note, shown so they can be checked before
/// anything is sent. A wrong reading the user can see is a typo; one they cannot
/// is a wrong calorie count with no explanation.
struct ExtractedMeasurementsView: View {
    let measurements: [ExtractedMeasurement]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(measurements) { measurement in
                HStack(spacing: 8) {
                    Image(systemName: measurement.quantitySource.symbolName)
                        .font(.caption)
                        .foregroundStyle(measurement.isApproximate ? .secondary : AppColors.calorie)
                    Text(measurement.foodName?.capitalized ?? LocalizedDisplayText.text("Amount", polish: "Ilość"))
                        .font(.subheadline)
                    Spacer()
                    Text(displayAmount(measurement))
                        .font(.subheadline.weight(.medium))
                    Text(measurement.quantitySource.displayLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func displayAmount(_ measurement: ExtractedMeasurement) -> String {
        let value = measurement.value == measurement.value.rounded()
            ? String(Int(measurement.value))
            : String(format: "%.1f", measurement.value)
        return "\(value) \(measurement.unit)"
    }
}
