// =============================================================================
// JSON2XML.ZIG - Core JSON to XML conversion library
// =============================================================================
// This module demonstrates advanced Zig concepts:
// - Type aliases and custom error types
// - Tagged unions (std.json.Value)
// - Switch expressions on tagged unions
// - Writer interface pattern
// - Recursive functions
// - Memory-efficient string building with ArrayList
// =============================================================================

const std = @import("std");

// -----------------------------------------------------------------------------
// PUBLIC OPTIONS STRUCT
// -----------------------------------------------------------------------------
// `pub` makes this struct accessible from other files that import this module.
// Other files can use: const Options = @import("json2xml.zig").Options;
pub const Options = struct {
    wrapper: []const u8 = "all",
    root: bool = true,
    pretty: bool = true,
    attr_type: bool = true,
    item_wrap: bool = true,
    xpath_format: bool = false,
    cdata: bool = false,
    list_headers: bool = false,
};

// -----------------------------------------------------------------------------
// INTERNAL STRUCT FOR SPECIAL JSON KEYS
// -----------------------------------------------------------------------------
// This struct handles special keys like @attrs, @val, @flat in JSON input.
// These allow users to control XML attributes and structure.
const SpecialKeys = struct {
    raw_value: std.json.Value,
    extra_attrs: ?std.json.ObjectMap = null, // ? makes it optional (nullable)
    flat: bool = false,
    skip_specials: bool = false,
};

// -----------------------------------------------------------------------------
// TYPE ALIASES
// -----------------------------------------------------------------------------
// Type aliases make code cleaner and more maintainable.
// Instead of writing std.ArrayList(u8).Writer everywhere, we use Writer.
//
// std.ArrayList(u8) is a dynamic array of bytes (like std::vector<uint8_t>
// in C++ or bytearray in Python). Its .Writer is an interface for appending.
const Writer = std.ArrayList(u8).Writer;

// -----------------------------------------------------------------------------
// CUSTOM ERROR TYPE
// -----------------------------------------------------------------------------
// error{...} defines a custom error set. This makes error handling explicit.
// Functions returning WriteError can only fail with OutOfMemory.
// This is safer than generic "any error" because callers know exactly what
// can go wrong.
const WriteError = error{OutOfMemory};

// -----------------------------------------------------------------------------
// MAIN PUBLIC FUNCTION: toXml
// -----------------------------------------------------------------------------
// Converts a JSON value to an XML string.
//
// Parameters:
//   - allocator: Memory allocator for dynamic allocation
//   - value: The parsed JSON value (a tagged union representing any JSON type)
//   - options: Conversion options controlling output format
//
// Returns: ![]u8 - either an error or an owned slice of bytes (the XML string)
//
// IMPORTANT: The caller owns the returned memory and must free it!
pub fn toXml(allocator: std.mem.Allocator, value: std.json.Value, options: Options) ![]u8 {
    return toXmlWithCapacity(allocator, value, options, 4096);
}

// -----------------------------------------------------------------------------
// OPTIMIZED PUBLIC FUNCTION: toXmlWithCapacity
// -----------------------------------------------------------------------------
// Same as toXml but allows specifying initial buffer capacity for better
// performance when the approximate output size is known.
pub fn toXmlWithCapacity(allocator: std.mem.Allocator, value: std.json.Value, options: Options, capacity: usize) ![]u8 {
    // Use provided capacity hint to reduce reallocations
    var output: std.ArrayList(u8) = try std.ArrayList(u8).initCapacity(allocator, capacity);

    // errdefer runs ONLY if the function returns an error.
    errdefer output.deinit(allocator);

    // Get a writer interface for appending to the ArrayList
    const writer = output.writer(allocator);

    if (options.xpath_format) {
        try writeXPathXml(writer, value, options, allocator);
        return output.toOwnedSlice(allocator);
    }

    if (options.root) {
        try writeXmlDeclaration(writer, options.pretty);
        try writeObjectWrapper(writer, value, options, options.wrapper, 0);
    } else {
        try writeValue(writer, value, options, null, 0, false);
    }

    return output.toOwnedSlice(allocator);
}

// -----------------------------------------------------------------------------
// WRITE XML DECLARATION
// -----------------------------------------------------------------------------
// Writes: <?xml version="1.0" encoding="UTF-8" ?>
//
// Note the return type: WriteError!void
// This means: can fail with WriteError, or succeed with void (nothing).
fn writeXmlDeclaration(writer: Writer, pretty: bool) WriteError!void {
    // writeAll appends a string to the writer
    try writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\" ?>");
    if (pretty) {
        try writer.writeAll("\n");
    }
}

