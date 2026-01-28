// =============================================================================
// MAIN.ZIG - Entry point for the json2xml-zig CLI application
// =============================================================================
// This file demonstrates core Zig concepts for newcomers:
// - Importing modules
// - Structs with default values
// - Memory allocation and management (RAII-like patterns via defer)
// - Error handling with the ! operator
// - Optionals with ? type modifier
// - Command-line argument parsing
// =============================================================================

// -----------------------------------------------------------------------------
// IMPORTS
// -----------------------------------------------------------------------------
// In Zig, @import is a built-in function (built-ins start with @).
// "std" is Zig's standard library - it provides data structures, I/O, memory
// allocators, and much more. Think of it like Python's stdlib or Go's packages.
const std = @import("std");

// Import our own module. When importing a .zig file, you get access to all
// its `pub` (public) declarations. Non-pub items remain private to that file.
const json2xml = @import("json2xml.zig");

// -----------------------------------------------------------------------------
// STRUCT DEFINITION WITH DEFAULT VALUES
// -----------------------------------------------------------------------------
// In Zig, structs are the primary way to group related data together.
// They can have default values (using = after the type), making them optional
// when creating an instance.
//
// The ? before a type (like ?[]const u8) makes it an OPTIONAL type.
// Optional means the value can either be:
//   - null (no value present)
//   - An actual value of that type
// This is Zig's way of handling nullable values safely at compile time.
const CliOptions = struct {
    // ?[]const u8 means: optional slice of constant bytes (a string, basically)
    // []const u8 is Zig's string type - a slice (pointer + length) of bytes
    // The ? prefix makes it nullable, defaulting to null
    input_string: ?[]const u8 = null,
    input_file: ?[]const u8 = null,
    output_file: ?[]const u8 = null,

    // []const u8 (without ?) is a non-optional string, must always have a value
    wrapper: []const u8 = "all",

    // bool is a simple boolean type (true or false)
    root: bool = true,
    pretty: bool = true,
    attr_type: bool = true,
    item_wrap: bool = true,
    xpath_format: bool = false,
    cdata: bool = false,
    list_headers: bool = false,
};

// -----------------------------------------------------------------------------
// MAIN FUNCTION - PROGRAM ENTRY POINT
// -----------------------------------------------------------------------------
// pub fn main() declares the public main function - the entry point.
//
// The !void return type is crucial to understand:
//   - void means the function returns nothing on success
//   - The ! prefix means it can FAIL with an error
//   - !void is shorthand for "anyerror!void" (can return any error, or void)
//
// In Zig, errors are values, not exceptions. Functions that can fail return
// an error union type (ErrorType!ReturnType). The `try` keyword unwraps these,
// propagating errors up the call stack if they occur.
pub fn main() !void {
    // -------------------------------------------------------------------------
    // MEMORY ALLOCATION - OPTIMIZED FOR PERFORMANCE
    // -------------------------------------------------------------------------
    // Use ArenaAllocator backed by page_allocator for fast bulk allocations.
    // Arena is much faster than GPA for JSON parsing which creates many small
    // allocations that are all freed together at the end.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // -------------------------------------------------------------------------
    // COMMAND-LINE ARGUMENTS
    // -------------------------------------------------------------------------
    const args = try std.process.argsAlloc(allocator);
    // No need to free with arena - it's all freed at once on deinit

    // -------------------------------------------------------------------------
    // CREATING STRUCT INSTANCES
    // -------------------------------------------------------------------------
    var opts = CliOptions{};
    parseArgs(args, &opts);

    // -------------------------------------------------------------------------
    // TRY AND ERROR PROPAGATION
    // -------------------------------------------------------------------------
    const input_data = try readInput(allocator, opts);

    // -------------------------------------------------------------------------
    // USING THE STANDARD LIBRARY JSON PARSER
    // -------------------------------------------------------------------------
    // parseFromSlice parses a JSON string into a Value type.
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input_data, .{});
    // No defer deinit needed - arena handles cleanup

    // -------------------------------------------------------------------------
    // STRUCT INITIALIZATION WITH NAMED FIELDS
    // -------------------------------------------------------------------------
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

    // Estimate output size: XML is typically 2-3x larger than JSON
    const estimated_size = input_data.len * (if (opts.pretty) @as(usize, 3) else @as(usize, 2));

    // Convert JSON to XML using our library with size hint
    const output = try json2xml.toXmlWithCapacity(allocator, parsed.value, xml_options, estimated_size);

    // Write the result to stdout or a file
    try writeOutput(output, opts);
}

