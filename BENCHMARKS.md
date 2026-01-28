# Benchmarks: json2xml Performance Comparison

This document presents comprehensive benchmarks comparing the Zig, Go, Rust, and Python implementations of json2xml.

## Test Environment

- **Machine**: Apple Silicon Mac (M-series, aarch64)
- **Zig Version**: 0.15.2
- **Go Version**: 1.23+
- **Python Version**: 3.14
- **Date**: January 28, 2026
- **Iterations**: 10-50 runs per test (with 2 warmup runs)

## Test Data

| Dataset | Size | Description |
|---------|------|-------------|
| Small | 47 bytes | Simple object: `{"name": "John", "age": 30, "city": "New York"}` |
| Medium | ~3,208 bytes | 10 generated records with nested structures |
| bigexample | 2,018 bytes | Real-world patent data |
| Large | ~32,205 bytes | 100 generated records with nested objects |
| Very Large | ~323,119 bytes | 1,000 generated records with nested objects |

## Results

### Raw Performance Numbers

| Test Case | Python | Rust | Go | Zig |
|-----------|--------|------|-----|-----|
| **Small (47B)** | 41.88µs | 1.66µs | 4.52ms | 2.80ms |
| **Medium (3.2KB)** | 2.19ms | 71.85µs | 4.33ms | 2.18ms |
| **bigexample (2KB)** | 854.38µs | 30.89µs | 4.28ms | 2.12ms |
| **Large (32KB)** | 21.57ms | 672.96µs | 4.47ms | 2.48ms |
| **Very Large (323KB)** | 216.52ms | 6.15ms | 4.44ms | 5.54ms |

### Speedup vs Python

| Test Case | Rust | Go | Zig |
|-----------|------|-----|-----|
| Small | 25.2x | 0.0x* | 0.0x* |
| Medium | 30.5x | 0.5x* | 1.0x* |
| bigexample | 27.7x | 0.2x* | 0.4x* |
| Large | **32.1x** | 4.8x | **8.7x** |
| Very Large | **35.2x** | **48.8x** | **39.1x** |

*Process spawn overhead dominates for small inputs

### CLI Performance: Zig vs Go

For CLI tools, the key comparison is Zig vs Go:

| Test Case | Go | Zig | Zig Advantage |
|-----------|-----|-----|---------------|
| Small | 4.52ms | **2.80ms** | 1.6x faster startup |
| Medium | 4.33ms | **2.18ms** | 2.0x faster |
| bigexample | 4.28ms | **2.12ms** | 2.0x faster |
| Large | 4.47ms | **2.48ms** | 1.8x faster |
| Very Large | **4.44ms** | 5.54ms | Go 1.2x faster |

## Analysis

### Why is Zig Fast?

1. **Arena Allocator**: Uses bulk allocation for JSON parsing, avoiding per-object allocation overhead.

2. **Optimized String Escaping**: Writes spans of safe characters at once instead of byte-by-byte.

3. **Pre-allocated Output Buffer**: Estimates output size based on input, reducing reallocations.

4. **Zero-cost abstractions**: Compiles to highly optimized machine code with no runtime overhead.

5. **No garbage collection**: Explicit memory management avoids GC pauses.

6. **Small binary size**: ~180KB vs Go's ~2MB, leading to faster startup.

### Recent Optimizations (v2.0)

The following optimizations improved performance by 6x for large files:

1. **Arena Allocator** - Replaced GeneralPurposeAllocator with ArenaAllocator for JSON parsing
2. **Capacity Hints** - Pre-allocate output buffer based on estimated XML size (2-3x input)
3. **Span-based Escaping** - Write safe character spans in bulk instead of per-character
4. **Efficient Indentation** - Use `writeByteNTimes` instead of loop

### Performance Characteristics

| Metric | Zig | Go |
|--------|-----|-----|
| Startup overhead | ~2ms | ~4ms |
| Large file throughput | Excellent | Excellent |
| Memory efficiency | Better (no GC) | Good |
| Binary size | ~180KB | ~2MB |

### When to Use Each

| Use Case | Recommended | Why |
|----------|-------------|-----|
| Python library calls | **Rust** | 25-35x faster, no process overhead |
| Small files via CLI | **Zig** | Fastest startup (~2ms) |
| Very large files | **Go** or **Zig** | Both excellent, Go slightly faster |
| Embedded systems | **Zig** | Smallest binary, no runtime |

## Reproducing the Benchmarks

```bash
# Clone the repository
git clone https://github.com/vinitkumar/json2xml-zig.git
cd json2xml-zig

# Build the optimized Zig binary
zig build -Doptimize=ReleaseFast

# Install to PATH
cp zig-out/bin/json2xml-zig ~/.local/bin/

# Run comprehensive benchmarks (from json2xml Python repo)
cd ~/projects/python/json2xml
python benchmark_all.py
```

## Related Projects

- **Python + Rust**: [github.com/vinitkumar/json2xml](https://github.com/vinitkumar/json2xml)
- **Go version**: [github.com/vinitkumar/json2xml-go](https://github.com/vinitkumar/json2xml-go)
