import Foundation

/// A quantity the user stated in their own words, pulled out of the meal note.
struct ExtractedMeasurement: Hashable, Identifiable {
    /// The fragment it came from, so the user can check what was understood.
    var rawText: String
    /// Best guess at what was being measured. Nil when the note gave a number
    /// without naming a food.
    var foodName: String?
    var value: Double
    /// Unit exactly as written, lowercased: "g", "ml", "tbsp", "slice".
    var unit: String
    /// Converted to grams when the unit allows it. Nil for units whose weight
    /// depends on the food (a "slice" of bread and of cake are not the same).
    var grams: Double?
    /// The user hedged — "about 200 g". A hedged number is still far better than
    /// a photo, but it is not a measurement and must not be recorded as one.
    var isApproximate: Bool

    var id: String { "\(foodName ?? "")|\(value)|\(unit)" }

    /// Provenance this measurement earns. A hedge downgrades it to an estimate,
    /// which keeps the app honest and leaves the question worth asking.
    var quantitySource: QuantitySource {
        isApproximate ? .visualEstimate : .userMeasured
    }

    /// One line for the prompt, e.g. `chicken: 185 g (stated by the user)`.
    var promptLine: String {
        let amount = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        let name = foodName.map { "\($0): " } ?? ""
        let hedge = isApproximate ? " (approximate, stated by the user)" : " (stated by the user)"
        return "\(name)\(amount) \(unit)\(hedge)"
    }
}

/// Pulls stated quantities out of a free-text meal note.
///
/// The point is not to parse language well — the model does that. The point is to
/// make one specific rule deterministic: if the user wrote "chicken 185 g", the
/// app must know it, so it never burns a clarification question asking for a
/// weight it was already given, and so the value can be marked as measured rather
/// than left at the model's discretion.
///
/// Anything this misses still reaches the model in the raw note, so a miss costs
/// accuracy, not correctness.
enum MeasurementExtractor {

    /// Units that convert to grams on their own. Volume units assume water-like
    /// density, which is close enough for drinks, soups and sauces and is the same
    /// assumption a person makes when they say "350 ml of soup".
    private static let gramsPerUnit: [String: Double] = [
        "g": 1, "gr": 1, "gram": 1, "grams": 1, "gramme": 1, "grammes": 1,
        "kg": 1000, "kilo": 1000, "kilos": 1000, "kilogram": 1000, "kilograms": 1000,
        "mg": 0.001,
        "ml": 1, "milliliter": 1, "millilitre": 1, "milliliters": 1, "millilitres": 1,
        "l": 1000, "liter": 1000, "litre": 1000, "liters": 1000, "litres": 1000,
        "oz": 28.3495, "ounce": 28.3495, "ounces": 28.3495,
        "lb": 453.592, "lbs": 453.592, "pound": 453.592, "pounds": 453.592
    ]

    /// Units that describe an amount but whose weight depends on the food.
    /// Recognised so the number is captured, but left unconverted.
    private static let foodDependentUnits: Set<String> = [
        "cup", "cups", "tbsp", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons",
        "slice", "slices", "piece", "pieces", "serving", "servings", "packet", "packets",
        "scoop", "scoops", "bowl", "bowls", "can", "cans", "bar", "bars",
        "fl oz", "floz"
    ]

    /// Words that turn a number into a guess. Includes the most common non-English
    /// hedges, since notes are not always written in the app's UI language.
    private static let hedgeWords: Set<String> = [
        "about", "approx", "approximately", "around", "roughly", "maybe", "some",
        "nearly", "almost", "ish", "circa",
        "yaklasik", "yaklaşık", "civari", "civarı", "kadar",
        "okolo", "mniej", "wiecej", "więcej"
    ]

    /// Filler stripped when working out what a number referred to.
    private static let noiseWords: Set<String> = [
        "i", "we", "used", "use", "ate", "eat", "had", "have", "has", "with", "and",
        "the", "a", "an", "of", "was", "were", "is", "are", "it", "there", "contains",
        "contained", "containing", "my", "this", "that", "in", "on", "plus", "total",
        "about", "approx", "approximately", "around", "roughly", "maybe", "nearly",
        "almost", "circa", "one", "two", "three", "each"
    ]

    static func extract(from note: String?) -> [ExtractedMeasurement] {
        guard let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var results: [ExtractedMeasurement] = []
        var seen = Set<String>()

        for segment in segments(of: note) {
            for measurement in measurements(in: segment) {
                guard seen.insert(measurement.id).inserted else { continue }
                results.append(measurement)
                if results.count >= 12 { return results }
            }
        }
        return results
    }

