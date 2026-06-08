import Foundation

struct ImageFile: Identifiable, Equatable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let width: CGFloat
    let height: CGFloat
    let tag: String?
    var isSelected: Bool
    var isPrinted: Bool
    
    static func == (lhs: ImageFile, rhs: ImageFile) -> Bool {
        return lhs.id == rhs.id && lhs.isSelected == rhs.isSelected && lhs.isPrinted == rhs.isPrinted
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PrintConfig: Equatable {
    var longerDim: CGFloat = 8.0
    var paperW: CGFloat = 8.5
    var paperH: CGFloat = 11.0
    var cupsPaperSize: String = "Letter"
    var mediaType: String = "any"
    var inputSlot: String = "auto"
    var printer: String = ""
}

struct PaperPreset: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let w: CGFloat
    let h: CGFloat
    let cups: String
    
    static let presets: [PaperPreset] = [
        PaperPreset(label: "4 x 6\"",    w: 4.0,   h: 6.0,  cups: "Custom.288x432"),
        PaperPreset(label: "5 x 7\"",    w: 5.0,   h: 7.0,  cups: "Custom.360x504"),
        PaperPreset(label: "8 x 10\"",   w: 8.0,   h: 10.0, cups: "Custom.576x720"),
        PaperPreset(label: "8.5 x 11\"", w: 8.5,  h: 11.0, cups: "Letter"),
        PaperPreset(label: "11 x 14\"",  w: 11.0,  h: 14.0, cups: "Custom.792x1008"),
        PaperPreset(label: "13 x 19\"",  w: 13.0,  h: 19.0, cups: "Custom.936x1368"),
        PaperPreset(label: "Custom",    w: 0.0,   h: 0.0,  cups: "")
    ]
}

struct LayoutItem: Identifiable, Equatable {
    var id: UUID { img.id }
    let w: CGFloat // Print width in inches
    let h: CGFloat // Print height in inches
    let img: ImageFile
    
    static func == (lhs: LayoutItem, rhs: LayoutItem) -> Bool {
        return lhs.id == rhs.id && lhs.w == rhs.w && lhs.h == rhs.h && lhs.img == rhs.img
    }
}

struct LayoutResult: Equatable {
    let rows: [[LayoutItem]]
    let totalH: CGFloat
    let rowHeights: [CGFloat]
    let orientation: String // "landscape" or "portrait"
}
