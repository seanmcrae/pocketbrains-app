import CoreGraphics
import Foundation
import Testing
@testable import PocketBrains

@Suite(.serialized, .timeLimit(.minutes(1)))
struct OrbitalLayoutTests {
    private let size = CGSize(width: 390, height: 560)
    private let center = CGPoint(x: 195, y: 280)

    private func node(_ title: String) -> GraphNode {
        GraphNode(id: UUID(), kind: .note, title: title)
    }

    @Test func focusSitsAtCenter() throws {
        let a = node("a"), b = node("b"), c = node("c")
        let positions = OrbitalLayout.positions(
            nodes: [a, b, c],
            edges: [.init(from: a.id, to: b.id, relation: "r"),
                    .init(from: a.id, to: c.id, relation: "r")],
            focus: a.id, in: size)
        let p = try #require(positions[a.id])
        #expect(p == center)
        #expect(positions.count == 3)
    }

    @Test func neighborsLandOnFirstRing() throws {
        let a = node("a"), b = node("b"), c = node("c")
        let positions = OrbitalLayout.positions(
            nodes: [a, b, c],
            edges: [.init(from: a.id, to: b.id, relation: "r"),
                    .init(from: a.id, to: c.id, relation: "r")],
            focus: a.id, in: size)
        for id in [b.id, c.id] {
            let p = try #require(positions[id])
            let r = hypot(p.x - center.x, p.y - center.y)
            #expect(r > 60 && r < 90, "ring-1 radius was \(r)")
        }
    }

    @Test func orphansAreBanishedOutward() throws {
        let a = node("a"), b = node("b"), lonely = node("lonely")
        let positions = OrbitalLayout.positions(
            nodes: [a, b, lonely],
            edges: [.init(from: a.id, to: b.id, relation: "r")],
            focus: a.id, in: size)
        let ringOne = try #require(positions[b.id])
        let orphan = try #require(positions[lonely.id])
        let rConnected = hypot(ringOne.x - center.x, ringOne.y - center.y)
        let rOrphan = hypot(orphan.x - center.x, orphan.y - center.y)
        #expect(rOrphan > rConnected * 1.5)
    }

    @Test func defaultFocusIsBestConnected() throws {
        let hub = node("hub"), s1 = node("s1"), s2 = node("s2"), s3 = node("s3")
        let positions = OrbitalLayout.positions(
            nodes: [hub, s1, s2, s3],
            edges: [.init(from: hub.id, to: s1.id, relation: "r"),
                    .init(from: hub.id, to: s2.id, relation: "r"),
                    .init(from: hub.id, to: s3.id, relation: "r")],
            focus: nil, in: size)
        #expect(try #require(positions[hub.id]) == center)
    }

    @Test func emptyGraphYieldsNoPositions() {
        #expect(OrbitalLayout.positions(nodes: [], edges: [], focus: nil, in: size).isEmpty)
    }
}
