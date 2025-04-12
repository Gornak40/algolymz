const std = @import("std");
const Sha512 = std.crypto.hash.sha2.Sha512;

pub const Config = struct {
    polygon_url: []const u8 = "https://polygon.codeforces.com",
    api_key: []const u8,
    api_secret: []const u8,
};

const Self = @This();

alloc: std.mem.Allocator,
client: std.http.Client,
config: Config,

var arena: std.heap.ArenaAllocator = undefined;

pub fn init(alloc: std.mem.Allocator, config: Config) Self {
    arena = std.heap.ArenaAllocator.init(alloc);
    return .{
        .alloc = alloc,
        .client = .{ .allocator = alloc }, // TODO: make it thread safe.
        .config = config,
    };
}

pub fn deinit(self: *Self) void {
    arena.deinit();
    self.client.deinit();
}

pub const Package = struct {
    id: i32,
    revision: i32,
    creationTimeSeconds: i32,
    state: []const u8,
    comment: []const u8,
    type: []const u8,
};

pub const Problem = struct {
    id: i32,
    owner: []const u8,
    name: []const u8,
    deleted: bool,
    favourite: bool,
    accessType: []const u8,
    revision: i32,
    latestPackage: ?i32 = null,
    modified: bool,
};

pub const ProblemInfo = struct {
    inputFile: []const u8,
    outputFile: []const u8,
    interactive: bool,
    timeLimit: i32,
    memoryLimit: i32,
};

pub fn problemInfo(self: *Self, problemId: i32) !ProblemInfo {
    const args = .{ .problemId = problemId };
    return try sendApi(self, ProblemInfo, "problem.info", args);
}

pub fn problemPackages(self: *Self, problemId: i32) ![]Package {
    const args = .{ .problemId = problemId };
    return try sendApi(self, []Package, "problem.packages", args);
}

pub fn problemViewGeneralDescription(self: *Self, problemId: i32) ![]const u8 {
    const args = .{ .problemId = problemId };
    return try sendApi(self, []const u8, "problem.viewGeneralDescription", args);
}

pub fn problemViewTags(self: *Self, problemId: i32) ![][]const u8 {
    const args = .{ .problemId = problemId };
    return try sendApi(self, [][]const u8, "problem.viewTags", args);
}

fn Result(comptime T: type) type {
    return struct {
        status: []const u8,
        comment: ?[]const u8 = null,
        result: ?T = null,
    };
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

fn apiParamsToBody(self: *Self, params: []ApiParam) ![]const u8 {
    var buf = std.ArrayList(u8).init(self.alloc);
    errdefer buf.deinit();
    for (params) |p| {
        try std.fmt.format(buf.writer(), "{s}={s}&", p);
    }
    if (params.len > 0) {
        _ = buf.pop();
    }
    return buf.toOwnedSlice();
}

const rand_str = "gorill";
const sig_length = rand_str.len + Sha512.digest_length * 2;

fn apiParamSig(self: *Self, api_method: []const u8, params: []ApiParam) ![sig_length]u8 {
    var buf = std.ArrayList(u8).init(self.alloc);
    defer buf.deinit();
    try std.fmt.format(buf.writer(), "{s}/{s}?", .{ rand_str, api_method });

    std.mem.sort(ApiParam, params, {}, ApiParam.lessThan);
    for (params) |p| {
        try std.fmt.format(buf.writer(), "{s}={s}&", p);
    }
    if (params.len > 0) {
        _ = buf.pop();
    }

    try std.fmt.format(buf.writer(), "#{s}", .{self.config.api_secret});
    var out: [Sha512.digest_length]u8 = undefined;
    Sha512.hash(buf.items, &out, .{});
    var sign: [sig_length]u8 = undefined;
    @memcpy(sign[0..rand_str.len], rand_str);
    @memcpy(sign[rand_str.len..], &std.fmt.bytesToHex(out, .lower));
    return sign;
}

fn sendApi(self: *Self, comptime T: type, api_method: []const u8, args: anytype) !T {
    std.log.info("Invoke {s} request", .{api_method});

    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .Struct) {
        @compileError("expected struct argument, found " ++ @typeName(ArgsType));
    }

    const url = try std.fmt.allocPrint(self.alloc, "{s}/api/{s}", .{ self.config.polygon_url, api_method });
    defer self.alloc.free(url);
    std.log.info("Prepare URL: {s}", .{url});

    var params = std.ArrayList(ApiParam).init(self.alloc);
    defer params.deinit();
    try params.append(.{ .name = "apiKey", .value = self.config.api_key });
    var timeBuf: [14]u8 = undefined;
    const time = try std.fmt.bufPrint(&timeBuf, "{d}", .{std.time.timestamp()});
    try params.append(.{ .name = "time", .value = time });

    const fields_info = args_type_info.Struct.fields;
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    inline for (fields_info) |field| {
        const value = switch (@typeInfo(field.type)) {
            .Int => try std.fmt.allocPrint(fba.allocator(), "{}", .{@field(args, field.name)}),
            else => @field(args, field.name),
        };
        const param = ApiParam{
            .name = field.name,
            .value = value,
        };
        try params.append(param);
    }

    const sign = try apiParamSig(self, api_method, params.items);
    try params.append(.{ .name = "apiSig", .value = &sign });

    const body = try apiParamsToBody(self, params.items);
    defer self.alloc.free(body);
    const resp = try sendRaw(self, url, body);
    defer self.alloc.free(resp);

    const result = std.json.parseFromSliceLeaky(Result(T), arena.allocator(), resp, .{ .allocate = .alloc_always }) catch |err| {
        std.log.err("Bad response: {s}", .{resp});
        return err;
    };
    errdefer std.log.err("Polygon comment: {?s}", .{result.comment});
    if (std.mem.eql(u8, result.status, "FAILED")) {
        return error.PolygonRequestFailed;
    }
    return result.result.?;
}

fn sendRaw(self: *Self, url: []const u8, body: []const u8) ![]const u8 {
    const uri = try std.Uri.parse(url);
    var head_buf: [4096]u8 = undefined;
    var req = try self.client.open(.POST, uri, .{ .server_header_buffer = &head_buf });
    defer req.deinit();
    req.transfer_encoding = .{ .content_length = body.len };
    req.headers.content_type = .{ .override = "application/x-www-form-urlencoded" };

    try req.send();
    std.log.info("Sending request body ({} bytes)", .{body.len});
    try req.writeAll(body);
    try req.finish();
    try req.wait();

    std.log.info("Response status: {}", .{@intFromEnum(req.response.status)});
    var resp_list = try std.ArrayList(u8).initCapacity(self.alloc, 4096);
    errdefer resp_list.deinit();
    try req.reader().readAllArrayList(&resp_list, 4096);
    return resp_list.toOwnedSlice();
}
