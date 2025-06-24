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

    var buffer: [256]u8 = undefined;

    pub fn match(s: []const u8) !InnerPattern {
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        inline for (std.meta.fields(Enum)) |f| {
            const field = @field(Enum, f.name);
            const pattern = comptime getPattern(field);
            comptime var cap = 0;
            inline for (pattern) |token| {
                if (token == .identifier or token == .value)
                    cap += 1;
            }
            var buf = std.ArrayList([]const u8).initCapacity(fba.allocator(), cap) catch unreachable;
            if (matchOne(s, pattern, &buf)) {
                var meta: std.meta.Tuple(&[_]type{[]const u8} ** cap) = undefined;
                inline for (0..cap) |i| {
                    meta[i] = buf.items[i];
                }
                return @unionInit(InnerPattern, f.name, meta);
            }
            fba.reset();
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

    fn matchOne(s: []const u8, pattern: []const Token, buf: *std.ArrayList([]const u8)) bool {
        var i: usize = 0;
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
                    const str = s[start..i];
                    buf.appendAssumeCapacity(str);
                },
                .value => {
                    const start = i;
                    i = s.len;
                    const str = s[start..i];
                    buf.appendAssumeCapacity(str);
                },
            }
        }
        return while (i < s.len and std.ascii.isWhitespace(s[i])) : (i += 1) {} else i >= s.len or s[i] == '#';
    }
};

fn innerParse(_: std.mem.Allocator, s: []const u8) !void {
    var iter = std.mem.splitScalar(u8, s, '\n');
    while (iter.next()) |line| {
        const p = try InnerPattern.match(line);
        std.debug.print("TAG {s}: {s}\n", .{ line, @tagName(p) });
    }
}

pub fn parseFromSlice(comptime T: type, alloc: std.mem.Allocator, s: []const u8) !T {
    try innerParse(alloc, s);
    return .{};
}

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
    _ = try parseFromSlice(struct {}, std.testing.allocator, config);
}