// -----------------------------------------------------------------------------
// WRITE INDENTATION
// -----------------------------------------------------------------------------
// Writes spaces for indentation (2 spaces per level).
// Optimized to use writeByteNTimes instead of a loop.
fn writeIndent(writer: Writer, indent: usize, pretty: bool) WriteError!void {
    if (!pretty) return; // Early return if not pretty printing
    // Write all spaces at once instead of looping
    try writer.writeByteNTimes(' ', indent * 2);
}

// -----------------------------------------------------------------------------
// WRITE NEWLINE
// -----------------------------------------------------------------------------
fn writeNewline(writer: Writer, pretty: bool) WriteError!void {
    if (pretty) {
        try writer.writeAll("\n");
    }
}

// -----------------------------------------------------------------------------
// GET XML TYPE NAME FROM JSON VALUE
// -----------------------------------------------------------------------------
// This demonstrates SWITCH EXPRESSIONS on tagged unions.
//
// std.json.Value is a TAGGED UNION - it can be one of several types,
// each with different associated data:
//   .null       - no data
//   .bool       - contains a bool
//   .string     - contains []const u8
//   .integer    - contains i64
//   .float      - contains f64
//   .object     - contains ObjectMap (like a hashmap)
//   .array      - contains Array (dynamic array of Values)
//
// Switch on tagged unions is exhaustive - you MUST handle all variants
// or the compiler will error. This prevents bugs from forgetting cases.
fn getXmlType(value: std.json.Value) []const u8 {
    return switch (value) {
        .null => "null",
        .bool => "bool",
        .string => "str",
        .integer => "int",
        .float => "float",
        .number_string => "number",
        .object => "dict",
        .array => "list",
    };
}

// -----------------------------------------------------------------------------
// ESCAPE SPECIAL XML CHARACTERS
// -----------------------------------------------------------------------------
// XML has special characters that must be escaped: & " ' < >
// This function replaces them with XML entities.
// Optimized: writes spans of safe characters at once instead of byte-by-byte.
fn writeEscaped(writer: Writer, input: []const u8) WriteError!void {
    var i: usize = 0;
    while (i < input.len) {
        // Find the next special character that needs escaping
        const special_chars = "&\"'<>";
        const j = std.mem.indexOfAnyPos(u8, input, i, special_chars) orelse {
            // No more special chars - write the rest and return
            try writer.writeAll(input[i..]);
            return;
        };

        // Write the safe span before the special character
        if (j > i) {
            try writer.writeAll(input[i..j]);
        }

        // Write the escape sequence for the special character
        switch (input[j]) {
            '&' => try writer.writeAll("&amp;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&apos;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            else => unreachable,
        }
        i = j + 1;
    }
}

// -----------------------------------------------------------------------------
// WRITE CDATA SECTION
// -----------------------------------------------------------------------------
// CDATA sections allow including special characters without escaping.
// They look like: <![CDATA[content here]]>
// The tricky part: if the content contains "]]>", we must split it.
fn writeCdata(writer: Writer, input: []const u8) WriteError!void {
    try writer.writeAll("<![CDATA[");
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        // Check for the forbidden sequence "]]>"
        if (i + 2 < input.len and std.mem.eql(u8, input[i .. i + 3], "]]>")) {
            // Split the CDATA section to escape "]]>"
            // This writes: ]]]]><![CDATA[>
            // Which becomes "]]>" when parsed
            try writer.writeAll("]]]]><![CDATA[>");
            i += 2;
        } else {
            try writer.writeByte(input[i]);
        }
    }
    try writer.writeAll("]]>");
}

// -----------------------------------------------------------------------------
// WRITE ATTRIBUTE VALUE
// -----------------------------------------------------------------------------
// Writes the value part of an XML attribute.
// Uses switch on tagged union to handle different JSON types.
fn writeAttrValue(writer: Writer, value: std.json.Value) WriteError!void {
    switch (value) {
        // "|s|" is PAYLOAD CAPTURE - it extracts the data from the variant.
        // For .string, the payload is the actual string ([]const u8).
        .string => |s| try writeEscaped(writer, s),

        // For .integer, payload is i64. We use print for formatted output.
        // {d} format specifier prints as decimal.
        // .{i} is an anonymous tuple containing the format arguments.
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .number_string => |ns| try writer.writeAll(ns),

        // Ternary-like expression: if b is true, use "true", else "false"
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),

        .null => {}, // Do nothing for null

        // Comma groups multiple variants that share the same handling
        .object, .array => {
            try writer.writeAll("[complex]");
        },
    }
}

