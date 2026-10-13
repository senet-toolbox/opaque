const std = @import("std");
const Vapor = @import("vapor");
const Box = Vapor.Box;
const Writer = Vapor.Writer;

/// A simple circular progress bar using SVG stroke-dasharray technique.
///
/// Usage:
/// ```zig
/// var progress = ProgressCircle.init(allocator, .{
///     .size = 120,
///     .stroke_width = 10,
///     .color = .hex("#3b82f6"),
///     .track_color = .hex("#e5e7eb"),
/// });
/// progress.setProgress(0.75); // 75%
/// progress.render();
///
/// // With gradient:
/// var gradient_progress = ProgressCircle.init(allocator, .{
///     .size = 120,
///     .stroke_width = 10,
///     .gradient = .{
///         .type = .linear,
///         .direction = .to_right,
///         .colors = &.{ .hex("#3b82f6"), .hex("#8b5cf6"), .hex("#ec4899") },
///     },
/// });
/// ```
pub const ProgressCircle = struct {
    allocator: std.mem.Allocator,
    config: Config,
    progress: f64 = 0, // 0.0 to 1.0
    current_svg: ?[]const u8 = null,
    platform: Platform,

    pub const Config = struct {
        size: u32 = 120,
        stroke_width: f32 = 10,
        color: ?Vapor.Types.Color = .hex("#3b82f6"),
        gradient: ?Gradient = null, // Use gradient instead of solid color
        track_color: Vapor.Types.Color = .hex("#e5e7eb"),
        track_gradient: ?Gradient = null, // Optional gradient for track
        background: ?Vapor.Types.Color = null,
        show_background: bool = true,
        rounded_caps: bool = true,
        show_label: bool = true,
        label_font_size: u32 = 24,
        label_color: ?Vapor.Types.Color = null,
        label_format: LabelFormat = .percent,
        clockwise: bool = true,
        start_angle: f64 = -90, // Start from top (12 o'clock)
    };

    pub const LabelFormat = enum {
        percent, // "75%"
        decimal, // "0.75"
        fraction, // "75/100"
        none,
    };

    pub const GradientType = enum {
        linear,
        radial,
        conic,
    };

    pub const GradientDirection = enum {
        to_right,
        to_left,
        to_top,
        to_bottom,
        to_top_right,
        to_top_left,
        to_bottom_right,
        to_bottom_left,

        /// Returns SVG gradient coordinates (x1, y1, x2, y2) as percentages
        pub fn toSvgCoords(self: GradientDirection) struct { x1: u8, y1: u8, x2: u8, y2: u8 } {
            return switch (self) {
                .to_right => .{ .x1 = 0, .y1 = 0, .x2 = 100, .y2 = 0 },
                .to_left => .{ .x1 = 100, .y1 = 0, .x2 = 0, .y2 = 0 },
                .to_top => .{ .x1 = 0, .y1 = 100, .x2 = 0, .y2 = 0 },
                .to_bottom => .{ .x1 = 0, .y1 = 0, .x2 = 0, .y2 = 100 },
                .to_top_right => .{ .x1 = 0, .y1 = 100, .x2 = 100, .y2 = 0 },
                .to_top_left => .{ .x1 = 100, .y1 = 100, .x2 = 0, .y2 = 0 },
                .to_bottom_right => .{ .x1 = 0, .y1 = 0, .x2 = 100, .y2 = 100 },
                .to_bottom_left => .{ .x1 = 100, .y1 = 0, .x2 = 0, .y2 = 100 },
            };
        }
    };

    pub const ColorStop = struct {
        color: Vapor.Types.Color,
        offset: ?f32 = null, // 0.0 to 1.0, null means auto-distribute
    };

    pub const Gradient = struct {
        type: GradientType = .linear,
        direction: GradientDirection = .to_right, // For linear gradients
        colors: []const Vapor.Types.Color = &.{}, // Simple color list (auto-distributed)
        stops: []const ColorStop = &.{}, // Or explicit stops with offsets
        // For radial gradients
        cx: f32 = 0.5, // Center X (0-1)
        cy: f32 = 0.5, // Center Y (0-1)
        r: f32 = 0.5, // Radius (0-1)
        // For conic gradients (note: limited SVG support, falls back to linear)
        angle: f32 = 0, // Start angle in degrees
    };

    pub const Platform = union(enum) {
        browser: BrowserPlatform,
        // Future: native: NativePlatform,
    };

    pub const BrowserPlatform = struct {
        pub fn setAttribute(_: BrowserPlatform, id: []const u8, key: []const u8, value: []const u8) void {
            if (!Vapor.lib.isWasi) return;
            Vapor.Wasm.setAttributeWasm(id.ptr, id.len, key.ptr, key.len, value.ptr, value.len);
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) ProgressCircle {
        return .{
            .allocator = allocator,
            .config = config,
            .platform = .{ .browser = .{} },
        };
    }

    pub fn deinit(self: *ProgressCircle) void {
        if (self.current_svg) |svg| {
            self.allocator.free(svg);
        }
    }

    /// Set progress value (0.0 to 1.0)
    pub fn setProgress(self: *ProgressCircle, value: f64) void {
        self.progress = std.math.clamp(value, 0.0, 1.0);
        self.build() catch {};
    }

    /// Set progress as percentage (0 to 100)
    pub fn setPercent(self: *ProgressCircle, percent: f64) void {
        self.setProgress(percent / 100.0);
    }

    /// Builder method to add a linear gradient
    pub fn linearGradient(self: *ProgressCircle, dir: GradientDirection, colors: []const Vapor.Types.Color) *ProgressCircle {
        self.config.gradient = .{
            .type = .linear,
            .direction = dir,
            .colors = colors,
        };
        return self;
    }

    /// Builder method to add a radial gradient
    pub fn radialGradient(self: *ProgressCircle, colors: []const Vapor.Types.Color) *ProgressCircle {
        self.config.gradient = .{
            .type = .radial,
            .colors = colors,
        };
        return self;
    }

    /// Builder method to add a radial gradient with custom center and radius
    pub fn radialGradientCustom(self: *ProgressCircle, cx: f32, cy: f32, r: f32, colors: []const Vapor.Types.Color) *ProgressCircle {
        self.config.gradient = .{
            .type = .radial,
            .cx = cx,
            .cy = cy,
            .r = r,
            .colors = colors,
        };
        return self;
    }

    /// Builder method to add gradient with explicit color stops
    pub fn gradientWithStops(self: *ProgressCircle, grad_type: GradientType, stops: []const ColorStop) *ProgressCircle {
        self.config.gradient = .{
            .type = grad_type,
            .stops = stops,
        };
        return self;
    }

    /// Builder method to set track gradient
    pub fn trackGradient(self: *ProgressCircle, dir: GradientDirection, colors: []const Vapor.Types.Color) *ProgressCircle {
        self.config.track_gradient = .{
            .type = .linear,
            .direction = dir,
            .colors = colors,
        };
        return self;
    }

    pub fn updateProgress(self: *ProgressCircle, value: f64) void {
        self.progress = std.math.clamp(value, 0.0, 1.0);
        var id_buf: [512]u8 = undefined;
        const id_suffix = std.fmt.bufPrint(&id_buf, "progress-fill-{x}", .{@intFromPtr(self)}) catch unreachable;
        var id_buf_text: [512]u8 = undefined;
        const text_suffix = std.fmt.bufPrint(&id_buf_text, "progress-label-{x}", .{@intFromPtr(self)}) catch unreachable;

        const size = self.config.size;
        const stroke_width = self.config.stroke_width;
        const half_size: f64 = @as(f64, @floatFromInt(size)) / 2.0;
        const radius: f64 = half_size - @as(f64, stroke_width) / 2.0;
        const circumference: f64 = 2.0 * std.math.pi * radius;

        const offset: f64 = circumference * (1.0 - self.progress);
        self.platform.browser.setAttribute(id_suffix, "stroke-dasharray", Vapor.fmtln("{d:.2}", .{circumference}));
        self.platform.browser.setAttribute(id_suffix, "stroke-dashoffset", Vapor.fmtln("{d:.2}", .{if (self.config.clockwise) offset else -offset}));
        Vapor.lib.mutateById(text_suffix, "innerHTML", Vapor.fmtln("{d:.0}%", .{self.progress * 100}));
    }

    pub fn rebuild(self: *ProgressCircle) void {
        self.build() catch |err| {
            std.log.err("Failed to rebuild progress bar: {any}", .{err});
            return;
        };
    }

    /// Write gradient definition to SVG defs
    fn writeGradientDef(self: *ProgressCircle, w: anytype, gradient: Gradient, id: []const u8) !void {
        switch (gradient.type) {
            .linear => {
                const coords = gradient.direction.toSvgCoords();
                try w.print(
                    \\<linearGradient id="{s}" x1="{d}%" y1="{d}%" x2="{d}%" y2="{d}%">
                    \\
                , .{ id, coords.x1, coords.y1, coords.x2, coords.y2 });
                try self.writeColorStops(w, gradient);
                try w.appendSlice("</linearGradient>\n");
            },
            .radial => {
                try w.print(
                    \\<radialGradient id="{s}" cx="{d:.0}%" cy="{d:.0}%" r="{d:.0}%">
                    \\
                , .{ id, gradient.cx * 100, gradient.cy * 100, gradient.r * 100 });
                try self.writeColorStops(w, gradient);
                try w.appendSlice("</radialGradient>\n");
            },
            .conic => {
                // SVG doesn't natively support conic gradients, fall back to linear
                const coords = gradient.direction.toSvgCoords();
                try w.print(
                    \\<linearGradient id="{s}" x1="{d}%" y1="{d}%" x2="{d}%" y2="{d}%">
                    \\
                , .{ id, coords.x1, coords.y1, coords.x2, coords.y2 });
                try self.writeColorStops(w, gradient);
                try w.appendSlice("</linearGradient>\n");
            },
        }
    }

    fn writeColorStops(self: *ProgressCircle, w: anytype, gradient: Gradient) !void {
        _ = self;
        // Use explicit stops if provided
        if (gradient.stops.len > 0) {
            for (gradient.stops, 0..) |stop, i| {
                const offset = stop.offset orelse (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(gradient.stops.len - 1)));
                try w.print(
                    \\<stop offset="{d:.0}%" stop-color="{s}"/>
                    \\
                , .{ offset * 100, colorToString(stop.color) });
            }
        } else if (gradient.colors.len > 0) {
            // Auto-distribute colors
            for (gradient.colors, 0..) |color, i| {
                const offset: f32 = if (gradient.colors.len == 1)
                    0.5
                else
                    @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(gradient.colors.len - 1));
                try w.print(
                    \\<stop offset="{d:.0}%" stop-color="{s}"/>
                    \\
                , .{ offset * 100, colorToString(color) });
            }
        }
    }

    /// Build the SVG
    pub fn build(self: *ProgressCircle) !void {
        if (!Vapor.lib.isWasi) return;

        var id_buf: [20]u8 = undefined;
        const id_suffix = try std.fmt.bufPrint(&id_buf, "{x}", .{@intFromPtr(self)});

        const size = self.config.size;
        const stroke_width = self.config.stroke_width;
        const half_size: f64 = @as(f64, @floatFromInt(size)) / 2.0;
        const radius: f64 = half_size - @as(f64, stroke_width) / 2.0;
        const circumference: f64 = 2.0 * std.math.pi * radius;

        const offset: f64 = circumference * (1.0 - self.progress);

        var buffer = std.array_list.Managed(u8).init(self.allocator);
        defer buffer.deinit();

        var w = buffer;

        // SVG header
        try w.print(
            \\<svg width="{d}" height="{d}" viewBox="0 0 {d} {d}" xmlns="http://www.w3.org/2000/svg">
            \\
        , .{ size, size, size, size });

        // Defs section for gradients
        const has_gradient = self.config.gradient != null;
        const has_track_gradient = self.config.track_gradient != null;

        if (has_gradient or has_track_gradient) {
            try w.appendSlice("<defs>\n");

            if (self.config.gradient) |gradient| {
                var grad_id_buf: [64]u8 = undefined;
                const grad_id = try std.fmt.bufPrint(&grad_id_buf, "progress-gradient-{s}", .{id_suffix});
                try self.writeGradientDef(&w, gradient, grad_id);
            }

            if (self.config.track_gradient) |gradient| {
                var grad_id_buf: [64]u8 = undefined;
                const grad_id = try std.fmt.bufPrint(&grad_id_buf, "track-gradient-{s}", .{id_suffix});
                try self.writeGradientDef(&w, gradient, grad_id);
            }

            try w.appendSlice("</defs>\n");
        }

        // Styles
        try w.print(
            \\<style>
            \\.progress-track {{ fill: none; }}
            \\.progress-bar {{ fill: none; transition: stroke-dashoffset 0.3s ease; }}
            \\.progress-label {{ font-family: system-ui, -apple-system, sans-serif; font-weight: 600; }}
            \\</style>
            \\
        , .{});

        // Background circle (optional)
        if (self.config.background) |bg| {
            try w.print(
                \\<circle cx="{d:.2}" cy="{d:.2}" r="{d:.2}" fill="{s}"/>
                \\
            , .{ half_size, half_size, half_size, colorToString(bg) });
        }

        // Track circle (background ring)
        const track_stroke: []const u8 = if (has_track_gradient) blk: {
            var track_url_buf: [128]u8 = undefined;
            break :blk std.fmt.bufPrint(&track_url_buf, "url(#track-gradient-{s})", .{id_suffix}) catch unreachable;
        } else colorToString(self.config.track_color);

        try w.print(
            \\<circle class="progress-track" cx="{d:.2}" cy="{d:.2}" r="{d:.2}" stroke="{s}" stroke-width="{d:.1}"/>
            \\
        , .{ half_size, half_size, radius, track_stroke, stroke_width });

        // Progress circle
        const linecap: []const u8 = if (self.config.rounded_caps) "round" else "butt";

        const progress_stroke: []const u8 = if (has_gradient) blk: {
            var url_buf: [128]u8 = undefined;
            break :blk std.fmt.bufPrint(&url_buf, "url(#progress-gradient-{s})", .{id_suffix}) catch unreachable;
        } else if (self.config.color) |color|
            colorToString(color)
        else
            "#3b82f6";

        try w.print(
            \\<circle id="progress-fill-{s}" class="progress-bar" cx="{d:.2}" cy="{d:.2}" r="{d:.2}" stroke="{s}" stroke-width="{d:.1}" stroke-linecap="{s}" stroke-dasharray="{d:.2}" stroke-dashoffset="{d:.2}" transform="rotate({d:.0} {d:.2} {d:.2})" style="transform-origin: center;"/>
            \\
        , .{
            id_suffix,
            half_size,
            half_size,
            radius,
            progress_stroke,
            stroke_width,
            linecap,
            circumference,
            if (self.config.clockwise) offset else -offset,
            self.config.start_angle,
            0,
            0,
        });

        // Label
        if (self.config.show_label and self.config.label_format != .none) {
            const label_color: Vapor.Types.Color = self.config.label_color orelse self.config.color orelse .hex("#3b82f6");
            var label_buf: [32]u8 = undefined;
            const label = switch (self.config.label_format) {
                .percent => try std.fmt.bufPrint(&label_buf, "{d:.0}%", .{self.progress * 100}),
                .decimal => try std.fmt.bufPrint(&label_buf, "{d:.2}", .{self.progress}),
                .fraction => try std.fmt.bufPrint(&label_buf, "{d:.0}/100", .{self.progress * 100}),
                .none => "",
            };

            try w.print(
                \\<text id="progress-label-{s}" class="progress-label" x="{d:.2}" y="{d:.2}" text-anchor="middle" dominant-baseline="central" font-size="{d}" fill="{s}">{s}</text>
                \\
            , .{ id_suffix, half_size, half_size, self.config.label_font_size, colorToString(label_color), label });
        }

        try w.appendSlice("</svg>\n");

        // Free old SVG if exists
        if (self.current_svg) |old| {
            self.allocator.free(old);
        }

        self.current_svg = try w.toOwnedSlice();
    }

    /// Render the progress circle
    pub fn render(self: *ProgressCircle) void {
        Box()
            .width(.px(@floatFromInt(self.config.size)))
            .height(.px(@floatFromInt(self.config.size)))
            .onMount(rebuild, .{self})
            .children({
            if (self.current_svg) |svg_content| {
                Vapor.Svg(.{ .svg = svg_content, .override = true }).end();
            }
        });
    }

    /// Helper to convert Color to string
    pub fn colorToString(color: Vapor.Types.Color) []const u8 {
        var w: Writer = undefined;
        var buffer: [2048]u8 = undefined;
        w.init(&buffer);
        color.toCss(&w) catch unreachable;
        return w.buffer[0..w.pos];
    }
};

