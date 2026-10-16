const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("opaque_ui", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
        .optimize = optimize,
    });

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.

    // Only when opaque-ui is the project being built: as a dependency, its
    // vapor module can be the app's own, and the stand-in theme and config
    // would replace the app's.
    if (b.pkg_hash.len == 0) addCheckStep(b, optimize);
}

/// `zig build check` compiles every exported component for the browser,
/// with check/theme.zig and check/config.zig in place of an app's.
fn addCheckStep(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const vapor_dep = b.dependency("vapor", .{ .target = wasm_target, .optimize = optimize });
    const vapor_module = vapor_dep.module("vapor");

    const config_module = b.createModule(.{ .root_source_file = b.path("check/config.zig") });
    const theme_module = b.createModule(.{
        .root_source_file = b.path("check/theme.zig"),
        .imports = &.{.{ .name = "vapor", .module = vapor_module }},
    });
    vapor_module.addImport("config", config_module);
    vapor_module.addImport("theme", theme_module);

    const ui_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "vapor", .module = vapor_module },
            .{ .name = "theme", .module = theme_module },
            .{ .name = "config", .module = config_module },
        },
    });
    const check_obj = b.addObject(.{
        .name = "opaque-ui-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("check/check.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .imports = &.{.{ .name = "opaque_ui", .module = ui_module }},
        }),
    });
    const check_step = b.step("check", "Type-check every exported component");
    check_step.dependOn(&check_obj.step);
}
