//
//  Program.swift
//  
//
//  Created by Lucas Tadeu Teixeira on 21/12/2021.
//
import Foundation
import ArgumentParser
import SwiftQOI
import CoreImage

struct Measurements {
    let imagePath: String
    var qoiDecodeTime: [Double] = []
    var qoiEncodeTime: [Double] = []
    var qoiSize: Int = 0
    var pngSize: Int = 0
    var rawSize: Int = 0
    var width: Int = 0
    var height: Int = 0
}

func generateBenchmarkEntry(_ measurements: Measurements) {
    print("<p><strong>\(measurements.imagePath)</strong> &nbsp; \(measurements.width)x\(measurements.height)</p>")
    
    print("<table>")
    print("  <thead>")
    print("  <tr>")
    
    print("    <th>decode time (ms)</th>")
    print("    <th>encode time (ms)</th>")
    print("    <th>png size (kb)</th>")
    print("    <th>qoi size (kb)</th>")
    print("    <th>raw size (kb)</th>")
    print("    <th>rate</th>")
    print("  </tr>")
    
    
    print("  </thead>")
    print("  <tbody>")
    print("  <tr>")
    
    print("<td>")
    print(String(format: "%.1f", measurements.qoiDecodeTime.reduce(0.0) { return $0 + $1/Double(measurements.qoiDecodeTime.count)}))
    print("</td>")
    
    print("<td>")
    print(String(format: "%.1f", measurements.qoiEncodeTime.reduce(0.0) { return $0 + $1/Double(measurements.qoiEncodeTime.count)}))
    print("</td>")
    print("    <td>\(measurements.pngSize / 1024)</td>")
    print("    <td>\(measurements.qoiSize / 1024)</td>")
    print("    <td>\(measurements.rawSize / 1024)</td>")
    
    let rate = String(format: "%.1f", Double(measurements.qoiSize) / Double(measurements.rawSize) * 100.0)
    print("    <td>\(rate)%</td>")
    print("  </tr>")
    
    
    print("  </tbody>")
    print("</table>")
}

func generateBenchmarkReport(_ results: [Measurements]) {
    print("<!doctype html>")
    print("<html><head><style>table { border: 1px solid #000; }</style></head><body>")
    print("<h1>SwiftQOI &mdash; Benchmarks</h1>")
    let date = Date()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "dd/MM/yyyy"
    print("Date: \(dateFormatter.string(from: date))")
    
    for m in results {
        generateBenchmarkEntry(m)
    }
    print("</body></html>")
}

var results: [Measurements] = []

@main
struct SwiftQOIBenchmark : ParsableCommand {
    @Argument(help: "Number of iterations to run")
    var iterations: Int
    
    @Argument(help: "Directory with benchmark images")
    var directory: String

    
    @Flag(help: "Don't descend into directories")
    var noRecurse = false
    

    mutating func run() throws {
        try forEachFile {url in benchmarkFile(url) }
        generateBenchmarkReport(results)
    }
    
    mutating func benchmarkFile(_ pngFileUrl: URL) {
        var measurements = Measurements(imagePath: pngFileUrl.relativePath)
        let pngData = try! Data(contentsOf: pngFileUrl)
        measurements.pngSize = pngData.count
        
        let qoiFileUrl = pngFileUrl.deletingPathExtension().appendingPathExtension("qoi")
        let qoiFileData = try! Data(contentsOf: qoiFileUrl)
                                    
        var image: Image = try! Image.decode(qoiFileData)
        
        for _ in 0..<iterations {
            let start = DispatchTime.now()
            image = try! Image.decode(qoiFileData)
            let end = DispatchTime.now()
            let elapsed = Double((end.uptimeNanoseconds - start.uptimeNanoseconds)) / 1_000_000.0
            measurements.qoiDecodeTime.append(elapsed)
        }
        
        var qoiEncodedData: Data = image.encode()
        
        for _ in 0..<iterations {
            let start = DispatchTime.now()
            qoiEncodedData = image.encode()
            let end = DispatchTime.now()
            let elapsed = Double((end.uptimeNanoseconds - start.uptimeNanoseconds)) / 1_000_000.0
            measurements.qoiEncodeTime.append(elapsed)
        }
        
        measurements.width = image.width
        measurements.height = image.height
        measurements.qoiSize = qoiEncodedData.count
        measurements.rawSize = image.pixels.count
        results.append(measurements)
    }
    
    
    func forEachFile(_ action: (URL) -> Void) throws {
        let fileManager = FileManager.default
        let directoryUrl = URL(fileURLWithPath: directory)
        
        var options : FileManager.DirectoryEnumerationOptions = [ .skipsHiddenFiles]

        if noRecurse {
            options.insert(.skipsSubdirectoryDescendants)
        }
        
        var queue = [directoryUrl]
        while !queue.isEmpty {
            let currentDir = queue.removeFirst()
            
            let fileUrls = try fileManager.contentsOfDirectory(at: currentDir, includingPropertiesForKeys: [.isDirectoryKey], options: options)

            for file in fileUrls {
                let fileAttributes = try file.resourceValues(forKeys: [.isDirectoryKey])

                if fileAttributes.isDirectory ?? false {
                    queue.append(file)
                } else if file.pathExtension == "png" {
                    action(file)
                }
            }
        }
    }
}
