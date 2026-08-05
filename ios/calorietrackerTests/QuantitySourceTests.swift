import Foundation
import Testing
@testable import calorietracker

struct QuantitySourceTests {

    // MARK: - Exactness

    /// The clarification logic asks for a weight only when the app does not
    /// already have a real one, so this split is load-bearing, not cosmetic.
    @Test func measurementSourcesAreExact() {
        #expect(QuantitySource.userMeasured.isExact)
        #expect(QuantitySource.kitchenScale.isExact)
        #expect(QuantitySource.nutritionLabel.isExact)
        #expect(QuantitySource.barcode.isExact)
        #expect(QuantitySource.knownServing.isExact)
    }

    @Test func guessesAreNotExact() {
        #expect(!QuantitySource.visualEstimate.isExact)
        #expect(!QuantitySource.inferred.isExact)
        #expect(!QuantitySource.unknown.isExact)
    }

    // MARK: - Authority

    @Test func userMeasurementOutranksEverything() {
        for source in QuantitySource.allCases where source != .userMeasured {
            #expect(QuantitySource.userMeasured.authority > source.authority)
        }
    }

    /// A follow-up analysis returning a visual guess must not be able to displace
    /// a value the user weighed.
    @Test func guessCannotOutrankMeasurement() {
        #expect(QuantitySource.visualEstimate.authority < QuantitySource.kitchenScale.authority)
        #expect(QuantitySource.inferred.authority < QuantitySource.nutritionLabel.authority)
        #expect(QuantitySource.unknown.authority < QuantitySource.visualEstimate.authority)
    }

    @Test func everyExactSourceOutranksEveryInexactOne() {
        let exact = QuantitySource.allCases.filter(\.isExact)
        let inexact = QuantitySource.allCases.filter { !$0.isExact }
        for high in exact {
            for low in inexact {
                #expect(high.authority > low.authority)
            }
        }
    }

    // MARK: - Parsing

    @Test func parsesCanonicalNames() {
        #expect(QuantitySource.parse("userMeasured") == .userMeasured)
        #expect(QuantitySource.parse("visualEstimate") == .visualEstimate)
    }

    /// Models paraphrase enum names constantly; snake_case is the most common.
    @Test func parsesSnakeCaseAndSpacing() {
        #expect(QuantitySource.parse("user_measured") == .userMeasured)
        #expect(QuantitySource.parse("kitchen scale") == .kitchenScale)
        #expect(QuantitySource.parse("NUTRITION-LABEL") == .nutritionLabel)
        #expect(QuantitySource.parse("  visual_estimate  ") == .visualEstimate)
    }

    @Test func parsesCommonSynonyms() {
        #expect(QuantitySource.parse("weighed") == .userMeasured)
        #expect(QuantitySource.parse("scale reading") == .kitchenScale)
        #expect(QuantitySource.parse("nutrition facts") == .nutritionLabel)
        #expect(QuantitySource.parse("estimated") == .visualEstimate)
        #expect(QuantitySource.parse("assumed") == .inferred)
    }

    /// An unreadable value has to fall to `.unknown`. Falling to `.userMeasured`
    /// would fabricate a measurement and silence a question worth asking.
    @Test func unrecognisedInputFallsToUnknown() {
        #expect(QuantitySource.parse("pretty sure it was about right") == .unknown)
        #expect(QuantitySource.parse("") == .unknown)
        #expect(QuantitySource.parse("   ") == .unknown)
        #expect(QuantitySource.parse(nil) == .unknown)
        #expect(QuantitySource.parse(42) == .unknown)
        #expect(QuantitySource.parse(["userMeasured"]) == .unknown)
    }

    @Test func unknownIsNeverExact() {
        #expect(!QuantitySource.parse("garbage").isExact)
    }

    // MARK: - Round trip

    @Test func survivesCodableRoundTrip() throws {
        for source in QuantitySource.allCases {
            let data = try JSONEncoder().encode(source)
            #expect(try JSONDecoder().decode(QuantitySource.self, from: data) == source)
        }
    }

    @Test func everyCaseHasDistinctPresentation() {
        let labels = Set(QuantitySource.allCases.map(\.displayLabel))
        let symbols = Set(QuantitySource.allCases.map(\.symbolName))
        #expect(labels.count == QuantitySource.allCases.count)
        #expect(symbols.count == QuantitySource.allCases.count)
    }
}
