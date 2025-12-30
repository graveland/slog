const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const zeit = @import("zeit");
const TimeZone = zeit.TimeZone;

const EventDispatcher = @import("./EventDispatcher.zig");
const LogHandler = @import("./LogHandler.zig");
const LogLevelSpec = @import("./LogLevelSpec.zig");
const Node = @import("./LogLevelSpecNode.zig");
const util = @import("./util.zig");
const Level = util.Level;
const LogEvent = util.LogEvent;
const Field = util.Field;
const Value = util.Value;

const Self = @This();

name: ?[]const u8,
allocator: std.mem.Allocator,
io: std.Io,
constant_fields: ?[]Field = null,
dispatcher: EventDispatcher,
parent: ?*Self,
kids: std.ArrayList(*Self),
kids_mutex: std.Thread.Mutex = .{},
is_root: bool,

timezone: *TimeZone,

pub fn init(name: ?[]const u8, spec: LogLevelSpec, handler: *LogHandler, alloc: Allocator, io: std.Io) !*Self {
    var spec_node = spec.root;
    const self = try alloc.create(Self);

    const tz = try alloc.create(TimeZone);
    tz.* = try zeit.local(alloc, io, null);

    if (name) |root_name| {
        var name_chunk_it = std.mem.splitScalar(u8, root_name, '.');
        while (name_chunk_it.next()) |sub_node_name| {
            if (spec_node.kids.get(sub_node_name)) |kid| {
                // This kid has the same name as the root -> promote it to the root.
                kid.configured_log_level = kid.logLevel();
                kid.parent = null;
                _ = spec_node.kids.remove(sub_node_name);
                spec_node.deinit();
                spec_node = kid;
            } else break;
        }
    }

    self.* = .{
        .name = if (name) |n| try alloc.dupe(u8, n) else null,
        .allocator = alloc,
        .io = io,
        .dispatcher = EventDispatcher{
            .handler = handler,
            .spec = spec_node,
            .log_level = spec_node.logLevel(),
        },
        .parent = null,
        .kids = std.ArrayList(*Self).empty,
        .is_root = true,
        .timezone = tz,
    };
    return self;
}

pub fn deinit(self: *Self) void {
    // Clear parent pointers before iterating to prevent kids from trying to
    // remove themselves from our list during cleanup (iterator invalidation).
    // Hold the lock while clearing parent pointers to prevent races with initChildLogger.
    self.kids_mutex.lock();
    for (self.kids.items) |kid| kid.parent = null;
    self.kids_mutex.unlock();
    for (self.kids.items) |kid| kid.deinit();
    self.kids.deinit(self.allocator);

    if (self.constant_fields) |fields| fields: {
        if (self.parent) |parent| {
            if (parent.constant_fields) |parent_fields| {
                if (parent_fields.ptr == fields.ptr) break :fields;
            }
        }
        self.deinitFields(fields, true);
    }

    if (self.name) |name| self.allocator.free(name);
    if (self.parent) |parent| {
        parent.removeKid(self);
    }
    // Only root logger owns and frees shared resources
    if (self.is_root) {
        self.timezone.deinit();
        self.allocator.destroy(self.timezone);

        self.dispatcher.handler.deinit();
        if (self.dispatcher.spec) |spec| spec.deinit();

        self.allocator.destroy(self.dispatcher.handler);
    }
    self.allocator.destroy(self);
}

fn deinitFields(self: *const Self, fields: []Field, free_values: bool) void {
    for (fields) |f| {
        if (free_values) {
            self.allocator.free(f.name);
            switch (f.value) {
                .string => |str| self.allocator.free(str),
                else => {},
            }
        }
        // Always free allocated_string values - these are owned by the logger
        switch (f.value) {
            .allocated_string => |str| self.allocator.free(str),
            else => {},
        }
    }
    self.allocator.free(fields);
}

pub fn initChildLogger(self: *Self, name: []const u8) !*Self {
    var lname: []u8 = undefined;
    if (self.name) |self_name| {
        lname = try self.allocator.alloc(u8, self_name.len + name.len + 1);
        @memcpy(lname[0..self_name.len], self_name);
        lname[self_name.len] = '.';
        @memcpy(lname[self_name.len + 1 ..], name);
    } else {
        lname = try self.allocator.dupe(u8, name);
    }

    const kid = try self.allocator.create(Self);

    kid.* = Self{
        .name = lname,
        .allocator = self.allocator,
        .io = self.io,
        .constant_fields = self.constant_fields,
        .dispatcher = self.dispatcher.createChildDispatcher(name),
        .parent = self,
        .kids = std.ArrayList(*Self).empty,
        .is_root = false,
        .timezone = self.timezone,
    };
    self.kids_mutex.lock();
    defer self.kids_mutex.unlock();
    try self.kids.append(self.allocator, kid);
    return kid;
}

