const std = @import("std");

fn getVersion(b: *std.Build) []const u8 {
    const src_dir = std.fs.path.dirname(@src().file) orelse ".";
    var exit_code: u8 = 0;
    const git_hash = b.runAllowFail(&[_][]const u8{
        "git", "-C", src_dir, "rev-parse", "HEAD",
    }, &exit_code, .Inherit) catch return "unknown";
    return std.mem.trim(u8, git_hash, &std.ascii.whitespace);
}

/// Creates the slog module with injected dependencies.
/// Use this when incorporating slog as a dependency to share modules with parent.
/// The caller must provide the path to slog's src/root.zig.
pub fn createModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zeit_mod: *std.Build.Module,
    /// Path to slog's src/root.zig (use b.path("deps/slog/src/root.zig") from parent)
    root_source_file: std.Build.LazyPath,
) *std.Build.Module {
    const slog_mod = b.addModule("slog", .{
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });
    slog_mod.addImport("zeit", zeit_mod);

    const options = b.addOptions();
    options.addOption([]const u8, "version", getVersion(b));
    slog_mod.addOptions("build_options", options);

    return slog_mod;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Fetch zeit dependency (for standalone use)
    const dep_zeit = b.dependency("zeit", .{
        .target = target,
        .optimize = optimize,
    });
    const mod_zeit = dep_zeit.module("zeit");

    // Create module (standalone mode uses b.path which is package-relative)
    const lib_mod = b.addModule("slog", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addImport("zeit", mod_zeit);

    const build_opts = b.addOptions();
    build_opts.addOption([]const u8, "version", getVersion(b));
    lib_mod.addOptions("build_options", build_opts);

    // Static library
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "slog",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    // Unit tests
    const test_filters = b.option([]const []const u8, "test-filter", "Skip tests that do not match any filter") orelse &.{};
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
        .filters = test_filters,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Debug
    {
        const lldb = b.addSystemCommand(&.{
            "lldb",
            "--",
        });
        lldb.addArtifactArg(lib_unit_tests);

        const lldb_step = b.step("debug", "run the tests under lldb");
        lldb_step.dependOn(&lldb.step);
    }

    // Example
    {
        const example_mod = b.createModule(.{
            .root_source_file = b.path("example/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        example_mod.addImport("slog", lib_mod);
        const exe = b.addExecutable(.{
            .name = "example",
            .root_module = example_mod,
        });
        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);

        const run_step = b.step("run-example", "Run the example");
        run_step.dependOn(&run_cmd.step);
    }

    // Docs
    {
        const install_docs = b.addInstallDirectory(.{
            .source_dir = lib.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });

        const docs_step = b.step("docs", "Install docs into zig-out/docs");
        docs_step.dependOn(&install_docs.step);
    }
}
