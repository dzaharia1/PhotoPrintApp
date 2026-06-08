import SwiftUI
import AppKit

// MARK: - Finder tag colors (matches macOS Finder default tag swatches)

func finderTagColor(_ tag: String) -> Color {
    switch tag {
    case "Red":    return Color(red: 0.988, green: 0.376, blue: 0.345) // #FC6058
    case "Orange": return Color(red: 0.992, green: 0.620, blue: 0.278) // #FD9E47
    case "Yellow": return Color(red: 0.996, green: 0.800, blue: 0.267) // #FECC44
    case "Green":  return Color(red: 0.365, green: 0.769, blue: 0.400) // #5DC466
    case "Blue":   return Color(red: 0.353, green: 0.784, blue: 0.980) // #5AC8FA
    case "Purple": return Color(red: 0.773, green: 0.541, blue: 0.976) // #C58AF9
    case "Gray":   return Color(red: 0.624, green: 0.624, blue: 0.624) // #9F9F9F
    default:       return Color.gray
    }
}

func finderTagNSColor(_ tag: String) -> NSColor {
    switch tag {
    case "Red":    return NSColor(red: 0.988, green: 0.376, blue: 0.345, alpha: 1)
    case "Orange": return NSColor(red: 0.992, green: 0.620, blue: 0.278, alpha: 1)
    case "Yellow": return NSColor(red: 0.996, green: 0.800, blue: 0.267, alpha: 1)
    case "Green":  return NSColor(red: 0.365, green: 0.769, blue: 0.400, alpha: 1)
    case "Blue":   return NSColor(red: 0.353, green: 0.784, blue: 0.980, alpha: 1)
    case "Purple": return NSColor(red: 0.773, green: 0.541, blue: 0.976, alpha: 1)
    case "Gray":   return NSColor(red: 0.624, green: 0.624, blue: 0.624, alpha: 1)
    default:       return NSColor.gray
    }
}

func finderTagSwatch(_ tag: String, size: CGFloat = 12) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        finderTagNSColor(tag).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
        return true
    }
    image.isTemplate = false
    return image
}

// MARK: - Liquid Glass helpers

// An invisible region that lets the user drag the window when they click+drag it.
// Uses performDrag(with:) which reliably moves borderless windows (the passive
// mouseDownCanMoveWindow path does not work for borderless windows).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension View {
    // Real Liquid Glass surface (macOS 26+). Clips contents to the shape so
    // child backgrounds don't square off the corners.
    func glassPanel(cornerRadius: CGFloat = 22) -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// Cache to prevent loading thumbnails repeatedly
class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSURL, NSImage>()
    
    func getThumbnail(for url: URL, size: CGFloat = 120) -> NSImage? {
        let nsUrl = url as NSURL
        if let cached = cache.object(forKey: nsUrl) {
            return cached
        }
        
        guard let source = CGImageSourceCreateWithURL(nsUrl, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size
        ]
        
        guard let cgImg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        
        let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
        cache.setObject(nsImg, forKey: nsUrl)
        return nsImg
    }
}

// Mini preview for individual items on the canvas
struct ImagePreviewItem: View {
    let img: ImageFile
    let rotate: Bool
    @State private var thumbnail: NSImage? = nil
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .rotationEffect(rotate ? .degrees(-90) : .degrees(0))
                    .clipped()
            } else {
                ZStack {
                    Color.gray.opacity(0.15)
                    ProgressView().scaleEffect(0.5)
                }
            }
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                if let thumb = ImageCache.shared.getThumbnail(for: img.url, size: 300) {
                    DispatchQueue.main.async {
                        self.thumbnail = thumb
                    }
                }
            }
        }
    }
}

struct ContentView: View {
    @AppStorage("appTheme") private var appTheme: String = "System"