fn removeKid(self: *Self, kid_ptr: *const Self) void {
    self.kids_mutex.lock();
    defer self.kids_mutex.unlock();
    var kids_index: ?usize = null;
    for (self.kids.items, 0..) |kid, ix| {
        if (kid == kid_ptr) {
            kids_index = ix;
            break;
        }
    }
    if (kids_index) |ix| {
        _ = self.kids.swapRemove(ix);
    } else unreachable;
}

pub fn trace(self: *Self, message: []const u8, fields: anytype) void {
    comptime if (@import("build_options").log_compile_verbose and !util.levelEnabled(.trace)) {
        @compileLog("slog: trace logs compiled out");
    };
    if (comptime !util.levelEnabled(.trace)) return;
    return self.log(Level.trace, message, fields) catch return;
}

pub fn debug(self: *Self, message: []const u8, fields: anytype) void {
    comptime if (@import("build_options").log_compile_verbose and !util.levelEnabled(.debug)) {
        @compileLog("slog: debug logs compiled out");
    };
    if (comptime !util.levelEnabled(.debug)) return;
    return self.log(Level.debug, message, fields) catch return;
}

pub fn info(self: *Self, message: []const u8, fields: anytype) void {
    comptime if (@import("build_options").log_compile_verbose and !util.levelEnabled(.info)) {
        @compileLog("slog: info logs compiled out");
    };
    if (comptime !util.levelEnabled(.info)) return;
    return self.log(Level.info, message, fields) catch return;
}

pub fn warn(self: *Self, message: []const u8, fields: anytype) void {
    comptime if (@import("build_options").log_compile_verbose and !util.levelEnabled(.warn)) {
        @compileLog("slog: warn logs compiled out");
    };
    if (comptime !util.levelEnabled(.warn)) return;
    return self.log(Level.warn, message, fields) catch return;
}

pub fn err(self: *Self, message: []const u8, fields: anytype) void {
    comptime if (@import("build_options").log_compile_verbose and !util.levelEnabled(.@"error")) {
        @compileLog("slog: error logs compiled out");
    };
    if (comptime !util.levelEnabled(.@"error")) return;
    return self.log(Level.@"error", message, fields) catch return;
}

pub fn tracef(self: *Self, comptime fmt: []const u8, args: anytype) void {
    comptime if (@import("build_options").log_compile_verbose and !util.levelEnabled(.trace)) {
        @compileLog("slog: tracef logs compiled out");
    };
    if (comptime !util.levelEnabled(.trace)) return;
    return self.logf(Level.trace, fmt, args) catch return;
}

pub fn debugf(self: *Self, comptime fmt: []const u8, args: anytype) void {
    comptime if (@import("build_options").log_compile_verbose and !util.levelEnabled(.debug)) {
        @compileLog("slog: debugf logs compiled out");
    };
    if (comptime !util.levelEnabled(.debug)) return;
    return self.logf(Level.debug, fmt, args) catch return;
}

pub fn infof(self: *Self, comptime fmt: []const u8, args: anytype) void {
    comptime if (@import("build_options").log_compile_verbose and !util.levelEnabled(.info)) {
        @compileLog("slog: infof logs compiled out");
    };
    if (comptime !util.levelEnabled(.info)) return;
    return self.logf(Level.info, fmt, args) catch return;
}

pub fn warnf(self: *Self, comptime fmt: []const u8, args: anytype) void {
    comptime if (@import("build_options").log_compile_verbose and !util.levelEnabled(.warn)) {
        @compileLog("slog: warnf logs compiled out");
    };
    if (comptime !util.levelEnabled(.warn)) return;
    return self.logf(Level.warn, fmt, args) catch return;
}

pub fn errf(self: *Self, comptime fmt: []const u8, args: anytype) void {
    comptime if (@import("build_options").log_compile_verbose and !util.levelEnabled(.@"error")) {
        @compileLog("slog: errf logs compiled out");
    };
    if (comptime !util.levelEnabled(.@"error")) return;
    return self.logf(Level.@"error", fmt, args) catch return;
}

