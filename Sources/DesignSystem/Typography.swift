import SwiftUI

/// The full type scale. No view declares an ad-hoc font.
/// Tokens ride the system text styles so Dynamic Type works everywhere;
/// defaults match the designed sizes exactly (34/28/22/17/15/13/11).
enum Type {
    /// New York display — project headlines only.
    static let display = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let title = Font.system(.title, weight: .bold)
    static let heading = Font.system(.title2, weight: .semibold)
    static let body = Font.system(.body)
    static let bodyMedium = Font.system(.body, weight: .medium)
    static let callout = Font.system(.subheadline, weight: .medium)
    static let caption = Font.system(.footnote, weight: .medium)
    static let micro = Font.system(.caption2, weight: .semibold)
    static let mono = Font.system(.footnote, design: .monospaced, weight: .medium)
}

struct MicroLabel: View {
    let text: String
    var color: Color = Paper.tertiary

    var body: some View {
        Text(text.uppercased())
            .font(Type.micro)
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

extension Text {
    func displayStyle() -> some View {
        self.font(Type.display).tracking(-0.5).foregroundStyle(Paper.primary)
    }
}
