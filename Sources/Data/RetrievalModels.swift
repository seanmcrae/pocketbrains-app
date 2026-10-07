import Foundation
import SwiftData

/// One retrievable passage of a note: the unit "Ask your notes" ranks and
/// cites. Rebuilt per note whenever that note's content hash changes.
@Model
final class NoteChunk {
    @Attribute(.unique) var id: UUID
    var noteID: UUID
    /// Position of the chunk within its note, from 0.
    var ordinal: Int
    var text: String
    /// Packed [Float] sentence embedding; empty when no embedder is available.
    var vector: Data
    /// Hash of the note's title + body when this chunk was cut.
    var noteHash: Int

    init(noteID: UUID, ordinal: Int, text: String, vector: [Float], noteHash: Int) {
        self.id = UUID()
        self.noteID = noteID
        self.ordinal = ordinal
        self.text = text
        self.vector = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        self.noteHash = noteHash
    }

    var floats: [Float] {
        vector.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

/// A source the agent cited: the [n] marker in an answer maps to a note.
struct Citation: Codable, Hashable, Identifiable {
    var index: Int
    var noteID: UUID
    var title: String
    var snippet: String

    var id: Int { index }
}

/// Deterministic string hash (Swift's `hashValue` is randomized per launch).
enum StableHash {
    static func of(_ text: String) -> Int {
        text.utf8.reduce(into: 5381) { result, byte in
            result = result &* 31 &+ Int(byte)
        }
    }
}