// -----------------------------------------------------------------------------
// WRITE XML ATTRIBUTES
// -----------------------------------------------------------------------------
fn writeAttributes(
    writer: Writer,
    value: std.json.Value,
    options: Options,
    extra_attrs: ?std.json.ObjectMap,
) WriteError!void {
    if (options.attr_type) {
        try writer.writeAll(" type=\"");
        try writer.writeAll(getXmlType(value));
        try writer.writeAll("\"");
    }

    // -------------------------------------------------------------------------
    // UNWRAPPING OPTIONALS IN IF
    // -------------------------------------------------------------------------
    // if (optional) |unwrapped| captures the non-null value.
    // This is Zig's safe way to handle nullable values.
    if (extra_attrs) |attrs| {
        // Iterate over the hashmap using .iterator()
        var it = attrs.iterator();
        while (it.next()) |entry| {
            // entry has .key_ptr and .value_ptr fields
            // The .* dereferences the pointer to get the actual value
            try writer.writeByte(' ');
            try writer.writeAll(entry.key_ptr.*);
            try writer.writeAll("=\"");
            try writeAttrValue(writer, entry.value_ptr.*);
            try writer.writeAll("\"");
        }
    }
}

// -----------------------------------------------------------------------------
// MAKE VALID XML ELEMENT NAME
// -----------------------------------------------------------------------------
// XML element names can't start with digits. This fixes that.
fn makeValidXmlName(key: []const u8) []const u8 {
    if (key.len == 0) return "key";

    // std.ascii.isDigit checks if a character is 0-9
    if (std.ascii.isDigit(key[0])) {
        // allocPrint allocates a formatted string.
        // Note: This uses page_allocator which is a global fallback.
        // In production code, you'd pass an allocator as a parameter.
        // The "catch" provides a fallback value if allocation fails.
        return std.fmt.allocPrint(std.heap.page_allocator, "n{s}", .{key}) catch "key";
    }
    return key;
}

// -----------------------------------------------------------------------------
// PARSE SPECIAL JSON KEYS (@attrs, @val, @flat)
// -----------------------------------------------------------------------------
// Looks for special keys that control XML generation.
fn parseSpecials(value: std.json.Value) SpecialKeys {
    // -------------------------------------------------------------------------
    // COMPARING TAGGED UNION VARIANTS
    // -------------------------------------------------------------------------
    // value != .object checks if it's NOT the object variant.
    // This is how you check what type a tagged union currently holds.
    if (value != .object) {
        return .{ .raw_value = value };
    }

    // Access the object's underlying map directly
    const obj = value.object;
    var result = SpecialKeys{ .raw_value = value };

    // .get() returns an optional - either null or the value
    if (obj.get("@attrs")) |attrs| {
        if (attrs == .object) {
            result.extra_attrs = attrs.object;
        }
    }

    if (obj.get("@flat")) |flat_val| {
        // Chained comparison: check type AND value
        if (flat_val == .bool and flat_val.bool) {
            result.flat = true;
        }
    }

    if (obj.get("@val")) |raw| {
        result.raw_value = raw;
        result.skip_specials = false;
    } else if (result.extra_attrs != null or result.flat) {
        result.skip_specials = true;
    }

    return result;
}

// -----------------------------------------------------------------------------
// WRITE OBJECT WITH WRAPPER TAG
// -----------------------------------------------------------------------------
fn writeObjectWrapper(writer: Writer, value: std.json.Value, options: Options, tag: []const u8, indent: usize) WriteError!void {
    const tag_name = makeValidXmlName(tag);
    try writeIndent(writer, indent, options.pretty);
    try writer.writeByte('<');
    try writer.writeAll(tag_name);
    try writer.writeByte('>');
    try writeNewline(writer, options.pretty);
    try writeValue(writer, value, options, null, indent + 1, false);
    try writeIndent(writer, indent, options.pretty);
    try writer.writeAll("</");
    try writer.writeAll(tag_name);
    try writer.writeByte('>');
    try writeNewline(writer, options.pretty);
}

