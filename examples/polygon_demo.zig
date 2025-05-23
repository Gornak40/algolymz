const std = @import("std");

const Polygon = @import("algolymz").Polygon;

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

    const cid = 41977;
    const cont = (try cli.contestProblems(cid)).map;
    var it = cont.iterator();
    while (it.next()) |e| {
        std.log.info("Problem {s}: {s}", .{ e.key_ptr.*, e.value_ptr.name });
    }

    const pid = 427411;
    std.log.info("Update working copy", .{});
    try cli.problemUpdateWorkingCopy(pid);
    std.log.info("Time limit: {}", .{(try cli.problemInfo(pid)).timeLimit});
    for (try cli.problemViewTags(pid)) |tag| {
        std.log.info("Problem tag: {s}", .{tag});
    }
    std.log.info("Description: {s}", .{try cli.problemViewGeneralDescription(pid)});
    std.log.info("Tutorial: {s}", .{try cli.problemViewGeneralTutorial(pid)});
    for (try cli.problemPackages(pid)) |package| {
        std.log.info("Problem package: {} {} {}", .{ package.id, package.revision, @intFromEnum(package.type) });
    }
    std.log.info("Build full package with verify", .{});
    cli.problemBuildPackage(pid, true, true) catch |err| {
        std.log.err("{}", .{err});
    };
    try cli.problemEnableGroups(pid, true, .{});
    try cli.problemEnablePoints(pid, true);
    for (try cli.problemViewTestGroup(pid, null, .{})) |group| {
        std.log.info("Test group: {s} {} {}", .{ group.name, @intFromEnum(group.pointsPolicy), @intFromEnum(group.feedbackPolicy) });
    }
    std.log.info("Tests count: {}", .{(try cli.problemTests(pid, false, .{})).len});
    std.log.info("Save script", .{});
    try cli.problemSaveScript(pid, "gen 123 > 2\ngen > 3", .{});
    const st = try cli.problemStatements(pid);
    std.log.info("Problem name: {s}", .{st.map.get("russian").?.name});
    std.log.info("Problem source files: {}", .{(try cli.problemFiles(pid)).sourceFiles.len});
    for (try cli.problemSolutions(pid)) |sol| {
        std.log.info("Problem solution: {s}", .{sol.name});
    }
    std.log.info("Problem save solution", .{});
    try cli.problemSaveSolution(.{
        .problemId = pid,
        .name = "algolymz.py",
        .file = "print('Hello')",
        .tag = .WA,
    });
    std.log.info("Problem save test", .{});
    try cli.problemSaveTest(.{
        .problemId = pid,
        .testIndex = 1,
        .testInput = "1\n2\n3",
        .testPoints = 2,
    });
    std.log.info("Problem set checker", .{});
    try cli.problemSetChecker(pid, "std::lcmp.cpp");
    std.log.info("Problem set validator", .{});
    try cli.problemSetValidator(pid, "val.cpp");
    std.log.info("Make problem interactive", .{});
    try cli.problemUpdateInfo(.{ .problemId = pid, .interactive = true });
    std.log.info("Problem set interactor", .{});
    try cli.problemSetInteractor(pid, "val.cpp");
}

fn readEnv(name: []const u8) []const u8 {
    return std.posix.getenv(name) orelse "";
}
