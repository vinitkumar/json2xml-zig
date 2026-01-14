const std = @import("std");
const json2xml = @import("json2xml.zig");
const testing = std.testing;

// Helper to parse JSON and convert to XML
fn convertJson(allocator: std.mem.Allocator, json_str: []const u8, options: json2xml.Options) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();
    return json2xml.toXml(allocator, parsed.value, options);
}

// ============================================
// Basic Type Conversion Tests
// ============================================

test "convert simple object with string" {
    const allocator = testing.allocator;
    const json = 
        \\{"name": "John"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expectEqualStrings(
        \\<?xml version="1.0" encoding="UTF-8" ?><all><name type="str">John</name></all>
    , xml);
}

test "convert simple object with integer" {
    const allocator = testing.allocator;
    const json = 
        \\{"age": 30}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expectEqualStrings(
        \\<?xml version="1.0" encoding="UTF-8" ?><all><age type="int">30</age></all>
    , xml);
}

test "convert simple object with float" {
    const allocator = testing.allocator;
    const json = 
        \\{"price": 19.99}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    // Float formatting may vary, check for key parts
    try testing.expect(std.mem.indexOf(u8, xml, "<price type=\"float\">") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "</price>") != null);
}

test "convert simple object with boolean true" {
    const allocator = testing.allocator;
    const json = 
        \\{"active": true}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expectEqualStrings(
        \\<?xml version="1.0" encoding="UTF-8" ?><all><active type="bool">true</active></all>
    , xml);
}

test "convert simple object with boolean false" {
    const allocator = testing.allocator;
    const json = 
        \\{"active": false}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expectEqualStrings(
        \\<?xml version="1.0" encoding="UTF-8" ?><all><active type="bool">false</active></all>
    , xml);
}

test "convert simple object with null" {
    const allocator = testing.allocator;
    const json = 
        \\{"value": null}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expectEqualStrings(
        \\<?xml version="1.0" encoding="UTF-8" ?><all><value type="null"></value></all>
    , xml);
}

// ============================================
// Array Tests
// ============================================

test "convert array of strings" {
    const allocator = testing.allocator;
    const json = 
        \\{"colors": ["red", "green", "blue"]}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "<colors type=\"list\">") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<item type=\"str\">red</item>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<item type=\"str\">green</item>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<item type=\"str\">blue</item>") != null);
}

test "convert array of integers" {
    const allocator = testing.allocator;
    const json = 
        \\{"numbers": [1, 2, 3]}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "<numbers type=\"list\">") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<item type=\"int\">1</item>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<item type=\"int\">2</item>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<item type=\"int\">3</item>") != null);
}

test "convert array of objects" {
    const allocator = testing.allocator;
    const json = 
        \\{"users": [{"name": "Alice"}, {"name": "Bob"}]}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "<users type=\"list\">") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<item type=\"dict\">") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<name type=\"str\">Alice</name>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<name type=\"str\">Bob</name>") != null);
}

test "convert empty array" {
    const allocator = testing.allocator;
    const json = 
        \\{"items": []}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expectEqualStrings(
        \\<?xml version="1.0" encoding="UTF-8" ?><all><items type="list"></items></all>
    , xml);
}

// ============================================
// Nested Object Tests
// ============================================

test "convert nested objects" {
    const allocator = testing.allocator;
    const json = 
        \\{"person": {"name": "John", "address": {"city": "NYC"}}}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "<person type=\"dict\">") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<name type=\"str\">John</name>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<address type=\"dict\">") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<city type=\"str\">NYC</city>") != null);
}

// ============================================
// Options Tests
// ============================================

test "custom wrapper element" {
    const allocator = testing.allocator;
    const json = 
        \\{"name": "John"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .wrapper = "root", .pretty = false });
    defer allocator.free(xml);
    
    try testing.expectEqualStrings(
        \\<?xml version="1.0" encoding="UTF-8" ?><root><name type="str">John</name></root>
    , xml);
}

test "disable type attributes" {
    const allocator = testing.allocator;
    const json = 
        \\{"name": "John", "age": 30}
    ;
    
    const xml = try convertJson(allocator, json, .{ .attr_type = false, .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "type=") == null);
    try testing.expect(std.mem.indexOf(u8, xml, "<name>John</name>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<age>30</age>") != null);
}

test "disable root element" {
    const allocator = testing.allocator;
    const json = 
        \\{"name": "John"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .root = false, .pretty = false });
    defer allocator.free(xml);
    
    // Should not have XML declaration or wrapper
    try testing.expect(std.mem.indexOf(u8, xml, "<?xml") == null);
    try testing.expect(std.mem.indexOf(u8, xml, "<all>") == null);
}

test "item wrap disabled" {
    const allocator = testing.allocator;
    const json = 
        \\{"colors": ["red", "green"]}
    ;
    
    const xml = try convertJson(allocator, json, .{ .item_wrap = false, .pretty = false });
    defer allocator.free(xml);
    
    // Items should use parent element name instead of <item>
    try testing.expect(std.mem.indexOf(u8, xml, "<colors type=\"str\">red</colors>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<colors type=\"str\">green</colors>") != null);
}

test "pretty print enabled" {
    const allocator = testing.allocator;
    const json = 
        \\{"name": "John"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = true });
    defer allocator.free(xml);
    
    // Should contain newlines and indentation
    try testing.expect(std.mem.indexOf(u8, xml, "\n") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "  ") != null);
}

// ============================================
// XML Escaping Tests
// ============================================

test "escape ampersand" {
    const allocator = testing.allocator;
    const json = 
        \\{"text": "Tom & Jerry"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "Tom &amp; Jerry") != null);
}

