const std = @import("std");
const slog = @import("slog");

pub fn main() !void {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator);
    defer threaded.deinit();
    const io = threaded.io();

    var log = try slog.initRootLogger(std.heap.page_allocator, io, .{});
    defer log.deinit();

    var log2 = try log.initChildLogger("mod1");
    var log3 = try log2.initChildLogger("mod2");
    var log4 = try log3.initChildLogger("mod3");

    log.info("Hello slog!", .{ .field1 = "value1", .field2 = "value1", .rate = 30 });
    log2.trace("Hello slog!", .{ .field1 = "value1", .field2 = "value2", .rate = 30 });
    log2.debug("Hello slog!", .{ .field1 = "value1", .field2 = "value3", .rate = 30 });
    log2.info("Hello slog!", .{ .field1 = "value1", .field2 = "value4", .rate = 30e2 });
    log3.warn("Hello slog!", .{ .field1 = "value1", .field2 = "value5", .rate = 30.34534 });
    log3.err("Hello slog!", .{ .field1 = "value1", .field2 = "value6", .rate = 30, .active = true, .metadata = null });
    log4.err("Hello slog!", .{ .field1 = "value1", .field2 = "value6", .rate = 30, .active = true, .metadata = null });

    // Test formatted logging
    log.infof("Formatted: count={d}, name={s}", .{ 42, "test" });
    log2.debugf("Debug formatted: value={d}", .{123});
    log3.warnf("Warning: {s} at position {d}", .{ "error", 10 });

    var jlog = try slog.initRootLogger(std.heap.page_allocator, io, .{ .formatter = .json });
    jlog.info("Hello slog!", .{ .field1 = "value1", .field2 = "value1", .rate = 30 });
    defer jlog.deinit();
}
