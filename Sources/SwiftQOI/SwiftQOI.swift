import Foundation

fileprivate struct Pixel : Equatable {
    var r : UInt8 = 0
    var g : UInt8 = 0
    var b : UInt8 = 0
    var a : UInt8 = 255
    
    func hash() -> Int {
        return (Int(r) * 3 + Int(g) * 5 + Int(b) * 7 + Int(a) * 11) % 64
    }
    
    static func == (lhs: Pixel, rhs: Pixel) -> Bool {
        return (
            lhs.r == rhs.r &&
            lhs.g == rhs.g &&
            lhs.b == rhs.b &&
            lhs.a == rhs.a
        )
    }
}

fileprivate let HEADER_SIZE = 14
fileprivate let END_MARKER: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 1]
fileprivate let END_MARKER_SIZE = END_MARKER.count
fileprivate let QOI_TAG_2BIT_MASK: UInt8 = 0b11000000
fileprivate let MAGIC_NUMBER:  UInt32 = 0x716F6966
fileprivate let QOI_TAG_RGB:   UInt8  = 0xfe
fileprivate let QOI_TAG_RGBA:  UInt8  = 0xff
fileprivate let QOI_TAG_INDEX: UInt8  = 0x00
fileprivate let QOI_TAG_DIFF:  UInt8  = 0x40
fileprivate let QOI_TAG_LUMA:  UInt8  = 0x80
fileprivate let QOI_TAG_RUN:   UInt8  = 0xc0


public enum Colorspace {
    case srgbLinearAlpha, allChannelsLinear, other(UInt8)
}

public class Image {
    public let width: Int
    public let height: Int
    public let channels: Int
    public let colorspace: Colorspace
    public var pixels : [UInt8]
    
    init(width: Int, height: Int, channels: Int, colorspace: UInt8) {
        self.width = width
        self.height = height
        self.channels = channels
        
        switch colorspace {
        case 3:
            self.colorspace = .srgbLinearAlpha
        case 4:
            self.colorspace = .srgbLinearAlpha
        default:
            self.colorspace = .other(colorspace)
        }
        
        self.pixels = [UInt8](repeating: 255, count: channels * width * height)
    }

}

public enum DecodeError : Error {
    case notEnoughData
    case badEndMarker
    case badMagicNumber
}

public extension Image {
    static func decode(_ data: Data) throws -> Image {
        try data.withUnsafeBytes { rawBufferPointer in
            try decode(rawBufferPointer)
        }
    }
    
    static func decode(_ rawBufferPointer: UnsafeRawBufferPointer) throws -> Image {
        let length = rawBufferPointer.count
        
        if length < (HEADER_SIZE + END_MARKER_SIZE) {
            throw DecodeError.notEnoughData
        }

        var rawPointer = UnsafeMutableRawPointer(mutating: rawBufferPointer.baseAddress!)
    
        let magic = rawPointer.readUInt32().byteSwapped
        if magic != MAGIC_NUMBER {
            throw DecodeError.badMagicNumber
        }
        
        let image = Image(
            width: Int(rawPointer.readUInt32().byteSwapped),
            height: Int(rawPointer.readUInt32().byteSwapped),
            channels: Int(rawPointer.readUInt8()),
            colorspace: rawPointer.readUInt8()
        )
    
        var index = [Pixel](repeating: Pixel(r: 0, g: 0, b: 0, a: 0), count: 64)
        let pixelsLen = image.pixels.count
        
        var previousPixel = Pixel(r: 0, g: 0, b: 0, a: 255)
        var pixelPos = 0
        var runLength = 0

        while pixelPos < pixelsLen {
            if (runLength > 0) {
                runLength -= 1
            } else {
                // Read the tag
                let tag = rawPointer.readUInt8()
                
                if tag == QOI_TAG_RGB { // RGB color
                    previousPixel.r = rawPointer.readUInt8()
                    previousPixel.g = rawPointer.readUInt8()
                    previousPixel.b = rawPointer.readUInt8()
                } else if tag == QOI_TAG_RGBA { // RGBA color
                    previousPixel.r = rawPointer.readUInt8()
                    previousPixel.g = rawPointer.readUInt8()
                    previousPixel.b = rawPointer.readUInt8()
                    previousPixel.a = rawPointer.readUInt8()
                } else {
                    // Reference to handle overflow
                    // https://developer.apple.com/documentation/swift/swift_standard_library/operator_declarations
                    switch (tag & QOI_TAG_2BIT_MASK) {
                    case QOI_TAG_INDEX: // Op index
                        previousPixel = index[Int(tag)]
                    case QOI_TAG_DIFF: // Diff
                        previousPixel.r &+= ((tag >> 4) & 0x3) &- 2
                        previousPixel.g &+= ((tag >> 2) & 0x3) &- 2
                        previousPixel.b &+= (tag        & 0x3) &- 2
                    case QOI_TAG_LUMA: // Luma
                        let nextByte = rawPointer.readUInt8()
                        let dg = (tag & 0x3f) &- 32
                        
                        previousPixel.r &+= (dg &- 8) &+ ((nextByte >> 4) & 0x0f)
                        previousPixel.g &+= dg
                        previousPixel.b &+= (dg &- 8) &+ (nextByte & 0x0f)
                    case QOI_TAG_RUN: // Run
                        runLength = Int(tag & 0x3f)
                    default:
                        fatalError("Unreachable")
                    }
                }
                index[previousPixel.hash()] = previousPixel
            }
            
            image.pixels[pixelPos]     = previousPixel.r
            image.pixels[pixelPos + 1] = previousPixel.g
            image.pixels[pixelPos + 2] = previousPixel.b
            
            if image.channels == 4 {
                image.pixels[pixelPos + 3] = previousPixel.a
            }
            
            pixelPos += image.channels
        }
        return image
    }
    
