import Cocoa
import ImageIO
import UniformTypeIdentifiers

struct ImageCompositor {
    
    // Fetch dimensions and Finder tags for a given image file
    static func getDimensionsAndTag(url: URL) -> (width: CGFloat, height: CGFloat, tag: String?)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        
        let propertiesOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, propertiesOptions) as? [CFString: Any] else {
            return nil
        }
        
        guard let widthNum = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let heightNum = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }
        
        var width = CGFloat(widthNum.doubleValue)
        var height = CGFloat(heightNum.doubleValue)
        
        // Adjust for EXIF orientation
        if let orientationNum = properties[kCGImagePropertyOrientation] as? NSNumber {
            let orientation = orientationNum.intValue
            // Orientations 5, 6, 7, 8 mean the image is rotated by 90 or 270 degrees
            if orientation >= 5 && orientation <= 8 {
                let temp = width
                width = height
                height = temp
            }
        }
        
        // Read Finder tags (from com.apple.metadata:_kMDItemUserTags)
        var tag: String? = nil
        if let values = try? url.resourceValues(forKeys: [.tagNamesKey]),
           let tags = values.tagNames {
            let validTags = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"]
            tag = tags.first(where: { validTags.contains($0) })
        }
        
        return (width, height, tag)
    }
    
    // Load a CGImage, optionally as a thumbnail, and respect EXIF orientation
    private static func loadOrientedImage(url: URL, maxPixelSize: CGFloat?) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        
        if let maxSize = maxPixelSize {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxSize
        } else {
            // Get original size to load at full resolution while applying transform
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let widthNum = properties[kCGImagePropertyPixelWidth] as? NSNumber,
               let heightNum = properties[kCGImagePropertyPixelHeight] as? NSNumber {
                var width = CGFloat(widthNum.doubleValue)
                var height = CGFloat(heightNum.doubleValue)
                
                // Read orientation to determine max size if rotated
                if let orientationNum = properties[kCGImagePropertyOrientation] as? NSNumber {
                    let orientation = orientationNum.intValue
                    if orientation >= 5 && orientation <= 8 {
                        let temp = width
                        width = height
                        height = temp
                    }
                }
                options[kCGImageSourceThumbnailMaxPixelSize] = max(width, height)
            }
        }
        
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
    
    // Build the composite layout
    static func buildComposite(images: [ImageFile], config: PrintConfig, layout: LayoutResult, dpi: CGFloat, useThumbnails: Bool) -> CGImage? {
        let pw = Int(round(config.paperW * dpi))
        let ph = Int(round(config.paperH * dpi))
        
        guard pw > 0, ph > 0 else { return nil }
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: pw,
                                      height: ph,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 4 * pw,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        
        // Fill white background
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
        
        // Convert layout items into pixels
        var rowItems = [[(image: CGImage, w: CGFloat, h: CGFloat, rotate: Bool)]]()
        var rowHeightsPixels = [CGFloat]()
        
        for row in layout.rows {
            var preparedRow = [(image: CGImage, w: CGFloat, h: CGFloat, rotate: Bool)]()
            for item in row {
                let img = item.img
                
                // Determine if we need to rotate 90 degrees counter-clockwise
                let rotate = layout.orientation == "landscape"
                    ? (img.height > img.width)
                    : (img.width > img.height)
                
                let tw = item.w * dpi
                
                // Load the image. If using thumbnails, scale down for performance
                let maxLoadSize: CGFloat? = useThumbnails ? (max(item.w, item.h) * dpi) : nil
                guard let cgImg = loadOrientedImage(url: img.url, maxPixelSize: maxLoadSize) else {
                    continue
                }
                
                let drawW = tw
                let drawH = item.h * dpi
                
                preparedRow.append((image: cgImg, w: drawW, h: drawH, rotate: rotate))
            }
            
            rowItems.append(preparedRow)
            let maxH = preparedRow.map { $0.h }.max() ?? 0
            rowHeightsPixels.append(maxH)
        }
        
        let totalRowsHPixels = rowHeightsPixels.reduce(0, +)
        let vertGap = CGFloat(ph - Int(totalRowsHPixels)) / CGFloat(rowItems.count + 1)
        
        var y: CGFloat = vertGap
        
        for r in 0..<rowItems.count {
            let row = rowItems[r]
            let rowH = rowHeightsPixels[r]
            let rowWidthPixels = row.reduce(0) { $0 + $1.w }
            let horizGap = CGFloat(pw - Int(rowWidthPixels)) / CGFloat(row.count + 1)
            
            var x = horizGap
            for item in row {
                let yCentered = y + (rowH - item.h) / 2.0
                
                // Convert top-left coordinates (x, yCentered) to bottom-left coordinates (x, yBL)
                let yBL = CGFloat(ph) - yCentered - item.h
                let rect = CGRect(x: x, y: yBL, width: item.w, height: item.h)
                
                context.saveGState()
                if item.rotate {
                    // Rotate -90 degrees around rect center
                    context.translateBy(x: rect.midX, y: rect.midY)
                    context.rotate(by: -CGFloat.pi / 2.0)
                    
                    // In the rotated system, swap width and height
                    let drawRect = CGRect(x: -rect.height / 2.0, y: -rect.width / 2.0, width: rect.height, height: rect.width)
                    context.draw(item.image, in: drawRect)
                } else {
                    context.draw(item.image, in: rect)
                }
                context.restoreGState()
                
                x += item.w + horizGap
            }
            y += rowH + vertGap
        }
        
        return context.makeImage()
    }
    
    // Save high-resolution composite to TIFF file at 300 DPI
    static func saveTIFF(cgImage: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil) else {
            return false
        }
        
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 300.0,
            kCGImagePropertyDPIHeight: 300.0
        ]
        
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
