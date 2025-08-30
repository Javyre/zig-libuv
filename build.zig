const std = @import("std");

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn build(b: *std.Build) !void {
    const libuv_dep = b.dependency("libuv", .{});

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libuv_mod = try add_libuv_module(b, libuv_dep, target, optimize);
    const libuv_static = b.addLibrary(.{
        .name = "libuv",
        .linkage = .static,
        .root_module = libuv_mod,
    });
    libuv_static.installHeadersDirectory(libuv_dep.path("include"), "", .{});
    b.installArtifact(libuv_static);

    const uv = b.addModule("uv", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    uv.linkLibrary(libuv_static);

    const tests = b.addTest(.{
        .name = "pixman-test",
        .root_module = uv,
    });

    const test_step = b.step("test", "Run tests");
    const tests_run = b.addRunArtifact(tests);
    test_step.dependOn(&tests_run.step);
}

pub fn add_libuv_module(
    b: *std.Build,
    libuv_dep: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Module {
    const include_path = libuv_dep.path("include");
    const src_path = libuv_dep.path("src");

    const libuv_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Include dirs
    libuv_mod.addIncludePath(include_path);
    libuv_mod.addIncludePath(src_path);

    // Links
    if (target.result.os.tag == .windows) {
        libuv_mod.linkSystemLibrary("psapi", .{});
        libuv_mod.linkSystemLibrary("user32", .{});
        libuv_mod.linkSystemLibrary("advapi32", .{});
        libuv_mod.linkSystemLibrary("iphlpapi", .{});
        libuv_mod.linkSystemLibrary("userenv", .{});
        libuv_mod.linkSystemLibrary("ws2_32", .{});
    }
    if (target.result.os.tag == .linux) {
        libuv_mod.linkSystemLibrary("pthread", .{});
    }

    // Compilation
    var flags: std.ArrayList([]const u8) = .empty;
    defer flags.deinit(b.allocator);

    if (target.result.os.tag != .windows) {
        try flags.appendSlice(b.allocator, &.{
            "-D_FILE_OFFSET_BITS=64",
            "-D_LARGEFILE_SOURCE",
        });
    }

    if (target.result.os.tag == .linux) {
        try flags.appendSlice(b.allocator, &.{
            "-D_GNU_SOURCE",
            "-D_POSIX_C_SOURCE=200112",
        });
    }

    if (target.result.os.tag.isDarwin()) {
        try flags.appendSlice(b.allocator, &.{
            "-D_DARWIN_UNLIMITED_SELECT=1",
            "-D_DARWIN_USE_64_BIT_INODE=1",
        });
    }

    // C files common to all platforms
    libuv_mod.addCSourceFiles(.{
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
        libuv_mod.addCSourceFiles(.{
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

    if (target.result.os.tag == .linux or target.result.os.tag.isDarwin()) {
        libuv_mod.addCSourceFiles(.{
            .root = src_path,
            .files = &.{"unix/proctitle.c"},
            .flags = flags.items,
        });
    }

    if (target.result.os.tag == .linux) {
        libuv_mod.addCSourceFiles(.{
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

    if (target.result.os.tag.isDarwin() or
        target.result.os.tag.isBSD())
    {
        libuv_mod.addCSourceFiles(.{
            .root = src_path,
            .files = &.{
                "unix/bsd-ifaddrs.c",
                "unix/kqueue.c",
            },
            .flags = flags.items,
        });
    }

    if (target.result.os.tag.isDarwin() or target.result.os.tag == .openbsd) {
        libuv_mod.addCSourceFiles(.{
            .root = src_path,
            .files = &.{"unix/random-getentropy.c"},
            .flags = flags.items,
        });
    }

    if (target.result.os.tag.isDarwin()) {
        libuv_mod.addCSourceFiles(.{
            .root = src_path,
            .files = &.{
                "unix/darwin-proctitle.c",
                "unix/darwin.c",
                "unix/fsevents.c",
            },
            .flags = flags.items,
        });
    }

    return libuv_mod;
}
