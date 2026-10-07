import Foundation
import NaturalLanguage
import SwiftData

/// On-device semantic search over notes. Sentence vectors from the
/// NaturalLanguage framework, cached in SwiftData, cosine-ranked in memory.
/// Sized for personal corpora (thousands of notes) — no ANN needed.
@MainActor
final class SemanticIndex {
    private let context: ModelContext

    /// Lazy and test-gated: the sentence-embedding asset lookup proved able
    /// to destabilize asset-less CI simulators, so it never runs during test
    /// hosting and otherwise happens on first use, off the launch path.
    private var embedderStorage: NLEmbedding??
    private var embedder: NLEmbedding? {
        if let cached = embedderStorage { return cached }
        guard NSClassFromString("XCTestCase") == nil else {
            embedderStorage = NLEmbedding?.none
            return nil
        }
        let created = NLEmbedding.sentenceEmbedding(for: .english)
        embedderStorage = created
        return created
    }

    init(context: ModelContext) {
        self.context = context
    }

    var isAvailable: Bool { embedder != nil }

    // MARK: Indexing

    func index(note: Note) {
        guard let vector = embed(note.title + ". " + note.body) else { return }
        let hash = (note.title + note.body).stableHash
        let records = context.fetchAll(EmbeddingRecord.self)
        if let existing = records.first(where: { $0.entityID == note.id }) {
            guard existing.contentHash != hash else { return }
            context.delete(existing)
        }
        context.insert(EmbeddingRecord(entityID: note.id, kind: .note,
                                       vector: vector, contentHash: hash))
        try? context.save()
    }

    /// Bring the index up to date with all notes (cheap no-op when current).
    func reindexAll(notes: [Note]) {
        for note in notes { index(note: note) }
    }

    // MARK: Search

    func search(_ query: String, limit: Int = 5) -> [Note] {
        guard let queryVec = embed(query) else { return [] }
        let records = context.fetchAll(EmbeddingRecord.self)
        let notes = context.fetchAll(Note.self)
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })

        return records
            .compactMap { record -> (Note, Float)? in
                guard let note = byID[record.entityID] else { return nil }
                return (note, cosine(queryVec, record.floats))
            }
            .filter { $0.1 > 0.45 } // relevance floor
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: Vectors

    private func embed(_ text: String) -> [Float]? {
        guard let embedder,
              let vector = embedder.vector(for: String(text.prefix(1024)))
        else { return nil }
        return vector.map(Float.init)
    }

    /// Sentence vector for arbitrary text (nil without the embedding asset).
    /// Shared with the "Ask your notes" passage index.
    func embedVector(_ text: String) -> [Float]? { embed(text) }

    private func cosine(_ a: [Float], _ b: [Float]) -> Float { Self.cosine(a, b) }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrt(na * nb)
        return denom > 0 ? dot / denom : 0
    }
}

// MARK: - Stable string hashing

private extension String {
    /// DJB2-style polynomial hash — deterministic across processes and
    /// launches, unlike Swift's randomized `hashValue` (SE-0206 / SE-0206).
    /// Used for cache-invalidation checks in `SemanticIndex`.
    var stableHash: Int {
        utf8.reduce(into: 5381) { result, byte in
            result = result &* 31 &+ Int(byte)
        }
    }
}
