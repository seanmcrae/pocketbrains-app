import Foundation
import SwiftData

/// A passage retrieved for a question, with its fused rank score.
struct RetrievedChunk: Equatable {
    let noteID: UUID
    let noteTitle: String
    let ordinal: Int
    let text: String
    let score: Double
}

/// "Ask your notes": an on-device retrieval index over note passages.
///
/// - Chunks come from `NoteChunker`, are stored as `NoteChunk` rows and are
///   kept incremental: `sync` re-cuts only notes whose content hash changed
///   and drops chunks of deleted notes, so edits made anywhere (the agent,
///   the note editor, undo) are picked up before every question.
/// - Ranking is hybrid: BM25 over title + passage tokens, fused by reciprocal
///   rank with cosine similarity of NaturalLanguage sentence embeddings when
///   the embedding asset is present. Without it (asset-less simulators, test
///   hosts) BM25 alone ranks, and the answer path is unchanged.
@MainActor
final class NotesRAG {
    private let context: ModelContext
    private let embedder: SemanticIndex
    private var keywordCache: (signature: Int, index: BM25Index, chunks: [NoteChunk])?

    init(context: ModelContext, embedder: SemanticIndex) {
        self.context = context
        self.embedder = embedder
    }

    struct SyncReport: Equatable {
        var reindexedNotes = 0
        var removedNotes = 0
    }

    static func hash(of note: Note) -> Int {
        StableHash.of(note.title + "\n" + note.body)
    }

    // MARK: Incremental maintenance

    /// Bring the chunk table in line with `notes`: re-cut changed or new
    /// notes, delete chunks whose note is gone. Cheap no-op when current.
    @discardableResult
    func sync(notes: [Note]) -> SyncReport {
        var report = SyncReport()
        let existing = context.fetchAll(NoteChunk.self)
        let byNote = Dictionary(grouping: existing, by: \.noteID)
        let liveIDs = Set(notes.map(\.id))

        for note in notes {
            let hash = Self.hash(of: note)
            if let chunks = byNote[note.id], !chunks.isEmpty, chunks.allSatisfy({ $0.noteHash == hash }) {
                continue
            }
            replaceChunks(for: note, hash: hash, existing: byNote[note.id] ?? [])
            report.reindexedNotes += 1
        }
        for (noteID, chunks) in byNote where !liveIDs.contains(noteID) {
            for chunk in chunks { context.delete(chunk) }
            report.removedNotes += 1
        }
        if report.reindexedNotes + report.removedNotes > 0 {
            try? context.save()
            keywordCache = nil
        }
        return report
    }

    /// Re-index one note right away (after the agent creates or appends).
    func upsert(_ note: Note) {
        let existing = context.fetchAll(NoteChunk.self).filter { $0.noteID == note.id }
        let hash = Self.hash(of: note)
        guard existing.isEmpty || existing.contains(where: { $0.noteHash != hash }) else { return }
        replaceChunks(for: note, hash: hash, existing: existing)
        try? context.save()
        keywordCache = nil
    }

    func remove(noteID: UUID) {
        for chunk in context.fetchAll(NoteChunk.self) where chunk.noteID == noteID {
            context.delete(chunk)
        }
        try? context.save()
        keywordCache = nil
    }

    func chunkCount(for noteID: UUID? = nil) -> Int {
        let all = context.fetchAll(NoteChunk.self)
        guard let noteID else { return all.count }
        return all.filter { $0.noteID == noteID }.count
    }

    private func replaceChunks(for note: Note, hash: Int, existing: [NoteChunk]) {
        for chunk in existing { context.delete(chunk) }
        var passages = NoteChunker.chunks(body: note.body)
        if passages.isEmpty { passages = [note.title] }
        for (ordinal, passage) in passages.enumerated() {
            let vector = embedder.embedVector(note.title + ". " + passage) ?? []
            context.insert(NoteChunk(noteID: note.id, ordinal: ordinal, text: passage,
                                     vector: vector, noteHash: hash))
        }
    }

    // MARK: Retrieval