    private var selectedColorScheme: ColorScheme? {
        switch appTheme {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
    }

    @State private var selectedDirectory: URL? = nil
    @State private var images = [ImageFile]()
    @State private var config = PrintConfig()
    
    // Dynamic CUPS states
    @State private var availablePrinters = [String]()
    @State private var availableMediaTypes = [String]()
    @State private var availableInputSlots = [String]()
    @State private var selectedPreset = PaperPreset.presets.first(where: { $0.label == "8.5 x 11\"" }) ?? PaperPreset.presets[3]
    
    // Custom paper fields
    @State private var customW: String = "8.5"
    @State private var customH: String = "11.0"
    
    // Pager & Auto-batching
    @State private var autoBatchedPages: [[ImageFile]] = []
    @State private var currentBatchPageIndex: Int = 0
    
    // Status/Action states
    @State private var isPrinting = false
    @State private var printStatusMessage: String? = nil
    @State private var showPrintSuccess = false
    @State private var showPrintFailed = false
    @State private var isLoadingImages = false
    
    // Filter tags
    @State private var nameFilter: String = ""
    
    var body: some View {
        ZStack {
            // Adaptive backdrop that follows the system light/dark theme
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                // Left floating glass panel — offset 8pt from window edges
                leftPanel
                    .frame(width: 320)
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                // Center: bare preview, no container
                centerArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                // Right: fixed (non-floating) settings panel attached to window edge
                rightPanel
                    .frame(width: 320)
            }
            .ignoresSafeArea(.all, edges: .top)
        }
        .frame(minWidth: 1100, minHeight: 700)
        .onAppear {
            initializeApp()
            updateWindowAppearance()
        }
        .onChange(of: appTheme) { _, _ in
            updateWindowAppearance()
        }
        .preferredColorScheme(selectedColorScheme)
    }

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Custom traffic lights + drag region (folder header lives in the center pane)
            ZStack(alignment: .topLeading) {
                WindowDragArea()
                    .frame(height: 38)
                WindowControls()
                    .padding(.leading, 14)
                    .padding(.top, 14)
            }

            filterBar

