import Foundation
import Testing
@testable import calorietracker

struct MeasurementExtractorTests {

    // MARK: - The cases from the spec

    @Test func extractsWeightWithFoodBefore() {
        let found = MeasurementExtractor.extract(from: "Chicken is 185 g.")
        #expect(found.count == 1)
        #expect(found.first?.value == 185)
        #expect(found.first?.unit == "g")
        #expect(found.first?.grams == 185)
        #expect(found.first?.foodName == "chicken")
        #expect(found.first?.isApproximate == false)
    }

    @Test func extractsWeightWithFoodAfter() {
        let found = MeasurementExtractor.extract(from: "I used 12 g olive oil")
        #expect(found.count == 1)
        #expect(found.first?.value == 12)
        #expect(found.first?.foodName == "olive oil")
    }

    @Test func extractsVolume() {
        let found = MeasurementExtractor.extract(from: "The bowl contains 350 ml")
        #expect(found.first?.unit == "ml")
        #expect(found.first?.grams == 350)
    }

    @Test func extractsMultipleItemsFromOneNote() {
        let found = MeasurementExtractor.extract(
            from: "Chicken 185 g, rice 220 g, 12 g olive oil, yogurt 150 g."
        )
        #expect(found.count == 4)
        #expect(found.map(\.value) == [185, 220, 12, 150])
        #expect(found.compactMap(\.foodName).contains("rice"))
        #expect(found.compactMap(\.foodName).contains("olive oil"))
    }

    /// "185g" without a space is at least as common as "185 g" in a real note.
    @Test func handlesNumberRunningIntoUnit() {
        let found = MeasurementExtractor.extract(from: "chicken 185g and rice 220g")
        #expect(found.count == 2)
        #expect(found.map(\.value) == [185, 220])
    }

    @Test func convertsNonGramWeightUnits() {
        #expect(MeasurementExtractor.extract(from: "1.5 kg beef").first?.grams == 1500)
        let ounces = MeasurementExtractor.extract(from: "4 oz salmon").first
        #expect(ounces != nil)
        #expect(abs((ounces?.grams ?? 0) - 113.398) < 0.01)
    }

    /// A slice of bread and a slice of cake are not the same weight, so the number
    /// is captured but deliberately left unconverted.
    @Test func foodDependentUnitsAreCapturedButNotConverted() {
        let found = MeasurementExtractor.extract(from: "2 tbsp peanut butter")
        #expect(found.first?.value == 2)
        #expect(found.first?.unit == "tbsp")
        #expect(found.first?.grams == nil)
    }

    @Test func handlesTwoWordUnit() {
        let found = MeasurementExtractor.extract(from: "8 fl oz milk")
        #expect(found.first?.unit == "fl oz")
        #expect(found.first?.value == 8)
    }

    @Test func acceptsCommaDecimalSeparator() {
        #expect(MeasurementExtractor.extract(from: "1,5 kg beef").first?.grams == 1500)
    }

    // MARK: - What must NOT be extracted

    /// These are the spec's examples of input that is not a measurement. None of
    /// them contains a number, so none may produce one.
    @Test func vagueDescriptionsYieldNothing() {
        for note in [
            "A normal portion",
            "One plate",
            "A small bowl",
            "A little rice",
            "The usual amount",
            "About one serving"
        ] {
            #expect(MeasurementExtractor.extract(from: note).isEmpty, "should not extract from: \(note)")
        }
    }

    @Test func numberWithoutUnitIsIgnored() {
        #expect(MeasurementExtractor.extract(from: "I ate 2 things").isEmpty)
        #expect(MeasurementExtractor.extract(from: "table 4").isEmpty)
    }

    @Test func emptyInputIsSafe() {
        #expect(MeasurementExtractor.extract(from: nil).isEmpty)
        #expect(MeasurementExtractor.extract(from: "").isEmpty)
        #expect(MeasurementExtractor.extract(from: "   ").isEmpty)
    }

    // MARK: - Hedging

    /// A hedged number is better than a photo but is not a measurement. Recording
    /// it as one would silence a question that is still worth asking.
    @Test func hedgedNumberIsNotTreatedAsMeasured() {
        let found = MeasurementExtractor.extract(from: "about 200 g rice")
        #expect(found.first?.isApproximate == true)
        #expect(found.first?.quantitySource == .visualEstimate)
        #expect(found.first?.quantitySource.isExact == false)
    }

    @Test func plainNumberIsTreatedAsMeasured() {
        let found = MeasurementExtractor.extract(from: "200 g rice")
        #expect(found.first?.isApproximate == false)
        #expect(found.first?.quantitySource == .userMeasured)
        #expect(found.first?.quantitySource.isExact == true)
    }

    @Test func tildeCountsAsHedge() {
        #expect(MeasurementExtractor.extract(from: "~200 g rice").first?.isApproximate == true)
    }

    @Test func recognisesNonEnglishHedges() {
        #expect(MeasurementExtractor.extract(from: "yaklaşık 200 g pilav").first?.isApproximate == true)
    }

    // MARK: - Output shape

    @Test func promptLineNamesTheSource() {
        let measured = MeasurementExtractor.extract(from: "chicken 185 g").first
        #expect(measured?.promptLine == "chicken: 185 g (stated by the user)")

        let hedged = MeasurementExtractor.extract(from: "about 185 g chicken").first
        #expect(hedged?.promptLine.contains("approximate") == true)
    }

    @Test func duplicatesAreCollapsed() {
        let found = MeasurementExtractor.extract(from: "rice 200 g, rice 200 g")
        #expect(found.count == 1)
    }

    /// A pathological note must not be able to flood the analysis prompt.
    @Test func outputIsBounded() {
        let note = (1...40).map { "food\($0) \($0) g" }.joined(separator: ", ")
        #expect(MeasurementExtractor.extract(from: note).count <= 12)
    }
}
