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

    const id = 427411;
    std.log.info("Time limit: {}", .{(try cli.problemInfo(id)).timeLimit});
    for (try cli.problemViewTags(id)) |tag| {
        std.log.info("Problem tag: {s}", .{tag});
    }
    std.log.info("Description: {s}", .{try cli.problemViewGeneralDescription(id)});
    for (try cli.problemPackages(id)) |package| {
        std.log.info("Problem package: {} {} {s}", .{ package.id, package.revision, package.type });
    }
}

fn readEnv(name: []const u8) []const u8 {
    return std.posix.getenv(name) orelse "";
}
