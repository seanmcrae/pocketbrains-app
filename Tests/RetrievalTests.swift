import Foundation
import SwiftData
import Testing
@testable import PocketBrains

/// "Ask your notes": chunking, BM25 ranking on a synthetic corpus,
/// citation mapping and incremental index maintenance.
///
/// The test host never loads the sentence-embedding asset (see
/// SemanticIndex), so these exercise the keyword (BM25) path of the hybrid
/// retriever. Recall numbers printed here describe that path only.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct RetrievalTests {
    private func makeBox() -> (ToolBox, ModelContainer) {
        let container = Store.makeContainer(inMemory: true)
        let services = DataServices(context: container.mainContext)
        return (ToolBox(services: services, semanticIndex: SemanticIndex(context: container.mainContext)),
                container)
    }

    // MARK: Chunking

    @Test func shortNoteIsOneChunk() {
        let chunks = NoteChunker.chunks(body: "Confident, never loud. Short sentences.")
        #expect(chunks == ["Confident, never loud. Short sentences."])
        #expect(NoteChunker.chunks(body: "   \n  ").isEmpty)
    }

    @Test func longNoteSplitsOnSentencesWithOverlap() {
        let sentences = (1...12).map { "Sentence number \($0) talks about topic \($0) in a few extra words." }
        let chunks = NoteChunker.chunks(body: sentences.joined(separator: " "), targetWords: 30)
        #expect(chunks.count > 1)
        // Never splits a sentence, and every sentence survives.
        for sentence in sentences {
            #expect(chunks.contains { $0.contains(sentence) })
        }
        for chunk in chunks {
            #expect(chunk.hasSuffix("words."))
        }
        // Consecutive chunks share the boundary sentence.
        for i in 1..<chunks.count {
            let lastOfPrevious = NoteChunker.sentences(in: chunks[i - 1]).last!
            #expect(chunks[i].hasPrefix(lastOfPrevious))
        }
    }

    @Test func tokenizerStemsAndDropsStopwords() {
        #expect(TextTokens.tokenize("What do my notes say about the invoices?") == ["invoice"])
        #expect(TextTokens.stem("launching") == "launch")
        #expect(TextTokens.stem("launches") == "launch")
        #expect(TextTokens.stem("prices") == "price")
    }

    // MARK: Ranking

    /// Synthetic corpus: 12 notes on distinct topics, 12 questions, each with
    /// exactly one relevant note. Written for this test; no real data.
    static let corpus: [(title: String, body: String)] = [
        ("Brand voice", "Confident, never loud. Short sentences. We avoid superlatives and show rather than claim."),
        ("Pricing research", "Annual plans convert better than monthly ones. A 20 percent annual discount tested best."),
        ("Offsite logistics", "The venue in Lisbon holds 40 people. Flights should land before noon on Thursday."),
        ("Hiring plan", "We need two backend engineers and one designer by October. Interviews run in pairs."),
        ("Security review", "Rotate the signing keys every quarter. The audit found no critical issues."),
        ("Garden", "Tomatoes go in after the last frost. Water the basil every morning."),
        ("Kickoff with the studio", "Three directions were proposed: Editorial, Instrument and Atelier. We leaned Instrument."),
        ("Reading: Alexander", "Places feel alive when patterns resolve real forces. Copy the force, not the form."),
        ("Customer interviews", "Users want offline mode and faster search. Two asked for a widget."),
        ("Budget Q3", "Marketing spend is capped at 50 thousand. Travel is frozen until September."),
        ("Recipe: dal", "Rinse the lentils, temper cumin in ghee, simmer for 25 minutes."),
        ("Car maintenance", "The tyres need rotating at 40 thousand kilometres. Insurance renews in March."),
    ]

    static let questions: [(question: String, expected: String)] = [
        ("How should our copy sound?", "Brand voice"),
        ("Do annual plans convert better?", "Pricing research"),
        ("How many people does the venue hold?", "Offsite logistics"),
        ("How many engineers are we hiring?", "Hiring plan"),
        ("How often do we rotate signing keys?", "Security review"),
        ("When do tomatoes get planted?", "Garden"),
        ("Which design direction did we lean towards?", "Kickoff with the studio"),
        ("What makes places feel alive?", "Reading: Alexander"),
        ("What features did users ask for?", "Customer interviews"),
        ("What is the marketing spend cap?", "Budget Q3"),
        ("How long do the lentils simmer?", "Recipe: dal"),
        ("When does the car insurance renew?", "Car maintenance"),
    ]

    @Test func recallOnSyntheticCorpus() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        for note in Self.corpus { _ = box.createNote(title: note.title, body: note.body) }

        var hitsAt1 = 0, hitsAt3 = 0
        for (question, expected) in Self.questions {
            let titles = box.notesIndex.retrieve(question, k: 3).map(\.noteTitle)
            if titles.first == expected { hitsAt1 += 1 }
            if titles.contains(expected) { hitsAt3 += 1 }
        }
        let n = Double(Self.questions.count)
        print(String(format: "EVAL ask-your-notes retrieval (BM25 path, %d synthetic questions): recall@1 %.1f%%, recall@3 %.1f%%",
                     Self.questions.count, 100 * Double(hitsAt1) / n, 100 * Double(hitsAt3) / n))
        #expect(Double(hitsAt3) / n >= 0.9)
        #expect(Double(hitsAt1) / n >= 0.75)
    }

    @Test func unrelatedQuestionRetrievesNothing() {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        for note in Self.corpus.prefix(4) { _ = box.createNote(title: note.title, body: note.body) }
        #expect(box.notesIndex.retrieve("quantum chromodynamics lattice", k: 3).isEmpty)
        let result = box.askNotes(question: "quantum chromodynamics lattice")
        #expect(result.citations.isEmpty)
    }

    @Test func fusionCombinesBothRankings() {
        // Doc 1 wins keyword, doc 2 wins semantic, doc 0 is decent at both.
        let fused = NotesRAG.fuse(keyword: [2, 3, 0], semantic: [0.7, 0.1, 0.9])
        #expect(fused.map(\.0).first == 0)
        #expect(Set(fused.map(\.0)) == [0, 1, 2])
        // Without vectors, only keyword hits count.
        #expect(NotesRAG.fuse(keyword: [0, 1, 0], semantic: nil).map(\.0) == [1])
    }

    // MARK: Citations

    @Test func citationsMapMarkersToSourceNotes() {
        let a = UUID(), b = UUID()
        let chunks = [
            RetrievedChunk(noteID: a, noteTitle: "Offsite logistics", ordinal: 0,
                           text: "The venue holds 40 people. Catering is vegetarian.", score: 1),
            RetrievedChunk(noteID: b, noteTitle: "Budget Q3", ordinal: 0,
                           text: "The venue deposit is 2 thousand. Travel is frozen.", score: 0.5),
            RetrievedChunk(noteID: a, noteTitle: "Offsite logistics", ordinal: 1,
                           text: "The venue opens at nine.", score: 0.4),
        ]
        let answer = CitedAnswerComposer.compose(question: "What about the venue?", chunks: chunks)
        #expect(answer.citations.map(\.index) == [1, 2])
        #expect(answer.citations.map(\.noteID) == [a, b])
        #expect(answer.text.contains("holds 40 people. [1]"))
        #expect(answer.text.contains("deposit is 2 thousand. [2]"))
        #expect(answer.text.contains("opens at nine. [1]")) // same note, same number
        #expect(!answer.text.contains("[3]"))

        let context = CitedAnswerComposer.groundingContext(chunks: chunks, citations: answer.citations)
        #expect(context.hasPrefix("[1] Offsite logistics:"))
        #expect(context.contains("[2] Budget Q3:"))
    }

    @Test func askNotesToolAnswersWithCitations() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        for note in Self.corpus { _ = box.createNote(title: note.title, body: note.body) }
        let result = box.askNotes(question: "How many people does the venue hold?")
        #expect(result.succeeded)
        let first = try #require(result.citations.first)
        #expect(first.title == "Offsite logistics")
        #expect(result.detail.contains("40 people"))
        #expect(result.detail.contains("[1]"))
        #expect(result.record(toolName: "askNotes").citations?.first?.noteID == first.noteID)

        let routed = IntentFallbackBackend.routeIntent("What do my notes say about the venue capacity?", toolbox: box)
        #expect(routed.tool == "askNotes")
        #expect(routed.reply.contains("Sources: [1] Offsite logistics"))
    }

    // MARK: Incremental index

    @Test func indexStaysIncrementalAcrossCreateEditDelete() throws {
        let (box, container) = makeBox()
        defer { withExtendedLifetime(container) {} }
        let rag = box.notesIndex
        _ = box.createNote(title: "Garden", body: "Water the basil every morning.")
        _ = box.createNote(title: "Recipe: dal", body: "Simmer the lentils for 25 minutes.")
        let garden = try #require(box.services.notes.find(matching: "garden"))
        let dal = try #require(box.services.notes.find(matching: "dal"))
        #expect(rag.chunkCount(for: garden.id) == 1)
        let dalChunkIDs = Set(box.services.context.fetchAll(NoteChunk.self).filter { $0.noteID == dal.id }.map(\.id))

        // Nothing changed → nothing re-indexed.
        #expect(rag.sync(notes: box.services.notes.all()) == .init(reindexedNotes: 0, removedNotes: 0))

        // Edit outside the agent (the note editor path) → only that note re-cut.
        box.services.notes.setBody(garden, "Plant tomatoes after the last frost.")
        #expect(rag.sync(notes: box.services.notes.all()) == .init(reindexedNotes: 1, removedNotes: 0))
        let dalAfter = Set(box.services.context.fetchAll(NoteChunk.self).filter { $0.noteID == dal.id }.map(\.id))
        #expect(dalAfter == dalChunkIDs)
        #expect(rag.retrieve("when to plant tomatoes", k: 1).first?.noteTitle == "Garden")
        #expect(rag.retrieve("basil", k: 1).isEmpty)

        // Append through the agent → re-indexed immediately.
        _ = box.appendNote(query: "dal", text: "Finish with lemon and coriander.")
        #expect(rag.retrieve("coriander", k: 1).first?.noteTitle == "Recipe: dal")

        // Delete (here via undo of the creation) → its chunks disappear.
        box.services.notes.delete(garden)
        #expect(rag.sync(notes: box.services.notes.all()).removedNotes == 1)
        #expect(rag.chunkCount(for: garden.id) == 0)
    }
}
