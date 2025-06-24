const std = @import("std");

const InnerPattern = union(enum) {
    header: struct { []const u8, []const u8 },
    simple: struct { []const u8, []const u8 },
    flag: struct { []const u8 },
    anchor: struct { []const u8, []const u8, []const u8 },
    empty: struct {},

    const Enum = std.meta.Tag(InnerPattern);

    const Token = enum {
        @"[",
        @"::",
        @"]",
        @"$",
        @"=",
        identifier,
        value,

        fn hasMeta(self: Token) bool {
            return self == .identifier or self == .value;
        }
    };

    fn getPattern(self: Enum) []const Token {
        return switch (self) {
            .header => &[_]Token{ .@"[", .identifier, .@"::", .identifier, .@"]" },
            .simple => &[_]Token{ .identifier, .@"=", .value },
            .flag => &[_]Token{.identifier},
            .anchor => &[_]Token{ .@"$", .identifier, .@"=", .identifier, .@"::", .identifier },
            .empty => &[_]Token{},
        };
    }

    pub fn match(s: []const u8) !InnerPattern {
        inline for (std.meta.fields(Enum)) |f| {
            const field = @field(Enum, f.name);
            const pattern = comptime getPattern(field);
            comptime var cap = 0;
            inline for (pattern) |token| {
                if (comptime token.hasMeta()) cap += 1;
            }
            var buf: [cap][]const u8 = undefined;
            if (matchOne(s, pattern, &buf)) {
                var meta: std.meta.Tuple(&[_]type{[]const u8} ** cap) = undefined;
                inline for (0..cap) |i|
                    meta[i] = buf[i];
                return @unionInit(InnerPattern, f.name, meta);
            }
        }
        return error.InvalidPattern;
    }

    test "match" {
        try std.testing.expectEqualDeep(InnerPattern{ .header = .{ "type", "name" } }, try match("[type::name]"));
        try std.testing.expectEqualDeep(InnerPattern{ .simple = .{ "key", "value" } }, try match("key  = value"));
        try std.testing.expectEqualDeep(InnerPattern{ .flag = .{"key"} }, try match(" key # comment"));
        try std.testing.expectEqualDeep(InnerPattern{ .anchor = .{ "key", "type", "name" } }, try match("$key =  type::name"));
        try std.testing.expectEqualDeep(InnerPattern{ .empty = .{} }, try match(""));
        try std.testing.expectError(error.InvalidPattern, match("$key = type::[name]"));
    }

    fn isIdentifierChar(c: u8) bool {
        return std.ascii.isLower(c) or c == '_';
    }

    fn matchOne(s: []const u8, pattern: []const Token, buf: [][]const u8) bool {
        var i: usize = 0;
        var buf_i: usize = 0;
        for (pattern) |token| {
            while (i < s.len and std.ascii.isWhitespace(s[i])) : (i += 1) {}
            if (i >= s.len or s[i] == '#') return false;
            switch (token) {
                .@"[" => {
                    if (s[i] != '[') return false;
                    i += 1;
                },
                .@"::" => {
                    if (s[i] != ':' or i + 1 >= s.len or s[i + 1] != ':') return false;
                    i += 2;
                },
                .@"]" => {
                    if (s[i] != ']') return false;
                    i += 1;
                },
                .@"$" => {
                    if (s[i] != '$') return false;
                    i += 1;
                },
                .@"=" => {
                    if (s[i] != '=') return false;
                    i += 1;
                },
                .identifier => {
                    const start = i;
                    while (i < s.len and isIdentifierChar(s[i])) : (i += 1) {}
                    buf[buf_i] = s[start..i];
                    buf_i += 1;
                },
                .value => {
                    const start = i;
                    i = s.len;
                    buf[buf_i] = s[start..i];
                    buf_i += 1;
                },
            }
        }
        return while (i < s.len and std.ascii.isWhitespace(s[i])) : (i += 1) {} else i >= s.len or s[i] == '#';
    }
};

pub const Parser = struct {
    base_alloc: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    data: std.StringHashMap(Collection),

    const Collection = std.StringArrayHashMap([]const InnerPattern);

    pub fn init(base_alloc: std.mem.Allocator) !Parser {
        var arena = try base_alloc.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(base_alloc);
        return .{
            .base_alloc = base_alloc,
            .arena = arena,
            .data = std.StringHashMap(Collection).init(arena.allocator()),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.arena.deinit();
        self.base_alloc.destroy(self.arena);
    }

    pub fn feed(self: *Parser, s: []const u8) !void {
        var header: ?struct { []const u8, []const u8 } = null;
        var fields = std.ArrayList(InnerPattern).init(self.arena.allocator());
        var iter = std.mem.splitScalar(u8, s, '\n');
        while (iter.next()) |line| {
            const p = try InnerPattern.match(line);
            std.debug.print("TAG {s}: {s}\n", .{ line, @tagName(p) });
            switch (p) {
                .header => |cur_header| {
                    if (header) |prev_header| {
                        try self.appendField(prev_header, try fields.toOwnedSlice());
                    }
                    header = cur_header;
                },
                .simple, .flag, .anchor => {
                    if (header) |_| try fields.append(p) else return error.MissingHeader;
                },
                .empty => continue,
            }
        } else if (header) |cur_header| {
            try self.appendField(cur_header, try fields.toOwnedSlice());
        }
    }

    fn appendField(self: *Parser, header: struct { []const u8, []const u8 }, fields: []const InnerPattern) !void {
        var entry = try self.data.getOrPut(header[0]);
        if (!entry.found_existing) {
            entry.value_ptr.* = Collection.init(self.arena.allocator());
        }
        const res = try entry.value_ptr.getOrPutValue(header[1], fields);
        if (res.found_existing) return error.DuplicateName;
    }
};

test "parse from slice" {
    const config =
        \\[aboba::aboltus]
        \\key = 13 # ok it's it
        \\
        \\ [amogus::sugoma]
        \\
        \\key = value
        \\# just a comment
        \\key = 0
        \\ key  = "sus aboba" # I'm comment
        \\flag_on
        \\$aboba = aboba::aboltus
    ;
    var p = try Parser.init(std.testing.allocator);
    defer p.deinit();
    _ = try p.feed(config);
}
