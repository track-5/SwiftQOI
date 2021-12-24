# SwiftQOI

This package implements an encoder and a decoder for the [QOI image format](https://qoiformat.org).

## Usage

### Read a QOI image file

```swift
import SwiftQOI

let imageFilePath = ...

let image = Image.decode(Data(contentsOf: imageFilePath))
```

### Write a QOI image to a file

```swift
import SwiftQOI

let imageFilePath = ...

image.encode().write(toFile: imageFilePath)
```

## Benchmarks

Benchmarks were run against the images available at https://qoiformat.org/benchmark/

To run the benchmarks, run the command below:

```
swift build --product SwiftQOIBenchmark -c release

./.build/release/SwiftQOIBenchmark <iterations> <path to images directory>
```

The `benchmark.html` file in this repository was generated on a MacBook Pro 14" (2021)
with an Apple M1 Pro chip (8-CPU cores and 16GB RAM).
