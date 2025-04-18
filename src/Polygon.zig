// Copyright (C) 2025 Alexander Gornak <s-kozelsk@yandex.ru>

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

pub const File = struct {
    name: []const u8,
    modificationTimeSeconds: i32,
    length: usize,
    sourceType: ?[]const u8 = null,
    resourceAdvancedProperties: ?ResourceAdvancedProperties = null,

    pub const ResourceAdvancedProperties = struct {
        forTypes: []const u8,
        main: bool,
        stages: []Stage,
        assets: []Asset,

        pub const Stage = enum {
            COMPILE,
            RUN,
        };

        pub const Asset = enum {
            VALIDATOR,
            INTERACTOR,
            CHECKER,
            SOLUTION,
        };
    };
};

pub const Files = struct {
    resourceFiles: []File,
    sourceFiles: []File,
    auxFiles: []File,
};

pub const Package = struct {
    id: i32,
    revision: i32,
    creationTimeSeconds: i32,
    state: State,
    comment: []const u8,
    type: Type,

    pub const State = enum {
        PENDING,
        RUNNING,
        READY,
        FAILED,
    };

    pub const Type = enum {
        standard,
        linux,
        windows,
    };
};

pub const Problem = struct {
    id: i32,
    owner: []const u8,
    name: []const u8,
    deleted: bool,
    favourite: bool,
    accessType: ?AccessType = null,
    revision: i32,
    latestPackage: ?i32 = null,
    modified: bool,

    pub const AccessType = enum {
        READ,
        WRITE,
        OWNER,
    };
};

pub const ProblemInfo = struct {
    inputFile: []const u8,
    outputFile: []const u8,
    interactive: bool,
    timeLimit: i32,
    memoryLimit: i32,
};

pub const Solution = struct {
    name: []const u8,
    modificationTimeSeconds: i32,
    length: usize,
    sourceType: []const u8,
    tag: Tag,

    pub const Tag = enum { MA, OK, RJ, TL, TO, WA, PE, ML, RE };
};

pub const Statement = struct {
    encoding: []const u8,
    name: []const u8,
    legend: []const u8,
    input: []const u8,
    output: []const u8,
    scoring: ?[]const u8 = null,
    interaction: ?[]const u8 = null,
    notes: []const u8,
    tutorial: []const u8,
};

pub const Test = struct {
    index: i32,
    manual: bool,
    input: ?[]const u8 = null,
    inputBase64: ?[]const u8 = null,
    description: ?[]const u8 = null,
    useInStatements: bool,
    scriptLine: ?[]const u8 = null,
    group: ?[]const u8 = null,
    points: ?f64 = null,
    inputForStatement: ?[]const u8 = null,
    outputForStatement: ?[]const u8 = null,
    verifyInputOutputForStatements: ?bool = null,
};

pub const TestGroup = struct {
    name: []const u8,
    pointsPolicy: PointsPolicy,
    feedbackPolicy: FeedbackPolicy,
    dependencies: [][]const u8,

    pub const PointsPolicy = enum {
        COMPLETE_GROUP,
        EACH_TEST,
    };

    pub const FeedbackPolicy = enum {
        NONE,
        POINTS,
        ICPC,
        COMPLETE,
    };
};

pub const TestsetOption = struct {
    name: []const u8 = "tests",
};

/// Returns a list of `Problem` objects - problems of the contest.
pub fn contestProblems(self: *Self, contestId: i32) !std.json.ArrayHashMap(Problem) {
    const args = .{ .contestId = contestId };
    return try sendApi(self, std.json.ArrayHashMap(Problem), "contest.problems", args);
}

/// Starts to build a new `Package`.
pub fn problemBuildPackage(self: *Self, problemId: i32, full: bool, verify: bool) !void {
    const args = .{ .problemId = problemId, .full = full, .verify = verify };
    try sendApi(self, void, "problem.buildPackage", args);
}

/// Enable or disable test points for the problem.
pub fn problemEnablePoints(self: *Self, problemId: i32, enable: bool) !void {
    const args = .{ .problemId = problemId, .enable = enable };
    try sendApi(self, void, "problem.enablePoints", args);
}

/// Enable or disable test groups for the specified testset.
pub fn problemEnableGroups(self: *Self, problemId: i32, enable: bool, testset: TestsetOption) !void {
    const args = .{ .problemId = problemId, .enable = enable, .testset = testset.name };
    try sendApi(self, void, "problem.enableGroups", args);
}

/// Returns the list of resource, source and aux files.
/// Method returns a JSON object with three fields:
/// resourceFiles, sourceFiles and auxFiles, each of them is a list of `File` objects.
pub fn problemFiles(self: *Self, problemId: i32) !Files {
    const args = .{ .problemId = problemId };
    return try sendApi(self, Files, "problem.files", args);
}

/// Returns a `ProblemInfo` object.
pub fn problemInfo(self: *Self, problemId: i32) !ProblemInfo {
    const args = .{ .problemId = problemId };
    return try sendApi(self, ProblemInfo, "problem.info", args);
}

/// Returns a list of `Package` objects - list all packages available for the problem
pub fn problemPackages(self: *Self, problemId: i32) ![]Package {
    const args = .{ .problemId = problemId };
    return try sendApi(self, []Package, "problem.packages", args);
}

