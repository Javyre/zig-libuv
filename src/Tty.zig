//! Tty handles represent a stream for the console.
const Tty = @This();

const std = @import("std");
const fd_t = std.posix.fd_t;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const c = @import("c.zig");
const errors = @import("error.zig");
const Loop = @import("Loop.zig");
const Handle = @import("handle.zig").Handle;
const Stream = @import("stream.zig").Stream;

handle: *c.uv_tty_t,

pub usingnamespace Handle(Tty);
pub usingnamespace Stream(Tty);

pub fn init(alloc: Allocator, loop: Loop, fd: fd_t) !Tty {
    const tty = try alloc.create(c.uv_tty_t);
    errdefer alloc.destroy(tty);
    try errors.convertError(c.uv_tty_init(loop.loop, tty, fd, 0));
    return Tty{ .handle = tty };
}

pub fn deinit(self: *Tty, alloc: Allocator) void {
    alloc.destroy(self.handle);
    self.* = undefined;
}

pub const Mode = enum(c.uv_tty_mode_t) {
    /// Initial/normal terminal mode
    normal = c.UV_TTY_MODE_NORMAL,
    /// Raw input mode (On Windows, ENABLE_WINDOW_INPUT is also enabled)
    raw = c.UV_TTY_MODE_RAW,
    /// Binary-safe I/O mode for IPC (Unix-only)
    io = c.UV_TTY_MODE_IO,
};

/// Set the TTY using the specified terminal mode.
pub fn setMode(self: *const Tty, mode: Mode) !void {
    const res = c.uv_tty_set_mode(self.handle, @intFromEnum(mode));
    try errors.convertError(res);
}

/// To be called when the program exits. Resets TTY settings to default values
/// for the next process to take over.
///
/// This function is async signal-safe on Unix platforms but can fail with error
/// code EBUSY if you call it when execution is inside Tty.setMode().
pub fn resetMode() !void {
    const res = c.uv_tty_reset_mode();
    try errors.convertError(res);
}
