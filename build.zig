const std = @import("std");

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
    const libuv = b.dependency("libuv", .{});
    const include_path = libuv.path("include");
    const src_path = libuv.path("src");

    const lib = b.addStaticLibrary(.{
        .name = "libuv",
        .target = target,
        .optimize = optimize,
    });

    // Include dirs
    lib.addIncludePath(include_path);
    lib.addIncludePath(src_path);
    lib.installHeadersDirectory(include_path, "libuv", .{});

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
    lib.addCSourceFiles(.{
        .root = src_path,
        .files = &.{
            "fs-poll.c",
            "idna.c",
            "inet.c",
            "random.c",
            "strscpy.c",
            "strtok.c",
            "threadpool.c",
            "timer.c",
            "uv-common.c",
            "uv-data-getter-setters.c",
            "version.c",
        },
        .flags = flags.items,
    });

    if (target.result.os.tag != .windows) {
        lib.addCSourceFiles(.{
            .root = src_path,
            .files = &.{
                "unix/async.c",
                "unix/core.c",
                "unix/dl.c",
                "unix/fs.c",
                "unix/getaddrinfo.c",
                "unix/getnameinfo.c",
                "unix/loop-watcher.c",
                "unix/loop.c",
                "unix/pipe.c",
                "unix/poll.c",
                "unix/process.c",
                "unix/random-devurandom.c",
                "unix/signal.c",
                "unix/stream.c",
                "unix/tcp.c",
                "unix/thread.c",
                "unix/tty.c",
                "unix/udp.c",
            },
            .flags = flags.items,
        });
    }

    if (target.result.os.tag == .linux or target.result.isDarwin()) {
        lib.addCSourceFiles(.{
            .root = src_path,
            .files = &.{"unix/proctitle.c"},
            .flags = flags.items,
        });
    }

    if (target.result.os.tag == .linux) {
        lib.addCSourceFiles(.{
            .root = src_path,
            .files = &.{
                "unix/linux.c",
                "unix/procfs-exepath.c",
                "unix/random-getrandom.c",
                "unix/random-sysctl-linux.c",
            },
            .flags = flags.items,
        });
    }

    if (target.result.isDarwin() or
        target.result.isBSD())
    {
        lib.addCSourceFiles(.{
            .root = src_path,
            .files = &.{
                "unix/bsd-ifaddrs.c",
                "unix/kqueue.c",
            },
            .flags = flags.items,
        });
    }

    if (target.result.isDarwin() or target.result.os.tag == .openbsd) {
        lib.addCSourceFiles(.{
            .root = src_path,
            .files = &.{"unix/random-getentropy.c"},
            .flags = flags.items,
        });
    }

    if (target.result.isDarwin()) {
        lib.addCSourceFiles(.{
            .root = src_path,
            .files = &.{
                "unix/darwin-proctitle.c",
                "unix/darwin.c",
                "unix/fsevents.c",
            },
            .flags = flags.items,
        });
    }

    return lib;
}
