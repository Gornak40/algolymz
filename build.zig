const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("algolymz", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const polygon_demo_exe = b.addExecutable(.{
        .name = "polygon_demo",
        .root_source_file = b.path("examples/polygon_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    polygon_demo_exe.root_module.addImport("algolymz", module);
    b.installArtifact(polygon_demo_exe);
    b.default_step.dependOn(&polygon_demo_exe.step);

    const polygon_demo_step = b.step("demo", "Run polygon demo example");
    const run_cmd = b.addRunArtifact(polygon_demo_exe);
    polygon_demo_step.dependOn(&run_cmd.step);
}