    private static let segmentSeparators: Set<Character> = [",", ";", ".", "+", "\n"]

    /// Splits on the punctuation people actually use to separate items, so
    /// "chicken 185 g, rice 220 g" yields two fragments each holding one food.
    ///
    /// A separator flanked by digits is a decimal mark, not a break — both "1.5 kg"
    /// and "1,5 kg" are single values. Splitting there would not merely lose the
    /// measurement, it would report a wrong one ("5 kg").
    private static func segments(of note: String) -> [String] {
        let characters = Array(note)
        var segments: [String] = []
        var current = ""

        for (index, character) in characters.enumerated() {
            guard segmentSeparators.contains(character) else {
                current.append(character)
                continue
            }
            let isDecimalMark = index > 0
                && index + 1 < characters.count
                && characters[index - 1].isNumber
                && characters[index + 1].isNumber
            if isDecimalMark {
                current.append(character)
            } else {
                segments.append(current)
                current = ""
            }
        }
        segments.append(current)

        return segments
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func measurements(in segment: String) -> [ExtractedMeasurement] {
        let tokens = tokenize(segment)
        guard !tokens.isEmpty else { return [] }

        var found: [ExtractedMeasurement] = []
        var index = 0
        while index < tokens.count {
            guard let value = numericValue(tokens[index]), value > 0 else {
                index += 1
                continue
            }

            // The unit is the next token, or the two next tokens for "fl oz".
            var unit: String?
            var unitLength = 0
            if index + 2 < tokens.count,
               isKnownUnit("\(tokens[index + 1]) \(tokens[index + 2])") {
                unit = "\(tokens[index + 1]) \(tokens[index + 2])"
                unitLength = 2
            } else if index + 1 < tokens.count, isKnownUnit(tokens[index + 1]) {
                unit = tokens[index + 1]
                unitLength = 1
            }

            guard let resolvedUnit = unit else {
                index += 1
                continue
            }

            let hedged = tokens.contains { hedgeWords.contains($0) }
            let name = foodName(
                tokens: tokens,
                numberIndex: index,
                unitEndIndex: index + unitLength
            )

            found.append(
                ExtractedMeasurement(
                    rawText: segment,
                    foodName: name,
                    value: value,
                    unit: resolvedUnit,
                    grams: gramsPerUnit[resolvedUnit].map { $0 * value },
                    isApproximate: hedged
                )
            )
            index += unitLength + 1
        }
        return found
    }

    private static func tokenize(_ segment: String) -> [String] {
        // "185g" is at least as common as "185 g" in a hurried note, so a digit
        // running straight into letters is split before tokenizing.
        var spaced = ""
        var previous: Character?
        for character in segment.lowercased().replacingOccurrences(of: "~", with: " about ") {
            if let previous, previous.isNumber, character.isLetter {
                spaced.append(" ")
            }
            spaced.append(character)
            previous = character
        }

        return spaced
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".,")).inverted)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ")) }
            .filter { !$0.isEmpty }
    }

    private static func isKnownUnit(_ token: String) -> Bool {
        gramsPerUnit[token] != nil || foodDependentUnits.contains(token)
    }

    private static func numericValue(_ token: String) -> Double? {
        // Accept both decimal conventions; "1,5" and "1.5" are the same amount.
        let normalized = token.contains(",") && !token.contains(".")
            ? token.replacingOccurrences(of: ",", with: ".")
            : token.replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    /// The food is whatever words in the fragment are neither the number, the
    /// unit, nor filler. Words before the number win, because "chicken 185 g"
    /// is the more common phrasing than "185 g chicken" — but both work.
    private static func foodName(tokens: [String], numberIndex: Int, unitEndIndex: Int) -> String? {
        func clean(_ range: ArraySlice<String>) -> String? {
            let words = range.filter { token in
                guard !noiseWords.contains(token) else { return false }
                guard !isKnownUnit(token) else { return false }
                guard numericValue(token) == nil else { return false }
                return token.count > 1
            }
            guard !words.isEmpty else { return nil }
            return words.joined(separator: " ")
        }

        if let before = clean(tokens[0..<numberIndex]) { return before }
        if unitEndIndex + 1 <= tokens.count, let after = clean(tokens[(unitEndIndex + 1)...]) { return after }
        return nil
    }
}
