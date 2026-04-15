import XCTest
@testable import Watch_Me_Type

final class EditOperationConverterTests: XCTestCase {

    // MARK: - Word Tokenization Tests

    func testTokenizeSimpleWords() {
        let result = tokenizeIntoWords("hello world")
        XCTAssertEqual(result, ["hello", " ", "world"])
    }

    func testTokenizeWithMultipleSpaces() {
        let result = tokenizeIntoWords("hello  world")
        XCTAssertEqual(result, ["hello", "  ", "world"])
    }

    func testTokenizeWithNewlines() {
        let result = tokenizeIntoWords("hello\nworld")
        XCTAssertEqual(result, ["hello", "\n", "world"])
    }

    func testTokenizeEmptyString() {
        let result = tokenizeIntoWords("")
        XCTAssertTrue(result.isEmpty)
    }

    func testTokenizeOnlyWhitespace() {
        let result = tokenizeIntoWords("   ")
        XCTAssertEqual(result, ["   "])
    }

    func testTokenizeWithPunctuation() {
        let result = tokenizeIntoWords("hello, world!")
        XCTAssertEqual(result, ["hello,", " ", "world!"])
    }

    // MARK: - Sentence Tokenization Tests

    func testSentencizeSingleSentence() {
        let result = sentencize("Hello world.")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], "Hello world.")
    }

    func testSentencizeMultipleSentences() {
        let result = sentencize("First. Second! Third?")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], "First. ")
        XCTAssertEqual(result[1], "Second! ")
        XCTAssertEqual(result[2], "Third?")
    }

    func testSentencizeWithNoEndingPunctuation() {
        let result = sentencize("Hello world")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], "Hello world")
    }

    func testSentencizeEmptyString() {
        let result = sentencize("")
        XCTAssertTrue(result.isEmpty)
    }

    func testSentencizeWithMultipleSpaces() {
        let result = sentencize("First.  Second.")
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Similarity Tests

    func testSimilarityIdenticalStrings() {
        let sim = similarity("hello world", "hello world")
        XCTAssertEqual(sim, 1.0)
    }

    func testSimilarityCompletelyDifferent() {
        let sim = similarity("hello world", "foo bar baz")
        XCTAssertEqual(sim, 0.0)
    }

    func testSimilarityPartialOverlap() {
        let sim = similarity("hello world", "hello there")
        // "hello" in common, "world" and "there" different
        // intersection = 1, union = 3
        XCTAssertEqual(sim, 1.0 / 3.0, accuracy: 0.001)
    }

    func testSimilarityEmptyStrings() {
        let sim = similarity("", "")
        XCTAssertEqual(sim, 0.0)
    }

    func testSimilarityOneEmpty() {
        let sim = similarity("hello", "")
        XCTAssertEqual(sim, 0.0)
    }

    // MARK: - LCS Edit Script Tests

    func testEditScriptIdentical() {
        let source = ["hello", " ", "world"]
        let dest = ["hello", " ", "world"]
        let script = computeEditScript(source, dest)

        XCTAssertEqual(script.count, 3)
        for edit in script {
            if case .keep(_) = edit { } else {
                XCTFail("Expected all keeps for identical sequences")
            }
        }
    }

    func testEditScriptSimpleDeletion() {
        let source = ["hello", " ", "world"]
        let dest = ["hello"]
        let script = computeEditScript(source, dest)

        // Should contain: keep(hello), delete( ), delete(world)
        var keepCount = 0
        var deleteCount = 0
        for edit in script {
            switch edit {
            case .keep: keepCount += 1
            case .delete: deleteCount += 1
            case .insert: XCTFail("Unexpected insert")
            }
        }
        XCTAssertEqual(keepCount, 1)
        XCTAssertEqual(deleteCount, 2)
    }

    func testEditScriptSimpleInsertion() {
        let source = ["hello"]
        let dest = ["hello", " ", "world"]
        let script = computeEditScript(source, dest)

        // Should contain: keep(hello), insert( ), insert(world)
        var keepCount = 0
        var insertCount = 0
        for edit in script {
            switch edit {
            case .keep: keepCount += 1
            case .insert: insertCount += 1
            case .delete: XCTFail("Unexpected delete")
            }
        }
        XCTAssertEqual(keepCount, 1)
        XCTAssertEqual(insertCount, 2)
    }

    func testEditScriptReplacement() {
        let source = ["quick"]
        let dest = ["slow"]
        let script = computeEditScript(source, dest)

        // Should contain: delete(quick), insert(slow)
        var deleteCount = 0
        var insertCount = 0
        for edit in script {
            switch edit {
            case .delete: deleteCount += 1
            case .insert: insertCount += 1
            case .keep: XCTFail("Unexpected keep")
            }
        }
        XCTAssertEqual(deleteCount, 1)
        XCTAssertEqual(insertCount, 1)
    }

    func testEditScriptEmpty() {
        let script = computeEditScript([], [])
        XCTAssertTrue(script.isEmpty)
    }

    // MARK: - Positioned Edits Tests

    func testPositionedEditsSimpleReplacement() {
        let draft1 = "Hello world"
        let draft2 = "Hello there"
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2)

        // Edits should be sorted right-to-left (descending position)
        for i in 0..<(edits.count - 1) {
            XCTAssertGreaterThanOrEqual(edits[i].position, edits[i + 1].position,
                "Edits should be sorted right-to-left")
        }
    }

    func testPositionedEditsIdentical() {
        let text = "Hello world"
        let edits = convertDraftsToPositionedEdits(draft1: text, draft2: text)

        // No edits needed for identical texts
        XCTAssertTrue(edits.isEmpty, "Identical texts should produce no edits")
    }

    func testPositionedEditsInsertion() {
        let draft1 = "Hello"
        let draft2 = "Hello world"
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2)

        // Should have at least one insert operation
        let hasInsert = edits.contains { edit in
            if case .insert = edit.operation { return true }
            return false
        }
        XCTAssertTrue(hasInsert, "Should have insert operation")
    }

    func testPositionedEditsDeletion() {
        let draft1 = "Hello world"
        let draft2 = "Hello"
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2)

        // Should have at least one delete operation
        let hasDelete = edits.contains { edit in
            if case .delete = edit.operation { return true }
            return false
        }
        XCTAssertTrue(hasDelete, "Should have delete operation")
    }

    // MARK: - Integration Tests

    func testEditApplicationProducesCorrectResult() {
        let draft1 = "The quick brown fox"
        let draft2 = "The slow red fox"
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2)

        // Apply edits to draft1 and verify result matches draft2
        let result = applyEdits(to: draft1, edits: edits)
        XCTAssertEqual(result, draft2, "Applying edits should produce draft2")
    }

    func testEditApplicationMultipleSentences() {
        let draft1 = "First sentence. Second sentence."
        let draft2 = "First sentence. Modified second."
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2)

        let result = applyEdits(to: draft1, edits: edits)
        XCTAssertEqual(result, draft2)
    }

    func testEditApplicationWithAddedSentence() {
        let draft1 = "First sentence."
        let draft2 = "First sentence. Second sentence."
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2)

        let result = applyEdits(to: draft1, edits: edits)
        XCTAssertEqual(result, draft2)
    }

    // MARK: - Edge Cases

    func testEmptyDraft1() {
        let edits = convertDraftsToPositionedEdits(draft1: "", draft2: "Hello")

        let hasInsert = edits.contains { edit in
            if case .insert = edit.operation { return true }
            return false
        }
        XCTAssertTrue(hasInsert)
    }

    func testEmptyDraft2() {
        let edits = convertDraftsToPositionedEdits(draft1: "Hello", draft2: "")

        let hasDelete = edits.contains { edit in
            if case .delete = edit.operation { return true }
            return false
        }
        XCTAssertTrue(hasDelete)
    }

    func testBothEmpty() {
        let edits = convertDraftsToPositionedEdits(draft1: "", draft2: "")
        XCTAssertTrue(edits.isEmpty)
    }

    func testUnicodeText() {
        let draft1 = "Hello world"
        let draft2 = "Hello monde"
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2)

        let result = applyEdits(to: draft1, edits: edits)
        XCTAssertEqual(result, draft2)
    }

    // MARK: - Left-to-Right Sorted Edits Tests

    func testPositionedEditsLeftToRightOrder() {
        let draft1 = "The quick brown fox"
        let draft2 = "A slow brown cat"
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2, direction: .leftToRight)

        for i in 0..<(edits.count - 1) {
            XCTAssertLessThanOrEqual(edits[i].position, edits[i + 1].position,
                "Edits should be sorted left-to-right")
        }
    }

    func testPositionedEditsRightToLeftOrderBackwardsCompatible() {
        let draft1 = "The quick brown fox"
        let draft2 = "A slow brown cat"
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2)

        for i in 0..<(edits.count - 1) {
            XCTAssertGreaterThanOrEqual(edits[i].position, edits[i + 1].position,
                "Default edits should be sorted right-to-left")
        }
    }

    // MARK: - Left-to-Right Edit Application Tests

    func testLeftToRightEditApplicationSimpleReplace() {
        let draft1 = "The quick brown fox"
        let draft2 = "The slow brown cat"
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2, direction: .leftToRight)
        let result = applyEditsLeftToRight(to: draft1, edits: edits)
        XCTAssertEqual(result, draft2, "Left-to-right edits should produce draft2")
    }

    func testLeftToRightEditApplicationWithLengthChange() {
        let draft1 = "The quick brown fox jumps over the lazy dog."
        let draft2 = "A fast brown fox leaps over a lazy dog."
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2, direction: .leftToRight)
        let result = applyEditsLeftToRight(to: draft1, edits: edits)
        XCTAssertEqual(result, draft2, "Left-to-right edits with length changes should produce draft2")
    }

    func testLeftToRightEditApplicationInsertOnly() {
        let draft1 = "Hello"
        let draft2 = "Hello world"
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2, direction: .leftToRight)
        let result = applyEditsLeftToRight(to: draft1, edits: edits)
        XCTAssertEqual(result, draft2)
    }

    func testLeftToRightEditApplicationDeleteOnly() {
        let draft1 = "Hello world"
        let draft2 = "Hello"
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2, direction: .leftToRight)
        let result = applyEditsLeftToRight(to: draft1, edits: edits)
        XCTAssertEqual(result, draft2)
    }

    func testLeftToRightEditApplicationMultipleSentences() {
        let draft1 = "First sentence. Second sentence. Third sentence."
        let draft2 = "Opening line. Second sentence. Final thought."
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2, direction: .leftToRight)
        let result = applyEditsLeftToRight(to: draft1, edits: edits)
        XCTAssertEqual(result, draft2)
    }

    func testLeftToRightEditApplicationIdentical() {
        let text = "No changes needed."
        let edits = convertDraftsToPositionedEdits(draft1: text, draft2: text, direction: .leftToRight)
        let result = applyEditsLeftToRight(to: text, edits: edits)
        XCTAssertEqual(result, text)
    }

    func testLeftToRightEditApplicationEmptyToText() {
        let edits = convertDraftsToPositionedEdits(draft1: "", draft2: "Hello", direction: .leftToRight)
        let result = applyEditsLeftToRight(to: "", edits: edits)
        XCTAssertEqual(result, "Hello")
    }

    func testLeftToRightEditApplicationTextToEmpty() {
        let edits = convertDraftsToPositionedEdits(draft1: "Hello", draft2: "", direction: .leftToRight)
        let result = applyEditsLeftToRight(to: "Hello", edits: edits)
        XCTAssertEqual(result, "")
    }

    func testLeftToRightAndRightToLeftProduceSameResult() {
        let draft1 = "The quick brown fox jumps over the lazy dog."
        let draft2 = "A fast brown fox leaps over a lazy dog."

        let rtlEdits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2, direction: .rightToLeft)
        let ltrEdits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2, direction: .leftToRight)

        let rtlResult = applyEdits(to: draft1, edits: rtlEdits)
        let ltrResult = applyEditsLeftToRight(to: draft1, edits: ltrEdits)

        XCTAssertEqual(rtlResult, draft2, "RTL should produce draft2")
        XCTAssertEqual(ltrResult, draft2, "LTR should produce draft2")
        XCTAssertEqual(rtlResult, ltrResult, "Both directions should produce identical results")
    }

    // MARK: - Helper Functions

    /// Applies edits to text to verify correctness
    /// Note: Edits must be applied in the order given (right-to-left)
    private func applyEdits(to text: String, edits: [EditWithPosition]) -> String {
        var chars = Array(text)

        for edit in edits {
            switch edit.operation {
            case .delete(let count):
                let endIndex = min(edit.position + count, chars.count)
                if edit.position < chars.count {
                    chars.removeSubrange(edit.position..<endIndex)
                }

            case .insert(let insertText):
                let insertIndex = min(edit.position, chars.count)
                chars.insert(contentsOf: insertText, at: insertIndex)

            case .replace(let oldCount, let newText):
                let endIndex = min(edit.position + oldCount, chars.count)
                if edit.position < chars.count {
                    chars.removeSubrange(edit.position..<endIndex)
                }
                let insertIndex = min(edit.position, chars.count)
                chars.insert(contentsOf: newText, at: insertIndex)

            default:
                break
            }
        }

        return String(chars)
    }

    /// Applies left-to-right sorted edits using an offset accumulator.
    /// This mirrors the cursor logic TypingManager will use for forward editing.
    private func applyEditsLeftToRight(to text: String, edits: [EditWithPosition]) -> String {
        var chars = Array(text)
        var offsetAccumulator = 0

        for edit in edits {
            let adjustedPosition = edit.position + offsetAccumulator

            switch edit.operation {
            case .delete(let count, _):
                let endIndex = min(adjustedPosition + count, chars.count)
                let deletedCount = adjustedPosition < chars.count ? endIndex - adjustedPosition : 0
                if deletedCount > 0 {
                    chars.removeSubrange(adjustedPosition..<endIndex)
                }
                offsetAccumulator -= deletedCount

            case .insert(let insertText):
                let insertIndex = min(adjustedPosition, chars.count)
                chars.insert(contentsOf: insertText, at: insertIndex)
                offsetAccumulator += insertText.count

            case .replace(let oldCount, let newText, _):
                let endIndex = min(adjustedPosition + oldCount, chars.count)
                let deletedCount = adjustedPosition < chars.count ? endIndex - adjustedPosition : 0
                if deletedCount > 0 {
                    chars.removeSubrange(adjustedPosition..<endIndex)
                }
                let insertIndex = min(adjustedPosition, chars.count)
                chars.insert(contentsOf: newText, at: insertIndex)
                offsetAccumulator += newText.count - deletedCount

            default:
                break
            }
        }

        return String(chars)
    }
}
