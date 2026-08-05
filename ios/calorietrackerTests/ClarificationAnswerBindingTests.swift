import Foundation
import Testing
@testable import calorietracker

/// The clarification UI binds directly to `ClarificationAnswer`, so the answer's
/// own state transitions are what actually decide whether a second analysis is
/// worth running. These cover the transitions the controls perform, without
/// standing up SwiftUI.
struct ClarificationAnswerBindingTests {

    private func answer(_ kind: ClarifyingQuestionKind) -> ClarificationAnswer {
        ClarificationAnswer(questionID: "q", kind: kind, questionText: "Question?")
    }

    /// Tapping the chosen chip again clears it, so a mis-tap does not force a
    /// pointless re-analysis.
    @Test func reselectingAChoiceClearsIt() {
        var value = answer(.singleChoice)
        value.choice = "Very oily"
        #expect(value.isAnswered)

        value.choice = value.choice == "Very oily" ? nil : "Very oily"
        #expect(!value.isAnswered)
    }

    @Test func yesNoTogglesOff() {
        var value = answer(.yesNo)
        value.boolValue = true
        #expect(value.isAnswered)
        value.boolValue = value.boolValue == true ? nil : true
        #expect(!value.isAnswered)
    }

    /// Answering after marking "I don't know" has to clear the flag, or the
    /// follow-up prompt would carry both claims at once.
    @Test func answeringSupersedesDontKnow() {
        var value = answer(.numericMeasurement)
        value.isDontKnow = true
        #expect(value.answerText == "user does not know")

        value.numericValue = 185
        value.isDontKnow = false
        #expect(value.impliedQuantitySource == .userMeasured)
        #expect(value.answerText.contains("185"))
    }

    /// A "don't know" measurement must not be read as a measurement of zero.
    @Test func dontKnowNeverImpliesAMeasurement() {
        var value = answer(.numericMeasurement)
        value.numericValue = 185
        value.isDontKnow = true
        #expect(value.impliedQuantitySource == nil)
        #expect(value.isAnswered)
    }

    @Test func blankTextIsNotAnAnswer() {
        var value = answer(.freeText)
        value.text = "   "
        #expect(!value.isAnswered)
        value.text = "It had mayonnaise in it"
        #expect(value.isAnswered)
    }

    @Test func photoRequestIsAnsweredOnceAKindIsChosen() {
        var value = answer(.requestAdditionalPhoto)
        #expect(!value.isAnswered)
        value.photoKind = .kitchenScale
        #expect(value.isAnswered)
    }

    /// The unit travels with the number; dropping it would turn 1 kg into 1 g.
    @Test func emptyAnswerCarriesTheSuggestedUnit() {
        let question = ClarifyingQuestion(
            id: "rice",
            kind: .numericMeasurement,
            question: "How much rice?",
            suggestedUnit: "ml"
        )
        #expect(question.emptyAnswer().unit == "ml")
    }

    /// The unit list is short on purpose — a long one turns a two-tap answer into
    /// a scroll — but it has to cover what the prompt suggests.
    @Test func unitOptionsCoverTheCommonCases() {
        #expect(ClarificationUnits.options.contains("g"))
        #expect(ClarificationUnits.options.contains("ml"))
        #expect(ClarificationUnits.options.count <= 10)
    }

    /// Skipping is always allowed, so a set of half-answered questions still has
    /// to produce something the follow-up can use.
    @Test func partialAnswersAreUsable() {
        var first = answer(.singleChoice)
        first.choice = "Very oily"
        let second = answer(.yesNo)

        let answered = [first, second].filter(\.isAnswered)
        #expect(answered.count == 1)

        let detail = MealAnalysisDetail().applying(answers: [first, second])
        #expect(detail.answers.count == 1)
    }
}
