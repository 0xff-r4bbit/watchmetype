import Foundation

// MARK: - Edit Operations

/// Represents a human-like editing operation
enum EditOperation {
    case navigateRight(count: Int)        // → arrow key
    case navigateLeft(count: Int)         // ← arrow key
    case navigateWordRight(count: Int)    // Option+→ arrow key (word jump)
    case navigateWordLeft(count: Int)     // Option+← arrow key (word jump)
    case selectLeft(count: Int)           // Shift+← arrow (select backwards)
    case selectRight(count: Int)          // Shift+→ arrow (select forwards)
    case delete(count: Int)               // Backspace/Delete key
    case insert(text: String)             // Type new text
    case replace(oldCount: Int, newText: String)  // Atomic replace: select old, delete, insert new
    case pause(duration: TimeInterval)    // Thinking pause
}

/// Edit operation with its position in the original draft1 text
struct EditWithPosition {
    let operation: EditOperation    // The edit to perform
    let position: Int                // Position in draft1 where this edit occurs
    let originalIndex: Int           // Original order in edit script (for stable sorting)
}

// NOTE: ArrowDirection and KeyModifier enums have been moved to TypingManager.swift
// where they are actually used.

// MARK: - Word Tokenization

/// Tokenizes text into words, preserving whitespace and punctuation
/// Each token is either a word or whitespace
func tokenizeIntoWords(_ text: String) -> [String] {
    var tokens: [String] = []
    var currentWord = ""
    var currentWhitespace = ""

    for char in text {
        if char.isWhitespace {
            // If we were building a word, save it
            if !currentWord.isEmpty {
                tokens.append(currentWord)
                currentWord = ""
            }
            // Accumulate whitespace
            currentWhitespace.append(char)
        } else {
            // If we were building whitespace, save it
            if !currentWhitespace.isEmpty {
                tokens.append(currentWhitespace)
                currentWhitespace = ""
            }
            // Accumulate word characters
            currentWord.append(char)
        }
    }

    // Save any remaining token
    if !currentWord.isEmpty {
        tokens.append(currentWord)
    }
    if !currentWhitespace.isEmpty {
        tokens.append(currentWhitespace)
    }

    return tokens
}

// MARK: - Sentence Tokenization

/// Splits text into sentences based on sentence-ending punctuation followed by whitespace
/// Returns array of sentences with their trailing whitespace/punctuation preserved
func sentencize(_ text: String) -> [String] {
    var sentences: [String] = []
    var currentSentence = ""
    var i = text.startIndex

    while i < text.endIndex {
        let char = text[i]
        currentSentence.append(char)

        // Check if this is a sentence boundary: . ! ? followed by space or newline or end
        if ".!?".contains(char) {
            let nextIndex = text.index(after: i)
            if nextIndex >= text.endIndex {
                // End of text - this is a sentence
                sentences.append(currentSentence)
                currentSentence = ""
                break
            }

            let nextChar = text[nextIndex]
            if nextChar.isWhitespace {
                // Sentence boundary found - include the whitespace
                currentSentence.append(nextChar)
                sentences.append(currentSentence)
                currentSentence = ""
                i = text.index(after: nextIndex)
                continue
            }
        }

        i = text.index(after: i)
    }

    // Add any remaining text as final sentence
    if !currentSentence.isEmpty {
        sentences.append(currentSentence)
    }

    return sentences
}

/// Calculates Jaccard similarity between two strings based on word overlap
/// Returns a value between 0.0 (no common words) and 1.0 (identical words)
func similarity(_ s1: String, _ s2: String) -> Double {
    let words1 = Set(s1.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init))
    let words2 = Set(s2.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init))

    guard !words1.isEmpty && !words2.isEmpty else { return 0.0 }

    let intersection = words1.intersection(words2).count
    let union = words1.union(words2).count

    guard union > 0 else { return 0.0 }

    return Double(intersection) / Double(union)
}

// MARK: - Diff to Operations Converter

/// Edit operations for diff algorithm
enum Edit {
    case keep(String)      // Token unchanged, navigate past it
    case delete(String)    // Token removed, delete it
    case insert(String)    // Token added, insert it
}

