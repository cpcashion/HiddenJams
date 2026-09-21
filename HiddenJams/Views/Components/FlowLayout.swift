import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        if rows.isEmpty { return .zero }
        
        let height = rows.last?.maxY ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        
        for row in rows {
            for item in row.items {
                let x = bounds.minX + item.x
                let y = bounds.minY + item.y
                item.subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            }
        }
    }
    
    private struct LayoutItem {
        let subview: LayoutSubview
        let x: CGFloat
        let y: CGFloat
    }
    
    private struct Row {
        var items: [LayoutItem] = []
        var maxY: CGFloat = 0
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        
        let maxWidth = proposal.width ?? 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && !currentRow.items.isEmpty {
                // New row
                currentRow.maxY = currentY + currentRowHeight
                rows.append(currentRow)
                
                currentY += currentRowHeight + spacing
                currentX = 0
                currentRow = Row()
                currentRowHeight = 0
            }
            
            currentRow.items.append(LayoutItem(subview: subview, x: currentX, y: currentY))
            currentX += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        
        // Add last row
        if !currentRow.items.isEmpty {
            currentRow.maxY = currentY + currentRowHeight
            rows.append(currentRow)
        }
        
        return rows
    }
}
