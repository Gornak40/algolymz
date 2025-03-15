const std = @import("std");

pub const Config = struct {
    polygon_url: []const u8 = "https://polygon.codeforces.com",
    api_key: []const u8,
    api_secret: []const u8,
};

const Self = @This();

alloc: std.mem.Allocator,
hcli: std.http.Client,
cfg: Config,

pub fn init(alloc: std.mem.Allocator, cfg: Config) Self {
    return .{
        .alloc = alloc,
        .hcli = .{ .allocator = alloc }, // TODO: make it thread safe.
        .cfg = cfg,
    };
}

pub fn deinit(self: *Self) void {
    self.hcli.deinit();
}

pub fn problemInfo(self: *Self) !void {
    std.log.info("Prepare problem.info request", .{});
    try self.sendApi("problem.info");
}

const ApiParam = struct {
    name: []const u8,
    value: []const u8,

    fn lessThan(_: void, a: ApiParam, b: ApiParam) bool {
        return switch (std.mem.order(u8, a.name, b.name)) {
            .lt => true,
            .eq => std.mem.lessThan(u8, a.value, b.value),
            .gt => false,
        };
    }
};

fn apiParamsToBody(alloc: std.mem.Allocator, params: []ApiParam) ![]const u8 {
    std.mem.sort(ApiParam, params, {}, ApiParam.lessThan);
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    for (params) |p| {
        try std.fmt.format(buf.writer(), "{s}={s}&", p);
    }
    if (params.len > 0) {
        _ = buf.pop();
    }
    std.log.info("Prepare body {s}", .{buf.items});
    return buf.toOwnedSlice();
}

fn sendApi(self: *Self, api_method: []const u8) !void {
    const url = try std.fmt.allocPrint(self.alloc, "{s}/api/{s}", .{ self.cfg.polygon_url, api_method });
    defer self.alloc.free(url);
    std.log.info("Prepare URL: {s}", .{url});

    var params = std.ArrayList(ApiParam).init(self.alloc);
    defer params.deinit();
    try params.append(.{ .name = "apiKey", .value = self.cfg.api_secret });
    const time = try std.fmt.allocPrint(self.alloc, "{d}", .{std.time.timestamp()});
    defer self.alloc.free(time);
    try params.append(.{ .name = "time", .value = time });

    const body = try apiParamsToBody(self.alloc, params.items);
    defer self.alloc.free(body);
    try self.sendRaw(url, body);
}

fn sendRaw(self: *Self, url: []const u8, body: []const u8) !void {
    const uri = try std.Uri.parse(url);
    var head: [4096]u8 = undefined;
    var req = try self.hcli.open(.POST, uri, .{
        .server_header_buffer = &head,
    });
    defer req.deinit();
    req.transfer_encoding = .{
        .content_length = body.len,
    };
    req.headers.content_type = .{ .override = "application/x-www-form-urlencoded" };
    try req.send();
    std.log.info("Send request...", .{});
    try req.writeAll(body);
    try req.finish();
    try req.wait();

    std.log.info("Response status: {d}", .{@intFromEnum(req.response.status)});
    const resp = try req.reader().readAllAlloc(self.alloc, 4096);
    defer self.alloc.free(resp);
    std.log.info("Response body: {s}", .{resp});
}