// -----------------------------------------------------------------------------
// WRITE ANY JSON VALUE
// -----------------------------------------------------------------------------
// This is the main dispatcher that handles all JSON types.
// It's a recursive function - arrays and objects call back to writeValue.
fn writeValue(
    writer: Writer,
    value: std.json.Value,
    options: Options,
    tag: ?[]const u8, // ? makes it optional (can be null)
    indent: usize,
    parent_is_list: bool,
) WriteError!void {
    switch (value) {
        // Payload capture: |obj| extracts the ObjectMap from the .object variant
        .object => |obj| try writeObject(writer, obj, options, tag, indent, parent_is_list, false, null),
        .array => |arr| try writeArray(writer, arr, options, tag, indent, parent_is_list, false),

        // Comma groups all primitive types that share the same handling
        .null, .bool, .integer, .float, .number_string, .string => {
            if (tag) |tag_name| {
                try writePrimitive(writer, value, options, tag_name, indent, null);
            }
        },
    }
}

// -----------------------------------------------------------------------------
// WRITE JSON OBJECT AS XML
// -----------------------------------------------------------------------------
fn writeObject(
    writer: Writer,
    obj: std.json.ObjectMap,
    options: Options,
    tag: ?[]const u8,
    indent: usize,
    parent_is_list: bool,
    flat: bool,
    extra_attrs: ?std.json.ObjectMap,
) WriteError!void {
    if (tag) |tag_name| {
        if (!flat) {
            const valid_tag = makeValidXmlName(tag_name);
            try writeIndent(writer, indent, options.pretty);
            try writer.writeByte('<');
            try writer.writeAll(valid_tag);
            // Create an anonymous tagged union value for attributes
            // .{ .object = obj } creates a Value with the object variant
            try writeAttributes(writer, .{ .object = obj }, options, extra_attrs);
            try writer.writeByte('>');
            try writeNewline(writer, options.pretty);
        }
    }

    // Iterate over all key-value pairs in the object
    var it = obj.iterator();
    while (it.next()) |entry| {
        const raw_key = entry.key_ptr.*;

        // Skip special keys that control XML generation
        if (std.mem.eql(u8, raw_key, "@attrs") or std.mem.eql(u8, raw_key, "@val") or std.mem.eql(u8, raw_key, "@flat")) {
            continue; // Skip to next iteration
        }

        var key = raw_key;
        var key_flat = false;

        // Check if key ends with "@flat" suffix
        if (std.mem.endsWith(u8, key, "@flat")) {
            // Slice to remove the "@flat" suffix (5 characters)
            key = key[0 .. key.len - 5];
            key_flat = true;
        }

        const specials = parseSpecials(entry.value_ptr.*);
        const value = specials.raw_value;
        const valid_key = makeValidXmlName(key);
        const is_flat = key_flat or specials.flat;

        // Recursively handle nested values
        switch (value) {
            .object => |inner_obj| {
                if (is_flat) {
                    try writeObject(writer, inner_obj, options, null, indent, parent_is_list, true, specials.extra_attrs);
                } else {
                    try writeObject(writer, inner_obj, options, valid_key, indent, parent_is_list, false, specials.extra_attrs);
                }
            },
            .array => |inner_arr| {
                try writeArray(writer, inner_arr, options, valid_key, indent, parent_is_list, is_flat or specials.flat);
            },
            .null, .bool, .integer, .float, .number_string, .string => {
                try writePrimitive(writer, value, options, valid_key, indent, specials.extra_attrs);
            },
        }
    }

    // Write closing tag
    if (tag) |tag_name| {
        if (!flat) {
            const valid_tag = makeValidXmlName(tag_name);
            try writeIndent(writer, indent, options.pretty);
            try writer.writeAll("</");
            try writer.writeAll(valid_tag);
            try writer.writeByte('>');
            try writeNewline(writer, options.pretty);
        }
    }
}

