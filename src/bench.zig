const std = @import("std");
const slog = @import("root.zig");
const util = @import("util.zig");

/// Simulates expensive computation - if this runs when filtered, benchmark will be slow.
fn expensiveComputation() []const u8 {
    var sum: u64 = 0;
    for (0..1_000_000) |i| {
        sum +%= i;
    }
    // Prevent optimization from removing the loop entirely
    if (sum == 0) return "zero";
    return "computed";
}

/// Benchmark: debug logging with expensive argument when min_log_level > debug.
/// If dead code elimination works, expensiveComputation() should NOT execute.
pub fn benchDebugFiltered(logger: *slog.Logger) void {
    for (0..10_000) |_| {
        logger.debug("benchmark test", .{ .value = expensiveComputation() });
    }
}

/// Benchmark: debug logging with static argument (baseline for comparison).
pub fn benchDebugStatic(logger: *slog.Logger) void {
    for (0..10_000) |_| {
        logger.debug("benchmark test", .{ .value = "static" });
    }
}

/// Simple test that runs the benchmark and reports timing.
pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    var threaded = std.Io.Threaded.init(gpa);
    defer threaded.deinit();
    const io = threaded.io();

    // Suppress actual log output by using error level
    var logger = try slog.initRootLogger(gpa, io, .{
        .log_spec = .{ .from_string = "error" },
    });
    defer logger.deinit();

    std.debug.print("slog.min_log_level = {s}\n", .{@tagName(slog.min_log_level)});

    // Warm up
    benchDebugFiltered(logger);

    // Timed run
    var timer = std.time.Timer.start() catch @panic("no timer");
    benchDebugFiltered(logger);
    const elapsed_ns = timer.read();

    std.debug.print("benchDebugFiltered: {d}ms ({d}ns/iter)\n", .{
        elapsed_ns / 1_000_000,
        elapsed_ns / 10_000,
    });

    // If min_log_level > debug, this should be ~0ms
    // If min_log_level <= debug, this will be slow due to expensiveComputation()
}

test "verify comptime level" {
    const expected_level: util.Level = switch (@import("builtin").mode) {
        .Debug => .trace,
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .info,
    };

    // If build option overrides, this test may fail - that's expected
    // The test is just to verify the default behavior
    if (@import("build_options").min_log_level == null) {
        try std.testing.expectEqual(expected_level, slog.min_log_level);
    }
}
