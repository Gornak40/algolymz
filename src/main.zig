const std = @import("std");

const Polygon = @import("Polygon.zig");

pub fn main() !void {
    var heap = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = heap.deinit();

    const api_key = readEnv("POLYGON_API_KEY");
    const api_secret = readEnv("POLYGON_API_SECRET");

    var cli = Polygon.init(heap.allocator(), .{
        .api_key = api_key,
        .api_secret = api_secret,
    });
    defer cli.deinit();

    const info = try cli.problemInfo("427411");
    std.log.info("Time limit: {}", .{info.timeLimit});
}

fn readEnv(name: []const u8) []const u8 {
    return std.posix.getenv(name) orelse "";
}
