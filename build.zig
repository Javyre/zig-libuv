const std = @import("std");

/// Directories with our includes.
const include_path = "vendor/libuv/include/";
const src_path = "vendor/libuv/src/";

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libuv = try buildLibuv(b, target, optimize);
    b.installArtifact(libuv);

    const uv = b.addModule("uv", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    uv.linkLibrary(libuv);

    const tests = b.addTest(.{
        .name = "pixman-test",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.linkLibrary(libuv);

    const test_step = b.step("test", "Run tests");
    const tests_run = b.addRunArtifact(tests);
    test_step.dependOn(&tests_run.step);
}

pub fn buildLibuv(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "libuv",
        .target = target,
        .optimize = optimize,
    });

    // Include dirs
    lib.addIncludePath(b.path(include_path));
    lib.addIncludePath(b.path(src_path));
    lib.installHeadersDirectory(b.path(include_path), "libuv", .{});

    // Links
    if (target.result.os.tag == .windows) {
        lib.linkSystemLibrary("psapi");
        lib.linkSystemLibrary("user32");
        lib.linkSystemLibrary("advapi32");
        lib.linkSystemLibrary("iphlpapi");
        lib.linkSystemLibrary("userenv");
        lib.linkSystemLibrary("ws2_32");
    }
    if (target.result.os.tag == .linux) {
        lib.linkSystemLibrary("pthread");
    }
    lib.linkLibC();

    // Compilation
    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    if (target.result.os.tag != .windows) {
        try flags.appendSlice(&.{
            "-D_FILE_OFFSET_BITS=64",
            "-D_LARGEFILE_SOURCE",
        });
    }

    if (target.result.os.tag == .linux) {
        try flags.appendSlice(&.{
            "-D_GNU_SOURCE",
            "-D_POSIX_C_SOURCE=200112",
        });
    }

    if (target.result.isDarwin()) {
        try flags.appendSlice(&.{
            "-D_DARWIN_UNLIMITED_SELECT=1",
            "-D_DARWIN_USE_64_BIT_INODE=1",
        });
    }

    // C files common to all platforms
    lib.addCSourceFiles(.{ .files = &.{
        src_path ++ "fs-poll.c",
        src_path ++ "idna.c",
        src_path ++ "inet.c",
        src_path ++ "random.c",
        src_path ++ "strscpy.c",
        src_path ++ "strtok.c",
        src_path ++ "threadpool.c",
        src_path ++ "timer.c",
        src_path ++ "uv-common.c",
        src_path ++ "uv-data-getter-setters.c",
        src_path ++ "version.c",
    }, .flags = flags.items });

    if (target.result.os.tag != .windows) {
        lib.addCSourceFiles(.{ .files = &.{
            src_path ++ "unix/async.c",
            src_path ++ "unix/core.c",
            src_path ++ "unix/dl.c",
            src_path ++ "unix/fs.c",
            src_path ++ "unix/getaddrinfo.c",
            src_path ++ "unix/getnameinfo.c",
            src_path ++ "unix/loop-watcher.c",
            src_path ++ "unix/loop.c",
            src_path ++ "unix/pipe.c",
            src_path ++ "unix/poll.c",
            src_path ++ "unix/process.c",
            src_path ++ "unix/random-devurandom.c",
            src_path ++ "unix/signal.c",
            src_path ++ "unix/stream.c",
            src_path ++ "unix/tcp.c",
            src_path ++ "unix/thread.c",
            src_path ++ "unix/tty.c",
            src_path ++ "unix/udp.c",
        }, .flags = flags.items });
    }

    if (target.result.os.tag == .linux or target.result.isDarwin()) {
        lib.addCSourceFiles(.{ .files = &.{
            src_path ++ "unix/proctitle.c",
        }, .flags = flags.items });
    }

    if (target.result.os.tag == .linux) {
        lib.addCSourceFiles(.{ .files = &.{
            src_path ++ "unix/linux.c",
            src_path ++ "unix/procfs-exepath.c",
            src_path ++ "unix/random-getrandom.c",
            src_path ++ "unix/random-sysctl-linux.c",
        }, .flags = flags.items });
    }

    if (target.result.isDarwin() or
        target.result.isBSD())
    {
        lib.addCSourceFiles(.{ .files = &.{
            src_path ++ "unix/bsd-ifaddrs.c",
            src_path ++ "unix/kqueue.c",
        }, .flags = flags.items });
    }

    if (target.result.isDarwin() or target.result.os.tag == .openbsd) {
        lib.addCSourceFiles(.{ .files = &.{
            src_path ++ "unix/random-getentropy.c",
        }, .flags = flags.items });
    }

    if (target.result.isDarwin()) {
        lib.addCSourceFiles(.{ .files = &.{
            src_path ++ "unix/darwin-proctitle.c",
            src_path ++ "unix/darwin.c",
            src_path ++ "unix/fsevents.c",
        }, .flags = flags.items });
    }

    return lib;
}
