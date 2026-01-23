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

/// Common abbreviations that end with a period but don't end a sentence
private let commonAbbreviations: Set<String> = [
    "mr", "mrs", "ms", "dr", "prof", "sr", "jr",
    "vs", "etc", "inc", "ltd", "corp",
    "e.g", "i.e", "cf", "al",  // Note: "e.g" and "i.e" without final period
    "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
    "st", "rd", "nd", "th",  // ordinals like 1st, 2nd, 3rd
    "no", "vol", "pp", "pg", "ch", "sec", "fig",
    "approx", "dept", "est", "govt", "max", "min"
]

/// Checks if the text before a period looks like an abbreviation
/// Returns true if it's likely an abbreviation (not a sentence end)
private func isLikelyAbbreviation(_ textBeforePeriod: String) -> Bool {
    // Get the last "word" before the period
    let trimmed = textBeforePeriod.trimmingCharacters(in: .whitespaces)

    // Find the last word (sequence of letters, possibly with embedded periods like "e.g")
    var lastWord = ""
    for char in trimmed.reversed() {
        if char.isLetter || char == "." {
            lastWord = String(char) + lastWord
        } else {
            break
        }
    }

    // Remove trailing period if present for comparison
    let wordToCheck = lastWord.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

    // Check against known abbreviations
    if commonAbbreviations.contains(wordToCheck) {
        return true
    }

    // Single uppercase letter followed by period is likely an initial (e.g., "J. Smith")
    if lastWord.count == 1 && lastWord.first?.isUppercase == true {
        return true
    }

    // Check for patterns like "e.g." or "i.e." (letters with embedded periods)
    if lastWord.contains(".") && lastWord.filter({ $0.isLetter }).count <= 4 {
        return true
    }

    return false
}

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
                // Check if this period is part of an abbreviation
                if char == "." {
                    let textBeforePeriod = String(currentSentence.dropLast())
                    if isLikelyAbbreviation(textBeforePeriod) {
                        // Not a sentence boundary - continue
                        i = text.index(after: i)
                        continue
                    }
                }

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

    // Handle edge cases where source or dest is empty
    if m == 0 && n == 0 {
        return []
    }
    if m == 0 {
        // All dest tokens are insertions
        return dest.map { .insert($0) }
    }
    if n == 0 {
        // All source tokens are deletions
        return source.map { .delete($0) }
    }

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

    appLog("Draft 1 sentences: \(sentences1.count), Draft 2 sentences: \(sentences2.count)", level: .debug)

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

            appLog("Sentence \(i) - similarity: \(String(format: "%.2f", sim))", level: .verbose)

            if sim >= SIMILARITY_THRESHOLD {
                // High similarity - do word-level diff
                appLog("Sentence \(i): word-level diff (high similarity)", level: .verbose)
                let words1 = tokenizeIntoWords(oldSent)
                let words2 = tokenizeIntoWords(newSent)
                let wordScript = computeEditScript(words1, words2)
                result.append(contentsOf: wordScript)
            } else {
                // Low similarity - replace entire sentence as one atomic operation
                appLog("Sentence \(i): sentence-level replace (low similarity)", level: .verbose)
                result.append(.delete(oldSent))
                result.append(.insert(newSent))
            }

        } else if i < sentences1.count {
            // Draft1 has extra sentence at this position - delete it
            appLog("Sentence \(i) - draft1 only (delete)", level: .verbose)
            let sent = sentences1[i]
            let tokens = tokenizeIntoWords(sent)
            for token in tokens {
                result.append(.delete(token))
            }

        } else {
            // Draft2 has extra sentence at this position - insert it
            appLog("Sentence \(i) - draft2 only (insert)", level: .verbose)
            let sent = sentences2[i]
            let tokens = tokenizeIntoWords(sent)
            for token in tokens {
                result.append(.insert(token))
            }
        }
    }

    appLog("Hybrid script produced \(result.count) token-level operations", level: .debug)
    return result
}

/// Converts two drafts into positioned edit operations for backwards editing
/// Returns edits sorted from end to beginning (right to left)
func convertDraftsToPositionedEdits(draft1: String, draft2: String) -> [EditWithPosition] {
    var editsWithPositions: [EditWithPosition] = []

    // Step 1: Compute hybrid edit script using sentence-level analysis
    let editScript = computeHybridEditScript(draft1: draft1, draft2: draft2)

    appLog("Hybrid edit script count: \(editScript.count)", level: .debug)

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
            // NOTE: We intentionally do NOT merge consecutive deletes anymore to keep
            // deletion granularity human-like (avoid wiping multiple sentences at once).
            let deleteCount = oldText.count
            var insertText = ""
            var j = i + 1

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
                appLog("Replace at position \(currentPosition): \(deleteCount) chars → \(insertText.count) chars", level: .verbose)
            } else {
                // Just delete, no insert
                let deleteOp = EditOperation.delete(count: deleteCount)
                editsWithPositions.append(EditWithPosition(
                    operation: deleteOp,
                    position: currentPosition,
                    originalIndex: editsWithPositions.count
                ))
                appLog("Delete at position \(currentPosition): \(deleteCount) chars", level: .verbose)
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
            appLog("Insert at position \(currentPosition): \(insertText.count) chars", level: .verbose)
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

    appLog("Computed \(sortedEdits.count) positioned edits (backwards order)", level: .debug)

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

    appLog("Draft 1 tokens: \(words1.count), Draft 2 tokens: \(words2.count)", level: .debug)

    // Step 3: Compute edit script using LCS algorithm
    let editScript = computeEditScript(words1, words2)

    appLog("Edit script computed: \(editScript.count) operations", level: .debug)

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

    appLog("Final operations count: \(optimizedOps.count)", level: .debug)

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
