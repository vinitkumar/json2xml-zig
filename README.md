# json2xml-zig

A blazing-fast JSON to XML converter written in Zig. This is a port of the Python [json2xml](https://github.com/vinitkumar/json2xml) library, designed for maximum performance.

## Performance

**json2xml-zig is up to 100x faster than Python and 14x faster than Go.**

### Benchmark Results

| Test Case | Python | Go | Zig | Zig vs Python | Zig vs Go |
|-----------|--------|-----|-----|---------------|-----------|
| **Small JSON** (47 bytes) | 68.88ms | 7.13ms | 2.65ms | 26.0x faster | 2.7x faster |
| **Medium JSON** (2.6 KB) | 73.40ms | 4.85ms | 2.13ms | 34.4x faster | 2.3x faster |
| **Large JSON** (323 KB) | 420.06ms | 68.88ms | 5.90ms | 71.2x faster | 11.7x faster |
| **Very Large JSON** (1.6 MB) | 2.08s | 288.75ms | 20.62ms | 101.1x faster | 14.0x faster |

**Overall: Zig is 84.5x faster than Python and 11.8x faster than Go**

## Installation

### Prerequisites

- [Zig](https://ziglang.org/download/) 0.15.0 or later

### Build from source

```bash
git clone https://github.com/vinitkumar/json2xml-zig.git
cd json2xml-zig
zig build -Doptimize=ReleaseFast
```

The binary will be available at `./zig-out/bin/json2xml-zig`.

### Install to system

```bash
sudo cp ./zig-out/bin/json2xml-zig /usr/local/bin/
```

## Usage

### Command Line

```bash
# Convert a JSON file to XML
json2xml-zig data.json

# Convert with custom wrapper element
json2xml-zig -w root data.json

# Read from string
json2xml-zig -s '{"name": "John", "age": 30}'

# Read from stdin
cat data.json | json2xml-zig -

# Output to file
json2xml-zig -o output.xml data.json

# Use XPath 3.1 json-to-xml format
json2xml-zig -x data.json

# Disable pretty printing
json2xml-zig -p=false data.json

# Disable type attributes
json2xml-zig -t=false data.json
```

### Options

```
Input Options:
  -s, --string string     Read JSON from string
  [input-file]            Read JSON from file (use - for stdin)

Output Options:
  -o, --output string     Output file (default: stdout)

Conversion Options:
  -w, --wrapper string    Wrapper element name (default "all")
  -r, --root=bool         Include root element (default true)
  -p, --pretty=bool       Pretty print output (default true)
  -t, --type=bool         Include type attributes (default true)
  -i, --item-wrap=bool    Wrap list items in <item> elements (default true)
  -x, --xpath             Use XPath 3.1 json-to-xml format
  -c, --cdata             Wrap string values in CDATA sections
  -l, --list-headers      Repeat headers for each list item
  -h, --help              Show help message
```

### Examples

#### Basic Conversion

```bash
$ json2xml-zig -s '{"name": "John", "age": 30}'
```

Output:
```xml
<?xml version="1.0" encoding="UTF-8" ?>
<all>
  <name type="str">John</name>
  <age type="int">30</age>
</all>
```

#### Without Type Attributes

```bash
$ json2xml-zig -t=false -s '{"name": "John", "age": 30}'
```

Output:
```xml
<?xml version="1.0" encoding="UTF-8" ?>
<all>
  <name>John</name>
  <age>30</age>
</all>
```

#### Arrays

```bash
$ json2xml-zig -s '{"colors": ["red", "green", "blue"]}'
```

Output:
```xml
<?xml version="1.0" encoding="UTF-8" ?>
<all>
  <colors type="list">
    <item type="str">red</item>
    <item type="str">green</item>
    <item type="str">blue</item>
  </colors>
</all>
```

#### XPath 3.1 Format

```bash
$ json2xml-zig -x -s '{"name": "John", "age": 30}'
```

Output:
```xml
<?xml version="1.0" encoding="UTF-8" ?>
<map xmlns="http://www.w3.org/2005/xpath-functions">
  <string key="name">John</string>
  <number key="age">30</number>
</map>
```

## Library Usage

You can also use json2xml-zig as a library in your Zig projects:

```zig
const std = @import("std");
const json2xml = @import("json2xml.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json_str = "{\"name\": \"John\", \"age\": 30}";
    
    var parsed = try std.json.parseFromSlice(
        std.json.Value, 
        allocator, 
        json_str, 
        .{}
    );
    defer parsed.deinit();

    const options = json2xml.Options{
        .wrapper = "root",
        .pretty = true,
        .attr_type = true,
    };

    const xml = try json2xml.toXml(allocator, parsed.value, options);
    defer allocator.free(xml);

    std.debug.print("{s}\n", .{xml});
}
```

## Running Benchmarks

The benchmark compares json2xml-zig against the Python and Go implementations:

```bash
# Install Python json2xml first
pip install json2xml

# Build Go version (if you have it)
cd ~/projects/go/json2xml-go && make build

# Run benchmark
python3 benchmark.py
```

## Related Projects

- [json2xml](https://github.com/vinitkumar/json2xml) - The original Python implementation
- [json2xml-go](https://github.com/vinitkumar/json2xml-go) - Go implementation

## License

MIT License - see LICENSE file for details.

## Author

Vinit Kumar <mail@vinitkumar.me>
