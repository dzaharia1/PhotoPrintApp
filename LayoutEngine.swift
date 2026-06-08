import Foundation

struct LayoutEngine {
    static let minGap: CGFloat = 0.15
    
    static func printH(img: ImageFile, longerDim: CGFloat) -> CGFloat {
        let l = max(img.width, img.height)
        let s = min(img.width, img.height)
        guard l > 0 else { return 0 }
        return longerDim * (s / l)
    }
    
    static func simulateLayoutForOrientation(images: [ImageFile], config: PrintConfig, orientation: String) -> LayoutResult {
        let longerDim = config.longerDim
        let paperW = config.paperW
        
        let items = images.map { img -> LayoutItem in
            let ph = printH(img: img, longerDim: longerDim)
            if orientation == "landscape" {
                return LayoutItem(w: longerDim, h: ph, img: img)
            } else {
                return LayoutItem(w: ph, h: longerDim, img: img)
            }
        }
        
        var rows = [[LayoutItem]]()
        var currentRow = [LayoutItem]()
        var currentRowW = minGap
        
        for item in items {
            // If a single image is too wide for the page (even with margins), it will never fit
            if item.w + 2 * minGap > paperW {
                return LayoutResult(rows: [], totalH: CGFloat.infinity, rowHeights: [], orientation: orientation)
            }
            
            if currentRowW + item.w + minGap <= paperW {
                currentRow.append(item)
                currentRowW += item.w + minGap
            } else {
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                }
                currentRow = [item]
                currentRowW = minGap + item.w + minGap
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        
        if rows.isEmpty {
            return LayoutResult(rows: [], totalH: 0, rowHeights: [], orientation: orientation)
        }
        
        var totalH = minGap
        var rowHeights = [CGFloat]()
        for row in rows {
            let maxH = row.map { $0.h }.max() ?? 0
            rowHeights.append(maxH)
            totalH += maxH + minGap
        }
        
        return LayoutResult(rows: rows, totalH: totalH, rowHeights: rowHeights, orientation: orientation)
    }
    
    static func calculateLayout(images: [ImageFile], config: PrintConfig) -> LayoutResult? {
        if images.isEmpty {
            return LayoutResult(rows: [], totalH: 0, rowHeights: [], orientation: "landscape")
        }
        
        let landscapeLayout = simulateLayoutForOrientation(images: images, config: config, orientation: "landscape")
        let portraitLayout = simulateLayoutForOrientation(images: images, config: config, orientation: "portrait")
        
        let landFits = landscapeLayout.totalH <= config.paperH
        let portFits = portraitLayout.totalH <= config.paperH
        
        if landscapeLayout.totalH == CGFloat.infinity && portraitLayout.totalH == CGFloat.infinity {
            return landscapeLayout
        }
        
        if landFits && !portFits {
            return landscapeLayout
        }
        if portFits && !landFits {
            return portraitLayout
        }
        
        // If both fit, or neither fits (but are finite), choose the one with smaller height
        if portraitLayout.totalH < landscapeLayout.totalH {
            return portraitLayout
        }
        return landscapeLayout
    }
    
    static func wouldFit(img: ImageFile, selected: [ImageFile], config: PrintConfig) -> Bool {
        guard let layout = calculateLayout(images: selected + [img], config: config) else {
            return false
        }
        return layout.totalH <= config.paperH
    }
    
    static func spaceUsed(images: [ImageFile], config: PrintConfig) -> CGFloat {
        guard let layout = calculateLayout(images: images, config: config) else { return 0 }
        return layout.totalH
    }
}