/// Computes edit script using LCS (Longest Common Subsequence) algorithm
/// This gives us a sequence of keep/delete/insert operations
func computeEditScript(_ source: [String], _ dest: [String]) -> [Edit] {
    let m = source.count
    let n = dest.count

    // Build LCS table using dynamic programming
    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

    for i in 1...m {
        for j in 1...n {
            if source[i-1] == dest[j-1] {
                dp[i][j] = dp[i-1][j-1] + 1
            } else {
                dp[i][j] = max(dp[i-1][j], dp[i][j-1])
            }
        }
    }

    // Backtrack to build edit script
    var edits: [Edit] = []
    var i = m
    var j = n

    while i > 0 || j > 0 {
        if i > 0 && j > 0 && source[i-1] == dest[j-1] {
            // Tokens match - keep it
            edits.append(.keep(source[i-1]))
            i -= 1
            j -= 1
        } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
            // Insert token from destination
            edits.append(.insert(dest[j-1]))
            j -= 1
        } else if i > 0 {
            // Delete token from source
            edits.append(.delete(source[i-1]))
            i -= 1
        }
    }

    return edits.reversed()
}

// MARK: - Hybrid Sentence-Level Diffing

/// Threshold for determining whether to do word-level diff or sentence-level replace
/// If similarity < threshold, replace entire sentence; otherwise do word-level diff
let SIMILARITY_THRESHOLD = 0.4

/// Computes hybrid edit script using sentence-level analysis
/// For sentences with low similarity, returns replace operations
/// For sentences with high similarity, returns word-level diff operations
/// Uses POSITIONAL ALIGNMENT instead of LCS to ensure each sentence is handled independently
func computeHybridEditScript(draft1: String, draft2: String) -> [Edit] {
    let sentences1 = sentencize(draft1)
    let sentences2 = sentencize(draft2)

    print("DEBUG: Draft 1 sentences: \(sentences1.count)")
    for (i, s) in sentences1.enumerated() {
        print("  [\(i)] '\(s.prefix(50))\(s.count > 50 ? "..." : "")'")
    }

    print("DEBUG: Draft 2 sentences: \(sentences2.count)")
    for (i, s) in sentences2.enumerated() {
        print("  [\(i)] '\(s.prefix(50))\(s.count > 50 ? "..." : "")'")
    }

    // Use POSITIONAL ALIGNMENT: compare sentence i in draft1 with sentence i in draft2
    // This ensures each sentence is independently evaluated for replacement vs. word-level diff
    var result: [Edit] = []
    let maxLen = max(sentences1.count, sentences2.count)

    for i in 0..<maxLen {
        if i < sentences1.count && i < sentences2.count {
            // Both drafts have a sentence at this position - compare them
            let oldSent = sentences1[i]
            let newSent = sentences2[i]
            let sim = similarity(oldSent, newSent)

            print("DEBUG: Sentence \(i) - similarity: \(String(format: "%.2f", sim))")
            print("  Old: '\(oldSent.prefix(50))\(oldSent.count > 50 ? "..." : "")'")
            print("  New: '\(newSent.prefix(50))\(newSent.count > 50 ? "..." : "")'")

            if sim >= SIMILARITY_THRESHOLD {
                // High similarity - do word-level diff
                print("  → Using word-level diff (high similarity)")
                let words1 = tokenizeIntoWords(oldSent)
                let words2 = tokenizeIntoWords(newSent)
                let wordScript = computeEditScript(words1, words2)
                result.append(contentsOf: wordScript)
            } else {
                // Low similarity - replace entire sentence as one atomic operation
                print("  → Using sentence-level replace (low similarity)")
                result.append(.delete(oldSent))
                result.append(.insert(newSent))
            }

        } else if i < sentences1.count {
            // Draft1 has extra sentence at this position - delete it
            print("DEBUG: Sentence \(i) - draft1 only (delete)")
            let sent = sentences1[i]
            let tokens = tokenizeIntoWords(sent)
            for token in tokens {
                result.append(.delete(token))
            }

        } else {
            // Draft2 has extra sentence at this position - insert it
            print("DEBUG: Sentence \(i) - draft2 only (insert)")
            let sent = sentences2[i]
            let tokens = tokenizeIntoWords(sent)
            for token in tokens {
                result.append(.insert(token))
            }
        }
    }

    print("DEBUG: Hybrid script produced \(result.count) token-level operations")
    return result
}

