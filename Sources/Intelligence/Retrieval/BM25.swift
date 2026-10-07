import Foundation

/// Okapi BM25 over pre-tokenized documents — the keyword half of the hybrid
/// retriever, and the whole retriever when sentence embeddings are absent.
struct BM25Index {
    let k1: Double
    let b: Double
    private let documents: [[String: Int]]   // term frequencies per document
    private let lengths: [Int]
    private let averageLength: Double
    private let documentFrequency: [String: Int]

    init(documents tokenized: [[String]], k1: Double = 1.2, b: Double = 0.75) {
        self.k1 = k1
        self.b = b
        self.documents = tokenized.map { tokens in
            tokens.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        }
        self.lengths = tokenized.map(\.count)
        let total = lengths.reduce(0, +)
        self.averageLength = tokenized.isEmpty ? 0 : Double(total) / Double(tokenized.count)
        var df: [String: Int] = [:]
        for doc in documents { for term in doc.keys { df[term, default: 0] += 1 } }
        self.documentFrequency = df
    }

    var count: Int { documents.count }

    func idf(_ term: String) -> Double {
        let n = Double(documents.count)
        let df = Double(documentFrequency[term] ?? 0)
        return log(1 + (n - df + 0.5) / (df + 0.5))
    }

    /// One score per document, in document order.
    func scores(for query: [String]) -> [Double] {
        let terms = Array(Set(query))
        return documents.indices.map { i in
            let doc = documents[i]
            let norm = 1 - b + b * Double(lengths[i]) / max(averageLength, 1)
            return terms.reduce(0) { sum, term in
                guard let tf = doc[term] else { return sum }
                let f = Double(tf)
                return sum + idf(term) * (f * (k1 + 1)) / (f + k1 * norm)
            }
        }
    }
}

/// Lowercase, alphanumeric tokens without stopwords, lightly stemmed so
/// "invoices"/"invoice" and "launching"/"launch" meet.
enum TextTokens {
    static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "for", "with", "at", "by",
        "from", "is", "are", "was", "were", "be", "been", "it", "its", "this", "that", "these",
        "those", "i", "we", "you", "they", "he", "she", "my", "our", "your", "their", "me", "us",
        "what", "which", "who", "whom", "how", "when", "where", "why", "do", "does", "did",
        "about", "say", "says", "said", "notes", "note", "tell", "any", "there", "as", "so",
        "if", "not", "no", "can", "could", "should", "would", "will", "just", "than", "then",
    ]

    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
            .filter { !stopwords.contains($0) && ($0.count > 1 || $0.first?.isNumber == true) }
            .map(stem)
    }

    static func stem(_ word: String) -> String {
        guard word.count > 4 else { return word }
        for suffix in ["ingly", "edly", "ing", "ies", "ed", "es", "s"] where word.hasSuffix(suffix) {
            let base = String(word.dropLast(suffix.count))
            guard base.count >= 3 else { continue }
            if suffix == "ies" { return base + "y" }
            if suffix == "es", !(base.hasSuffix("s") || base.hasSuffix("x") || base.hasSuffix("ch") || base.hasSuffix("sh")) {
                return base + "e"
            }
            return base
        }
        return word
    }
}
