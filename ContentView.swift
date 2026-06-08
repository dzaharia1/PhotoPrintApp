import SwiftUI

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
        HStack(spacing: 0) {
            // Left sidebar: Folder & Image List
            VStack(spacing: 0) {
                folderHeader
                
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
                        }
                    }
                    Spacer()
                } else {
                    imageList
                    selectionHelpers
                }
            }
            .frame(width: 350)
            
            Divider()
            
            // Middle: Live Print Preview Canvas
            VStack(spacing: 0) {
                previewCanvas
                
                if !autoBatchedPages.isEmpty {
                    batchPagerControls
                }
                
                spaceUsageBanner
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Right Sidebar: Settings & Action Panel
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Print Settings")
                            .font(.headline)
                            .padding(.top, 16)
                            .padding(.horizontal)
                        
                        Divider()
                            .padding(.horizontal)
                        
                        printerSelectionSection
                        
                        paperSettingsSection
                        
                        imageSettingsSection
                    }
                }
                
                Spacer()
                
                Divider()
                
                actionsSection
            }
            .frame(width: 350)
        }
        .frame(minWidth: 1000, minHeight: 650)
        .onAppear(perform: initializeApp)
    }
    
    // MARK: - Subviews
    
    private var folderHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Folder Source")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
                if let dir = selectedDirectory {
                    Text(dir.lastPathComponent)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                } else {
                    Text("None Selected")
                        .font(.body)
                        .italic()
                        .foregroundColor(.gray)
                }
            }
            Spacer()
            Button(action: selectFolder) {
                Image(systemName: "folder.badge.plus")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .help("Choose image directory")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var filterBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search images...", text: $nameFilter)
                .textFieldStyle(.plain)
            if !nameFilter.isEmpty {
                Button(action: { nameFilter = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .padding(.horizontal)
        .padding(.vertical, 8)
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
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
        }
    }
    
    private var selectionHelpers: some View {
        HStack(spacing: 8) {
            Button(action: selectAllRedTags) {
                HStack {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("Select Red")
                }
            }
            .disabled(images.isEmpty)
            
            Button("Clear All") {
                images = images.map {
                    var img = $0
                    img.isSelected = false
                    return img
                }
                clearBatch()
            }
            .disabled(selectedImages.isEmpty)
            
            Spacer()
            
            Button(action: autoBatchAll) {
                Text("Auto-Batch")
                    .fontWeight(.semibold)
            }
            .disabled(images.filter { !$0.isPrinted }.isEmpty)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
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
        HStack(spacing: 20) {
            Button(action: prevBatchPage) {
                Image(systemName: "chevron.left")
                    .imageScale(.large)
            }
            .disabled(currentBatchPageIndex == 0)
            
            Text("Page \(currentBatchPageIndex + 1) of \(autoBatchedPages.count)")
                .font(.headline)
                .frame(minWidth: 100)
            
            Button(action: nextBatchPage) {
                Image(systemName: "chevron.right")
                    .imageScale(.large)
            }
            .disabled(currentBatchPageIndex >= autoBatchedPages.count - 1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Capsule().fill(Color(NSColor.controlBackgroundColor)))
        .padding(.bottom, 12)
    }
    
    private var spaceUsageBanner: some View {
        VStack(spacing: 4) {
            if let layout = currentLayout {
                HStack {
                    let used = layout.totalH
                    let pct = min(1.0, used / config.paperH)
                    
                    ProgressView(value: pct)
                        .accentColor(pct > 0.95 ? .red : pct > 0.75 ? .orange : .green)
                        .frame(maxWidth: 300)
                    
                    Text("\(used, specifier: "%.2f")\" used")
                        .fontWeight(.bold)
                    Text("/ \(config.paperH, specifier: "%.2f")\" height")
                        .foregroundColor(.gray)
                    Spacer()
                    Text("Grid: \(layout.rows.map { "\($0.count)" }.joined(separator: "+")) (\(layout.orientation))")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.cyan.opacity(0.15))
                        .cornerRadius(4)
                        .foregroundColor(.cyan)
                }
                .font(.subheadline)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }
    
    private var printerSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Printer")
                .font(.subheadline)
                .fontWeight(.bold)
            
            Picker("Select Printer", selection: $config.printer) {
                if availablePrinters.isEmpty {
                    Text("Searching...").tag("")
                } else {
                    ForEach(availablePrinters, id: \.self) { p in
                        Text(p).tag(p)
                    }
                }
            }
            .labelsHidden()
            .onChange(of: config.printer) { _, newPrinter in
                queryPrinterOptions(printer: newPrinter)
                clearBatch()
            }
            
            if !availableMediaTypes.isEmpty {
                Text("Media Type")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 4)
                
                Picker("Media Type", selection: $config.mediaType) {
                    ForEach(availableMediaTypes, id: \.self) { m in
                        Text(friendlyMediaName(m)).tag(m)
                    }
                }
                .labelsHidden()
            }
            
            if !availableInputSlots.isEmpty {
                Text("Input Tray")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 4)
                
                Picker("Input Tray", selection: $config.inputSlot) {
                    ForEach(availableInputSlots, id: \.self) { s in
                        Text(s).tag(s)
                    }
                }
                .labelsHidden()
            }
        }
        .padding(.horizontal)
    }
    
    private var paperSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paper Size")
                .font(.subheadline)
                .fontWeight(.bold)
            
            Picker("Preset", selection: $selectedPreset) {
                ForEach(PaperPreset.presets) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .labelsHidden()
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
            
            if selectedPreset.label == "Custom" {
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("Width (in)").font(.caption).foregroundColor(.gray)
                        TextField("W", text: $customW)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: customW) { _, _ in updateCustomPaperValues() }
                    }
                    VStack(alignment: .leading) {
                        Text("Height (in)").font(.caption).foregroundColor(.gray)
                        TextField("H", text: $customH)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: customH) { _, _ in updateCustomPaperValues() }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal)
    }
    
    private var imageSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Image Scale")
                .font(.subheadline)
                .fontWeight(.bold)
            
            HStack {
                Text("Longer edge:")
                Spacer()
                Text("\(config.longerDim, specifier: "%.1f") inches")
                    .fontWeight(.bold)
            }
            .font(.subheadline)
            
            Slider(value: $config.longerDim, in: 2.0...18.0, step: 0.5) {
                Text("Image Size")
            }
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
                    .foregroundColor(showPrintSuccess ? .green : (showPrintFailed ? .red : .gray))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            
            HStack(spacing: 12) {
                if !autoBatchedPages.isEmpty {
                    Button(action: printAllBatchPages) {
                        if isPrinting {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Text("Print All Pages")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isPrinting)
                }
                
                Button(action: printCurrentPage) {
                    if isPrinting && autoBatchedPages.isEmpty {
                        ProgressView().scaleEffect(0.5)
                    } else {
                        let btnLabel = autoBatchedPages.isEmpty ? "Print Current Page" : "Print This Page"
                        Text(btnLabel)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(autoBatchedPages.isEmpty ? .blue : .gray)
                .disabled(isPrinting || (!autoBatchedPages.isEmpty && autoBatchedPages.isEmpty) || (autoBatchedPages.isEmpty && selectedImages.isEmpty))
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
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
    
    private func initializeApp() {
        // Find default project directory
        let defaultPath = "/Users/dan/Projects/photoprint"
        let url = URL(fileURLWithPath: defaultPath)
        if FileManager.default.fileExists(atPath: defaultPath) {
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
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedDirectory = url
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
    
    private func selectAllRedTags() {
        clearBatch()
        
        let redImgs = images.filter { $0.tag == "Red" && !$0.isPrinted }
        let allRedSelected = !redImgs.isEmpty && redImgs.allSatisfy { $0.isSelected }
        
        // Deselect if all are selected, otherwise add as many as fit
        if allRedSelected {
            images = images.map {
                var item = $0
                if item.tag == "Red" { item.isSelected = false }
                return item
            }
        } else {
            var selected = selectedImages
            for redImg in redImgs {
                if !redImg.isSelected && LayoutEngine.wouldFit(img: redImg, selected: selected, config: config) {
                    if let idx = images.firstIndex(where: { $0.id == redImg.id }) {
                        images[idx].isSelected = true
                        selected.append(images[idx])
                    }
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
        printStatusMessage = "Compositing image at 300 DPI..."
        showPrintSuccess = false
        showPrintFailed = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let layout = LayoutEngine.calculateLayout(images: imagesToPrint, config: self.config),
                  let compositeCgImage = ImageCompositor.buildComposite(images: imagesToPrint, config: self.config, layout: layout, dpi: 300.0, useThumbnails: false) else {
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
            
            guard ImageCompositor.saveTIFF(cgImage: compositeCgImage, to: tempUrl) else {
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            var successCount = 0
            var failedCount = 0
            
            for (index, pageImages) in pagesToPrint.enumerated() {
                DispatchQueue.main.async {
                    self.printStatusMessage = "Compositing page \(index + 1) of \(pagesToPrint.count)..."
                }
                
                guard let layout = LayoutEngine.calculateLayout(images: pageImages, config: self.config),
                      let compositeCgImage = ImageCompositor.buildComposite(images: pageImages, config: self.config, layout: layout, dpi: 300.0, useThumbnails: false) else {
                    failedCount += 1
                    continue
                }
                
                let tempDir = FileManager.default.temporaryDirectory
                let tempFilename = "photoprint_batch_\(index)_\(Int(Date().timeIntervalSince1970)).tiff"
                let tempUrl = tempDir.appendingPathComponent(tempFilename)
                
                guard ImageCompositor.saveTIFF(cgImage: compositeCgImage, to: tempUrl) else {
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
        .opacity(img.isPrinted ? 0.6 : (img.isSelected ? 1.0 : (wouldFit ? 1.0 : 0.4)))
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
    
    private func finderColor(_ tag: String) -> Color {
        switch tag {
        case "Red": return .red
        case "Orange": return .orange
        case "Yellow": return .yellow
        case "Green": return .green
        case "Blue": return .blue
        case "Purple": return .purple
        case "Gray": return .gray
        default: return .gray
        }
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
                    .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
                    .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No Layout Preview")
                        .foregroundColor(.gray)
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
        DispatchQueue.global(qos: .userInitiated).async {
            guard let layout = LayoutEngine.calculateLayout(images: images, config: config),
                  let cgImg = ImageCompositor.buildComposite(images: images, config: config, layout: layout, dpi: 72.0, useThumbnails: true) else {
                DispatchQueue.main.async {
                    self.previewImage = nil
                    self.isGenerating = false
                }
                return
            }
            
            let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
            DispatchQueue.main.async {
                self.previewImage = nsImg
                self.isGenerating = false
            }
        }
    }
}
