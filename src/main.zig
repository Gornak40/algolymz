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
    std.log.info("Tutorial: {s}", .{try cli.problemViewGeneralTutorial(id)});
    for (try cli.problemPackages(id)) |package| {
        std.log.info("Problem package: {} {} {}", .{ package.id, package.revision, @intFromEnum(package.type) });
    }
    std.log.info("Build full package with verify", .{});
    cli.problemBuildPackage(id, true, true) catch |err| {
        std.log.err("{}", .{err});
    };
    try cli.problemEnableGroups(id, true, .{});
    try cli.problemEnablePoints(id, true);
    for (try cli.problemViewTestGroup(id, null, .{})) |group| {
        std.log.info("Test group: {s} {} {}", .{ group.name, @intFromEnum(group.pointsPolicy), @intFromEnum(group.feedbackPolicy) });
    }
    std.log.info("Tests count: {}", .{(try cli.problemTests(id, false, .{})).len});
    std.log.info("Save script", .{});
    try cli.problemSaveScript(id, "gen 123 > 2\ngen > 3", .{});
}

fn readEnv(name: []const u8) []const u8 {
    return std.posix.getenv(name) orelse "";
}
