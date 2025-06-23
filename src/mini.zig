const std = @import("std");

const InnerPattern = enum {
    header,
    simple,
    flag,
    anchor,
    empty,

    const Token = enum {
        @"[",
        @"::",
        @"]",
        @"$",
        @"=",
        identifier,
        value,
    };

    var mapping = std.EnumArray(InnerPattern, []const Token).init(.{
        .header = &[_]Token{ .@"[", .identifier, .@"::", .identifier, .@"]" },
        .simple = &[_]Token{ .identifier, .@"=", .value },
        .flag = &[_]Token{.identifier},
        .anchor = &[_]Token{ .@"$", .identifier, .@"=", .identifier, .@"::", .identifier },
        .empty = &[_]Token{},
    });

    pub fn match(s: []const u8) !InnerPattern {
        var iter = mapping.iterator();
        while (iter.next()) |e| {
            if (matchOne(s, e.value.*)) return e.key;
        }
        return error.InvalidPattern;
    }

    fn isIdentifierChar(c: u8) bool {
        return std.ascii.isLower(c) or c == '_';
    }

    fn matchOne(s: []const u8, pattern: []const Token) bool {
        var i: usize = 0;
        for (pattern) |token| {
            while (i < s.len and std.ascii.isWhitespace(s[i])) : (i += 1) {}
            if (i == s.len or s[i] == '#') return false;
            switch (token) {
                .@"[" => {
                    if (s[i] != '[') return false;
                    i += 1;
                },
                .@"::" => {
                    if (s[i] != ':' or i + 1 == s.len or s[i + 1] != ':') return false;
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
                    while (i < s.len and isIdentifierChar(s[i])) : (i += 1) {}
                },
                .value => {
                    // TODO: better "" handle
                    i = s.len;
                },
            }
        }
        return while (i < s.len and std.ascii.isWhitespace(s[i])) : (i += 1) {} else i == s.len or s[i] == '#';
    }
};

fn innerParse(_: std.mem.Allocator, s: []const u8) !void {
    var iter = std.mem.splitScalar(u8, s, '\n');
    while (iter.next()) |line| {
        const p = try InnerPattern.match(line);
        std.debug.print("SOLVE: {s} {}\n", .{ line, p });
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
        \\flag_on
        \\$aboba = aboba::aboltus
    ;
    _ = try parseFromSlice(struct {}, std.testing.allocator, config);
}