// -----------------------------------------------------------------------------
// PARSING COMMAND-LINE ARGUMENTS
// -----------------------------------------------------------------------------
// fn declares a function. This one is private (no pub keyword).
//
// Parameters:
//   - args: [][:0]u8 - A slice of zero-terminated strings.
//     [:0] means the inner slices are sentinel-terminated with 0 (null byte).
//     This is for compatibility with C-style strings from the OS.
//   - opts: *CliOptions - A pointer to a CliOptions struct.
//     The * means we receive a pointer, so we can modify the original.
//
// Return type: void - this function cannot fail (no ! prefix).
fn parseArgs(args: [][:0]u8, opts: *CliOptions) void {
    // -------------------------------------------------------------------------
    // WHILE LOOP WITH UPDATE CLAUSE
    // -------------------------------------------------------------------------
    // Zig while loops can have an update clause after the colon.
    // This is like: for (var i = 1; i < args.len; i += 1) in C.
    // usize is an unsigned integer the size of a pointer (like size_t in C).
    var i: usize = 1; // Start at 1 to skip the program name (argv[0])
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        // std.mem.eql compares slices for equality.
        // Arguments: (element_type, slice1, slice2)
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--string")) {
            if (i + 1 < args.len) {
                // opts.* would dereference the pointer, but Zig lets you
                // access fields directly through pointers with just .
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
            // Slice syntax: arg[start..end] extracts a sub-slice.
            // arg[argIndex(arg, '=') + 1 ..] means: from after '=' to the end.
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
            // Positional argument (not starting with -) is treated as input file
            opts.input_file = arg;
        }
    }
}

// -----------------------------------------------------------------------------
// HELPER: FIND CHARACTER INDEX
// -----------------------------------------------------------------------------
// Returns the index of `needle` in `arg`, or arg.len if not found.
//
// The loop uses Zig's for-with-index syntax:
//   for (slice, 0..) |element, index| { ... }
// This iterates over `arg` while also tracking the index starting from 0.
fn argIndex(arg: []const u8, needle: u8) usize {
    for (arg, 0..) |c, idx| {
        if (c == needle) return idx;
    }
    return arg.len;
}

// -----------------------------------------------------------------------------
// HELPER: PARSE BOOLEAN STRING
// -----------------------------------------------------------------------------
// Converts string representations of booleans to actual bool values.
fn parseBool(value: []const u8) bool {
    if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "yes")) {
        return true;
    }
    if (std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "0") or std.mem.eql(u8, value, "no")) {
        return false;
    }
    return false;
}

// -----------------------------------------------------------------------------
// READ INPUT FROM STRING, FILE, OR STDIN
// -----------------------------------------------------------------------------
// This function demonstrates:
//   - Optional unwrapping with if (optional) |value| { ... }
//   - Error unions with !
//   - Returning custom errors
//
// Return type: ![]u8 means "either an error or a slice of bytes"
fn readInput(allocator: std.mem.Allocator, opts: CliOptions) ![]u8 {
    // -------------------------------------------------------------------------
    // OPTIONAL UNWRAPPING WITH IF
    // -------------------------------------------------------------------------
    // If opts.input_string is not null, unwrap it into `input`.
    // The |input| syntax is called "payload capture" - it captures the
    // non-null value from the optional.
    if (opts.input_string) |input| {
        // dupe creates a copy of the slice (allocates new memory).
        // We need to copy because the original args might be freed.
        return allocator.dupe(u8, input);
    }

    if (opts.input_file) |path| {
        // Read from stdin if path is "-"
        if (std.mem.eql(u8, path, "-")) {
            const stdin = std.fs.File.stdin();
            // readToEndAlloc reads until EOF, allocating memory as needed.
            // The second arg is max bytes to read (10 MB here).
            return stdin.readToEndAlloc(allocator, 10 * 1024 * 1024);
        }
        // Read from file. cwd() returns the current working directory.
        // readFileAlloc reads the entire file into allocated memory.
        return std.fs.cwd().readFileAlloc(allocator, path, 100 * 1024 * 1024);
    }

    // -------------------------------------------------------------------------
    // RETURNING ERRORS
    // -------------------------------------------------------------------------
    // error.NoInput is an anonymous error - Zig creates the error type
    // automatically. This is a quick way to return simple errors.
    return error.NoInput;
}

// -----------------------------------------------------------------------------
// WRITE OUTPUT TO FILE OR STDOUT
// -----------------------------------------------------------------------------
fn writeOutput(output: []const u8, opts: CliOptions) !void {
    if (opts.output_file) |path| {
        // createFile creates or truncates a file for writing.
        // The .{} is an empty options struct (use defaults).
        const file = try std.fs.cwd().createFile(path, .{});

        // IMPORTANT: defer file.close() ensures the file is closed when
        // this scope exits, even if an error occurs later.
        defer file.close();

        try file.writeAll(output);
        return;
    }

    // Write to stdout if no output file specified
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(output);
}

// -----------------------------------------------------------------------------
// PRINT USAGE/HELP MESSAGE
// -----------------------------------------------------------------------------
fn printUsage() void {
    // -------------------------------------------------------------------------
    // MULTI-LINE STRING LITERALS
    // -------------------------------------------------------------------------
    // The \\ at the start of lines creates a multi-line string literal.
    // Each \\ continues the string on the next line without adding newlines
    // (the actual newlines in the source become \n in the string).
    // This is different from regular strings - it's Zig's way of writing
    // long strings cleanly across multiple source lines.
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

    // -------------------------------------------------------------------------
    // FORMATTED PRINTING
    // -------------------------------------------------------------------------
    // std.debug.print is like printf. The format string uses {s} for strings.
    // The .{usage} is an anonymous tuple containing the arguments.
    // Common format specifiers:
    //   {s} - string ([]const u8)
    //   {d} - decimal integer
    //   {x} - hexadecimal
    //   {} - default formatting for any type
    std.debug.print("{s}", .{usage});
}