    /// Top-k passages for a question, best first. Syncs first so the answer
    /// never cites a stale or deleted note.
    func retrieve(_ question: String, k: Int = 4) -> [RetrievedChunk] {
        let notes = context.fetchAll(Note.self)
        sync(notes: notes)
        let titles = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.title) })

        let chunks = context.fetchAll(NoteChunk.self)
            .sorted { ($0.noteID.uuidString, $0.ordinal) < ($1.noteID.uuidString, $1.ordinal) }
        guard !chunks.isEmpty else { return [] }

        // Keyword ranking (BM25), cached until the chunk set changes.
        let signature = StableHash.of(chunks.map { "\($0.id)\($0.noteHash)" }.joined())
        let index: BM25Index
        if let cache = keywordCache, cache.signature == signature {
            index = cache.index
        } else {
            index = BM25Index(documents: chunks.map {
                TextTokens.tokenize((titles[$0.noteID] ?? "") + " " + $0.text)
            })
            keywordCache = (signature, index, chunks)
        }
        let queryTokens = TextTokens.tokenize(question)
        let keyword = index.scores(for: queryTokens)

        // Semantic ranking, when vectors exist for both sides.
        var semantic: [Double]?
        if let queryVector = embedder.embedVector(question) {
            semantic = chunks.map { chunk in
                let v = chunk.floats
                return v.isEmpty ? 0 : Double(SemanticIndex.cosine(queryVector, v))
            }
        }

        let fused = Self.fuse(keyword: keyword, semantic: semantic)
        return fused
            .prefix(k)
            .map { i, score in
                RetrievedChunk(noteID: chunks[i].noteID, noteTitle: titles[chunks[i].noteID] ?? "Untitled",
                               ordinal: chunks[i].ordinal, text: chunks[i].text, score: score)
            }
    }

    /// Reciprocal-rank fusion (k = 60) of the keyword and semantic rankings.
    /// Only candidates with a positive keyword score or a cosine above the
    /// relevance floor take part, so unrelated notes are never cited.
    static func fuse(keyword: [Double], semantic: [Double]?, floor: Double = 0.45) -> [(Int, Double)] {
        var fused: [Int: Double] = [:]
        let keywordRanked = keyword.indices.filter { keyword[$0] > 0 }
            .sorted { keyword[$0] > keyword[$1] }
        for (rank, i) in keywordRanked.enumerated() { fused[i, default: 0] += 1 / Double(60 + rank + 1) }
        if let semantic {
            let semanticRanked = semantic.indices.filter { semantic[$0] > floor }
                .sorted { semantic[$0] > semantic[$1] }
            for (rank, i) in semanticRanked.enumerated() { fused[i, default: 0] += 1 / Double(60 + rank + 1) }
        }
        return fused.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }
}

// MARK: - Cited answers

struct CitedAnswer: Equatable {
    var text: String
    var citations: [Citation]
}

/// Builds the answer the user sees. Extractive (no model): the sentences of
/// the retrieved passages that best overlap the question, each followed by
/// the [n] of its source note. Citations are numbered by first use, one per
/// note, so [1] is always the note the answer leans on most.
enum CitedAnswerComposer {
    static func compose(question: String, chunks: [RetrievedChunk], maxSentences: Int = 3) -> CitedAnswer {
        guard !chunks.isEmpty else { return CitedAnswer(text: "", citations: []) }
        let queryTerms = Set(TextTokens.tokenize(question))

        struct Candidate { let sentence: String; let chunkRank: Int; let position: Int; let score: Double }
        var candidates: [Candidate] = []
        for (rank, chunk) in chunks.enumerated() {
            for (position, sentence) in NoteChunker.sentences(in: chunk.text).enumerated() {
                let terms = Set(TextTokens.tokenize(sentence))
                let overlap = Double(terms.intersection(queryTerms).count)
                guard overlap > 0 else { continue }
                // Overlap dominates; earlier (better-ranked) passages break ties.
                candidates.append(Candidate(sentence: sentence, chunkRank: rank, position: position,
                                            score: overlap - Double(rank) * 0.25))
            }
        }
        var picked = candidates.sorted { $0.score > $1.score }.prefix(maxSentences)
            .sorted { ($0.chunkRank, $0.position) < ($1.chunkRank, $1.position) }
        if picked.isEmpty, let first = NoteChunker.sentences(in: chunks[0].text).first {
            picked = [Candidate(sentence: first, chunkRank: 0, position: 0, score: 0)]
        }

        var citations: [Citation] = []
        var numberFor: [UUID: Int] = [:]
        var parts: [String] = []
        var seen = Set<String>()
        for candidate in picked where seen.insert(candidate.sentence).inserted {
            let chunk = chunks[candidate.chunkRank]
            let number: Int
            if let existing = numberFor[chunk.noteID] {
                number = existing
            } else {
                number = citations.count + 1
                numberFor[chunk.noteID] = number
                citations.append(Citation(index: number, noteID: chunk.noteID, title: chunk.noteTitle,
                                          snippet: String(chunk.text.prefix(160))))
            }
            parts.append("\(candidate.sentence) [\(number)]")
        }
        return CitedAnswer(text: parts.joined(separator: " "), citations: citations)
    }

    /// Numbered source passages for a language model to ground on.
    static func groundingContext(chunks: [RetrievedChunk], citations: [Citation]) -> String {
        var numberFor = Dictionary(uniqueKeysWithValues: citations.map { ($0.noteID, $0.index) })
        var next = (citations.map(\.index).max() ?? 0) + 1
        return chunks.map { chunk -> String in
            let n: Int
            if let existing = numberFor[chunk.noteID] { n = existing } else {
                n = next; numberFor[chunk.noteID] = n; next += 1
            }
            return "[\(n)] \(chunk.noteTitle): \(chunk.text)"
        }.joined(separator: "\n")
    }
}
