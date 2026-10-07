import Foundation
import NaturalLanguage

/// Cuts a note into overlapping passages of roughly `targetWords` words on
/// sentence boundaries (NLTokenizer), never splitting a sentence. Each chunk
/// after the first repeats the previous chunk's last sentence so an answer
/// spanning a boundary is still retrievable from one passage.
enum NoteChunker {
    static func chunks(body: String, targetWords: Int = 80, overlapSentences: Int = 1) -> [String] {
        let paragraphs = body
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let sentences = paragraphs.flatMap(Self.sentences(in:))
        guard !sentences.isEmpty else { return [] }

        var chunks: [String] = []
        var current: [String] = []
        var words = 0
        var fresh = 0 // sentences in `current` that aren't carried overlap
        for sentence in sentences {
            let count = wordCount(sentence)
            if words + count > targetWords, fresh > 0 {
                chunks.append(current.joined(separator: " "))
                let carry = overlapSentences > 0 ? Array(current.suffix(overlapSentences)) : []
                current = carry
                words = carry.reduce(0) { $0 + wordCount($1) }
                fresh = 0
            }
            current.append(sentence)
            words += count
            fresh += 1
        }
        if fresh > 0 { chunks.append(current.joined(separator: " ")) }
        return chunks
    }

    static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var out: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { out.append(sentence) }
            return true
        }
        return out.isEmpty && !text.isEmpty ? [text] : out
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
