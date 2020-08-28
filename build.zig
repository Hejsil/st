const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) !void {
    b.setPreferredReleaseMode(.ReleaseFast);
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});
    const cflags = [_][]const u8{
        "-std=gnu99",
        "-DVERSION=\"0.8.1\"",
        "-D_XOPEN_SOURCE=600",
    };

    const exe = b.addExecutable("zt", null);
    exe.install();
    exe.setBuildMode(mode);
    exe.setTarget(target);

    for ([_][]const u8{
        "c",
        "m",
        "rt",
        "X11",
        "util",
        "Xft",
        "fontconfig",
        "freetype2",
    }) |lib| {
        exe.linkSystemLibrary(lib);
    }

    for ([_][]const u8{
        "st",
        "x",
    }) |name| {
        exe.addCSourceFile(b.fmt("{}.c", .{name}), &cflags);
    }

    for ([_][]const u8{
        "st",
    }) |name| {
        const lib = b.addStaticLibrary(name, b.fmt("{}.zig", .{name}));
        for ([_][]const u8{
            "c",
        }) |l| {
            lib.linkSystemLibrary(l);
        }

        exe.linkLibrary(lib);
    }

    const run_step = b.step("run", "Run the zt");
    run_step.dependOn(&exe.run().step);
    b.default_step.dependOn(&exe.step);
}
