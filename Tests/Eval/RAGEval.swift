import Foundation
import SwiftData
import Testing
@testable import PocketBrains

/// "Ask your notes" eval on the synthetic fixture in `RAGEvalFixture`
/// (22 notes, 61 questions). Scores, per retrieval method:
///   - recall@1 / recall@3: the relevant note is the top passage's note, or
///     among the notes of the top three passages;
///   - answer-span hit rate: the extractive answer contains the span;
///   - citation faithfulness: every [n] in the extractive answer maps to a
///     retrieved passage of note n that contains the sentence it follows;
///   - span attribution: when the answer contains the span, the [n] on that
///     sentence points at a passage that contains the span.
/// BM25 runs in every CI build. Semantic and hybrid need the NLEmbedding
/// sentence asset, which the test host never loads; they run only when CI's
/// separate embedding step sets PB_EMBEDDING_EVAL=1, and print "skipped"
/// otherwise or when the asset is missing on the runner.
@Suite(.serialized, .timeLimit(.minutes(3)))
@MainActor
struct RAGEval {
    struct Score {
        var n = 0, hitsAt1 = 0, hitsAt3 = 0
        var spanFound = 0, spanAttributed = 0
        var markers = 0, faithfulMarkers = 0

        func rate(_ part: Int, _ whole: Int) -> Double { whole == 0 ? 0 : Double(part) / Double(whole) }
    }

    private func makeBox(embeddings: Bool) -> (ToolBox, ModelContainer) {
        let container = Store.makeContainer(inMemory: true)
        let services = DataServices(context: container.mainContext)
        let index = SemanticIndex(context: container.mainContext, allowUnderTests: embeddings)
        let box = ToolBox(services: services, semanticIndex: index)
        for note in RAGEvalFixture.notes { _ = box.createNote(title: note.title, body: note.body) }
        return (box, container)
    }

