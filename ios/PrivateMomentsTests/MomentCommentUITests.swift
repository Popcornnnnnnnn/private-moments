import XCTest
@testable import PrivateMoments

final class MomentCommentUITests: XCTestCase {
    func testEmptyDraftCannotSubmit() {
        let policy = MomentCommentDraftPolicy(rawText: "")

        XCTAssertFalse(policy.canSubmit)
        XCTAssertEqual(policy.trimmedText, "")
        XCTAssertNil(policy.submissionText())
    }

    func testWhitespaceOnlyDraftCannotSubmit() {
        let policy = MomentCommentDraftPolicy(rawText: "  \n\t  \r\n")

        XCTAssertFalse(policy.canSubmit)
        XCTAssertEqual(policy.trimmedText, "")
        XCTAssertNil(policy.submissionText())
    }

    func testSubmissionTextTrimsLeadingAndTrailingWhitespace() {
        let policy = MomentCommentDraftPolicy(rawText: "  \n  Private comment  \t\n")

        XCTAssertTrue(policy.canSubmit)
        XCTAssertEqual(policy.trimmedText, "Private comment")
        XCTAssertEqual(policy.submissionText(), "Private comment")
    }

    func testInternalNewlinesAndBulletsRemainPlainText() {
        let draft = "\n- first line\n- second line\n\nclosing line\n"
        let policy = MomentCommentDraftPolicy(rawText: draft)

        XCTAssertTrue(policy.canSubmit)
        XCTAssertEqual(policy.submissionText(), "- first line\n- second line\n\nclosing line")
    }

    func testMarkdownLikeCharactersAreNotInterpretedOrRemoved() {
        let draft = "  **bold?** [link](https://example.com) `code` # heading  "
        let policy = MomentCommentDraftPolicy(rawText: draft)

        XCTAssertTrue(policy.canSubmit)
        XCTAssertEqual(policy.submissionText(), "**bold?** [link](https://example.com) `code` # heading")
    }

    func testPolicyDoesNotCreateReplyOrRichTextSemantics() {
        let draft = "  > quoted\n@person reply-like text\nplain text  "
        let policy = MomentCommentDraftPolicy(rawText: draft)

        XCTAssertEqual(policy.submissionText(), "> quoted\n@person reply-like text\nplain text")
        XCTAssertFalse(policy.submissionText()?.contains("<blockquote>") ?? true)
        XCTAssertFalse(policy.submissionText()?.contains("replyTo") ?? true)
    }

    func testDraftClearsOnlyAfterSuccessfulSubmission() {
        let policy = MomentCommentDraftPolicy(rawText: "retry this")

        XCTAssertEqual(policy.draftText(afterSubmissionSucceeded: true), "")
        XCTAssertEqual(policy.draftText(afterSubmissionSucceeded: false), "retry this")
    }
}
