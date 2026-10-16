//! Compile-only gate for opaque-ui: references every public declaration so
//! the compiler type-checks all of it. Apps only compile the components they
//! use, so without this a broken component goes unnoticed until someone
//! reaches for it. `theme.zig` and `config.zig` stand in for an app's own.

const std = @import("std");
const Opaque = @import("opaque_ui");

/// Takes a reference to every public declaration of `T` and recurses into
/// opaque-ui's own container types (all of them live in `src/components/`).
/// Generic functions are only named.
fn refAll(comptime T: type, comptime depth: usize) void {
    if (depth == 0) return;
    @setEvalBranchQuota(100_000);
    inline for (comptime std.meta.declarations(T)) |decl| {
        const Value = @TypeOf(@field(T, decl.name));
        if (Value == type) {
            const Decl = @field(T, decl.name);
            switch (@typeInfo(Decl)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => {
                    if (comptime std.mem.startsWith(u8, @typeName(Decl), "components.")) refAll(Decl, depth - 1);
                },
                else => {},
            }
            continue;
        }
        switch (@typeInfo(Value)) {
            .@"fn" => |info| {
                if (info.is_generic or info.is_var_args) {
                    _ = @field(T, decl.name);
                } else {
                    _ = &@field(T, decl.name);
                }
            },
            else => _ = @field(T, decl.name),
        }
    }
}

export fn __opaque_ui_check() void {
    refAll(Opaque, 4);
}