/// Add or edit test. In case of editing, all parameters except for testset and testIndex are optional.
pub fn problemSaveScript(self: *Self, problemId: i32, source: []const u8, testset: TestsetOption) !void {
    const args = .{ .problemId = problemId, .source = source, .testset = testset.name };
    try sendApi(self, void, "problem.saveScript", args);
}

pub const ProblemSaveSolutionOptions = struct {
    problemId: i32,
    checkExisting: ?bool = null,
    name: []const u8,
    file: ?[]const u8 = null,
    sourceType: ?[]const u8 = null,
    tag: ?Solution.Tag = null,
};

/// Add or edit solution. In case of editing, all parameters except for name are optional.
pub fn problemSaveSolution(self: *Self, opts: ProblemSaveSolutionOptions) !void {
    try sendApi(self, void, "problem.saveSolution", opts);
}

pub const ProblemSaveTestOptions = struct {
    problemId: i32,
    checkExisting: ?bool = null,
    testset: []const u8 = (TestsetOption{}).name,
    testIndex: i32,
    testInput: ?[]const u8 = null,
    testGroup: ?[]const u8 = null,
    testPoints: ?f64 = null,
    testDescription: ?[]const u8 = null,
    testUseInStatements: ?bool = null,
    testInputForStatements: ?[]const u8 = null,
    testOutputForStatements: ?[]const u8 = null,
    verifyInputOutputForStatements: ?bool = null,
};

/// Add or edit test. In case of editing, all parameters except for testset and testIndex are optional.
pub fn problemSaveTest(self: *Self, opts: ProblemSaveTestOptions) !void {
    try sendApi(self, void, "problem.saveTest", opts);
}

/// Update checker.
pub fn problemSetChecker(self: *Self, problemId: i32, checker: []const u8) !void {
    const args = .{ .problemId = problemId, .checker = checker };
    try sendApi(self, void, "problem.setChecker", args);
}

/// Update validator.
pub fn problemSetValidator(self: *Self, problemId: i32, validator: []const u8) !void {
    const args = .{ .problemId = problemId, .validator = validator };
    try sendApi(self, void, "problem.setValidator", args);
}

/// Returns the list of `Solution` objects.
pub fn problemSolutions(self: *Self, problemId: i32) ![]Solution {
    const args = .{ .problemId = problemId };
    return try sendApi(self, []Solution, "problem.solutions", args);
}

/// Returns a map from language to a `Statement` object for that language.
pub fn problemStatements(self: *Self, problemId: i32) !std.json.ArrayHashMap(Statement) {
    const args = .{ .problemId = problemId };
    return try sendApi(self, std.json.ArrayHashMap(Statement), "problem.statements", args);
}

/// Returns tests for the given testset.
pub fn problemTests(self: *Self, problemId: i32, noInputs: bool, testset: TestsetOption) ![]Test {
    const args = .{ .problemId = problemId, .noInputs = noInputs, .testset = testset.name };
    return try sendApi(self, []Test, "problem.tests", args);
}

/// Returns problem general description.
pub fn problemViewGeneralDescription(self: *Self, problemId: i32) ![]const u8 {
    const args = .{ .problemId = problemId };
    return try sendApi(self, []const u8, "problem.viewGeneralDescription", args);
}

/// Returns problem general tutorial.
pub fn problemViewGeneralTutorial(self: *Self, problemId: i32) ![]const u8 {
    const args = .{ .problemId = problemId };
    return try sendApi(self, []const u8, "problem.viewGeneralTutorial", args);
}

/// Returns tags for the problem.
pub fn problemViewTags(self: *Self, problemId: i32) ![][]const u8 {
    const args = .{ .problemId = problemId };
    return try sendApi(self, [][]const u8, "problem.viewTags", args);
}

/// Returns test groups for the specified testset.
///
/// Pass `null` to `group` to get all test groups.
pub fn problemViewTestGroup(self: *Self, problemId: i32, group: ?[]const u8, testset: TestsetOption) ![]TestGroup {
    const args = .{ .problemId = problemId, .testset = testset.name, .group = group };
    return try sendApi(self, []TestGroup, "problem.viewTestGroup", args);
}

fn Result(comptime T: type) type {
    return struct {
        status: enum {
            OK,
            FAILED,
        },
        comment: ?[]const u8 = null,
        result: if (T == void) ?struct {} else ?T = null,
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

fn reflectType(alloc: std.mem.Allocator, value: anytype) !?[]const u8 {
    return switch (@typeInfo(@TypeOf(value))) {
        inline .Int, .Bool => try std.fmt.allocPrint(alloc, "{}", .{value}),
        inline .Float => try std.fmt.allocPrint(alloc, "{d}", .{value}),
        inline .Optional => if (value) |v| try reflectType(alloc, v) else null,
        inline .Enum => @tagName(value),
        else => value,
    };
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
        const value = try reflectType(fba.allocator(), @field(args, field.name));
        if (value) |value_str| {
            const param = ApiParam{
                .name = field.name,
                .value = value_str,
            };
            try params.append(param);
        }
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
    return switch (result.status) {
        .OK => if (T == void) {} else result.result.?,
        .FAILED => error.PolygonRequestFailed,
    };
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
    var resp_list = try std.ArrayList(u8).initCapacity(self.alloc, 1024);
    errdefer resp_list.deinit();
    try req.reader().readAllArrayList(&resp_list, std.math.maxInt(usize));
    return resp_list.toOwnedSlice();
}