// -----------------------------------------------------------------------------
// WRITE JSON ARRAY AS XML
// -----------------------------------------------------------------------------
fn writeArray(
    writer: Writer,
    array: std.json.Array,
    options: Options,
    tag: ?[]const u8,
    indent: usize,
    _: bool, // Underscore means: accept the parameter but ignore it
    flat: bool,
) WriteError!void {
    // Complex boolean logic for determining wrapper behavior
    const has_tag = tag != null and !flat and options.item_wrap and !options.list_headers;

    if (has_tag) {
        // tag.? unwraps the optional, but ONLY use this when you're 100% sure
        // it's not null. Here we know because has_tag checks tag != null first.
        const tag_name = makeValidXmlName(tag.?);
        try writeIndent(writer, indent, options.pretty);
        try writer.writeByte('<');
        try writer.writeAll(tag_name);
        try writeAttributes(writer, .{ .array = array }, options, null);
        try writer.writeByte('>');
        try writeNewline(writer, options.pretty);
    }

    // Iterate over array items
    // .items gives access to the underlying slice of a dynamic array
    for (array.items) |item| {
        // Ternary expression for choosing tag name
        const item_tag: []const u8 = if (options.item_wrap) "item" else (tag orelse "item");

        switch (item) {
            .object => |obj| {
                const use_tag = if (options.list_headers and tag != null) tag.? else item_tag;
                // @intFromBool converts bool to int: true -> 1, false -> 0
                // This is idiomatic for conditional indentation
                try writeObject(writer, obj, options, use_tag, indent + @intFromBool(has_tag), true, false, null);
            },
            .array => |arr| try writeArray(writer, arr, options, item_tag, indent + @intFromBool(has_tag), true, false),
            .null, .bool, .integer, .float, .number_string, .string => try writePrimitive(writer, item, options, item_tag, indent + @intFromBool(has_tag), null),
        }
    }

    if (has_tag) {
        const tag_name = makeValidXmlName(tag.?);
        try writeIndent(writer, indent, options.pretty);
        try writer.writeAll("</");
        try writer.writeAll(tag_name);
        try writer.writeByte('>');
        try writeNewline(writer, options.pretty);
    }
}

// -----------------------------------------------------------------------------
// WRITE PRIMITIVE JSON VALUE AS XML
// -----------------------------------------------------------------------------
// Handles: null, bool, integer, float, number_string, string
fn writePrimitive(
    writer: Writer,
    value: std.json.Value,
    options: Options,
    tag: []const u8,
    indent: usize,
    extra_attrs: ?std.json.ObjectMap,
) WriteError!void {
    const tag_name = makeValidXmlName(tag);
    try writeIndent(writer, indent, options.pretty);
    try writer.writeByte('<');
    try writer.writeAll(tag_name);
    try writeAttributes(writer, value, options, extra_attrs);
    try writer.writeByte('>');

    // Write the actual value content
    switch (value) {
        .string => |s| {
            if (options.cdata) {
                try writeCdata(writer, s);
            } else {
                try writeEscaped(writer, s);
            }
        },
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .number_string => |ns| try writer.writeAll(ns),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .null => {}, // Empty element for null
        .object, .array => {}, // Shouldn't happen for primitives
    }

    try writer.writeAll("</");
    try writer.writeAll(tag_name);
    try writer.writeByte('>');
    try writeNewline(writer, options.pretty);
}

// -----------------------------------------------------------------------------
// XPATH 3.1 FORMAT SUPPORT
// -----------------------------------------------------------------------------
// XPath 3.1 has a standard JSON-to-XML mapping. This implements it.
// See: https://www.w3.org/TR/xpath-functions-31/#json-to-xml-mapping
fn writeXPathXml(writer: Writer, value: std.json.Value, options: Options, allocator: std.mem.Allocator) WriteError!void {
    try writeXmlDeclaration(writer, options.pretty);

    // Use a temporary buffer for building the inner XML
    // .empty is a shorthand for zero-initialized struct
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator); // Clean up when done
    const bufWriter = buffer.writer(allocator);
    try convertToXPath31(bufWriter, value, null);

    const xml = buffer.items; // Get the slice of accumulated bytes

    // Insert the namespace declaration into the root element
    // std.mem.startsWith checks if a slice starts with another slice
    if (std.mem.startsWith(u8, xml, "<map>")) {
        try writer.writeAll("<map xmlns=\"http://www.w3.org/2005/xpath-functions\">");
        if (xml.len > 5) {
            try writer.writeAll(xml[5..]); // Write everything after "<map>"
        }
        return;
    }
    if (std.mem.startsWith(u8, xml, "<map ")) {
        try writer.writeAll("<map xmlns=\"http://www.w3.org/2005/xpath-functions\" ");
        if (xml.len > 5) {
            try writer.writeAll(xml[5..]);
        }
        return;
    }
    if (std.mem.startsWith(u8, xml, "<array>")) {
        try writer.writeAll("<array xmlns=\"http://www.w3.org/2005/xpath-functions\">");
        if (xml.len > 7) {
            try writer.writeAll(xml[7..]);
        }
        return;
    }
    if (std.mem.startsWith(u8, xml, "<array ")) {
        try writer.writeAll("<array xmlns=\"http://www.w3.org/2005/xpath-functions\" ");
        if (xml.len > 7) {
            try writer.writeAll(xml[7..]);
        }
        return;
    }

    // Fallback: wrap in <map>
    try writer.writeAll("<map xmlns=\"http://www.w3.org/2005/xpath-functions\">");
    try writer.writeAll(xml);
    try writer.writeAll("</map>");
    try writeNewline(writer, options.pretty);
}