// ============ Convenience Functions ============

/// Create a simple progress circle with default styling
pub fn progressCircle(allocator: std.mem.Allocator, progress: f64) ProgressCircle {
    var p = ProgressCircle.init(allocator, .{});
    p.setProgress(progress);
    return p;
}

/// Create a progress circle with custom color
pub fn progressCircleColored(allocator: std.mem.Allocator, progress: f64, color: Vapor.Types.Color) ProgressCircle {
    var p = ProgressCircle.init(allocator, .{ .color = color });
    p.setProgress(progress);
    return p;
}

/// Create a progress circle with a linear gradient
pub fn progressCircleGradient(allocator: std.mem.Allocator, progress: f64, dir: ProgressCircle.GradientDirection, colors: []const Vapor.Types.Color) ProgressCircle {
    var p = ProgressCircle.init(allocator, .{
        .color = null,
        .gradient = .{
            .type = .linear,
            .direction = dir,
            .colors = colors,
        },
    });
    p.setProgress(progress);
    return p;
}

// ============ Tests ============

test "progress circle clamps values" {
    var p = ProgressCircle.init(std.testing.allocator, .{});

    p.setProgress(1.5);
    try std.testing.expectEqual(@as(f64, 1.0), p.progress);

    p.setProgress(-0.5);
    try std.testing.expectEqual(@as(f64, 0.0), p.progress);

    p.setPercent(75);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), p.progress, 0.001);
}

test "gradient direction coords" {
    const coords = ProgressCircle.GradientDirection.to_right.toSvgCoords();
    try std.testing.expectEqual(@as(u8, 0), coords.x1);
    try std.testing.expectEqual(@as(u8, 100), coords.x2);
}