fn logf(self: *Self, level: Level, comptime fmt: []const u8, args: anytype) !void {
    var buf: [4096]u8 = undefined;
    const message = std.fmt.bufPrint(&buf, fmt, args) catch |e| switch (e) {
        error.NoSpaceLeft => blk: {
            const truncated = "(message truncated) ";
            @memcpy(buf[buf.len - truncated.len ..], truncated);
            break :blk &buf;
        },
    };
    return self.log(level, message, .{});
}

fn log(self: *Self, level: Level, message: []const u8, fields: anytype) !void {
    // Note: LogEvent is stack-allocated; only toFieldList() may allocate for user-supplied fields
    var event = LogEvent{
        .timestamp = try zeit.instant(.{ .io = self.io, .source = .now, .timezone = self.timezone }),
        .logger_name = self.name,
        .level = level,
        .message = message,
        .constant_fields = self.constant_fields,
        .fields = try toFieldList(fields, self.allocator),
    };
    defer self.deinitFields(event.fields, false);

    try self.dispatcher.dispatch(&event);
}

fn toFieldList(fields: anytype, alloc: Allocator) ![]Field {
    const FieldsType = @TypeOf(fields);
    const ti = @typeInfo(FieldsType);
    if (ti != .@"struct") {
        @compileError(std.fmt.comptimePrint("expected struct, but found {s}={any}", .{ @typeName(FieldsType), fields }));
    }

    const ff = ti.@"struct".fields;

    // Early return for empty structs - no allocation needed
    if (ff.len == 0) {
        return &[0]Field{};
    }

    // Use comptime-sized stack array - ff.len is known at compile time
    var stack_fields: [ff.len]Field = undefined;

    inline for (ff, 0..) |field, i| {
        const field_type = @typeInfo(field.type);
        const field_val = @field(fields, field.name);
        const value: Value = switch (field_type) {
            .pointer, .int, .comptime_int, .float, .comptime_float, .bool, .null => try toPlainValue(field_val, alloc),
            .optional => if (field_val) |val| try toPlainValue(val, alloc) else Value.null,
            else => {
                @compileError(std.fmt.comptimePrint("unsupported type: {any}", .{field_type}));
            },
        };
        stack_fields[i] = Field{ .name = field.name, .value = value };
    }

    return try alloc.dupe(Field, stack_fields[0..ff.len]);
}

fn toPlainValue(value: anytype, alloc: std.mem.Allocator) std.mem.Allocator.Error!Value {
    const field_type = @typeInfo(@TypeOf(value));
    return val: switch (field_type) {
        .pointer => |pti| {
            const cti = @typeInfo(pti.child);
            if (pti.child == u8 or cti == .array and cti.array.child == u8) {
                break :val Value{ .string = value };
            }
            @compileError(std.fmt.comptimePrint("unsupported pointer type: {any}", .{field_type}));
        },
        .int => |int_info| if (int_info.bits > 64) {
            break :val Value{ .allocated_string = try std.fmt.allocPrint(alloc, "{d}", .{value}) };
        } else if (int_info.signedness == .unsigned) {
            break :val Value{ .uinteger = @intCast(value) };
        } else {
            break :val Value{ .integer = @intCast(value) };
        },
        .comptime_int => Value{ .integer = @intCast(value) },
        .float, .comptime_float => Value{ .float = @floatCast(value) },
        .bool => Value{ .bool = value },
        .null => Value.null,
        else => {
            @compileError(std.fmt.comptimePrint("not a plain type: {any}", .{field_type}));
        },
    };
}

test "toField string" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();

    const x = try al.dupe(u8, "v2");
    const result = try toFieldList(.{ .field1 = "v1", .field2 = x }, al);

    try testing.expectEqual(2, result.len);
    try testing.expectEqualStrings("field1", result[0].name);
    try testing.expectEqualStrings("v1", result[0].value.string);
    try testing.expectEqualStrings("v2", result[1].value.string);
}

test "toField optional" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();

    const v1: ?usize = null;
    const v2: ?i64 = 34;
    const result = try toFieldList(.{ .field1 = v1, .field2 = v2 }, al);

    try testing.expectEqual(2, result.len);
    try testing.expectEqual(Value.null, result[0].value);
    try testing.expectEqual(34, result[1].value.integer);
}