/// Converts two drafts into positioned edit operations for backwards editing
/// Returns edits sorted from end to beginning (right to left)
func convertDraftsToPositionedEdits(draft1: String, draft2: String) -> [EditWithPosition] {
    var editsWithPositions: [EditWithPosition] = []

    // Step 1: Compute hybrid edit script using sentence-level analysis
    let editScript = computeHybridEditScript(draft1: draft1, draft2: draft2)

    print("DEBUG: Hybrid edit script (count: \(editScript.count)):")
    for (index, edit) in editScript.prefix(20).enumerated() {
        switch edit {
        case .keep(let word):
            print("  [\(index)] keep: '\(word.prefix(20))\(word.count > 20 ? "..." : "")'")
        case .delete(let word):
            print("  [\(index)] delete: '\(word.prefix(20))\(word.count > 20 ? "..." : "")'")
        case .insert(let word):
            print("  [\(index)] insert: '\(word.prefix(20))\(word.count > 20 ? "..." : "")'")
        }
    }
    if editScript.count > 20 {
        print("  ... (\(editScript.count - 20) more operations)")
    }

    // Step 2: Convert edit script to positioned operations with smart grouping
    // Group consecutive delete+insert at same position into .replace operations
    var currentPosition = 0
    var i = 0

    while i < editScript.count {
        let edit = editScript[i]

        switch edit {
        case .keep(let word):
            // Token unchanged - move position forward in draft1
            currentPosition += word.count
            i += 1

        case .delete(let oldText):
            // Group consecutive deletes and inserts into a single replace operation
            // Each logical unit (sentence or word group) produces one delete+insert pair
            var deleteCount = oldText.count
            var insertText = ""
            var j = i + 1

            // Accumulate any additional consecutive deletes (for word-level edits)
            while j < editScript.count {
                if case .delete(let moreText) = editScript[j] {
                    deleteCount += moreText.count
                    j += 1
                } else {
                    break
                }
            }

            // Now accumulate any consecutive inserts immediately following
            while j < editScript.count {
                if case .insert(let text) = editScript[j] {
                    insertText += text
                    j += 1
                } else {
                    break
                }
            }

            // Create replace or delete operation
            if !insertText.isEmpty {
                let replaceOp = EditOperation.replace(oldCount: deleteCount, newText: insertText)
                editsWithPositions.append(EditWithPosition(
                    operation: replaceOp,
                    position: currentPosition,
                    originalIndex: editsWithPositions.count
                ))
                print("DEBUG: Replace at position \(currentPosition): \(deleteCount) chars → \(insertText.count) chars")
            } else {
                // Just delete, no insert
                let deleteOp = EditOperation.delete(count: deleteCount)
                editsWithPositions.append(EditWithPosition(
                    operation: deleteOp,
                    position: currentPosition,
                    originalIndex: editsWithPositions.count
                ))
                print("DEBUG: Delete at position \(currentPosition): \(deleteCount) chars")
            }

            // Move forward in draft1 past the deleted text
            currentPosition += deleteCount
            i = j

        case .insert(let text):
            // Group consecutive inserts at the same position into a single insert
            var insertText = text
            var j = i + 1

            // Accumulate consecutive inserts
            while j < editScript.count {
                if case .insert(let moreText) = editScript[j] {
                    insertText += moreText
                    j += 1
                } else {
                    break
                }
            }

            let insertOp = EditOperation.insert(text: insertText)
            editsWithPositions.append(EditWithPosition(
                operation: insertOp,
                position: currentPosition,
                originalIndex: editsWithPositions.count
            ))
            print("DEBUG: Insert at position \(currentPosition): \(insertText.count) chars '\(insertText.prefix(30))\(insertText.count > 30 ? "..." : "")'")
            // Don't move position - insertions don't affect draft1 positions
            i = j
        }
    }

    // Step 4: Sort by position descending, then by originalIndex ascending
    // This ensures: (1) we work right-to-left, (2) same-position edits stay in order
    let sortedEdits = editsWithPositions.sorted {
        if $0.position != $1.position {
            return $0.position > $1.position  // Higher position first (right to left)
        } else {
            return $0.originalIndex < $1.originalIndex  // Earlier edits first at same position
        }
    }

    print("DEBUG: Computed \(sortedEdits.count) positioned edits (backwards order):")
    for (index, edit) in sortedEdits.prefix(10).enumerated() {
        switch edit.operation {
        case .delete(let count):
            print("  [\(index)] pos \(edit.position): delete \(count) chars")
        case .insert(let text):
            print("  [\(index)] pos \(edit.position): insert '\(text.prefix(20))\(text.count > 20 ? "..." : "")'")
        case .replace(let oldCount, let newText):
            print("  [\(index)] pos \(edit.position): replace \(oldCount) chars with \(newText.count) chars '\(newText.prefix(20))\(newText.count > 20 ? "..." : "")'")
        default:
            print("  [\(index)] pos \(edit.position): \(edit.operation)")
        }
    }
    if sortedEdits.count > 10 {
        print("  ... (\(sortedEdits.count - 10) more edits)")
    }

    return sortedEdits
}

