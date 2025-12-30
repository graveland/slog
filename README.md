# Structured Logging for Zig
[![Zig Docs](https://img.shields.io/badge/docs-zig-%23f7a41d)](https://graveland.github.io/slog)

`slog` is a configurable, structured logging package for Zig with support for hierarchical loggers.
![img](./doc/log-output.png)

## Usage
Add `slog` to your `build.zig.zon`
```
zig fetch --save git+https://github.com/graveland/slog
```

Example code:
```zig
const std = @import("std");
const slog = @import("slog");

pub fn main() !void {
    var log = try slog.initRootLogger(std.heap.page_allocator, .{});
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
}
```


## Compile-Time Log Level Filtering

slog supports compile-time log level filtering to completely eliminate log calls from release builds. This provides zero runtime overhead for filtered log levels.

### Build Options

| Option | Description | Default |
|--------|-------------|---------|
| `-Dmin_log_level=<level>` | Minimum log level to compile | `trace` (Debug), `info` (Release) |
| `-Dlog_compile_verbose=true` | Show compile-time messages when logs are filtered | `false` |

Valid levels: `trace`, `debug`, `info`, `warn`, `error`

### Usage

```bash
# Default: trace in debug builds, info in release builds
zig build

# Force only warn+ logs in any build
zig build -Dmin_log_level=warn

# Release build with debug logs enabled
zig build -Doptimize=ReleaseFast -Dmin_log_level=debug
```

### Runtime Introspection

You can check the compiled minimum level at runtime:

```zig
const slog = @import("slog");
std.debug.print("min_log_level = {s}\n", .{@tagName(slog.min_log_level)});
```

### Performance

In release builds, LLVM completely eliminates filtered log calls including argument evaluation:

```zig
// When min_log_level > debug, this entire line compiles to nothing
logger.debug("msg", .{ .value = expensive_computation() });
```

**Benchmark results** (10,000 iterations calling `expensiveComputation()`):

| Build Mode | min_log_level | Time | Dead Code Eliminated |
|------------|---------------|------|---------------------|
| Debug | trace | 10,798ms | No |
| Debug | info | 10,080ms | No (args still evaluated) |
| ReleaseSafe | info | 0ms | Yes |
| ReleaseFast | info | 0ms | Yes |
| ReleaseSmall | info | 0ms | Yes |

### Interaction with Runtime Filtering

Compile-time filtering sets a floor. Runtime filtering via `ZIG_LOG` can further restrict but cannot enable levels below the compile-time minimum:

- Compile with `-Dmin_log_level=info` → trace/debug calls don't exist in binary
- Setting `ZIG_LOG=debug` at runtime has no effect on debug logs (they're not in the binary)
- Setting `ZIG_LOG=warn` at runtime restricts to warn/error only

## Environment Variables

* `ZIG_LOG` - configures runtime log level, e.g. `info,mod1=debug,mod2.mod3=warn`.
* `ZIG_LOG_COLORS` - configures color scheme for text logger, e.g. `timestamp=31;1,logger=33`.

## Dependencies

* [zeit](https://github.com/rockorager/zeit?tab=readme-ov-file) - a great date and time library for Zig
