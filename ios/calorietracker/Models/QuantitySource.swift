import Foundation

/// Where a quantity actually came from.
///
/// The app's core honesty problem is that a photo cannot measure food, yet every
/// number looks equally solid once it lands in the diary. Tracking provenance
/// alongside the value is what lets the UI say "185 g · Measured" instead of
/// "185 g", lets the analysis skip asking for a weight the user already gave, and
/// lets a second-pass analysis refuse to overwrite something the user weighed.
enum QuantitySource: String, Codable, CaseIterable, Hashable {
    /// A number the user typed or stated in their note ("chicken is 185 g").
    case userMeasured
    /// Read off a kitchen-scale display visible in a photo.
    case kitchenScale
    /// Taken from a nutrition label in a photo.
    case nutritionLabel
    /// From a barcode lookup against a product database.
    case barcode
    /// A standard packaged serving ("one 45 g packet").
    case knownServing
    /// The model's guess from what the photo shows. The common case.
    case visualEstimate
    /// Derived from something else rather than seen — e.g. oil inferred from a
    /// dish being fried, when no oil is visible.
    case inferred
    /// Provenance was not reported. Treated as no better than a guess.
    case unknown

    /// Whether this counts as a real measurement.
    ///
    /// This is the line the clarification logic is built on: exact sources are
    /// never questioned again, everything else is fair game for "how much was it?"
    var isExact: Bool {
        switch self {
        case .userMeasured, .kitchenScale, .nutritionLabel, .barcode, .knownServing:
            return true
        case .visualEstimate, .inferred, .unknown:
            return false
        }
    }

    /// Ranking used when two passes disagree about the same component.
    ///
    /// A follow-up analysis may not quietly replace a weighed value with a guess,
    /// so merging compares authority rather than trusting whichever answer is
    /// newer. Higher wins; equal means the newer value may take over.
    var authority: Int {
        switch self {
        case .userMeasured: return 100
        case .kitchenScale: return 90
        case .nutritionLabel: return 80
        case .barcode: return 70
        case .knownServing: return 60
        case .visualEstimate: return 20
        case .inferred: return 10
        case .unknown: return 0
        }
    }

    /// Short suffix for a quantity row: "185 g · Measured".
    var displayLabel: String {
        switch self {
        case .userMeasured: return LocalizedDisplayText.text("Measured", polish: "Zmierzone")
        case .kitchenScale: return LocalizedDisplayText.text("From scale", polish: "Z wagi")
        case .nutritionLabel: return LocalizedDisplayText.text("From label", polish: "Z etykiety")
        case .barcode: return LocalizedDisplayText.text("From barcode", polish: "Z kodu")
        case .knownServing: return LocalizedDisplayText.text("Standard serving", polish: "Standardowa porcja")
        case .visualEstimate: return LocalizedDisplayText.text("Estimate", polish: "Szacunek")
        case .inferred: return LocalizedDisplayText.text("Assumed", polish: "Założone")
        case .unknown: return LocalizedDisplayText.text("Unverified", polish: "Niezweryfikowane")
        }
    }

    var symbolName: String {
        switch self {
        case .userMeasured: return "hand.raised.fill"
        case .kitchenScale: return "scalemass.fill"
        case .nutritionLabel: return "doc.text.fill"
        case .barcode: return "barcode"
        case .knownServing: return "shippingbox.fill"
        case .visualEstimate: return "eye.fill"
        case .inferred: return "lightbulb.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Reads whatever the model sent. Providers are inconsistent about casing and
    /// word separators, and an unrecognised string must degrade to `.unknown`
    /// rather than to a false claim of measurement.
    static func parse(_ raw: Any?) -> QuantitySource {
        guard let string = raw as? String else { return .unknown }
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !normalized.isEmpty else { return .unknown }

        for candidate in QuantitySource.allCases where candidate.rawValue.lowercased() == normalized {
            return candidate
        }

        // Reasonable synonyms seen from models that paraphrase the enum.
        switch normalized {
        case "user", "usersupplied", "userprovided", "userstated", "measured", "weighed":
            return .userMeasured
        case "scale", "scalereading", "kitchenscalereading":
            return .kitchenScale
        case "label", "nutritionfacts", "nutritionfactslabel", "packaginglabel":
            return .nutritionLabel
        case "packaged", "package", "productdatabase":
            return .barcode
        case "serving", "standardserving", "packetserving":
            return .knownServing
        case "visual", "estimate", "estimated", "visualestimation", "photoestimate":
            return .visualEstimate
        case "assumed", "assumption", "derived", "deduced":
            return .inferred
        default:
            return .unknown
        }
    }
}