// -----------------------------------------------------------------------------
// CONVERT VALUE TO XPATH 3.1 FORMAT
// -----------------------------------------------------------------------------
// Recursive function that writes XPath 3.1 compliant XML.
// Each JSON type maps to a specific XML element:
//   null   -> <null/>
//   bool   -> <boolean>true/false</boolean>
//   number -> <number>value</number>
//   string -> <string>value</string>
//   object -> <map>...</map>
//   array  -> <array>...</array>
fn convertToXPath31(writer: Writer, value: std.json.Value, key: ?[]const u8) WriteError!void {
    // Simplified null-check: if key is non-null, use it, else null
    const key_attr = if (key) |k| k else null;

    switch (value) {
        .null => {
            try writer.writeAll("<null");
            if (key_attr) |k| {
                try writer.writeAll(" key=\"");
                try writeEscaped(writer, k);
                try writer.writeAll("\"");
            }
            try writer.writeAll("/>");
        },
        .bool => |b| {
            try writer.writeAll("<boolean");
            if (key_attr) |k| {
                try writer.writeAll(" key=\"");
                try writeEscaped(writer, k);
                try writer.writeAll("\"");
            }
            try writer.writeAll(">");
            try writer.writeAll(if (b) "true" else "false");
            try writer.writeAll("</boolean>");
        },
        .integer => |i| {
            try writer.writeAll("<number");
            if (key_attr) |k| {
                try writer.writeAll(" key=\"");
                try writeEscaped(writer, k);
                try writer.writeAll("\"");
            }
            try writer.writeAll(">");
            try writer.print("{d}", .{i});
            try writer.writeAll("</number>");
        },
        .float => |f| {
            try writer.writeAll("<number");
            if (key_attr) |k| {
                try writer.writeAll(" key=\"");
                try writeEscaped(writer, k);
                try writer.writeAll("\"");
            }
            try writer.writeAll(">");
            try writer.print("{d}", .{f});
            try writer.writeAll("</number>");
        },
        .number_string => |ns| {
            try writer.writeAll("<number");
            if (key_attr) |k| {
                try writer.writeAll(" key=\"");
                try writeEscaped(writer, k);
                try writer.writeAll("\"");
            }
            try writer.writeAll(">");
            try writer.writeAll(ns);
            try writer.writeAll("</number>");
        },
        .string => |s| {
            try writer.writeAll("<string");
            if (key_attr) |k| {
                try writer.writeAll(" key=\"");
                try writeEscaped(writer, k);
                try writer.writeAll("\"");
            }
            try writer.writeAll(">");
            try writeEscaped(writer, s);
            try writer.writeAll("</string>");
        },
        .object => |obj| {
            try writer.writeAll("<map");
            if (key_attr) |k| {
                try writer.writeAll(" key=\"");
                try writeEscaped(writer, k);
                try writer.writeAll("\"");
            }
            try writer.writeAll(">");

            // Recursively convert each key-value pair
            var it = obj.iterator();
            while (it.next()) |entry| {
                // Pass the key to the recursive call for the key="" attribute
                try convertToXPath31(writer, entry.value_ptr.*, entry.key_ptr.*);
            }
            try writer.writeAll("</map>");
        },
        .array => |arr| {
            try writer.writeAll("<array");
            if (key_attr) |k| {
                try writer.writeAll(" key=\"");
                try writeEscaped(writer, k);
                try writer.writeAll("\"");
            }
            try writer.writeAll(">");

            // Array items don't have keys
            for (arr.items) |item| {
                try convertToXPath31(writer, item, null);
            }
            try writer.writeAll("</array>");
        },
    }
}
