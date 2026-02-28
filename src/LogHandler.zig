const std = @import("std");
const builtin = @import("builtin");

const Formatter = @import("./formatter.zig").Formatter;
const Output = @import("./root.zig").Output;
const util = @import("./util.zig");
const Level = util.Level;
const LogEvent = util.LogEvent;

const Self = @This();

output: Output,
formatter: Formatter,
io: std.Io,
mutex: std.Io.Mutex = .init,

pub fn deinit(self: *Self) void {
    self.formatter.deinit();
}

pub fn handle(self: *Self, event: *const LogEvent) !void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);

    var buf: [4096]u8 = undefined;
    switch (self.output) {
        .file => |f| {
            var w = f.writer(self.io, &buf);
            try self.formatter.format(&w.interface, event);
            try w.interface.flush();
        },
        .writer => |w| {
            try self.formatter.format(w, event);
            try w.flush();
        },
    }
}