    /// "sentence [n]" pairs of an extractive answer, in order.
    static func claims(in answer: String) -> [(sentence: String, number: Int)] {
        guard let regex = try? NSRegularExpression(pattern: #"\s*(.+?) \[(\d+)\]"#) else { return [] }
        let ns = answer as NSString
        return regex.matches(in: answer, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let number = Int(ns.substring(with: m.range(at: 2))) else { return nil }
            return (ns.substring(with: m.range(at: 1)), number)
        }
    }

    /// Score one ranking of passages per question. `rank` returns passages
    /// best first (the production path, or a single-signal variant).
    private func evaluate(_ rank: (String) -> [RetrievedChunk]) -> Score {
        var result = Score()
        for q in RAGEvalFixture.questions {
            result.n += 1
            let chunks = rank(q.question)
            if chunks.first?.noteTitle == q.note { result.hitsAt1 += 1 }
            if chunks.prefix(3).contains(where: { $0.noteTitle == q.note }) { result.hitsAt3 += 1 }

            let answer = CitedAnswerComposer.compose(question: q.question, chunks: chunks)
            for claim in Self.claims(in: answer.text) {
                result.markers += 1
                guard let cited = answer.citations.first(where: { $0.index == claim.number }) else { continue }
                if chunks.contains(where: { $0.noteID == cited.noteID && $0.text.contains(claim.sentence) }) {
                    result.faithfulMarkers += 1
                }
                if claim.sentence.contains(q.span) {
                    result.spanFound += 1
                    if chunks.contains(where: { $0.noteID == cited.noteID && $0.text.contains(q.span) }) {
                        result.spanAttributed += 1
                    }
                }
            }
        }
        return result
    }

    private func report(_ method: String, _ r: Score) {
        func pct(_ x: Double) -> String { String(format: "%.1f%%", 100 * x) }
        let parts = [
            "recall@1 \(pct(r.rate(r.hitsAt1, r.n)))",
            "recall@3 \(pct(r.rate(r.hitsAt3, r.n)))",
            "answer contains span \(pct(r.rate(r.spanFound, r.n)))",
            "citation faithfulness \(pct(r.rate(r.faithfulMarkers, r.markers))) of \(r.markers) markers",
            "span attribution \(pct(r.rate(r.spanAttributed, r.spanFound)))",
        ]
        print("EVAL rag \(method) (\(r.n) synthetic questions, \(RAGEvalFixture.notes.count) notes): "
              + parts.joined(separator: ", "))
        print(IntentRouterEval.json([
            ("suite", "rag"), ("method", method), ("n", r.n),
            ("recall_at_1", r.rate(r.hitsAt1, r.n)), ("recall_at_3", r.rate(r.hitsAt3, r.n)),
            ("span_hit", r.rate(r.spanFound, r.n)), ("markers", r.markers),
            ("citation_faithfulness", r.rate(r.faithfulMarkers, r.markers)),
            ("span_attribution", r.rate(r.spanAttributed, r.spanFound)),
        ]))
    }

    @Test func fixtureIsWellFormed() {
        let titles = Set(RAGEvalFixture.notes.map(\.title))
        #expect(titles.count == RAGEvalFixture.notes.count)
        #expect(RAGEvalFixture.questions.count >= 50)
        for q in RAGEvalFixture.questions {
            let body = RAGEvalFixture.notes.first { $0.title == q.note }?.body ?? ""
            #expect(body.contains(q.span), "span not in note: \(q.question)")
        }
    }

    @Test func claimsParserReadsEveryMarker() {
        let claims = Self.claims(in: "The venue holds 40 people. [1] Travel is frozen. [2]")
        #expect(claims.map(\.number) == [1, 2])
        #expect(claims.first?.sentence == "The venue holds 40 people.")
    }

    @Test func bm25() {
        let (box, container) = makeBox(embeddings: false)
        defer { withExtendedLifetime(container) {} }
        let result = evaluate { box.notesIndex.retrieve($0, k: 4) }
        report("bm25", result)
        let paraphrased = RAGEvalFixture.questions.filter(\.paraphrased).count
        print("EVAL rag note: \(paraphrased) of \(result.n) questions are worded differently from their note")
        // Faithfulness is structural (each [n] is attached by the composer to
        // a sentence from note n), so anything below 100% is a bug.
        #expect(result.faithfulMarkers == result.markers)
        #expect(result.markers > 0)
        // Regression floors, set below the first measured CI values.
        #expect(result.rate(result.hitsAt3, result.n) >= 0.7)
        #expect(result.rate(result.hitsAt1, result.n) >= 0.6)
    }

    @Test func semanticAndHybrid() {
        guard ProcessInfo.processInfo.environment["PB_EMBEDDING_EVAL"] == "1" else {
            print("EVAL rag semantic/hybrid: skipped (runs only in the CI embedding step)")
            print(IntentRouterEval.json([("suite", "rag"), ("method", "hybrid"), ("skipped", "not this step")]))
            return
        }
        let (box, container) = makeBox(embeddings: true)
        defer { withExtendedLifetime(container) {} }
        guard box.semanticIndex.isAvailable else {
            print("EVAL rag semantic/hybrid: skipped (NLEmbedding English sentence asset unavailable on this runner)")
            print(IntentRouterEval.json([("suite", "rag"), ("method", "hybrid"), ("skipped", "asset unavailable")]))
            return
        }
        let hybrid = evaluate { box.notesIndex.retrieve($0, k: 4) }
        report("hybrid", hybrid)

        // Semantic only: the same passages ranked by cosine alone.
        _ = box.notesIndex.retrieve("warm up", k: 1) // ensure chunks are synced
        let context = box.services.context
        let titles = Dictionary(uniqueKeysWithValues: context.fetchAll(Note.self).map { ($0.id, $0.title) })
        let chunks = context.fetchAll(NoteChunk.self)
        let semantic = evaluate { question in
            guard let q = box.semanticIndex.embedVector(question) else { return [] }
            let cosines = chunks.map { Double(SemanticIndex.cosine(q, $0.floats)) }
            return NotesRAG.fuse(keyword: Array(repeating: 0, count: chunks.count), semantic: cosines)
                .prefix(4)
                .map { i, score in
                    RetrievedChunk(noteID: chunks[i].noteID, noteTitle: titles[chunks[i].noteID] ?? "",
                                   ordinal: chunks[i].ordinal, text: chunks[i].text, score: score)
                }
        }
        report("semantic", semantic)
        #expect(hybrid.faithfulMarkers == hybrid.markers)
    }
}
