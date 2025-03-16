const std = @import("std");

const Polygon = @import("Polygon.zig");

pub fn main() !void {
    var arena = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = arena.deinit();

    const api_key = std.posix.getenv("POLYGON_API_KEY") orelse "";
    const api_secret = std.posix.getenv("POLYGON_API_SECRET") orelse "";
    std.log.info("API key: {s}", .{api_key});

    var cli = Polygon.init(arena.allocator(), .{
        .api_key = api_key,
        .api_secret = api_secret,
    });
    defer cli.deinit();

    try cli.problemInfo("427411");
}
