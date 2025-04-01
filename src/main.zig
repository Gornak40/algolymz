const std = @import("std");

const Polygon = @import("Polygon.zig");

pub fn main() !void {
    var heap = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = heap.deinit();

    const api_key = std.posix.getenv("POLYGON_API_KEY") orelse "";
    const api_secret = std.posix.getenv("POLYGON_API_SECRET") orelse "";

    var cli = Polygon.init(heap.allocator(), .{
        .api_key = api_key,
        .api_secret = api_secret,
    });
    defer cli.deinit();

    try cli.problemInfo("427411");
}