/// Converts two drafts into edit operations using word-by-word diff
/// After typing Draft 1, cursor is at the end. We navigate back and edit forward.
func convertDraftsToEditOperations(draft1: String, draft2: String) -> [EditOperation] {
    var operations: [EditOperation] = []

    // Step 1: Navigate to the beginning of Draft 1
    if draft1.count > 0 {
        // Move cursor left by the length of Draft 1 to get back to the start
        operations.append(.navigateLeft(count: draft1.count))
    }

    // Step 2: Tokenize both drafts into words
    let words1 = tokenizeIntoWords(draft1)
    let words2 = tokenizeIntoWords(draft2)

    print("DEBUG: Draft 1 tokens: \(words1)")
    print("DEBUG: Draft 2 tokens: \(words2)")

    // Step 3: Compute edit script using LCS algorithm
    let editScript = computeEditScript(words1, words2)

    print("DEBUG: Edit script:")
    for (index, edit) in editScript.enumerated() {
        switch edit {
        case .keep(let word):
            print("  [\(index)] keep: '\(word)'")
        case .delete(let word):
            print("  [\(index)] delete: '\(word)'")
        case .insert(let word):
            print("  [\(index)] insert: '\(word)'")
        }
    }

    // Step 4: Convert edit script to operations using simple, reliable approach
    // Key principle: NEVER use select-and-replace. Always delete then insert.
    var i = 0
    while i < editScript.count {
        let edit = editScript[i]

        switch edit {
        case .keep(let word):
            // Token unchanged - just navigate past it
            operations.append(.navigateRight(count: word.count))
            i += 1

        case .delete(let word):
            // Simply delete the word (backspace each character)
            // Don't try to merge with following inserts - keep it simple
            operations.append(.delete(count: word.count))
            i += 1

        case .insert(let word):
            // Token added - insert it at current cursor position
            operations.append(.insert(text: word))
            i += 1
        }
    }

    let optimizedOps = optimizeOperations(operations)

    print("DEBUG: Final operations (count: \(optimizedOps.count)):")
    for (index, op) in optimizedOps.prefix(20).enumerated() {
        print("  [\(index)] \(op)")
    }
    if optimizedOps.count > 20 {
        print("  ... (\(optimizedOps.count - 20) more operations)")
    }

    return optimizedOps
}

/// Stub for compatibility
func convertDiffToEditOperations(
    _ diff: CollectionDifference<Character>,
    from draft1: String
) -> [EditOperation] {
    return []
}

// MARK: - Operation Optimization

func optimizeOperations(_ operations: [EditOperation]) -> [EditOperation] {
    guard !operations.isEmpty else { return [] }

    var optimized: [EditOperation] = []
    var i = 0

    while i < operations.count {
        let op = operations[i]

        // Merge consecutive navigateRight operations
        if case .navigateRight(var count) = op {
            var j = i + 1
            while j < operations.count {
                if case .navigateRight(let nextCount) = operations[j] {
                    count += nextCount
                    j += 1
                } else {
                    break
                }
            }
            optimized.append(.navigateRight(count: count))
            i = j
            continue
        }

        // Merge consecutive insert operations
        if case .insert(var text) = op {
            var j = i + 1
            while j < operations.count {
                if case .insert(let nextText) = operations[j] {
                    text += nextText
                    j += 1
                } else {
                    break
                }
            }
            optimized.append(.insert(text: text))
            i = j
            continue
        }

        // Merge consecutive delete operations
        if case .delete(var count) = op {
            var j = i + 1
            while j < operations.count {
                if case .delete(let nextCount) = operations[j] {
                    count += nextCount
                    j += 1
                } else {
                    break
                }
            }
            optimized.append(.delete(count: count))
            i = j
            continue
        }

        optimized.append(op)
        i += 1
    }

    return optimized
}
