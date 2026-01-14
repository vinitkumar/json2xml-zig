const std = @import("std");

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

const SpecialKeys = struct {
    raw_value: std.json.Value,
    extra_attrs: ?std.json.ObjectMap = null,
    flat: bool = false,
    skip_specials: bool = false,
};

// Use a concrete writer type alias
const Writer = std.ArrayList(u8).Writer;
const WriteError = error{OutOfMemory};

pub fn toXml(allocator: std.mem.Allocator, value: std.json.Value, options: Options) ![]u8 {
    var output: std.ArrayList(u8) = try std.ArrayList(u8).initCapacity(allocator, 4096);
    errdefer output.deinit(allocator);

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

fn writeXmlDeclaration(writer: Writer, pretty: bool) WriteError!void {
    try writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\" ?>");
    if (pretty) {
        try writer.writeAll("\n");
    }
}

fn writeIndent(writer: Writer, indent: usize, pretty: bool) WriteError!void {
    if (!pretty) return;
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeAll("  ");
    }
}

fn writeNewline(writer: Writer, pretty: bool) WriteError!void {
    if (pretty) {
        try writer.writeAll("\n");
    }
}

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

fn writeEscaped(writer: Writer, input: []const u8) WriteError!void {
    for (input) |c| {
        switch (c) {
            '&' => try writer.writeAll("&amp;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&apos;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            else => try writer.writeByte(c),
        }
    }
}

fn writeCdata(writer: Writer, input: []const u8) WriteError!void {
    try writer.writeAll("<![CDATA[");
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        if (i + 2 < input.len and std.mem.eql(u8, input[i .. i + 3], "]]>")) {
            try writer.writeAll("]]]]><![CDATA[>");
            i += 2;
        } else {
            try writer.writeByte(input[i]);
        }
    }
    try writer.writeAll("]]>");
}

fn writeAttrValue(writer: Writer, value: std.json.Value) WriteError!void {
    switch (value) {
        .string => |s| try writeEscaped(writer, s),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .number_string => |ns| try writer.writeAll(ns),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .null => {},
        .object, .array => {
            // Complex values are not typically used as attributes
            try writer.writeAll("[complex]");
        },
    }
}

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
    if (extra_attrs) |attrs| {
        var it = attrs.iterator();
        while (it.next()) |entry| {
            try writer.writeByte(' ');
            try writer.writeAll(entry.key_ptr.*);
            try writer.writeAll("=\"");
            try writeAttrValue(writer, entry.value_ptr.*);
            try writer.writeAll("\"");
        }
    }
}

fn makeValidXmlName(key: []const u8) []const u8 {
    if (key.len == 0) return "key";
    if (std.ascii.isDigit(key[0])) {
        return std.fmt.allocPrint(std.heap.page_allocator, "n{s}", .{key}) catch "key";
    }
    return key;
}

fn parseSpecials(value: std.json.Value) SpecialKeys {
    if (value != .object) {
        return .{ .raw_value = value };
    }

    const obj = value.object;
    var result = SpecialKeys{ .raw_value = value };

    if (obj.get("@attrs")) |attrs| {
        if (attrs == .object) {
            result.extra_attrs = attrs.object;
        }
    }

    if (obj.get("@flat")) |flat_val| {
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

fn writeValue(
    writer: Writer,
    value: std.json.Value,
    options: Options,
    tag: ?[]const u8,
    indent: usize,
    parent_is_list: bool,
) WriteError!void {
    switch (value) {
        .object => |obj| try writeObject(writer, obj, options, tag, indent, parent_is_list, false, null),
        .array => |arr| try writeArray(writer, arr, options, tag, indent, parent_is_list, false),
        .null, .bool, .integer, .float, .number_string, .string => {
            if (tag) |tag_name| {
                try writePrimitive(writer, value, options, tag_name, indent, null);
            }
        },
    }
}

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
            try writeAttributes(writer, .{ .object = obj }, options, extra_attrs);
            try writer.writeByte('>');
            try writeNewline(writer, options.pretty);
        }
    }

    var it = obj.iterator();
    while (it.next()) |entry| {
        const raw_key = entry.key_ptr.*;
        if (std.mem.eql(u8, raw_key, "@attrs") or std.mem.eql(u8, raw_key, "@val") or std.mem.eql(u8, raw_key, "@flat")) {
            continue;
        }

        var key = raw_key;
        var key_flat = false;
        if (std.mem.endsWith(u8, key, "@flat")) {
            key = key[0 .. key.len - 5];
            key_flat = true;
        }

        const specials = parseSpecials(entry.value_ptr.*);
        const value = specials.raw_value;
        const is_flat = key_flat or specials.flat;
        const valid_key = makeValidXmlName(key);

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

fn writeArray(
    writer: Writer,
    array: std.json.Array,
    options: Options,
    tag: ?[]const u8,
    indent: usize,
    _: bool, // parent_is_list (reserved for future use)
    flat: bool,
) WriteError!void {
    const has_tag = tag != null and !flat and options.item_wrap and !options.list_headers;
    if (has_tag) {
        const tag_name = makeValidXmlName(tag.?);
        try writeIndent(writer, indent, options.pretty);
        try writer.writeByte('<');
        try writer.writeAll(tag_name);
        try writeAttributes(writer, .{ .array = array }, options, null);
        try writer.writeByte('>');
        try writeNewline(writer, options.pretty);
    }

    for (array.items) |item| {
        const item_tag: []const u8 = if (options.item_wrap) "item" else (tag orelse "item");
        switch (item) {
            .object => |obj| {
                const use_tag = if (options.list_headers and tag != null) tag.? else item_tag;
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
        .null => {},
        .object, .array => {},
    }

    try writer.writeAll("</");
    try writer.writeAll(tag_name);
    try writer.writeByte('>');
    try writeNewline(writer, options.pretty);
}

fn writeXPathXml(writer: Writer, value: std.json.Value, options: Options, allocator: std.mem.Allocator) WriteError!void {
    try writeXmlDeclaration(writer, options.pretty);
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);
    const bufWriter = buffer.writer(allocator);
    try convertToXPath31(bufWriter, value, null);

    const xml = buffer.items;
    
    // Insert xmlns attribute into the root element only
    if (std.mem.startsWith(u8, xml, "<map>")) {
        try writer.writeAll("<map xmlns=\"http://www.w3.org/2005/xpath-functions\">");
        if (xml.len > 5) {
            try writer.writeAll(xml[5..]);
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

    try writer.writeAll("<map xmlns=\"http://www.w3.org/2005/xpath-functions\">");
    try writer.writeAll(xml);
    try writer.writeAll("</map>");
    try writeNewline(writer, options.pretty);
}

fn convertToXPath31(writer: Writer, value: std.json.Value, key: ?[]const u8) WriteError!void {
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
            var it = obj.iterator();
            while (it.next()) |entry| {
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
            for (arr.items) |item| {
                try convertToXPath31(writer, item, null);
            }
            try writer.writeAll("</array>");
        },
    }
}
