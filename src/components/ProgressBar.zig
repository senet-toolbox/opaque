const std = @import("std");
const Vapor = @import("vapor");
const Box = Vapor.Box;
const Writer = Vapor.Writer;

/// A simple linear progress bar using SVG.
///
/// Usage:
/// ```zig
/// var progress = ProgressBar.init(allocator, .{
///     .width = 200,
///     .height = 20,
///     .color = .hex("#3b82f6"),
///     .track_color = .hex("#e5e7eb"),
/// });
/// progress.setProgress(0.75); // 75%
/// progress.render();
/// ```
pub const ProgressBar = struct {
    allocator: std.mem.Allocator,
    config: Config,
    progress: f64 = 0, // 0.0 to 1.0
    current_svg: ?[]const u8 = null,
    platform: Platform,

    pub const Config = struct {
        width: u32 = 200,
        height: u32 = 20,
        color: Vapor.Types.Color = .hex("#3b82f6"),
        track_color: Vapor.Types.Color = .hex("#e5e7eb"),
        background: ?Vapor.Types.Color = null,
        border_radius: ?f32 = null, // null = fully rounded (height/2)
        show_label: bool = false,
        label_font_size: u32 = 12,
        label_color: ?Vapor.Types.Color = null,
        label_format: LabelFormat = .percent,
        label_position: LabelPosition = .inside,
        animated: bool = true,
        direction: Direction = .ltr,
        striped: bool = false,
        stripe_color: ?Vapor.Types.Color = null,
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

    pub const LabelFormat = enum {
        percent, // "75%"
        decimal, // "0.75"
        fraction, // "75/100"
        none,
    };

    pub const LabelPosition = enum {
        inside, // Centered inside the bar
        above, // Above the bar
        below, // Below the bar
        right, // To the right of the bar
    };

    pub const Direction = enum {
        ltr, // Left to right
        rtl, // Right to left
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) ProgressBar {
        return .{
            .allocator = allocator,
            .config = config,
            .platform = Platform.browser,
        };
    }

    pub fn deinit(self: *ProgressBar) void {
        if (self.current_svg) |svg| {
            self.allocator.free(svg);
        }
    }

    /// Set progress value (0.0 to 1.0)
    pub fn setProgress(self: *ProgressBar, value: f64) void {
        self.progress = std.math.clamp(value, 0.0, 1.0);
        self.build() catch {};
    }

    pub fn updateProgress(self: *ProgressBar, value: f64) void {
        self.progress = std.math.clamp(value, 0.0, 1.0);
        var id_buf: [512]u8 = undefined;
        const id_suffix = std.fmt.bufPrint(&id_buf, "bar-fill-{x}", .{@intFromPtr(self)}) catch unreachable;
        const text_suffix = Vapor.fmtln("bar-label-{x}", .{@intFromPtr(self)});

        const width = self.config.width;

        // Calculate progress bar width
        const progress_width: f64 = @as(f64, @floatFromInt(width)) * self.progress;

        self.platform.browser.setAttribute(id_suffix, "width", Vapor.fmtln("{d:.2}", .{progress_width}));
        // The label is only drawn when it is shown.
        if (self.config.show_label and self.config.label_format != .none) {
            Vapor.lib.mutateById(text_suffix, "innerHTML", Vapor.fmtln("{d:.0}%", .{self.progress * 100}));
        }
        // No render follows, so the value screen readers see moves here too.
        self.platform.browser.setAttribute(self.elementId(), "aria-valuenow", Vapor.fmtln("{d:.0}", .{self.progress * 100}));
    }

    fn elementId(self: *const ProgressBar) []const u8 {
        return Vapor.fmtln("bar-{x}", .{@intFromPtr(self)});
    }

    pub fn rebuild(self: *ProgressBar) void {
        self.build() catch |err| {
            std.log.err("Failed to rebuild progress bar: {any}", .{err});
            return;
        };
        Vapor.cycle();
    }

    /// Set progress as percentage (0 to 100)
    pub fn setPercent(self: *ProgressBar, percent: f64) void {
        self.setProgress(percent / 100.0);
    }

    /// Build the SVG
    pub fn build(self: *ProgressBar) !void {
        if (!Vapor.lib.isWasi) return;

        var id_buf: [20]u8 = undefined;
        const id_suffix = try std.fmt.bufPrint(&id_buf, "{x}", .{@intFromPtr(self)});

        const width = self.config.width;
        const height = self.config.height;
        const radius = self.config.border_radius orelse @as(f32, @floatFromInt(height)) / 2.0;

        // Calculate progress bar width
        const progress_width: f64 = @as(f64, @floatFromInt(width)) * self.progress;

        // Calculate total SVG height based on label position
        const total_height: u32 = switch (self.config.label_position) {
            .above, .below => height + self.config.label_font_size + 8,
            else => height,
        };
        const bar_y: u32 = if (self.config.label_position == .above) self.config.label_font_size + 8 else 0;

        var buffer = std.array_list.Managed(u8).init(self.allocator);
        defer buffer.deinit();

        var w = buffer;

        var color_buffer: [2048]u8 = undefined;
        var w_color: Writer = undefined;
        w_color.init(&color_buffer);

        // SVG header - adjust width for right label
        const svg_width: u32 = if (self.config.label_position == .right) width + 50 else width;
        try w.print(
            \\<svg width="{d}" height="{d}" viewBox="0 0 {d} {d}" xmlns="http://www.w3.org/2000/svg">
            \\
        , .{ svg_width, total_height, svg_width, total_height });

        // Styles
        try w.print(
            \\<style>
            \\.bar-track {{ fill: {s}; }}
            \\.bar-fill {{ fill: {s}; {s} }}
            \\.bar-label {{ font-family: system-ui, -apple-system, sans-serif; font-weight: 600; }}
            \\</style>
            \\
        , .{
            colorToString(self.config.track_color, &w_color),
            colorToString(self.config.color, &w_color),
            if (self.config.animated) "transition: width 0.3s ease;" else "",
        });

        // Defs for clip path and optional stripe pattern
        try w.appendSlice("<defs>\n");

        // Clip path for rounded corners
        try w.print(
            \\<clipPath id="bar-clip-{s}">
            \\<rect x="0" y="{d}" width="{d}" height="{d}" rx="{d:.1}" ry="{d:.1}"/>
            \\</clipPath>
        , .{ id_suffix, bar_y, width, height, radius, radius }); // Stripe pattern if enabled

        if (self.config.striped) {
            const stripe_color = self.config.stripe_color orelse Vapor.Types.Color.white;
            try w.print(
                \\<pattern id="stripe-pattern" width="20" height="20" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
                \\<rect width="10" height="20" fill="{s}"/>
                \\</pattern>
                \\
            , .{colorToString(stripe_color, &w_color)});
        }

        try w.appendSlice("</defs>\n");

        // Background (optional)
        if (self.config.background) |bg| {
            try w.print(
                \\<rect x="0" y="{d}" width="{d}" height="{d}" rx="{d:.1}" ry="{d:.1}" fill="{s}"/>
                \\
            , .{ bar_y, width, height, radius, radius, colorToString(bg, &w_color) });
        }

        // Track (background bar)
        try w.print(
            \\<rect class="bar-track" x="0" y="{d}" width="{d}" height="{d}" rx="{d:.1}" ry="{d:.1}"/>
            \\
        , .{ bar_y, width, height, radius, radius });

        // Progress fill
        // Progress fill
        const x_pos: f64 = if (self.config.direction == .rtl)
            @as(f64, @floatFromInt(width)) - progress_width
        else
            0;

        try w.print(
            \\<g clip-path="url(#bar-clip-{s})">
            \\<rect id="bar-fill-{s}" class="bar-fill" x="{d:.2}" y="{d}" width="{d:.2}" height="{d}" rx="{d:.1}" ry="{d:.1}"/>
        , .{ id_suffix, id_suffix, x_pos, bar_y, progress_width, height, radius, radius });

        // Add stripes if enabled
        if (self.config.striped) {
            try w.print(
                \\<rect x="{d:.2}" y="{d}" width="{d:.2}" height="{d}" rx="{d:.1}" ry="{d:.1}" fill="url(#stripe-pattern)"/>
            , .{ x_pos, bar_y, progress_width, height, radius, radius });
        }

        try w.appendSlice("</g>\n");

        // Label
        if (self.config.show_label and self.config.label_format != .none) {
            const label_color = self.config.label_color orelse switch (self.config.label_position) {
                .inside => Vapor.Types.Color.hex("#ffffff"),
                else => self.config.color,
            };

            var label_buf: [32]u8 = undefined;
            const label = switch (self.config.label_format) {
                .percent => try std.fmt.bufPrint(&label_buf, "{d:.0}%", .{self.progress * 100}),
                .decimal => try std.fmt.bufPrint(&label_buf, "{d:.2}", .{self.progress}),
                .fraction => try std.fmt.bufPrint(&label_buf, "{d:.0}/100", .{self.progress * 100}),
                .none => "",
            };

            const label_x: f64, const label_y: f64, const anchor: []const u8 = switch (self.config.label_position) {
                .inside => .{
                    @as(f64, @floatFromInt(width)) / 2.0,
                    @as(f64, @floatFromInt(bar_y)) + @as(f64, @floatFromInt(height)) / 2.0,
                    "middle",
                },
                .above => .{
                    @as(f64, @floatFromInt(width)) / 2.0,
                    @as(f64, @floatFromInt(self.config.label_font_size)),
                    "middle",
                },
                .below => .{
                    @as(f64, @floatFromInt(width)) / 2.0,
                    @as(f64, @floatFromInt(bar_y + height + self.config.label_font_size + 4)),
                    "middle",
                },
                .right => .{
                    @as(f64, @floatFromInt(width + 8)),
                    @as(f64, @floatFromInt(height)) / 2.0,
                    "start",
                },
            };

            const baseline: []const u8 = if (self.config.label_position == .inside or self.config.label_position == .right)
                "central"
            else
                "auto";

            try w.print(
                \\<text id="bar-label-{s}" class="bar-label" x="{d:.2}" y="{d:.2}" text-anchor="{s}" dominant-baseline="{s}" font-size="{d}" fill="{s}">{s}</text>
                \\
            , .{ id_suffix, label_x, label_y, anchor, baseline, self.config.label_font_size, colorToString(label_color, &w_color), label });
        }

        try w.appendSlice("</svg>\n");

        // Free old SVG if exists
        if (self.current_svg) |old| {
            self.allocator.free(old);
        }

        self.current_svg = try w.toOwnedSlice();
    }

    /// Render the progress bar
    pub fn render(self: *ProgressBar) void {
        const render_width: u32 = if (self.config.label_position == .right) self.config.width + 50 else self.config.width;
        const render_height: u32 = switch (self.config.label_position) {
            .above, .below => self.config.height + self.config.label_font_size + 8,
            else => self.config.height,
        };

        Box()
            .id(self.elementId())
            .a11y(Vapor.Accessibility.progressBar(@floatCast(self.progress * 100), 100).setLabel("Progress"))
            .width(.px(@floatFromInt(render_width)))
            .height(.px(@floatFromInt(render_height)))
            .onMount(rebuild, .{self})
            .children({
            if (self.current_svg) |svg_content| {
                Vapor.Svg(.{ .svg = svg_content, .override = true }).end();
            }
        });
    }

    /// Helper to convert Color to string
    fn colorToString(color: Vapor.Types.Color, writer: *Writer) []const u8 {
        writer.mark();
        color.toCss(writer) catch unreachable;
        return writer.getWritten();
    }
};

// ============ Convenience Functions ============

/// Create a simple progress bar with default styling
pub fn progressBar(allocator: std.mem.Allocator, progress: f64) ProgressBar {
    var p = ProgressBar.init(allocator, .{});
    p.setProgress(progress);
    return p;
}

/// Create a progress bar with custom color
pub fn progressBarColored(allocator: std.mem.Allocator, progress: f64, color: Vapor.Types.Color) ProgressBar {
    var p = ProgressBar.init(allocator, .{ .color = color });
    p.setProgress(progress);
    return p;
}

/// Create a progress bar with label
pub fn progressBarWithLabel(allocator: std.mem.Allocator, progress: f64, position: ProgressBar.LabelPosition) ProgressBar {
    var p = ProgressBar.init(allocator, .{
        .show_label = true,
        .label_position = position,
    });
    p.setProgress(progress);
    return p;
}

/// Create a thin/slim progress bar
pub fn progressBarSlim(allocator: std.mem.Allocator, progress: f64) ProgressBar {
    var p = ProgressBar.init(allocator, .{
        .height = 8,
        .show_label = false,
    });
    p.setProgress(progress);
    return p;
}

/// Create a striped progress bar
pub fn progressBarStriped(allocator: std.mem.Allocator, progress: f64, color: Vapor.Types.Color) ProgressBar {
    var p = ProgressBar.init(allocator, .{
        .color = color,
        .striped = true,
    });
    p.setProgress(progress);
    return p;
}

// ============ Tests ============

test "progress bar clamps values" {
    var p = ProgressBar.init(std.testing.allocator, .{});

    p.setProgress(1.5);
    try std.testing.expectEqual(@as(f64, 1.0), p.progress);

    p.setProgress(-0.5);
    try std.testing.expectEqual(@as(f64, 0.0), p.progress);

    p.setPercent(75);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), p.progress, 0.001);
}

test "progress bar config defaults" {
    const p = ProgressBar.init(std.testing.allocator, .{});
    try std.testing.expectEqual(@as(u32, 200), p.config.width);
    try std.testing.expectEqual(@as(u32, 20), p.config.height);
    try std.testing.expectEqual(false, p.config.show_label);
    try std.testing.expectEqual(true, p.config.animated);
    try std.testing.expectEqual(ProgressBar.Direction.ltr, p.config.direction);
}

test "progress bar with custom dimensions" {
    var p = ProgressBar.init(std.testing.allocator, .{
        .width = 300,
        .height = 30,
        .border_radius = 5,
    });
    defer p.deinit();

    try std.testing.expectEqual(@as(u32, 300), p.config.width);
    try std.testing.expectEqual(@as(u32, 30), p.config.height);
    try std.testing.expectEqual(@as(f32, 5), p.config.border_radius.?);
}
