// scales/scale.zig
pub const ScaleType = enum {
    linear,
    log,
    sqrt,
    // time, // future
};

pub const DomainConfig = union(enum) {
    auto,
    auto_zero, // auto but include 0
    manual: [2]f64,
};

pub const ScaleConfig = struct {
    type: ScaleType = .linear,
    domain: DomainConfig = .auto,
    nice: bool = true,
    padding: f64 = 0.05, // 5% padding
};

// scales/scale.zig
const LinearScale = @import("linear.zig").LinearScale;
const LogScale = @import("log.zig").LogScale;
const std = @import("std");

pub const Scale = union(enum) {
    linear: LinearScale,
    log: LogScale,

    pub fn scale(self: Scale, value: f64) f64 {
        return switch (self) {
            .linear => |s| s.scale(value),
            .log => |s| s.scale(value),
        };
    }

    pub fn ticks(self: Scale, count: usize, allocator: std.mem.Allocator) ![]f64 {
        return switch (self) {
            .linear => |s| s.ticks(count, allocator),
            .log => |s| s.ticks(count, allocator),
        };
    }

    pub fn domainMin(self: Scale) f64 {
        return switch (self) {
            .linear => |s| s.domain_min,
            .log => |s| s.domain_min,
        };
    }

    pub fn domainMax(self: Scale) f64 {
        return switch (self) {
            .linear => |s| s.domain_max,
            .log => |s| s.domain_max,
        };
    }

    pub fn rangeMin(self: Scale) f64 {
        return switch (self) {
            .linear => |s| s.range_min,
            .log => |s| s.range_min,
        };
    }

    pub fn rangeMax(self: Scale) f64 {
        return switch (self) {
            .linear => |s| s.range_max,
            .log => |s| s.range_max,
        };
    }

    pub fn invert(self: Scale, range_val: f64) f64 {
        return switch (self) {
            .linear => |s| s.invert(range_val),
            .log => |s| s.invert(range_val),
        };
    }
};
