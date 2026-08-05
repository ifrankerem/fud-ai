import Foundation

/// What an attached photo is meant to prove.
///
/// The app already accepts several photos per meal but treats them all as "more
/// pixels of the same plate". They are not interchangeable: a kitchen-scale
/// display is a measurement, a nutrition label is product data, and a second
/// angle is the same food again and must not be counted twice. Labelling the
/// photo is what lets the analysis apply those rules instead of guessing.
enum PhotoEvidenceKind: String, Codable, CaseIterable, Hashable {
    /// The same food from a different viewpoint. Improves volume estimation and
    /// must never be added to the meal a second time.
    case anotherAngle
    /// A scale display showing a weight.
    case kitchenScale
    /// A nutrition facts panel.
    case nutritionLabel
    /// Front-of-pack: brand, product name, serving count.
    case packaging
    /// The full portion before eating.
    case beforeEating
    /// What was left afterwards, for working out what was actually consumed.
    case afterEating
    /// Unlabelled. Treated as an ordinary photo of the meal.
    case other

    var displayName: String {
        switch self {
        case .anotherAngle: return LocalizedDisplayText.text("Another angle", polish: "Inne ujęcie")
        case .kitchenScale: return LocalizedDisplayText.text("Kitchen scale", polish: "Waga kuchenna")
        case .nutritionLabel: return LocalizedDisplayText.text("Nutrition label", polish: "Etykieta")
        case .packaging: return LocalizedDisplayText.text("Packaging", polish: "Opakowanie")
        case .beforeEating: return LocalizedDisplayText.text("Before eating", polish: "Przed jedzeniem")
        case .afterEating: return LocalizedDisplayText.text("After eating", polish: "Po jedzeniu")
        case .other: return LocalizedDisplayText.text("Other", polish: "Inne")
        }
    }

    var symbolName: String {
        switch self {
        case .anotherAngle: return "arrow.triangle.2.circlepath.camera"
        case .kitchenScale: return "scalemass"
        case .nutritionLabel: return "doc.text"
        case .packaging: return "shippingbox"
        case .beforeEating: return "fork.knife"
        case .afterEating: return "checkmark.circle"
        case .other: return "photo"
        }
    }

    /// How this photo is described to the model. Phrased as an instruction because
    /// the label only matters if it changes what the model does with the image.
    var promptDescription: String {
        switch self {
        case .anotherAngle:
            return "another angle of the SAME food already shown — use it to refine the portion estimate, do not add it as extra food"
        case .kitchenScale:
            return "a kitchen scale display — read the weight and treat it as a measurement that overrides any visual portion estimate"
        case .nutritionLabel:
            return "a nutrition facts label — use its printed values instead of estimating"
        case .packaging:
            return "product packaging — use it to identify the brand, product and stated serving size"
        case .beforeEating:
            return "the full portion before eating"
        case .afterEating:
            return "the leftovers after eating — what was consumed is the before amount minus this"
        case .other:
            return "an additional photo of the meal"
        }
    }

    /// The provenance a quantity read from this photo earns.
    ///
    /// This is the "prefer scale and label over visual estimation" rule expressed
    /// as data rather than as prompt wording the model may ignore: a quantity
    /// sourced from a scale photo outranks a guess by [`QuantitySource.authority`].
    var impliedQuantitySource: QuantitySource? {
        switch self {
        case .kitchenScale: return .kitchenScale
        case .nutritionLabel: return .nutritionLabel
        case .packaging: return .knownServing
        case .anotherAngle, .beforeEating, .afterEating, .other: return nil
        }
    }

    /// Whether this photo shows food that is already accounted for elsewhere in
    /// the meal. Guards against double-counting.
    var depictsAlreadyCountedFood: Bool {
        switch self {
        case .anotherAngle, .afterEating: return true
        case .kitchenScale, .nutritionLabel, .packaging, .beforeEating, .other: return false
        }
    }

    static func parse(_ raw: Any?) -> PhotoEvidenceKind {
        guard let string = raw as? String else { return .other }
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        for candidate in PhotoEvidenceKind.allCases where candidate.rawValue.lowercased() == normalized {
            return candidate
        }
        switch normalized {
        case "angle", "sideangle", "secondangle", "differentangle": return .anotherAngle
        case "scale", "weight", "scalephoto": return .kitchenScale
        case "label", "nutritionfacts", "nutrition": return .nutritionLabel
        case "package", "box", "wrapper", "front": return .packaging
        case "before", "full", "start": return .beforeEating
        case "after", "leftover", "leftovers", "remaining": return .afterEating
        default: return .other
        }
    }
}
