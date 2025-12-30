const std = @import("std");

const zeit = @import("zeit");

pub const Level = enum(u3) {
    trace,
    debug,
    info,
    warn,
    @"error",

    pub const ErrInvalid = error.InvalidLogLevel;

    pub fn parse(str: []const u8) error{InvalidLogLevel}!Level {
        if (std.mem.eql(u8, str, "trace")) return Level.trace;
        if (std.mem.eql(u8, str, "debug")) return Level.debug;
        if (std.mem.eql(u8, str, "info")) return Level.info;
        if (std.mem.eql(u8, str, "warn")) return Level.warn;
        if (std.mem.eql(u8, str, "error")) return Level.@"error";
        return ErrInvalid;
    }
};

/// Returns the effective comptime minimum log level based on build options and mode.
pub fn comptimeMinLevel() Level {
    const build_options = @import("build_options");
    const builtin = @import("builtin");

    if (build_options.min_log_level) |level_str| {
        return Level.parse(level_str) catch {
            @compileError("Invalid min_log_level: " ++ level_str);
        };
    }

    return switch (builtin.mode) {
        .Debug => .trace,
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .info,
    };
}

/// Returns true if the given level should be compiled in (not filtered out).
pub fn levelEnabled(comptime level: Level) bool {
    const min = comptimeMinLevel();
    return @intFromEnum(level) >= @intFromEnum(min);
}

pub const Field = struct {
    name: []const u8,
    value: Value,
};

pub const Value = union(enum) {
    null,
    bool: bool,
    integer: i64,
    uinteger: u64,
    float: f64,
    string: []const u8,
    /// String that was allocated by the logger and must be freed
    allocated_string: []const u8,

    pub fn write(self: Value, w: *std.Io.Writer) !void {
        switch (self) {
            .null => try w.writeAll("null"),
            .bool => |x| try w.print("{}", .{x}),
            .integer => |x| try w.print("{d}", .{x}),
            .uinteger => |x| try w.print("{d}", .{x}),
            .float => |x| try w.print("{d:.10}", .{x}),
            .string, .allocated_string => |x| try std.json.Stringify.encodeJsonString(x, .{}, w),
        }
    }
};

pub const LogEvent = struct {
    // Fields ordered by size for optimal packing
    timestamp: zeit.Instant,
    fields: []Field,
    message: []const u8,
    constant_fields: ?[]const Field,
    logger_name: ?[]const u8,
    level: Level,
};
