import Foundation
import CoreGraphics
import PDFKit

// Usage: pdf-render <file.pdf> [<png-out> <dpi>] — prints the page count, media box,
// fonts (embedded or not), images and text; with an output path, renders the page.
let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path)
guard let doc = CGPDFDocument(url as CFURL) else { print("cannot open"); exit(1) }
print("pages:", doc.numberOfPages)
let page = doc.page(at: 1)!
let mb = page.getBoxRect(.mediaBox)
print("mediaBox:", mb)
var seen = Set<String>()
var images: [String] = []
func walk(_ res: CGPDFDictionaryRef, depth: Int) {
    var fonts: CGPDFDictionaryRef?
    if CGPDFDictionaryGetDictionary(res, "Font", &fonts), let fonts {
        CGPDFDictionaryApplyBlock(fonts, { _, obj, _ in
            var fd: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(obj, .dictionary, &fd), let fd else { return true }
            var name: UnsafePointer<CChar>?
            CGPDFDictionaryGetName(fd, "BaseFont", &name)
            var sub: UnsafePointer<CChar>?
            CGPDFDictionaryGetName(fd, "Subtype", &sub)
            var target = fd
            var arr: CGPDFArrayRef?
            var kind = ""
            if CGPDFDictionaryGetArray(fd, "DescendantFonts", &arr), let arr {
                var d: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(arr, 0, &d), let d { target = d; kind = " Type0" }
            }
            var desc: CGPDFDictionaryRef?
            var embedded = "NOT EMBEDDED"
            if CGPDFDictionaryGetDictionary(target, "FontDescriptor", &desc), let desc {
                var s: CGPDFStreamRef?
                if CGPDFDictionaryGetStream(desc, "FontFile2", &s) { embedded = "embedded FontFile2" }
                else if CGPDFDictionaryGetStream(desc, "FontFile3", &s) { embedded = "embedded FontFile3" }
                else if CGPDFDictionaryGetStream(desc, "FontFile", &s) { embedded = "embedded FontFile" }
            } else if sub.map({ String(cString: $0) }) == "Type3" { embedded = "Type3 (glyph procs)" }
            let line = "font \(name.map { String(cString: $0) } ?? "?") \(sub.map { String(cString: $0) } ?? "?")\(kind) \(embedded)"
            if seen.insert(line).inserted { print(line) }
            return true
        }, nil)
    }
    var xobjs: CGPDFDictionaryRef?
    if CGPDFDictionaryGetDictionary(res, "XObject", &xobjs), let xobjs {
        CGPDFDictionaryApplyBlock(xobjs, { _, obj, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(obj, .stream, &stream), let stream, let sd = CGPDFStreamGetDictionary(stream) else { return true }
            var sub: UnsafePointer<CChar>?
            CGPDFDictionaryGetName(sd, "Subtype", &sub)
            let s = sub.map { String(cString: $0) } ?? "?"
            if s == "Image" {
                var w: CGPDFInteger = 0, h: CGPDFInteger = 0
                CGPDFDictionaryGetInteger(sd, "Width", &w); CGPDFDictionaryGetInteger(sd, "Height", &h)
                images.append("\(w)x\(h)")
            } else if s == "Form" {
                var r: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(sd, "Resources", &r), let r { walk(r, depth: depth + 1) }
            }
            return true
        }, nil)
    }
}
if let dict = page.dictionary {
    var res: CGPDFDictionaryRef?
    if CGPDFDictionaryGetDictionary(dict, "Resources", &res), let res { walk(res, depth: 0) }
}
print("images:", images)
if let pdf = PDFDocument(url: url), let p = pdf.page(at: 0) {
    print("text:", (p.string ?? "").replacingOccurrences(of: "\n", with: " | "))
}
if CommandLine.arguments.count > 3 {
    let out = CommandLine.arguments[2]
    let dpi = Double(CommandLine.arguments[3])!
    let scale = dpi / 72
    let w = Int((mb.width * scale).rounded()), h = Int((mb.height * scale).rounded())
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -mb.minX, y: -mb.minY)
    ctx.drawPDFPage(page)
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    CGImageDestinationFinalize(dest)
    print("wrote", out, w, "x", h)
}
