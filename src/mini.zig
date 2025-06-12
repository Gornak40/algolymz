const std = @import("std");

const Line = union(enum) {
    const Pair = struct {
        key: []const u8,
        value: []const u8,
    };

    simple: Pair, // key = value
    flag: []const u8, // flag
    link: Pair, // $type = id
    include: []const u8, // %id
};

const TypeItems = std.StringArrayHashMap(std.ArrayList(Line));

const ParserState = enum {
    initial,
    sectype,
    secid,
};

// TODO: extend
pub const ParseError = std.mem.Allocator.Error || error{
    InvalidSectionId,
    InvalidSectionType,
};

const innerContext = struct {
    type: ?[]const u8 = null,
    id: ?[]const u8 = null,
};

fn innerParse(alloc: std.mem.Allocator, types: anytype, s: []const u8) ParseError!void {
    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    _ = types;
    var state: ParserState = .initial;
    var ctx: innerContext = .{};
    defer {
        if (ctx.id) |id| alloc.free(id);
        if (ctx.type) |typ| alloc.free(typ);
    }
    for (s) |c| {
        switch (state) {
            .initial => {
                switch (c) {
                    '[' => state = .sectype,
                    else => {
                        // TODO
                    },
                }
            },
            .sectype => {
                switch (c) {
                    '@' => {
                        if (buf.items.len == 0)
                            return ParseError.InvalidSectionType;
                        ctx.type = try buf.toOwnedSlice();
                        state = .secid;
                    },
                    'a'...'z', '_' => try buf.append(c),
                    else => return ParseError.InvalidSectionType,
                }
            },
            .secid => {
                switch (c) {
                    ']' => {
                        if (buf.items.len == 0)
                            return ParseError.InvalidSectionId;
                        ctx.id = try buf.toOwnedSlice();
                        state = .initial;
                    },
                    'a'...'z', '_' => try buf.append(c),
                    else => return ParseError.InvalidSectionId,
                }
            },
        }
    }
    // TODO: check state
}

pub fn parseFromSlice(comptime T: type, alloc: std.mem.Allocator, s: []const u8) ParseError!T {
    var types = std.StringArrayHashMap(TypeItems).init(alloc);
    defer types.deinit();
    try innerParse(alloc, types, s);
    return .{};
}

test "inner parser" {
    const parse = struct {
        fn parse(comptime s: []const u8) !void {
            _ = try parseFromSlice(struct {}, std.testing.allocator, s);
        }
    }.parse;

    try std.testing.expectError(error.InvalidSectionType, parse("[amogus]"));
    try std.testing.expectError(error.InvalidSectionType, parse("[ amogus@sugoma]"));
    try std.testing.expectError(error.InvalidSectionId, parse("[amogus@]"));
    try parse("[amogus@sugoma]");
}