            if isLoadingImages {
                Spacer()
                ProgressView("Loading folder images...")
                Spacer()
            } else if images.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text(selectedDirectory == nil ? "Select a folder to begin" : "No images found in this folder")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Button(action: selectFolder) {
                        Text("Open Folder")
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
                Spacer()
            } else {
                imageList
                selectionHelpers
            }
        }
        .glassPanel(cornerRadius: 19)
    }

    private var centerArea: some View {
        VStack(spacing: 12) {
            // Top bar: folder source on the left, drag-able region filling the rest
            ZStack {
                WindowDragArea()
                    .frame(height: 60)
                HStack {
                    folderHeader
                        .frame(maxWidth: 320, alignment: .leading)
                    Spacer()
                    themeMenuButton
                        .padding(.trailing, 16)
                }
            }

            previewCanvas

            if !autoBatchedPages.isEmpty {
                batchPagerControls
            }

            spaceUsageBanner
        }
    }

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Drag region at the very top of the right panel
            WindowDragArea().frame(height: 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Print Settings")
                        .font(.headline)
                        .padding(.top, 4)
                        .padding(.horizontal)
                        .padding(.bottom, 14)

                    VStack(alignment: .leading, spacing: 24) {
                        printerSelectionSection
                        paperSettingsSection
                        resolutionSection
                        imageSettingsSection
                    }
                }
                .padding(.bottom, 16)
            }

            actionsSection
        }
        .frame(maxHeight: .infinity)
        .background(
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 0.5)
        }
    }

    private var windowTitle: String {
        if let dir = selectedDirectory {
            return "PhotoPrint — \(dir.path)"
        }
        return "PhotoPrint"
    }
    
    // MARK: - Subviews
    
    private var folderHeader: some View {
        HStack(spacing: 12) {
            Button(action: selectFolder) {
                Image(systemName: "folder.badge.plus")
                    .imageScale(.large)
            }
            .buttonStyle(.glass)
            .help("Choose image directory")

            VStack(alignment: .leading, spacing: 4) {
                Text("FOLDER SOURCE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(0.6)
                if let dir = selectedDirectory {
                    Text(dir.lastPathComponent)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                } else {
                    Text("None Selected")
                        .font(.body)
                        .italic()
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private var themeMenuButton: some View {
        Menu {
            Button(action: { appTheme = "Light" }) {
                Label("Light", systemImage: "sun.max")
            }
            Button(action: { appTheme = "Dark" }) {
                Label("Dark", systemImage: "moon")
            }
            Button(action: { appTheme = "System" }) {
                Label("Follow System", systemImage: "display")
            }
        } label: {
            Image(systemName: currentThemeIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6)
                )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Select Theme")
    }

    private var currentThemeIcon: String {
        switch appTheme {
        case "Light": return "sun.max"
        case "Dark": return "moon"
        default: return "display"
        }
    }

    private var filterBar: some View {
        let isDisabled = selectedDirectory == nil
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search images...", text: $nameFilter)
                .textFieldStyle(.plain)
                .disabled(isDisabled)
            if !nameFilter.isEmpty {
                Button(action: { nameFilter = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule(style: .continuous))
        .opacity(isDisabled ? 0.45 : 1.0)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private var imageList: some View {
        List {
            let filtered = images.filter {
                nameFilter.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(nameFilter)
            }

            ForEach(filtered) { img in
                ImageRow(
                    img: img,
                    longerDim: config.longerDim,
                    wouldFit: LayoutEngine.wouldFit(img: img, selected: selectedImages, config: config),
                    onToggle: { toggleImageSelection(img) }
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .padding(.horizontal, 8)
    }

    private var selectionHelpers: some View {
        HStack(spacing: 3) {
            Menu {
                ForEach(["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"], id: \.self) { tag in
                    Button(action: { addImagesByTag(tag) }) {
                        Image(nsImage: finderTagSwatch(tag))
                        Text("\(tag) tag")
                    }
                    .disabled(!images.contains { $0.tag == tag && !$0.isPrinted && !$0.isSelected })
                }
            } label: {
                Text("Add by...")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
            .disabled(images.isEmpty)

            Spacer()

            HStack(spacing: 4) {
                Button(action: autoBatchAll) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.3x3.fill")
                        Text("Auto")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.glassProminent)
                .disabled(images.filter { !$0.isPrinted }.isEmpty)

                Button("Clear") {
                    images = images.map {
                        var img = $0
                        img.isSelected = false
                        return img
                    }
                    clearBatch()
                }
                .buttonStyle(.glass)
                .disabled(selectedImages.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var previewCanvas: some View {
        VStack {
            let imagesToPreview = autoBatchedPages.isEmpty ? selectedImages : autoBatchedPages[currentBatchPageIndex]
            if !imagesToPreview.isEmpty {
                PrintPreviewView(images: imagesToPreview, config: config)
            } else {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "printer")
                        .font(.system(size: 64))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("No Images Selected")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                    Text("Check boxes on the left sidebar to add images to the sheet.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
        }
    }
    
    private var batchPagerControls: some View {
        HStack(spacing: 14) {
            Button(action: firstBatchPage) {
                Image(systemName: "chevron.left.2")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .disabled(currentBatchPageIndex == 0)

            Button(action: prevBatchPage) {
                Image(systemName: "chevron.left")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .disabled(currentBatchPageIndex == 0)

            Menu {
                ForEach(autoBatchedPages.indices, id: \.self) { idx in
                    Button("Page \(idx + 1) of \(autoBatchedPages.count)") {
                        jumpToBatchPage(idx)
                    }
                    .disabled(idx == currentBatchPageIndex)
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Page \(currentBatchPageIndex + 1) of \(autoBatchedPages.count)")
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 140)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()

            Button(action: nextBatchPage) {
                Image(systemName: "chevron.right")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .disabled(currentBatchPageIndex >= autoBatchedPages.count - 1)

            Button(action: lastBatchPage) {
                Image(systemName: "chevron.right.2")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .disabled(currentBatchPageIndex >= autoBatchedPages.count - 1)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 22)
        .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
    }

    private var spaceUsageBanner: some View {
        VStack(spacing: 4) {
            if let layout = currentLayout {
                let used = layout.totalH
                let pct = min(1.0, used / config.paperH)

                HStack(spacing: 0) {
                    // Left: Grid chip
                    Text("Grid: \(layout.rows.map { "\($0.count)" }.joined(separator: "+")) (\(layout.orientation))")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.cyan.opacity(0.18))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.cyan.opacity(0.4), lineWidth: 0.5)
                        )
                        .foregroundColor(.cyan)

                    // Middle: progress bar filling remaining space with 48pt margins
                    ProgressView(value: pct)
                        .progressViewStyle(.linear)
                        .tint(pct > 0.95 ? .red : pct > 0.75 ? .orange : .green)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 48)

                    // Right: used/height indicator
                    HStack(spacing: 4) {
                        Text("\(used, specifier: "%.2f")\" used")
                            .fontWeight(.semibold)
                        Text("/ \(config.paperH, specifier: "%.2f")\" height")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
    
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
    }

    // A popup-style dropdown that actually fills its container's width.
    private func dropdown<T: Hashable>(
        selection: Binding<T>,
        options: [T],
        label: @escaping (T) -> String,
        placeholder: String = "—"
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button(label(opt)) { selection.wrappedValue = opt }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.isEmpty ? placeholder : label(selection.wrappedValue))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func fieldRow<V: View>(_ label: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            content()
        }
    }

    private var printerSelectionSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            fieldRow("Printer") {
                dropdown(
                    selection: $config.printer,
                    options: availablePrinters,
                    label: { $0 },
                    placeholder: "Searching..."
                )
                .onChange(of: config.printer) { _, newPrinter in
                    queryPrinterOptions(printer: newPrinter)
                    clearBatch()
                }
            }

            if !availableMediaTypes.isEmpty {
                fieldRow("Media Type") {
                    dropdown(
                        selection: $config.mediaType,
                        options: availableMediaTypes,
                        label: { friendlyMediaName($0) }
                    )
                }
            }

            if !availableInputSlots.isEmpty {
                fieldRow("Input Tray") {
                    dropdown(
                        selection: $config.inputSlot,
                        options: availableInputSlots,
                        label: { $0 }
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    private var paperSettingsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            fieldRow("Paper Size") {
                dropdown(
                    selection: $selectedPreset,
                    options: PaperPreset.presets,
                    label: { $0.label }
                )
                .onChange(of: selectedPreset) { _, preset in
                    if preset.label != "Custom" {
                        config.paperW = preset.w
                        config.paperH = preset.h
                        config.cupsPaperSize = preset.cups
                    } else {
                        updateCustomPaperValues()
                    }
                    clearBatch()
                }
            }

            if selectedPreset.label == "Custom" {
                HStack(spacing: 12) {
                    fieldRow("Width (in)") {
                        TextField("W", text: $customW)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: customW) { _, _ in updateCustomPaperValues() }
                    }
                    fieldRow("Height (in)") {
                        TextField("H", text: $customH)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: customH) { _, _ in updateCustomPaperValues() }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            fieldRow("Print Resolution") {
                dropdown(
                    selection: $config.dpi,
                    options: [150, 240, 300, 360, 600],
                    label: { "\(Int($0)) DPI" }
                )
                .onChange(of: config.dpi) { _, _ in clearBatch() }
            }
        }
        .padding(.horizontal)
    }

    private var imageSettingsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 4) {
                fieldLabel("Image Size (longer edge)")
                Spacer()
                TextField("", value: Binding(
                    get: { Double(config.longerDim) },
                    set: { config.longerDim = CGFloat($0) }
                ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .fontWeight(.semibold)
                    .frame(width: 50)
                    .onChange(of: config.longerDim) { _, _ in clearBatch() }
                Text("inches")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Slider(value: $config.longerDim, in: 2.0...18.0, step: 0.5)
                .labelsHidden()
                .onChange(of: config.longerDim) { _, _ in
                    clearBatch()
                }
        }
        .padding(.horizontal)
    }
    
    private var actionsSection: some View {
        VStack(spacing: 10) {
            if let msg = printStatusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(showPrintSuccess ? .green : (showPrintFailed ? .red : .secondary))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            HStack(spacing: 10) {
                if !autoBatchedPages.isEmpty {
                    Button(action: printAllBatchPages) {
                        Group {
                            if isPrinting {
                                ProgressView().scaleEffect(0.5)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Print All Pages")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(.blue)
                    .disabled(isPrinting)
                }

                Button(action: printCurrentPage) {
                    Group {
                        if isPrinting && autoBatchedPages.isEmpty {
                            ProgressView().scaleEffect(0.5)
                                .frame(maxWidth: .infinity)
                        } else {
                            let btnLabel = autoBatchedPages.isEmpty ? "Print Current Page" : "Print This Page"
                            Text(btnLabel)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(autoBatchedPages.isEmpty ? .blue : .gray)
                .disabled(isPrinting || (!autoBatchedPages.isEmpty && autoBatchedPages.isEmpty) || (autoBatchedPages.isEmpty && selectedImages.isEmpty))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Computed Properties
    
    private var selectedImages: [ImageFile] {
        return images.filter { $0.isSelected }
    }
    
    private var currentLayout: LayoutResult? {
        if !autoBatchedPages.isEmpty {
            guard currentBatchPageIndex < autoBatchedPages.count else { return nil }
            return LayoutEngine.calculateLayout(images: autoBatchedPages[currentBatchPageIndex], config: config)
        } else {
            return LayoutEngine.calculateLayout(images: selectedImages, config: config)
        }
    }
    
    // MARK: - Layout Helpers
    
    private func calculateRowY(rowIndex: Int, layout: LayoutResult, vertGap: CGFloat) -> CGFloat {
        var y: CGFloat = vertGap
        for i in 0..<rowIndex {
            y += layout.rowHeights[i] + vertGap
        }
        return y
    }
    
    private func getItemsWithX(row: [LayoutItem], horizGap: CGFloat) -> [(item: LayoutItem, x: CGFloat)] {
        var list = [(LayoutItem, CGFloat)]()
        var currentX = horizGap
        for item in row {
            list.append((item, currentX))
            currentX += item.w + horizGap
        }
        return list
    }
    
    private func tagColor(_ tag: String) -> Color {
        finderTagColor(tag)
    }

    private func friendlyMediaName(_ systemName: String) -> String {
        let mapping = [
            "photographic": "Photo Glossy/Lustre",
            "stationery":   "Matte",
            "envelope":     "Envelope",
            "any":          "Auto"
        ]
        return mapping[systemName] ?? systemName
    }
    
    // MARK: - Handlers & API Calls
    
    private static let lastFolderKey = "PhotoPrint.lastFolderPath"

    private func initializeApp() {
        // Restore the most recently opened folder, if it still exists.
        if let saved = UserDefaults.standard.string(forKey: Self.lastFolderKey),
           FileManager.default.fileExists(atPath: saved) {
            let url = URL(fileURLWithPath: saved)
            selectedDirectory = url
            loadImages(from: url)
        }

        // Load printers list
        DispatchQueue.global(qos: .userInitiated).async {
            let printers = PrinterManager.getPrinters()
            DispatchQueue.main.async {
                self.availablePrinters = printers
                if let first = printers.first {
                    self.config.printer = first
                    self.queryPrinterOptions(printer: first)
                }
            }
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let current = selectedDirectory {
            panel.directoryURL = current
        }

        if panel.runModal() == .OK, let url = panel.url {
            selectedDirectory = url
            UserDefaults.standard.set(url.path, forKey: Self.lastFolderKey)
            loadImages(from: url)
        }
    }
    
    private func loadImages(from directory: URL) {
        isLoadingImages = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
                DispatchQueue.main.async { self.isLoadingImages = false }
                return
            }
            
            let allowedExtensions = ["jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "webp"]
            let imageFiles = files.filter {
                allowedExtensions.contains($0.pathExtension.lowercased())
            }.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            
            var loaded = [ImageFile]()
            for url in imageFiles {
                if let info = ImageCompositor.getDimensionsAndTag(url: url) {
                    let img = ImageFile(
                        id: UUID(),
                        url: url,
                        name: url.lastPathComponent,
                        width: info.width,
                        height: info.height,
                        tag: info.tag,
                        isSelected: false,
                        isPrinted: false
                    )
                    loaded.append(img)
                }
            }
            
            DispatchQueue.main.async {
                self.images = loaded
                self.isLoadingImages = false
                self.clearBatch()
            }
        }
    }
    
    private func queryPrinterOptions(printer: String) {
        guard !printer.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let medias = PrinterManager.getPrinterOptions(printer: printer, key: "MediaType")
            let slots = PrinterManager.getPrinterOptions(printer: printer, key: "InputSlot")
            
            DispatchQueue.main.async {
                self.availableMediaTypes = medias
                if let defaultMedia = medias.first(where: { $0.hasPrefix("*") }) {
                    self.config.mediaType = String(defaultMedia.dropFirst())
                } else {
                    self.config.mediaType = medias.first ?? "any"
                }
                
                self.availableInputSlots = slots
                if let defaultSlot = slots.first(where: { $0.hasPrefix("*") }) {
                    self.config.inputSlot = String(defaultSlot.dropFirst())
                } else {
                    self.config.inputSlot = slots.first ?? "auto"
                }
            }
        }
    }
    
    private func updateCustomPaperValues() {
        if let wVal = Double(customW) {
            config.paperW = CGFloat(wVal)
        }
        if let hVal = Double(customH) {
            config.paperH = CGFloat(hVal)
        }
        config.cupsPaperSize = "Custom.\(Int(round(config.paperW * 72.0)))x\(Int(round(config.paperH * 72.0)))"
    }
    
    private func toggleImageSelection(_ img: ImageFile) {
        // If we are in auto-batch mode, toggle exits it
        if !autoBatchedPages.isEmpty {
            clearBatch()
        }
        
        if let idx = images.firstIndex(where: { $0.id == img.id }) {
            let selected = images.filter { $0.isSelected }
            
            if images[idx].isSelected {
                images[idx].isSelected = false
            } else {
                // Check if it fits
                if LayoutEngine.wouldFit(img: img, selected: selected, config: config) {
                    images[idx].isSelected = true
                }
            }
        }
    }
    
    private func addImagesByTag(_ tag: String) {
        clearBatch()

        let candidates = images.filter { $0.tag == tag && !$0.isPrinted && !$0.isSelected }
        var selected = selectedImages

        for img in candidates {
            if LayoutEngine.wouldFit(img: img, selected: selected, config: config) {
                if let idx = images.firstIndex(where: { $0.id == img.id }) {
                    images[idx].isSelected = true
                    selected.append(images[idx])
                }
            }
        }
    }
    
    // MARK: - Auto-batching
    
    private func autoBatchAll() {
        let unprinted = images.filter { !$0.isPrinted }
        guard !unprinted.isEmpty else { return }
        
        // De-select current manually selected items to perform clean auto-batch
        images = images.map {
            var item = $0
            item.isSelected = false
            return item
        }
        
        var pages = [[ImageFile]]()
        var currentPage = [ImageFile]()
        
        for img in unprinted {
            if LayoutEngine.wouldFit(img: img, selected: currentPage, config: config) {
                currentPage.append(img)
            } else {
                if !currentPage.isEmpty {
                    pages.append(currentPage)
                }
                currentPage = [img]
            }
        }
        if !currentPage.isEmpty {
            pages.append(currentPage)
        }
        
        if !pages.isEmpty {
            autoBatchedPages = pages
            currentBatchPageIndex = 0
            
            // Mirror current selection to first page
            let firstPageIds = Set(pages[0].map { $0.id })
            images = images.map {
                var item = $0
                item.isSelected = firstPageIds.contains(item.id)
                return item
            }
        }
    }
    
    private func nextBatchPage() {
        guard currentBatchPageIndex < autoBatchedPages.count - 1 else { return }
        currentBatchPageIndex += 1
        syncSelectionToCurrentPage()
    }
    
    private func prevBatchPage() {
        guard currentBatchPageIndex > 0 else { return }
        currentBatchPageIndex -= 1
        syncSelectionToCurrentPage()
    }

    private func firstBatchPage() {
        guard !autoBatchedPages.isEmpty, currentBatchPageIndex != 0 else { return }
        currentBatchPageIndex = 0
        syncSelectionToCurrentPage()
    }

    private func lastBatchPage() {
        let last = autoBatchedPages.count - 1
        guard last >= 0, currentBatchPageIndex != last else { return }
        currentBatchPageIndex = last
        syncSelectionToCurrentPage()
    }

    private func jumpToBatchPage(_ idx: Int) {
        guard idx >= 0, idx < autoBatchedPages.count, idx != currentBatchPageIndex else { return }
        currentBatchPageIndex = idx
        syncSelectionToCurrentPage()
    }
    
    private func syncSelectionToCurrentPage() {
        let pageIds = Set(autoBatchedPages[currentBatchPageIndex].map { $0.id })
        images = images.map {
            var item = $0
            item.isSelected = pageIds.contains(item.id)
            return item
        }
    }
    
    private func clearBatch() {
        autoBatchedPages = []
        currentBatchPageIndex = 0
    }
    
    // MARK: - Printing Actions
    
    private func printCurrentPage() {
        let imagesToPrint = autoBatchedPages.isEmpty ? selectedImages : autoBatchedPages[currentBatchPageIndex]
        guard !imagesToPrint.isEmpty else { return }
        
        isPrinting = true
        printStatusMessage = "Compositing image at \(Int(config.dpi)) DPI..."
        showPrintSuccess = false
        showPrintFailed = false

        let dpi = self.config.dpi
        DispatchQueue.global(qos: .userInitiated).async {
            guard let layout = LayoutEngine.calculateLayout(images: imagesToPrint, config: self.config),
                  let compositeCgImage = ImageCompositor.buildComposite(images: imagesToPrint, config: self.config, layout: layout, dpi: dpi, useThumbnails: false) else {
                DispatchQueue.main.async {
                    self.isPrinting = false
                    self.printStatusMessage = "Compositing failed."
                    self.showPrintFailed = true
                }
                return
            }

            // Save to temporary TIFF file
            let tempDir = FileManager.default.temporaryDirectory
            let tempFilename = "photoprint_\(Int(Date().timeIntervalSince1970)).tiff"
            let tempUrl = tempDir.appendingPathComponent(tempFilename)

            guard ImageCompositor.saveTIFF(cgImage: compositeCgImage, to: tempUrl, dpi: dpi) else {
                DispatchQueue.main.async {
                    self.isPrinting = false
                    self.printStatusMessage = "Failed to save TIFF composite."
                    self.showPrintFailed = true
                }
                return
            }
            
            DispatchQueue.main.async {
                self.printStatusMessage = "Sending composite to printer..."
            }
            
            // Shell out to lp via PrinterManager
            let printResult = PrinterManager.printComposite(filePath: tempUrl.path, config: self.config)
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempUrl)
            
            DispatchQueue.main.async {
                self.isPrinting = false
                if let res = printResult {
                    self.printStatusMessage = "Successfully printed! \(res)"
                    self.showPrintSuccess = true
                    
                    // Mark images as printed
                    let printedIds = Set(imagesToPrint.map { $0.id })
                    self.images = self.images.map {
                        var item = $0
                        if printedIds.contains(item.id) {
                            item.isPrinted = true
                            item.isSelected = false
                        }
                        return item
                    }
                    
                    // Handle batch progression
                    if !self.autoBatchedPages.isEmpty {
                        // Remove current page from queue
                        self.autoBatchedPages.remove(at: self.currentBatchPageIndex)
                        if self.autoBatchedPages.isEmpty {
                            self.clearBatch()
                        } else {
                            if self.currentBatchPageIndex >= self.autoBatchedPages.count {
                                self.currentBatchPageIndex = self.autoBatchedPages.count - 1
                            }
                            self.syncSelectionToCurrentPage()
                        }
                    }
                } else {
                    self.printStatusMessage = "Printing command failed."
                    self.showPrintFailed = true
                }
            }
        }
    }
    
    private func printAllBatchPages() {
        guard !autoBatchedPages.isEmpty else { return }
        
        isPrinting = true
        printStatusMessage = "Printing all pages in batch..."
        showPrintSuccess = false
        showPrintFailed = false
        
        let pagesToPrint = autoBatchedPages
        
        let dpi = self.config.dpi
        DispatchQueue.global(qos: .userInitiated).async {
            var successCount = 0
            var failedCount = 0

            for (index, pageImages) in pagesToPrint.enumerated() {
                DispatchQueue.main.async {
                    self.printStatusMessage = "Compositing page \(index + 1) of \(pagesToPrint.count) at \(Int(dpi)) DPI..."
                }

                guard let layout = LayoutEngine.calculateLayout(images: pageImages, config: self.config),
                      let compositeCgImage = ImageCompositor.buildComposite(images: pageImages, config: self.config, layout: layout, dpi: dpi, useThumbnails: false) else {
                    failedCount += 1
                    continue
                }

                let tempDir = FileManager.default.temporaryDirectory
                let tempFilename = "photoprint_batch_\(index)_\(Int(Date().timeIntervalSince1970)).tiff"
                let tempUrl = tempDir.appendingPathComponent(tempFilename)

                guard ImageCompositor.saveTIFF(cgImage: compositeCgImage, to: tempUrl, dpi: dpi) else {
                    failedCount += 1
                    continue
                }
                
                DispatchQueue.main.async {
                    self.printStatusMessage = "Sending page \(index + 1) of \(pagesToPrint.count) to printer..."
                }
                
                let printResult = PrinterManager.printComposite(filePath: tempUrl.path, config: self.config)
                try? FileManager.default.removeItem(at: tempUrl)
                
                if printResult != nil {
                    successCount += 1
                } else {
                    failedCount += 1
                }
            }
            
            DispatchQueue.main.async {
                self.isPrinting = false
                if failedCount == 0 {
                    self.printStatusMessage = "Successfully printed all \(successCount) pages!"
                    self.showPrintSuccess = true
                    
                    // Mark all batch images as printed
                    let allBatchIds = Set(pagesToPrint.flatMap { $0 }.map { $0.id })
                    self.images = self.images.map {
                        var item = $0
                        if allBatchIds.contains(item.id) {
                            item.isPrinted = true
                            item.isSelected = false
                        }
                        return item
                    }
                    self.clearBatch()
                } else {
                    self.printStatusMessage = "Printed \(successCount) pages, failed \(failedCount) pages."
                    self.showPrintFailed = true
                    
                    // Clear only printed items from batch
                    // Just reset auto-batch so user can retry manual selections
                    self.clearBatch()
                }
            }
        }
    }

    private func updateWindowAppearance() {
        guard let window = WindowRef.shared.window else { return }
        switch appTheme {
        case "Light":
            window.appearance = NSAppearance(named: .aqua)
        case "Dark":
            window.appearance = NSAppearance(named: .darkAqua)
        default:
            window.appearance = nil
        }
    }
}

// MARK: - Row View for Image List

struct ImageRow: View {
    let img: ImageFile
    let longerDim: CGFloat
    let wouldFit: Bool
    let onToggle: () -> Void
    
    @State private var thumbnail: NSImage? = nil
    
    var body: some View {
        let aspectHeight = LayoutEngine.printH(img: img, longerDim: longerDim)
        
        HStack(spacing: 12) {
            // Checkbox/Toggle Button
            Button(action: onToggle) {
                Image(systemName: img.isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(img.isSelected ? .green : .gray)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            
            // Thumbnail Image View
            ZStack {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .cornerRadius(3)
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 44, height: 44)
                    ProgressView().scaleEffect(0.4)
                }
            }
            .onAppear {
                DispatchQueue.global(qos: .userInitiated).async {
                    if let thumb = ImageCache.shared.getThumbnail(for: img.url, size: 88) {
                        DispatchQueue.main.async {
                            self.thumbnail = thumb
                        }
                    }
                }
            }
            
            // Image Details
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let tagColor = img.tag {
                        Circle()
                            .fill(finderColor(tagColor))
                            .frame(width: 8, height: 8)
                            .help("Finder tag: \(tagColor)")
                    }
                    Text(img.name)
                        .font(.body)
                        .lineLimit(1)
                }
                
                Text("\(longerDim, specifier: "%.1f")\" x \(aspectHeight, specifier: "%.2f")\" print size")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Printed Status Badge
            if img.isPrinted {
                Text("Printed")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(img.isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.001))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(img.isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 0.6)
        )
        .opacity(img.isPrinted ? 0.55 : (img.isSelected ? 1.0 : (wouldFit ? 1.0 : 0.4)))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            onToggle()
        }
    }
    
    private func finderColor(_ tag: String) -> Color {
        finderTagColor(tag)
    }
}

// MARK: - Print Preview View (WYSIWYG generated from Core Graphics compositor)

struct PrintPreviewView: View {
    let images: [ImageFile]
    let config: PrintConfig
    
    @State private var previewImage: NSImage? = nil
    @State private var isGenerating = false
    
    var body: some View {
        ZStack {
            if isGenerating {
                ProgressView("Updating preview...")
            } else if let img = previewImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 10)
                    .padding(20)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Layout Preview")
                        .foregroundColor(.secondary)
                }
            }
        }
        .onChange(of: images) { _, _ in updatePreview() }
        .onChange(of: config) { _, _ in updatePreview() }
        .onAppear { updatePreview() }
    }
    
    private func updatePreview() {
        guard !images.isEmpty else {
            previewImage = nil
            return
        }
        
        isGenerating = true
        // Render at the display's physical pixel density so the preview is crisp on Retina.
        // Cap at 144 (2x) so big sheets don't blow up memory/CPU.
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let previewDPI: CGFloat = min(144, 72 * scale)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let layout = LayoutEngine.calculateLayout(images: images, config: config),
                  let cgImg = ImageCompositor.buildComposite(images: images, config: config, layout: layout, dpi: previewDPI, useThumbnails: true) else {
                DispatchQueue.main.async {
                    self.previewImage = nil
                    self.isGenerating = false
                }
                return
            }

            // Hand the NSImage its logical (point) size, not pixel size, so SwiftUI lays it out
            // at the right scale while keeping the extra pixels for Retina rendering.
            let pointSize = NSSize(width: CGFloat(cgImg.width) / scale, height: CGFloat(cgImg.height) / scale)
            let nsImg = NSImage(cgImage: cgImg, size: pointSize)
            DispatchQueue.main.async {
                self.previewImage = nsImg
                self.isGenerating = false
            }
        }
    }
}