    func encode() -> Data {
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: HEADER_SIZE + END_MARKER_SIZE + width * height * channels)
        let baseAddress = buffer.baseAddress!
        var rawPointer = UnsafeMutableRawPointer(buffer.baseAddress!)
        let startPointer = rawPointer
        
        rawPointer.writeUInt32(MAGIC_NUMBER.byteSwapped)
        rawPointer.writeUInt32(UInt32(width).byteSwapped)
        rawPointer.writeUInt32(UInt32(height).byteSwapped)
        rawPointer.writeUInt8(UInt8(channels))
        
        switch colorspace {
        case .srgbLinearAlpha:
            rawPointer.writeUInt8(0)
        case .allChannelsLinear:
            rawPointer.writeUInt8(1)
        case .other(let value):
            rawPointer.writeUInt8(value)
        }
        
        var table = [Pixel](repeating: Pixel(r: 0, g: 0, b: 0, a:0), count: 64)
        var run = 0
        let pixelsLength = pixels.count
        let pixelsEnd = pixelsLength - channels
        var previousPixel = Pixel(r: 0, g: 0, b: 0, a: 255)
        var currentPixel = Pixel(r: 0, g: 0, b: 0, a: 255)
        
        for pixelPos in stride(from: 0, to: pixelsLength, by: channels) {
            currentPixel.r = pixels[pixelPos]
            currentPixel.g = pixels[pixelPos + 1]
            currentPixel.b = pixels[pixelPos + 2]

            if channels == 4 {
                currentPixel.a = pixels[pixelPos + 3]
            }
            
            if previousPixel == currentPixel {
                run += 1
                
                if (run == 62) || (pixelPos == pixelsEnd) {
                    rawPointer.writeUInt8(QOI_TAG_RUN | UInt8(run - 1))
                    run = 0
                }
            } else {
                if run > 0 {
                    rawPointer.writeUInt8(QOI_TAG_RUN | UInt8(run - 1))
                    run = 0
                }
                
                let index = currentPixel.hash()
                
                if table[index] == currentPixel {
                    rawPointer.writeUInt8(QOI_TAG_INDEX | UInt8(index))
                } else {
                    table[index] = currentPixel
                    
                    if (currentPixel.a == previousPixel.a) {
                        let vr = Int8(bitPattern: currentPixel.r &- previousPixel.r)
                        let vg = Int8(bitPattern: currentPixel.g &- previousPixel.g)
                        let vb = Int8(bitPattern: currentPixel.b &- previousPixel.b)

                        let vg_r = vr &- vg
                        let vg_b = vb &- vg
                        
                        if vr > -3 && vr < 2 &&
                           vg > -3 && vg < 2 &&
                           vb > -3 && vb < 2 {
                            let tag = QOI_TAG_DIFF | UInt8(bitPattern: vr + 2) << 4 | (UInt8(bitPattern: vg + 2) << 2) | UInt8(bitPattern: vb + 2)
                            rawPointer.writeUInt8(tag)
                            
                        } else if vg_r > -9 && vg_r < 8 && vg > -33 && vg < 32 && vg_b > -9 && vg_b < 8 {
                            rawPointer.writeUInt8(QOI_TAG_LUMA | UInt8(bitPattern: vg + 32))
                            rawPointer.writeUInt8((UInt8(bitPattern: vg_r + 8) << 4) | UInt8(bitPattern: vg_b + 8))
                        } else {
                            rawPointer.writeUInt8(QOI_TAG_RGB)
                            rawPointer.writeUInt8(currentPixel.r)
                            rawPointer.writeUInt8(currentPixel.g)
                            rawPointer.writeUInt8(currentPixel.b)
                        }
                    } else {
                        rawPointer.writeUInt8(QOI_TAG_RGBA)
                        rawPointer.writeUInt8(currentPixel.r)
                        rawPointer.writeUInt8(currentPixel.g)
                        rawPointer.writeUInt8(currentPixel.b)
                        rawPointer.writeUInt8(currentPixel.a)
                    }
                }
            }
            
            previousPixel = currentPixel
        }
        
        // storeBytes requires the pointer to be aligned for the type you're trying to store.
        // This fails at debug time: https://forums.swift.org/t/unsafemutablerawpointer-binding-and-alignment/36021/3
        for byte in END_MARKER {
            rawPointer.writeUInt8(byte)
        }
        
        let numBytes = rawPointer - startPointer
        return Data(bytes: baseAddress, count: numBytes)
    }
}

fileprivate extension UnsafeMutableRawPointer {
    mutating func writeUInt8(_ value: UInt8) {
        self.storeBytes(of: value, as: UInt8.self)
        self += 1
    }
    
    mutating func writeUInt32(_ value: UInt32) {
        self.storeBytes(of: value, as: UInt32.self)
        self += 4
    }
    
    mutating func readUInt8() -> UInt8 {
        let value = self.load(as: UInt8.self)
        self += 1
        return value
    }
    
    mutating func readUInt32() -> UInt32 {
        let value = self.load(as: UInt32.self)
        self += 4
        return value
    }
}
