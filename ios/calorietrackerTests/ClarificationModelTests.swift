import Foundation
import Testing
@testable import calorietracker

struct ClarifyingQuestionTests {

    @Test func inferredKindFollowsShapeWhenModelOmitsIt() {
        #expect(ClarifyingQuestionKind.parse(nil, optionCount: 3) == .singleChoice)
        #expect(ClarifyingQuestionKind.parse(nil, optionCount: 0) == .freeText)
    }

    @Test func parsesDeclaredKinds() {
        #expect(ClarifyingQuestionKind.parse("numeric_measurement", optionCount: 0) == .numericMeasurement)
        #expect(ClarifyingQuestionKind.parse("YES-NO", optionCount: 0) == .yesNo)
        #expect(ClarifyingQuestionKind.parse("request additional photo", optionCount: 0) == .requestAdditionalPhoto)
        #expect(ClarifyingQuestionKind.parse("weight", optionCount: 0) == .numericMeasurement)
    }

    /// A choice question with nothing to choose between is a dead end.
    @Test func choiceQuestionNeedsOptionsToRender() {
        let empty = ClarifyingQuestion(kind: .singleChoice, question: "Grilled?", options: [])
        let single = ClarifyingQuestion(kind: .singleChoice, question: "Grilled?", options: ["Yes"])
        let real = ClarifyingQuestion(kind: .singleChoice, question: "Grilled?", options: ["Yes", "No"])
        #expect(!empty.isRenderable)
        #expect(!single.isRenderable)
        #expect(real.isRenderable)
    }

    @Test func otherKindsRenderWithoutOptions() {
        #expect(ClarifyingQuestion(kind: .numericMeasurement, question: "How much rice?").isRenderable)
        #expect(ClarifyingQuestion(kind: .yesNo, question: "Any oil?").isRenderable)
        #expect(ClarifyingQuestion(kind: .freeText, question: "What sauce?").isRenderable)
    }

    @Test func blankQuestionNeverRenders() {
        #expect(!ClarifyingQuestion(kind: .yesNo, question: "   ").isRenderable)
    }

    @Test func emptyAnswerCarriesQuestionContext() {
        let question = ClarifyingQuestion(
            id: "rice_weight",
            kind: .numericMeasurement,
            question: "How much rice?",
            suggestedUnit: "g"
        )
        let answer = question.emptyAnswer()
        #expect(answer.questionID == "rice_weight")
        #expect(answer.kind == .numericMeasurement)
        #expect(answer.unit == "g")
        #expect(!answer.isAnswered)
    }

    /// Ids must survive storage: they are how a follow-up analysis matches answers
    /// back to the questions that produced them.
    @Test func stableIDSurvivesRoundTrip() throws {
        let question = ClarifyingQuestion(id: "rice_oil", kind: .singleChoice, question: "Oily?", options: ["Yes", "No"])
        let data = try JSONEncoder().encode(question)
        let decoded = try JSONDecoder().decode(ClarifyingQuestion.self, from: data)
        #expect(decoded.id == "rice_oil")
        #expect(decoded.kind == .singleChoice)
    }

    @Test func decodesEntryWrittenBeforeKindExisted() throws {
        let legacy = #"{"id":"abc","question":"Grilled or fried?","options":["Grilled","Fried"]}"#
        let decoded = try JSONDecoder().decode(ClarifyingQuestion.self, from: Data(legacy.utf8))
        #expect(decoded.kind == .singleChoice)
        #expect(decoded.options.count == 2)
    }
}

struct ClarificationAnswerTests {

    @Test func answeredDetectionPerKind() {
        #expect(!ClarificationAnswer(questionID: "a", kind: .singleChoice).isAnswered)
        #expect(ClarificationAnswer(questionID: "a", kind: .singleChoice, choice: "Grilled").isAnswered)
        #expect(ClarificationAnswer(questionID: "a", kind: .yesNo, boolValue: false).isAnswered)
        #expect(ClarificationAnswer(questionID: "a", kind: .numericMeasurement, numericValue: 185).isAnswered)
        #expect(!ClarificationAnswer(questionID: "a", kind: .numericMeasurement, numericValue: 0).isAnswered)
        #expect(!ClarificationAnswer(questionID: "a", kind: .freeText, text: "  ").isAnswered)
    }

    /// "I don't know" is information: it tells the follow-up analysis to stop
    /// leaning on that detail. It is not the same as leaving a question blank.
    @Test func dontKnowCountsAsAnswered() {
        let answer = ClarificationAnswer(questionID: "a", kind: .numericMeasurement, isDontKnow: true)
        #expect(answer.isAnswered)
        #expect(answer.answerText == "user does not know")
        #expect(answer.impliedQuantitySource == nil)
    }

    /// A number the user typed is the strongest provenance the app can obtain.
    @Test func numericAnswerImpliesUserMeasurement() {
        let answer = ClarificationAnswer(questionID: "a", kind: .numericMeasurement, numericValue: 185, unit: "g")
        #expect(answer.impliedQuantitySource == .userMeasured)
        #expect(answer.answerText.contains("185 g"))
        #expect(answer.answerText.contains("measured by the user"))
    }

