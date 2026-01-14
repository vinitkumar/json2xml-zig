# Benchmarks: json2xml Performance Comparison

This document presents comprehensive benchmarks comparing the Zig, Go, and Python implementations of json2xml.

## Test Environment

- **Machine**: Apple Silicon Mac
- **Zig Version**: 0.15.2
- **Go Version**: 1.23+
- **Python Version**: 3.12+
- **Iterations**: 10 runs per test (with 2 warmup runs)

## Test Data

| Dataset | Size | Description |
|---------|------|-------------|
| Small | 47 bytes | Simple object: `{"name": "John", "age": 30, "city": "New York"}` |
| Medium | 2,598 bytes | Real-world patent data (bigexample.json) |
| Large | 323,122 bytes | 1,000 generated records with nested objects |
| Very Large | 1,619,980 bytes | 5,000 generated records with nested objects |

## Results

### Raw Performance Numbers

| Test Case | Python | Go | Zig |
|-----------|--------|-----|-----|
| **Small JSON** | 68.88ms | 7.13ms | **2.65ms** |
| **Medium JSON** | 73.40ms | 4.85ms | **2.13ms** |
| **Large JSON** | 420.06ms | 68.88ms | **5.90ms** |
| **Very Large JSON** | 2,083ms | 288.75ms | **20.62ms** |

### Speedup vs Python

| Test Case | Go | Zig |
|-----------|-----|-----|
| Small | 9.7x | **26.0x** |
| Medium | 15.1x | **34.4x** |
| Large | 6.1x | **71.2x** |
| Very Large | 7.2x | **101.1x** |
| **Overall** | 7.2x | **84.5x** |

### Speedup: Zig vs Go

| Test Case | Zig Speedup |
|-----------|-------------|
| Small | 2.7x |
| Medium | 2.3x |
| Large | 11.7x |
| Very Large | 14.0x |
| **Overall** | **11.8x** |

## Analysis

### Why is Zig so fast?

1. **Zero-cost abstractions**: Zig compiles to highly optimized machine code with no runtime overhead.

2. **No garbage collection**: Unlike Go, Zig uses explicit memory management, avoiding GC pauses.

3. **Compile-time evaluation**: Many operations are resolved at compile time.

4. **Small binary size**: The Zig binary is ~180KB vs Go's ~2MB, leading to faster startup.

5. **Efficient string handling**: Direct memory manipulation without intermediate allocations.

### Scaling Behavior

The performance advantage of Zig increases dramatically with data size:

```
Small (47B):      Zig is 26x faster than Python
Medium (2.6KB):   Zig is 34x faster than Python  
Large (323KB):    Zig is 71x faster than Python
Very Large (1.6MB): Zig is 101x faster than Python
```

This demonstrates that Zig's efficiency becomes more pronounced as the workload increases, making it ideal for processing large JSON files.

### Memory Efficiency

While not measured in detail, Zig's explicit memory management typically results in:
- Lower peak memory usage
- More predictable memory patterns
- No GC-related memory spikes

## Reproducing the Benchmarks

```bash
# Clone the repository
git clone https://github.com/vinitkumar/json2xml-zig.git
cd json2xml-zig

# Build the optimized Zig binary
zig build -Doptimize=ReleaseFast

# Install Python json2xml
pip install json2xml

# Build Go version (optional)
cd ~/projects/go/json2xml-go && make build
cd -

# Run benchmarks
python3 benchmark.py
```

## Conclusion

For applications requiring JSON to XML conversion:

| Use Case | Recommended |
|----------|-------------|
| Maximum performance | **Zig** |
| Balance of speed and ease | Go |
| Rapid prototyping | Python |
| Processing large files | **Zig** (up to 100x faster) |
| Embedded/constrained systems | **Zig** (smallest binary) |

The Zig implementation provides exceptional performance, making it the ideal choice for high-throughput data processing pipelines and performance-critical applications.
