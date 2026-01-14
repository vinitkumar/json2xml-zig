const std = @import("std");
const json2xml = @import("json2xml.zig");

const CliOptions = struct {
    input_string: ?[]const u8 = null,
    input_file: ?[]const u8 = null,
    output_file: ?[]const u8 = null,
    wrapper: []const u8 = "all",
    root: bool = true,
    pretty: bool = true,
    attr_type: bool = true,
    item_wrap: bool = true,
    xpath_format: bool = false,
    cdata: bool = false,
    list_headers: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse args and keep them alive until we're done
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var opts = CliOptions{};
    parseArgs(args, &opts);

    const input_data = try readInput(allocator, opts);
    defer allocator.free(input_data);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, input_data, .{});
    defer parsed.deinit();

    const xml_options = json2xml.Options{
        .wrapper = opts.wrapper,
        .root = opts.root,
        .pretty = opts.pretty,
        .attr_type = opts.attr_type,
        .item_wrap = opts.item_wrap,
        .xpath_format = opts.xpath_format,
        .cdata = opts.cdata,
        .list_headers = opts.list_headers,
    };

    const output = try json2xml.toXml(allocator, parsed.value, xml_options);
    defer allocator.free(output);

    try writeOutput(output, opts);
}

fn parseArgs(args: [][:0]u8, opts: *CliOptions) void {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--string")) {
            if (i + 1 < args.len) {
                opts.input_string = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            if (i + 1 < args.len) {
                opts.output_file = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--wrapper")) {
            if (i + 1 < args.len) {
                opts.wrapper = args[i + 1];
                i += 1;
            }
        } else if (std.mem.startsWith(u8, arg, "-r=") or std.mem.startsWith(u8, arg, "--root=")) {
            opts.root = parseBool(arg[argIndex(arg, '=') + 1 ..]);
        } else if (std.mem.startsWith(u8, arg, "-p=") or std.mem.startsWith(u8, arg, "--pretty=")) {
            opts.pretty = parseBool(arg[argIndex(arg, '=') + 1 ..]);
        } else if (std.mem.startsWith(u8, arg, "-t=") or std.mem.startsWith(u8, arg, "--type=")) {
            opts.attr_type = parseBool(arg[argIndex(arg, '=') + 1 ..]);
        } else if (std.mem.startsWith(u8, arg, "-i=") or std.mem.startsWith(u8, arg, "--item-wrap=")) {
            opts.item_wrap = parseBool(arg[argIndex(arg, '=') + 1 ..]);
        } else if (std.mem.eql(u8, arg, "-x") or std.mem.eql(u8, arg, "--xpath")) {
            opts.xpath_format = true;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--cdata")) {
            opts.cdata = true;
        } else if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--list-headers")) {
            opts.list_headers = true;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            opts.input_file = arg;
        }
    }
}

fn argIndex(arg: []const u8, needle: u8) usize {
    for (arg, 0..) |c, idx| {
        if (c == needle) return idx;
    }
    return arg.len;
}

fn parseBool(value: []const u8) bool {
    if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "yes")) {
        return true;
    }
    if (std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "0") or std.mem.eql(u8, value, "no")) {
        return false;
    }
    return false;
}

fn readInput(allocator: std.mem.Allocator, opts: CliOptions) ![]u8 {
    if (opts.input_string) |input| {
        return allocator.dupe(u8, input);
    }

    if (opts.input_file) |path| {
        if (std.mem.eql(u8, path, "-")) {
            const stdin = std.fs.File.stdin();
            return stdin.readToEndAlloc(allocator, 10 * 1024 * 1024);
        }
        return std.fs.cwd().readFileAlloc(allocator, path, 100 * 1024 * 1024);
    }

    return error.NoInput;
}

fn writeOutput(output: []const u8, opts: CliOptions) !void {
    if (opts.output_file) |path| {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(output);
        return;
    }
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(output);
}

fn printUsage() void {
    const usage =
        \\json2xml-zig - Convert JSON to XML
        \\
        \\Usage:
        \\  json2xml-zig [flags] [input-file]
        \\
        \\Input Options:
        \\  -s, --string string     Read JSON from string
        \\  [input-file]            Read JSON from file (use - for stdin)
        \\
        \\Output Options:
        \\  -o, --output string     Output file (default: stdout)
        \\
        \\Conversion Options:
        \\  -w, --wrapper string    Wrapper element name (default "all")
        \\  -r, --root=bool         Include root element (default true)
        \\  -p, --pretty=bool       Pretty print output (default true)
        \\  -t, --type=bool         Include type attributes (default true)
        \\  -i, --item-wrap=bool    Wrap list items in <item> elements (default true)
        \\  -x, --xpath             Use XPath 3.1 json-to-xml format
        \\  -c, --cdata             Wrap string values in CDATA sections
        \\  -l, --list-headers      Repeat headers for each list item
        \\  -h, --help              Show help message
        \\
    ;
    std.debug.print("{s}", .{usage});
}