    @Test func nonNumericAnswersImplyNoMeasurement() {
        #expect(ClarificationAnswer(questionID: "a", kind: .singleChoice, choice: "Fried").impliedQuantitySource == nil)
        #expect(ClarificationAnswer(questionID: "a", kind: .yesNo, boolValue: true).impliedQuantitySource == nil)
    }

    @Test func promptLineIncludesQuestionAndAnswer() {
        let answer = ClarificationAnswer(
            questionID: "rice_oil",
            kind: .singleChoice,
            questionText: "How oily was the rice?",
            choice: "Very oily"
        )
        #expect(answer.promptLine == "How oily was the rice? — Very oily")
    }

    @Test func survivesRoundTrip() throws {
        let answer = ClarificationAnswer(
            questionID: "rice_weight",
            kind: .numericMeasurement,
            questionText: "How much rice?",
            numericValue: 220,
            unit: "g"
        )
        let decoded = try JSONDecoder().decode(
            ClarificationAnswer.self,
            from: try JSONEncoder().encode(answer)
        )
        #expect(decoded == answer)
    }
}

struct PhotoEvidenceKindTests {

    /// This is the "prefer scale and label over visual estimation" rule expressed
    /// as data, so it holds even when the model ignores the prompt wording.
    @Test func measurementPhotosCarryExactProvenance() {
        #expect(PhotoEvidenceKind.kitchenScale.impliedQuantitySource == .kitchenScale)
        #expect(PhotoEvidenceKind.nutritionLabel.impliedQuantitySource == .nutritionLabel)
        #expect(PhotoEvidenceKind.kitchenScale.impliedQuantitySource?.isExact == true)
        #expect(
            (PhotoEvidenceKind.kitchenScale.impliedQuantitySource?.authority ?? 0)
                > QuantitySource.visualEstimate.authority
        )
    }

    @Test func plainPhotosCarryNoProvenance() {
        #expect(PhotoEvidenceKind.anotherAngle.impliedQuantitySource == nil)
        #expect(PhotoEvidenceKind.other.impliedQuantitySource == nil)
    }

    /// A second angle and a leftovers shot both depict food already counted;
    /// treating them as new food would double the meal.
    @Test func repeatViewsAreMarkedAsAlreadyCounted() {
        #expect(PhotoEvidenceKind.anotherAngle.depictsAlreadyCountedFood)
        #expect(PhotoEvidenceKind.afterEating.depictsAlreadyCountedFood)
        #expect(!PhotoEvidenceKind.beforeEating.depictsAlreadyCountedFood)
        #expect(!PhotoEvidenceKind.kitchenScale.depictsAlreadyCountedFood)
    }

    @Test func parsesLooseLabels() {
        #expect(PhotoEvidenceKind.parse("kitchen_scale") == .kitchenScale)
        #expect(PhotoEvidenceKind.parse("leftovers") == .afterEating)
        #expect(PhotoEvidenceKind.parse("side angle") == .anotherAngle)
        #expect(PhotoEvidenceKind.parse("nonsense") == .other)
        #expect(PhotoEvidenceKind.parse(nil) == .other)
    }

    @Test func everyKindDescribesItselfToTheModel() {
        for kind in PhotoEvidenceKind.allCases {
            #expect(!kind.promptDescription.isEmpty)
            #expect(!kind.displayName.isEmpty)
        }
    }
}

struct AnalysisProvenanceTests {

    /// A silent fallback means the provider that answered is not the one that was
    /// selected — recording the selected one would be a lie in exactly the cases
    /// that matter most for judging reliability.
    @Test func builtFromOutcomeKeepsFallbackFlag() {
        let outcome = AIRequestOutcome(
            text: "{}",
            providerName: "Anthropic Claude",
            model: "claude-sonnet-5",
            usedFallback: true
        )
        let provenance = AnalysisProvenance(outcome: outcome, stage: .refined)
        #expect(provenance.providerName == "Anthropic Claude")
        #expect(provenance.model == "claude-sonnet-5")
        #expect(provenance.usedFallback)
        #expect(provenance.stage == .refined)
        #expect(provenance.displaySummary.contains("Fallback"))
    }

    @Test func summaryOmitsFallbackWhenPrimaryAnswered() {
        let provenance = AnalysisProvenance(providerName: "Google Gemini", model: "gemini-3.6-flash")
        #expect(!provenance.displaySummary.contains("Fallback"))
        #expect(provenance.displaySummary.contains("Google Gemini"))
    }

    @Test func survivesRoundTrip() throws {
        let provenance = AnalysisProvenance(
            providerName: "OpenAI",
            model: "gpt-5.5",
            usedFallback: false,
            stage: .refined,
            userEdited: true,
            answeredQuestionCount: 2
        )
        let decoded = try JSONDecoder().decode(
            AnalysisProvenance.self,
            from: try JSONEncoder().encode(provenance)
        )
        #expect(decoded == provenance)
    }

    @Test func decodesPartialRecordWithoutThrowing() throws {
        let partial = #"{"providerName":"Groq"}"#
        let decoded = try JSONDecoder().decode(AnalysisProvenance.self, from: Data(partial.utf8))
        #expect(decoded.providerName == "Groq")
        #expect(decoded.stage == .initial)
        #expect(!decoded.userEdited)
    }
}