test "escape less than" {
    const allocator = testing.allocator;
    const json = 
        \\{"text": "a < b"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "a &lt; b") != null);
}

test "escape greater than" {
    const allocator = testing.allocator;
    const json = 
        \\{"text": "a > b"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "a &gt; b") != null);
}

test "escape quotes" {
    const allocator = testing.allocator;
    const json = 
        \\{"text": "He said \"hello\""}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "&quot;hello&quot;") != null);
}

test "escape apostrophe" {
    const allocator = testing.allocator;
    const json = 
        \\{"text": "It's fine"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "It&apos;s fine") != null);
}

// ============================================
// CDATA Tests
// ============================================

test "cdata wrapping" {
    const allocator = testing.allocator;
    const json = 
        \\{"content": "Hello World"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .cdata = true, .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "<![CDATA[Hello World]]>") != null);
}

test "cdata with special characters" {
    const allocator = testing.allocator;
    const json = 
        \\{"content": "a < b & c > d"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .cdata = true, .pretty = false });
    defer allocator.free(xml);
    
    // In CDATA, special chars should NOT be escaped
    try testing.expect(std.mem.indexOf(u8, xml, "<![CDATA[a < b & c > d]]>") != null);
}

// ============================================
// XPath 3.1 Format Tests
// ============================================

test "xpath format with string" {
    const allocator = testing.allocator;
    const json = 
        \\{"name": "John"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .xpath_format = true, .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "xmlns=\"http://www.w3.org/2005/xpath-functions\"") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<string key=\"name\">John</string>") != null);
}

test "xpath format with number" {
    const allocator = testing.allocator;
    const json = 
        \\{"age": 30}
    ;
    
    const xml = try convertJson(allocator, json, .{ .xpath_format = true, .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "<number key=\"age\">30</number>") != null);
}

test "xpath format with boolean" {
    const allocator = testing.allocator;
    const json = 
        \\{"active": true}
    ;
    
    const xml = try convertJson(allocator, json, .{ .xpath_format = true, .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "<boolean key=\"active\">true</boolean>") != null);
}

test "xpath format with null" {
    const allocator = testing.allocator;
    const json = 
        \\{"value": null}
    ;
    
    const xml = try convertJson(allocator, json, .{ .xpath_format = true, .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "<null key=\"value\"/>") != null);
}

test "xpath format with array" {
    const allocator = testing.allocator;
    const json = 
        \\{"items": [1, 2]}
    ;
    
    const xml = try convertJson(allocator, json, .{ .xpath_format = true, .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "<array key=\"items\">") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<number>1</number>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<number>2</number>") != null);
}

test "xpath format with nested object" {
    const allocator = testing.allocator;
    const json = 
        \\{"person": {"name": "John"}}
    ;
    
    const xml = try convertJson(allocator, json, .{ .xpath_format = true, .pretty = false });
    defer allocator.free(xml);
    
    // The root map has xmlns, nested maps have key attribute
    try testing.expect(std.mem.indexOf(u8, xml, "xmlns=\"http://www.w3.org/2005/xpath-functions\"") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "key=\"person\"") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<string key=\"name\">John</string>") != null);
}

// ============================================
// Edge Cases
// ============================================

test "empty object" {
    const allocator = testing.allocator;
    const json = 
        \\{}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expectEqualStrings(
        \\<?xml version="1.0" encoding="UTF-8" ?><all></all>
    , xml);
}

test "numeric key handling" {
    const allocator = testing.allocator;
    const json = 
        \\{"123": "value"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    // Numeric keys should be prefixed with 'n'
    try testing.expect(std.mem.indexOf(u8, xml, "<n123") != null);
}

test "unicode characters" {
    const allocator = testing.allocator;
    const json = 
        \\{"greeting": "Hello 世界"}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "Hello 世界") != null);
}

test "mixed types in object" {
    const allocator = testing.allocator;
    const json = 
        \\{"str": "hello", "num": 42, "bool": true, "nil": null}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "<str type=\"str\">hello</str>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<num type=\"int\">42</num>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<bool type=\"bool\">true</bool>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<nil type=\"null\"></nil>") != null);
}

test "deeply nested structure" {
    const allocator = testing.allocator;
    const json = 
        \\{"a": {"b": {"c": {"d": "deep"}}}}
    ;
    
    const xml = try convertJson(allocator, json, .{ .pretty = false });
    defer allocator.free(xml);
    
    try testing.expect(std.mem.indexOf(u8, xml, "<a type=\"dict\">") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<b type=\"dict\">") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<c type=\"dict\">") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<d type=\"str\">deep</d>") != null);
}

test "list headers option" {
    const allocator = testing.allocator;
    const json = 
        \\{"users": [{"name": "Alice"}, {"name": "Bob"}]}
    ;
    
    const xml = try convertJson(allocator, json, .{ .list_headers = true, .pretty = false });
    defer allocator.free(xml);
    
    // With list_headers, each item should use the parent element name
    try testing.expect(std.mem.indexOf(u8, xml, "<users type=\"dict\">") != null);
}

// ============================================
// Large Data Test
// ============================================

test "large array" {
    const allocator = testing.allocator;
    
    // Build a large JSON array
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);
    
    const writer = json_buf.writer(allocator);
    try writer.writeAll("{\"items\": [");
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{d}", .{i});
    }
    try writer.writeAll("]}");
    
    const xml = try convertJson(allocator, json_buf.items, .{ .pretty = false });
    defer allocator.free(xml);
    
    // Verify start and end
    try testing.expect(std.mem.indexOf(u8, xml, "<items type=\"list\">") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<item type=\"int\">0</item>") != null);
    try testing.expect(std.mem.indexOf(u8, xml, "<item type=\"int\">99</item>") != null);
}
