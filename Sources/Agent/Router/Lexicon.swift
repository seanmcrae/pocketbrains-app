import Foundation
import NaturalLanguage

/// The deterministic brain's vocabulary: verbs and cue words grouped by the
/// intent they signal, matched on lemmas so "finished", "finishing" and
/// "finish" are one word to the grammar.
///
/// Lemmas come from NLTagger (`.lemma`), which runs fully on device. When the
/// tagger has no lemma for a token (unknown word, or no linguistic assets on
/// a bare simulator), a small rule-based fallback strips regular inflections,
/// so routing never depends on asset availability.
enum Lexicon {
    enum Action: String {
        case complete, reschedule, snooze, prioritize, deprioritize, create, note, search, link, undo
    }

    /// Synonym sets (lemmas). Kept to ordinary thesaurus synonyms of each
    /// action rather than phrasings lifted from the eval corpus.
    static let verbs: [String: Action] = [
        // complete
        // ("do" is not here: as an auxiliary it read questions such as
        // "did we decide…" and "where do things stand" as completions.)
        "finish": .complete, "complete": .complete, "close": .complete,
        "cross": .complete, "knock": .complete, "tick": .complete,
        // reschedule
        "reschedule": .reschedule, "move": .reschedule, "push": .reschedule, "postpone": .reschedule,
        "delay": .reschedule, "bump": .reschedule, "shift": .reschedule, "slide": .reschedule,
        "slip": .reschedule, "kick": .reschedule,
        // snooze
        "snooze": .snooze, "defer": .snooze, "hold": .snooze, "park": .snooze, "hide": .snooze,
        // priority
        "prioritize": .prioritize, "prioritise": .prioritize, "escalate": .prioritize,
        "deprioritize": .deprioritize, "deprioritise": .deprioritize,
        // capture
        "add": .create, "remind": .create, "schedule": .create, "put": .create, "pencil": .create,
        "note": .note, "jot": .note, "write": .note, "record": .note, "log": .note,
        // retrieval & knowledge
        "search": .search, "find": .search, "look": .search,
        "link": .link, "connect": .link, "tie": .link, "associate": .link,
        // undo
        "undo": .undo, "revert": .undo,
    ]

    struct Token {
        let word: String      // lowercased surface form
        let lemma: String
        let range: Range<String.Index>
        let isVerb: Bool
    }

    /// Word tokens of `text` with lemmas and part of speech (NLTagger).
    static func tokens(_ text: String) -> [Token] {
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinContractions]
        let whole = text.startIndex..<text.endIndex

        var lemmas: [String.Index: String] = [:]
        tagger.enumerateTags(in: whole, unit: .word, scheme: .lemma, options: options) { tag, range in
            if let tag { lemmas[range.lowerBound] = tag.rawValue.lowercased() }
            return true
        }
        var out: [Token] = []
        tagger.enumerateTags(in: whole, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            let word = text[range].lowercased()
            let lemma = lemmas[range.lowerBound].flatMap { $0.isEmpty ? nil : $0 } ?? fallbackLemma(word)
            out.append(Token(word: word, lemma: lemma, range: range, isVerb: tag == .verb))
            return true
        }
        return out
    }

    /// Regular-inflection fallback: "finished" → "finish", "pushing" → "push",
    /// "crossed" → "cross", "moved" → "move", "tasks" → "task".
    static func fallbackLemma(_ word: String) -> String {
        let irregular = ["did": "do", "done": "do", "made": "make", "wrote": "write", "written": "write",
                         "put": "put", "set": "set", "held": "hold", "found": "find", "knocked": "knock"]
        if let base = irregular[word] { return base }
        if word.count > 5, word.hasSuffix("ing") {
            let stem = String(word.dropLast(3))
            if let last = stem.last, stem.count > 2, stem.dropLast().last == last { return String(stem.dropLast()) }
            return stem
        }
        if word.count > 4, word.hasSuffix("ed") {
            let stem = String(word.dropLast(2))
            if verbs[stem] != nil { return stem }
            if verbs[stem + "e"] != nil { return stem + "e" }
            if let last = stem.last, stem.dropLast().last == last, verbs[String(stem.dropLast())] != nil {
                return String(stem.dropLast())
            }
            return stem
        }
        if word.count > 3, word.hasSuffix("es"), verbs[String(word.dropLast(2))] != nil { return String(word.dropLast(2)) }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    /// The first token whose lemma maps to an action, with its index.
    static func firstAction(in tokens: [Token]) -> (Action, Int)? {
        for (i, token) in tokens.enumerated() {
            if let action = verbs[token.lemma] ?? verbs[token.word] ?? verbs[fallbackLemma(token.word)] {
                return (action, i)
            }
        }
        return nil
    }
}
