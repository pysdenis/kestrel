import SwiftUI
import KestrelCore

/// Squarified treemap layout (Bruls et al.) — lays out a node's children as rectangles
/// sized by their byte size, keeping cells close to square so labels stay readable.
enum Treemap {
    struct Cell { let node: DirNode; let rect: CGRect }

    static func layout(_ nodes: [DirNode], in bounds: CGRect) -> [Cell] {
        let items = nodes.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        guard !items.isEmpty, bounds.width > 2, bounds.height > 2 else { return [] }
        let totalSize = items.reduce(0.0) { $0 + Double($1.size) }
        guard totalSize > 0 else { return [] }
        let scale = Double(bounds.width) * Double(bounds.height) / totalSize
        let areas = items.map { (node: $0, area: Double($0.size) * scale) }

        var cells: [Cell] = []
        var rect = bounds
        var i = 0
        while i < areas.count, rect.width > 1, rect.height > 1 {
            let side = Double(min(rect.width, rect.height))
            var row = [areas[i]]
            i += 1
            while i < areas.count {
                let candidate = row + [areas[i]]
                if worstRatio(candidate, side) <= worstRatio(row, side) {
                    row = candidate; i += 1
                } else { break }
            }
            cells.append(contentsOf: place(row, in: &rect))
        }
        return cells
    }

    private static func worstRatio(_ row: [(node: DirNode, area: Double)], _ side: Double) -> Double {
        let sum = row.reduce(0) { $0 + $1.area }
        guard sum > 0 else { return .infinity }
        let maxA = row.map(\.area).max() ?? 0
        let minA = row.map(\.area).min() ?? 0
        guard minA > 0 else { return .infinity }
        let s2 = side * side
        return max(s2 * maxA / (sum * sum), sum * sum / (s2 * minA))
    }

    private static func place(_ row: [(node: DirNode, area: Double)], in rect: inout CGRect) -> [Cell] {
        let sum = row.reduce(0) { $0 + $1.area }
        var cells: [Cell] = []
        if rect.width >= rect.height {
            let stripW = CGFloat(sum) / rect.height
            var y = rect.minY
            for item in row {
                let h = rect.height * CGFloat(item.area / sum)
                cells.append(Cell(node: item.node, rect: CGRect(x: rect.minX, y: y, width: stripW, height: h)))
                y += h
            }
            rect = CGRect(x: rect.minX + stripW, y: rect.minY, width: rect.width - stripW, height: rect.height)
        } else {
            let stripH = CGFloat(sum) / rect.width
            var x = rect.minX
            for item in row {
                let w = rect.width * CGFloat(item.area / sum)
                cells.append(Cell(node: item.node, rect: CGRect(x: x, y: rect.minY, width: w, height: stripH)))
                x += w
            }
            rect = CGRect(x: rect.minX, y: rect.minY + stripH, width: rect.width, height: rect.height - stripH)
        }
        return cells
    }
}

/// Renders a treemap of a node's children; tapping a folder drills in.
struct TreemapView: View {
    let node: DirNode
    let onSelect: (DirNode) -> Void
    var onReveal: ((DirNode) -> Void)? = nil
    var onClean: ((DirNode) -> Void)? = nil

    private let tints: [Color] = [Palette.accent, Palette.accent2, Palette.violet, Palette.warn, Palette.good, Palette.pink]

    var body: some View {
        GeometryReader { geo in
            let cells = Treemap.layout(node.children, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                    cellView(cell, tint: tints[index % tints.count])
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(_ cell: Treemap.Cell, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(tint.opacity(0.55))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
            .overlay(alignment: .topLeading) { cellLabel(cell) }
            .frame(width: max(1, cell.rect.width), height: max(1, cell.rect.height))
            .position(x: cell.rect.midX, y: cell.rect.midY)
            .onTapGesture { if !cell.node.children.isEmpty { onSelect(cell.node) } }
            .help("\(cell.node.name) — \(bytesString(cell.node.size))")
            .contextMenu {
                if let onReveal { Button { onReveal(cell.node) } label: { Label(L("Reveal in Finder"), systemImage: "magnifyingglass") } }
                if let onClean { Button(role: .destructive) { onClean(cell.node) } label: { Label(L("Move to Vault"), systemImage: "tray.and.arrow.down") } }
            }
    }

    @ViewBuilder
    private func cellLabel(_ cell: Treemap.Cell) -> some View {
        if cell.rect.width > 58, cell.rect.height > 26 {
            VStack(alignment: .leading, spacing: 1) {
                Text(cell.node.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Text(bytesString(cell.node.size)).font(.system(size: 9)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(5)
        }
    }
}
