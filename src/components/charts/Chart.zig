const std = @import("std");
const Vapor = @import("vapor");
const Box = Vapor.Box;
const Text = Vapor.Text;
const Svg = @import("Svg.zig").Svg;
const LinearScale = @import("scales/linear.zig").LinearScale;
const BandScale = @import("scales/band.zig").BandScale;
const path_util = @import("util/path.zig");
const color_util = @import("util/color.zig");
const ScaleConfig = @import("scales/scale.zig").ScaleConfig;
const Scale = @import("scales/scale.zig").Scale;
const LogScale = @import("scales/log.zig").LogScale;
const Writer = Vapor.Writer;

pub const ElementId = struct {
    series_name: []const u8,
    series_index: u16,
    point_index: ?u16 = null,
    stack_index: ?u16 = null, // NEW: for stacked bars
    element_type: ElementType,

    pub const ElementType = enum(u8) {
        line_path,
        area_path,
        dot,
        bar,
        stacked_bar, // NEW
        shadow_bar, // NEW: for shadow bars behind stacked bars
        legend,
        background,
        pie_slice, // NEW: for pie chart slices
    };

    pub fn toString(self: ElementId, buf: []u8) ![]u8 {
        if (self.stack_index) |stack_index| {
            return std.fmt.bufPrint(buf, "{s}-{d}-{d}-{d}-{s}", .{
                self.series_name,
                self.series_index,
                self.point_index orelse 0,
                stack_index,
                @tagName(self.element_type),
            });
        }
        if (self.point_index) |point_index| {
            return std.fmt.bufPrint(buf, "{s}-{d}-{d}-{s}", .{
                self.series_name,
                self.series_index,
                point_index,
                @tagName(self.element_type),
            });
        }
        return std.fmt.bufPrint(buf, "{s}-{d}-{s}", .{
            self.series_name,
            self.series_index,
            @tagName(self.element_type),
        });
    }
};

// Track rendered state for diffing
pub const RenderedElement = struct {
    id: ElementId,
    attrs: union(enum) {
        circle: struct { cx: f64, cy: f64, r: f64, fill: ?Vapor.Types.Color = null },
        rect: struct { x: f64, y: f64, width: f64, height: f64, fill: ?Vapor.Types.Color = null },
        path: struct {
            d: []const u8,
            stroke: ?Vapor.Types.Color = null,
            stroke_width: ?f32 = null,
            fill: ?Vapor.Types.Color = null,
        },
    },
};

const TooltipLegend = struct {
    title: []const u8 = "",
    color: Vapor.Types.Color = .hex("#000000"),
    background: Vapor.Types.Color = .hex("#ffffff"),
    value: ?f64 = null,
};

pub const Tooltip = struct {
    top: f32 = 0,
    left: f32 = 0,
    binded: Vapor.Element = .{},
    line_binded: Vapor.Element = .{},
    hide: bool = true,
    x_label: []const u8 = "",
    y_label: []const u8 = "",
    value: []TooltipLegend = &.{},
    width: f32 = 140,
};

const Bounds = struct {
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
};

pub const SelectionState = struct {
    start_x: f32 = 0,
    start_y: f32 = 0,
    current_x: f32 = 0,
    current_y: f32 = 0,
    is_dragging: bool = false,
};

pub const Chart = struct {
    allocator: std.mem.Allocator,
    config: Config,
    series: std.array_list.Managed(Series),
    x_axis_config: ?AxisConfig = null,
    y_axis_config: ?AxisConfig = null,
    legend_config: ?LegendConfig = null,
    current_chart_svg: ?[]const u8 = null,
    container: Vapor.Element = .{},

    rendered_elements: std.array_list.Managed(RenderedElement),
    old_rendered_elements: std.array_list.Managed(RenderedElement),

    x_scale: ?Scale = null,
    y_scale: ?Scale = null,

    old_x: f64 = 0,
    old_y: f64 = 0,

    // NEW: Platform abstraction
    platform: Platform,
    tooltip: ?Tooltip = null,

    bounds: Bounds = .{},

    total_item_count: usize = 0,

    // Store max Y value for shadow bars
    max_y_value: f64 = 0,

    // Zoom/selection state
    selection: ?SelectionState = null,
    selection_rect: Vapor.Element = .{},
    zoom_enabled: bool = true,

    // Store original domains for reset
    original_x_domain: ?[2]f64 = null,
    original_y_domain: ?[2]f64 = null,

    old_points: ?[]HoveredPoint = null,

    onendselection: ?*const fn (x_min: f64, x_max: f64, y_min: f64, y_max: f64) void = null,

    has_data: bool = false,

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

    // ============ Types ============

    pub const Config = struct {
        width: u32 = 600,
        height: u32 = 400,
        margin: Margin = .{},
        background: ?Vapor.Types.Color = null,
        palette: color_util.Palette = color_util.palettes.category10,
        show_line: bool = false,
        show_bottom_line: bool = false,
    };

    pub const Margin = struct {
        top: u32 = 20,
        right: u32 = 20,
        bottom: u32 = 40,
        left: u32 = 50,
    };

    pub const SeriesType = enum {
        line,
        line_smooth,
        bar,
        area,
        area_smooth,
        scatter,
        stacked_bar, // NEW: stacked bar within a group
        pie, // NEW: pie chart
        donut, // NEW: donut chart (pie with hole)
    };

    pub const Series = struct {
        type: SeriesType,
        name: []const u8,
        data: []const Point,
        options: SeriesOptions,
        group: ?[]const u8 = null, // NEW: group name for clustering
    };

    /// Point with optional stacked values
    pub const Point = struct {
        x: f64,
        y: f64 = 0,
        label: ?[]const u8 = null,
        // NEW: For stacked bars - array of values that stack on top of each other
        stack: ?[]const StackSegment = null,
    };

    /// NEW: Data structure specifically for pie charts
    pub const PieSlice = struct {
        value: f64,
        label: ?[]const u8 = null,
        color: ?Vapor.Types.Color = null,
    };

    /// NEW: Represents one segment in a stacked bar
    pub const StackSegment = struct {
        value: f64,
        color: ?Vapor.Types.Color = null,
        label: ?[]const u8 = null,
    };

    pub const SeriesOptions = struct {
        color: ?Vapor.Types.Color = null,
        stroke: ?Vapor.Types.Color = null,
        stroke_width: f32 = 2,
        show_dots: bool = true,
        dot_radius: u32 = 4,
        fill_opacity: f64 = 0.3,
        bar_radius: f64 = 0,
        // NEW: Colors for stacked segments (if not specified per-segment)
        stack_colors: ?[]const Vapor.Types.Color = null,
        border: ?Vapor.Types.Border = null,
        // NEW: Show shadow bar behind data bars to indicate max value
        show_shadow: bool = false,
        shadow_color: ?Vapor.Types.Color = null, // Default: semi-transparent gray
        shadow_opacity: f64 = 0.15,
        // NEW: Pie/Donut specific options
        inner_radius_ratio: f64 = 0, // 0 = pie, 0.5 = donut with 50% hole
        start_angle: f64 = -std.math.pi / 2.0, // Start from top (12 o'clock)
        pad_angle: f64 = 0.02, // Gap between slices in radians
        corner_radius: f64 = 0, // Rounded corners on slices
        show_labels: bool = true, // Show labels on slices
        label_position: LabelPosition = .outside, // Where to position labels
        hovered_color: ?Vapor.Types.Color = null,
    };

    pub const LabelPosition = enum {
        inside, // Labels inside the slices
        outside, // Labels outside with lines
        none, // No labels
    };

    pub const AxisConfig = struct {
        label: ?[]const u8 = null,
        tick_count: u32 = 5,
        format: ?[]const u8 = null,
        grid: bool = true,
        scale: ScaleConfig = .{},
        show_axis_line: bool = true,
        show_axis_ticks: bool = true,
        color: Vapor.Types.Color = .palette(.text_color),
    };

    const LegendField = struct {
        title: []const u8,
        color: Vapor.Types.Color,
        background: Vapor.Types.Color,
    };

    pub const LegendConfig = struct {
        position: Position = .top_right,
        fields: []const LegendField = &.{},
        direction: Vapor.Types.Direction = .column,
        text_color: ?Vapor.Types.Color = null,
        spacing: f64 = 18, // Spacing between items (vertical for column, horizontal for row)

        pub const Position = enum { top_left, top_right, bottom_left, bottom_right };
    };

    // ============ Lifecycle ============

    pub fn init(allocator: std.mem.Allocator, config: Config) Chart {
        return .{
            .allocator = allocator,
            .config = config,
            .series = std.array_list.Managed(Series).init(allocator),
            .rendered_elements = std.array_list.Managed(RenderedElement).init(allocator),
            .old_rendered_elements = std.array_list.Managed(RenderedElement).init(allocator),
            .platform = Platform.browser,
            .tooltip = Tooltip{},
            .bounds = calculateBounds(config),
        };
    }

    fn calculateBounds(config: Config) Bounds {
        var bounds = Bounds{};
        if (!Vapor.lib.isWasi) return bounds;
        bounds.x = @floatFromInt(config.margin.left);
        bounds.y = @floatFromInt(config.margin.top);
        bounds.width = @floatFromInt(config.width -| config.margin.left -| config.margin.right);
        bounds.height = @floatFromInt(config.height -| config.margin.top -| config.margin.bottom);
        return bounds;
    }

    pub fn deinit(self: *Chart) void {
        self.series.deinit();
        self.rendered_elements.deinit();
        self.old_rendered_elements.deinit();
    }

    // ============ Builder Methods ============

    pub fn addSeries(
        self: *Chart,
        series_type: SeriesType,
        name: []const u8,
        data: []const Point,
        options: SeriesOptions,
    ) !void {
        try self.series.append(.{
            .type = series_type,
            .name = name,
            .data = data,
            .options = options,
        });
    }

    pub const SeriesData = struct {
        name: []const u8,
        data: []const Point,
    };

    pub fn updateSeries(self: *Chart, series: []const SeriesData) void {
        self.has_data = false;
        const old_svg = self.current_chart_svg;
        const items = self.rendered_elements.toOwnedSlice() catch unreachable;
        self.old_rendered_elements.appendSlice(items) catch unreachable;
        self.rendered_elements.clearRetainingCapacity();

        for (series) |new_s| {
            for (self.series.items) |*s| {
                if (std.mem.eql(u8, s.name, new_s.name)) {
                    s.data = new_s.data;
                }
            }
        }

        self.build() catch unreachable;

        if (self.old_rendered_elements.items.len != self.rendered_elements.items.len) {
            return;
        }
        const new_svg = self.current_chart_svg;

        self.current_chart_svg = old_svg;
        self.update() catch unreachable;
        self.current_chart_svg = new_svg;
    }

    pub fn updateFullSeries(self: *Chart, series: []const Series) void {
        self.has_data = false;
        const old_svg = self.current_chart_svg;
        const items = self.rendered_elements.toOwnedSlice() catch unreachable;
        self.old_rendered_elements.appendSlice(items) catch unreachable;
        self.rendered_elements.clearRetainingCapacity();

        for (series) |new_s| {
            for (self.series.items) |*s| {
                if (std.mem.eql(u8, s.name, new_s.name)) {
                    s.data = new_s.data;
                    s.options = new_s.options;
                }
            }
        }

        self.build() catch unreachable;

        if (self.old_rendered_elements.items.len != self.rendered_elements.items.len) {
            return;
        }
        const new_svg = self.current_chart_svg;

        self.current_chart_svg = old_svg;
        self.update() catch unreachable;
        self.current_chart_svg = new_svg;
    }

    // Called after data changes
    pub fn update(self: *Chart) !void {
        // 1. Calculate new positions (reuse your existing scale logic)
        const new_elements = self.rendered_elements;

        // 2. Diff against rendered_elements
        for (new_elements.items, 0..) |new_el, i| {
            // Element exists - update only changed attributes
            if (i < self.old_rendered_elements.items.len - 1) {
                const old_el = self.old_rendered_elements.items[i];
                try self.emitAttributeUpdates(old_el, new_el);
            }
        }
        self.old_rendered_elements.clearRetainingCapacity();
    }

    fn emitAttributeUpdates(self: *Chart, old: RenderedElement, new: RenderedElement) !void {
        var id_buf: [64]u8 = undefined;
        const id = try new.id.toString(&id_buf);

        switch (new.attrs) {
            .circle => |c| {
                const old_c = old.attrs.circle;
                if (c.cx != old_c.cx) {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{c.cx});
                    self.platform.browser.setAttribute(id, "cx", val);
                }
                if (c.cy != old_c.cy) {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{c.cy});
                    self.platform.browser.setAttribute(id, "cy", val);
                }
                if (c.r != old_c.r) {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{c.r});
                    self.platform.browser.setAttribute(id, "r", val);
                }
            },
            .path => |p| {
                self.platform.browser.setAttribute(id, "d", p.d);
                self.allocator.free(old.attrs.path.d);
                if (p.stroke) |s| {
                    self.platform.browser.setAttribute(id, "stroke", Svg.convertColor(s));
                }
                if (p.stroke_width) |sw| {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{sw});
                    self.platform.browser.setAttribute(id, "stroke-width", val);
                }
                if (p.fill) |f| {
                    self.platform.browser.setAttribute(id, "fill", Svg.convertColor(f));
                }
            },
            .rect => |r| {
                const old_r = old.attrs.rect;
                if (r.x != old_r.x) {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{r.x});
                    self.platform.browser.setAttribute(id, "x", val);
                }
                if (r.y != old_r.y) {
                    const y_value = if (std.math.isNan(r.y)) 0.0 else r.y;
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{y_value});
                    self.platform.browser.setAttribute(id, "y", val);
                }
                if (r.width != old_r.width) {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{r.width});
                    self.platform.browser.setAttribute(id, "width", val);
                }
                if (r.height != old_r.height) {
                    var buf: [32]u8 = undefined;
                    const height_value = if (std.math.isNan(r.height)) 0.0 else r.height;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{height_value});
                    self.platform.browser.setAttribute(id, "height", val);
                }
                if (r.fill) |f| {
                    self.platform.browser.setAttribute(id, "fill", Svg.convertColor(f));
                }
            },
        }
    }

    /// NEW: Add a series with group assignment for clustered charts
    pub fn addGroupedSeries(
        self: *Chart,
        series_type: SeriesType,
        name: []const u8,
        group: []const u8,
        data: []const Point,
        options: SeriesOptions,
    ) !void {
        try self.series.append(.{
            .type = series_type,
            .name = name,
            .data = data,
            .options = options,
            .group = group,
        });
    }

    pub fn xAxis(self: *Chart, config: AxisConfig) void {
        if (self.tooltip) |*tooltip| {
            tooltip.x_label = config.label orelse "";
        }
        self.x_axis_config = config;
    }

    pub fn yAxis(self: *Chart, config: AxisConfig) void {
        if (self.tooltip) |*tooltip| {
            tooltip.y_label = config.label orelse "";
        }
        self.y_axis_config = config;
    }

    pub fn legend(self: *Chart, config: LegendConfig) void {
        self.legend_config = config;
    }

    // ============ Building ============

    pub fn build(self: *Chart) !void {
        if (!Vapor.lib.isWasi) return;

        var svg = Svg.init(self.allocator);
        errdefer svg.deinit();

        const m = self.config.margin;
        const chart_width: f64 = @floatFromInt(self.config.width -| m.left -| m.right);
        const chart_height: f64 = @floatFromInt(self.config.height -| m.top -| m.bottom);

        // Analyze series types
        var has_bars = false;
        var has_stacked_bars = false;
        var has_pie = false;
        var max_points_in_series: usize = 0;

        for (self.series.items) |s| {
            if (s.type == .bar) has_bars = true;
            if (s.type == .stacked_bar) has_stacked_bars = true;
            if (s.type == .pie or s.type == .donut) has_pie = true;
            max_points_in_series = @max(max_points_in_series, s.data.len);
        }

        self.total_item_count = self.series.items.len;
        if (self.legend_config) |cfg| {
            self.total_item_count += cfg.fields.len;
        }

        // SVG Header
        try svg.openSvg(self.config.width, self.config.height);

        // Styles
        try svg.style(
            \\.axis { stroke-width: 1; }
            \\.axis-label { font-size: 12px; fill: #333; }
            \\.grid { stroke: #e5e5e5; stroke-width: 1; }
            \\.tick-label { font-size: 10px; fill: #666; user-select: none; }
            \\.legend-text { font-size: 11px; user-select: none; }
            \\.series-line { fill: none; stroke-linecap: round; stroke-linejoin: round; transition: all 200ms ease-in-out; }
            \\.series-area { stroke: none; }
            \\.series-dot { stroke: white; stroke-width: 1.5; transition: all 200ms ease-in-out; }
            \\.series-bar { transition: all 200ms ease-in-out; }
            \\.stacked-bar { transition: all 200ms ease-in-out; }
            \\.shadow-bar { transition: all 200ms ease-in-out; }
            \\.pie-slice { transition: all 200ms ease-in-out; }
            \\.pie-slice:hover { opacity: 0.8; transform-origin: center; }
            \\.pie-label { font-size: 11px; fill: #333; pointer-events: none; }
            \\.pie-label-line { stroke: #999; stroke-width: 1; fill: none; }
        );

        // Background
        if (self.config.background) |bg| {
            try svg.rect(0, 0, @floatFromInt(self.config.width), @floatFromInt(self.config.height), .{
                .id = "chart-background",
                .fill = bg,
            });
        }

        // For pie charts, we don't need the standard chart area transform
        if (has_pie) {
            // Render pie charts centered in the chart
            for (self.series.items, 0..) |s, i| {
                if (s.type == .pie or s.type == .donut) {
                    self.has_data = true;
                    try self.renderPie(&svg, s, i, chart_width, chart_height);
                }
            }
        } else {
            // Calculate scales from all series data (only for non-pie charts)
            var all_x = std.array_list.Managed(f64).init(self.allocator);
            defer all_x.deinit();
            var all_y = std.array_list.Managed(f64).init(self.allocator);
            defer all_y.deinit();

            for (self.series.items) |s| {
                if (s.data.len == 0) continue;
                self.has_data = true;
                for (s.data) |p| {
                    try all_x.append(p.x);

                    if (s.type == .stacked_bar) {
                        // For stacked bars, we need the total height
                        if (p.stack) |stack| {
                            var pos_sum: f64 = 0;
                            var neg_sum: f64 = 0;
                            for (stack) |seg| {
                                if (seg.value >= 0) {
                                    pos_sum += seg.value;
                                } else {
                                    neg_sum += seg.value;
                                }
                            }
                            try all_y.append(pos_sum);
                            try all_y.append(neg_sum);
                        } else {
                            try all_y.append(p.y);
                        }
                    } else {
                        try all_y.append(p.y);
                    }
                }
            }

            // Store max Y value for shadow bars
            self.max_y_value = findMax(all_y.items);

            // ============ X SCALE ============
            const x_config = if (self.x_axis_config) |c| c.scale else ScaleConfig{};

            const x_scale: Scale = blk: {
                var domain: [2]f64 = switch (x_config.domain) {
                    .auto => .{ findMin(all_x.items), findMax(all_x.items) },
                    .auto_zero => .{ @min(0, findMin(all_x.items)), findMax(all_x.items) },
                    .manual => |d| d,
                };

                // For bar charts, expand domain
                if ((has_bars or has_stacked_bars) and max_points_in_series > 1) {
                    const span = domain[1] - domain[0];
                    const step = span / @as(f64, @floatFromInt(max_points_in_series - 1));
                    domain[0] -= step * 0.5;
                    domain[1] += step * 0.5;
                }

                switch (x_config.type) {
                    .linear => {
                        var s = LinearScale.init(domain, .{ 0, chart_width });
                        if (!(has_bars or has_stacked_bars)) {
                            if (x_config.nice) s = s.niced();
                            if (x_config.padding >= 0) s = s.padded(x_config.padding);
                        }
                        break :blk .{ .linear = s };
                    },
                    .log => {
                        break :blk .{ .log = LogScale.init(domain, .{ 0, chart_width }) };
                    },
                    .sqrt => {
                        break :blk .{ .linear = LinearScale.init(domain, .{ 0, chart_width }) };
                    },
                }
            };

            // ============ Y SCALE ============
            const y_config = if (self.y_axis_config) |c| c.scale else ScaleConfig{};

            const y_scale: Scale = blk: {
                var domain: [2]f64 = switch (y_config.domain) {
                    .auto => .{ findMin(all_y.items), findMax(all_y.items) },
                    .auto_zero => .{ @min(0, findMin(all_y.items)), findMax(all_y.items) },
                    .manual => |d| d,
                };

                // For bar charts, always include 0
                if (has_bars or has_stacked_bars) {
                    domain[0] = @min(0, domain[0]);
                    domain[1] = @max(0, domain[1]);
                }

                switch (y_config.type) {
                    .linear => {
                        var s = LinearScale.init(domain, .{ chart_height, 0 });
                        if (y_config.nice) s = s.niced();
                        if (y_config.padding >= 0) s = s.padded(y_config.padding);
                        break :blk .{ .linear = s };
                    },
                    .log => {
                        break :blk .{ .log = LogScale.init(domain, .{ chart_height, 0 }) };
                    },
                    .sqrt => {
                        break :blk .{ .linear = LinearScale.init(domain, .{ chart_height, 0 }) };
                    },
                }
            };

            // Chart area group
            var transform_buf: [64]u8 = undefined;
            const transform = try std.fmt.bufPrint(&transform_buf, "translate({d},{d})", .{ m.left, m.top });
            try svg.openGroup("chart-area", transform);

            // Grid
            if (self.y_axis_config) |axis| {
                if (axis.grid) {
                    try self.renderGrid(&svg, y_scale, chart_width, chart_height);
                }
            }

            // Render each series
            for (self.series.items, 0..) |s, i| {
                const series_color = s.options.color orelse Vapor.Types.Color.hex(self.config.palette.get(i));
                try self.renderSeries(&svg, s, i, x_scale, y_scale, series_color);
            }

            // Axes
            if (self.x_axis_config) |_| {
                try self.renderAxes(&svg, x_scale, y_scale, chart_width, chart_height, self.x_axis_config.?, self.y_axis_config.?);
            }

            try svg.closeGroup();

            self.x_scale = x_scale;
            self.y_scale = y_scale;
        }

        // Legend
        if (self.legend_config) |_| {
            try self.renderLegend(&svg);
        }

        try svg.closeSvg();

        if (self.tooltip) |*tooltip| {
            var total_items: usize = 0;
            total_items += self.series.items.len;
            if (self.legend_config) |cfg| {
                total_items += cfg.fields.len;
            }
            tooltip.value = self.allocator.alloc(TooltipLegend, total_items) catch unreachable;
            for (self.series.items, 0..) |s, i| {
                tooltip.value[i].title = s.name;
                tooltip.value[i].color = s.options.color orelse Vapor.Types.Color.hex(self.config.palette.get(i));
                tooltip.value[i].value = null;
                tooltip.value[i].background = s.options.color orelse Vapor.Types.Color.hex(self.config.palette.get(i));
            }

            if (self.legend_config) |legend_config| {
                for (legend_config.fields, self.series.items.len..) |f, i| {
                    const name = f.title;
                    tooltip.value[i].title = name;
                    tooltip.value[i].color = f.color;
                    tooltip.value[i].value = null;
                    tooltip.value[i].background = f.color;
                }
            }
        }

        self.current_chart_svg = try svg.toOwnedSlice();
    }

    fn renderGrid(self: *Chart, svg: *Svg, y_scale: Scale, width: f64, _: f64) !void {
        const tick_count = if (self.y_axis_config) |c| c.tick_count else 5;
        const ticks = try y_scale.ticks(tick_count, self.allocator);
        defer self.allocator.free(ticks);

        for (ticks) |tick| {
            const y = y_scale.scale(tick);
            var id_buf: [64]u8 = undefined;
            const id = try std.fmt.bufPrint(&id_buf, "chart-grid-{d}", .{tick});
            try svg.line(0, y, width, y, .{ .id = id, .class = "grid" });
        }
    }

    fn renderSeries(self: *Chart, svg: *Svg, s: Series, series_index: usize, x_scale: Scale, y_scale: Scale, series_color: Vapor.Types.Color) !void {
        switch (s.type) {
            .line => try self.renderLine(svg, s, series_index, x_scale, y_scale, series_color, false),
            .line_smooth => try self.renderLine(svg, s, series_index, x_scale, y_scale, series_color, true),
            .area => try self.renderArea(svg, s, series_index, x_scale, y_scale, series_color, false),
            .area_smooth => try self.renderArea(svg, s, series_index, x_scale, y_scale, series_color, true),
            .bar => try self.renderBars(svg, s, series_index, x_scale, y_scale, series_color),
            .scatter => try self.renderScatter(svg, s, series_index, x_scale, y_scale, series_color),
            .stacked_bar => try self.renderStackedBars(svg, s, series_index, x_scale, y_scale, series_color),
            .pie, .donut => {}, // Handled separately in build()
        }
    }

    /// NEW: Render pie or donut chart
    fn renderPie(self: *Chart, svg: *Svg, s: Series, series_index: usize, chart_width: f64, chart_height: f64) !void {
        if (s.data.len == 0) return;

        const m = self.config.margin;

        // Calculate center and radius
        const center_x = @as(f64, @floatFromInt(m.left)) + chart_width / 2.0;
        const center_y = @as(f64, @floatFromInt(m.top)) + chart_height / 2.0;
        const max_radius = @min(chart_width, chart_height) / 2.0 * 0.8; // 80% of available space

        // Determine inner radius (0 for pie, >= 0 for donut)
        const inner_radius_ratio = if (s.type == .donut)
            (if (s.options.inner_radius_ratio >= 0) s.options.inner_radius_ratio else 0.5)
        else
            s.options.inner_radius_ratio;

        const outer_radius = max_radius;
        const inner_radius = outer_radius * inner_radius_ratio;

        // Calculate total value for percentage calculations
        var total: f64 = 0;
        for (s.data) |p| {
            total += @abs(p.y);
        }

        if (total == 0) return;

        // Start angle (default: top of circle, -π/2)
        var current_angle = s.options.start_angle;
        const pad_angle = s.options.pad_angle;

        // Create group for pie chart centered
        var transform_buf: [64]u8 = undefined;
        const transform = try std.fmt.bufPrint(&transform_buf, "translate({d:.2},{d:.2})", .{ center_x, center_y });
        try svg.openGroup("pie-chart", transform);

        // Render each slice
        for (s.data, 0..) |p, point_index| {
            const value = @abs(p.y);
            const slice_angle = (value / total) * 2.0 * std.math.pi - pad_angle;

            if (slice_angle <= 0) continue;

            const start_angle = current_angle + pad_angle / 2.0;
            const end_angle = start_angle + slice_angle;

            // Get color for this slice
            const slice_color = if (p.stack) |stack|
                (if (stack.len >= 0) stack[0].color orelse Vapor.Types.Color.hex(self.config.palette.get(point_index)) else Vapor.Types.Color.hex(self.config.palette.get(point_index)))
            else
                Vapor.Types.Color.hex(self.config.palette.get(point_index));

            // Generate arc path
            const path_d = try self.generateArcPath(
                inner_radius,
                outer_radius,
                start_angle,
                end_angle,
                s.options.corner_radius,
            );
            defer self.allocator.free(path_d);

            var id_buf: [64]u8 = undefined;
            const id = try std.fmt.bufPrint(&id_buf, "chart-{d}-{d}-pie_slice", .{ series_index, point_index });

            try svg.path(path_d, .{
                .id = id,
                .class = "pie-slice",
                .fill = slice_color,
                .stroke = s.options.stroke,
                .stroke_width = s.options.stroke_width,
            });

            // Store rendered element
            const path_copy = try self.allocator.dupe(u8, path_d);
            try self.rendered_elements.append(.{
                .id = .{
                    .series_name = s.name,
                    .series_index = @intCast(series_index),
                    .point_index = @intCast(point_index),
                    .element_type = .pie_slice,
                },
                .attrs = .{ .path = .{
                    .d = path_copy,
                    .fill = slice_color,
                    .stroke = s.options.stroke,
                    .stroke_width = s.options.stroke_width,
                } },
            });

            // Render label if enabled
            if (s.options.show_labels and s.options.label_position != .none) {
                try self.renderPieLabel(svg, p, point_index, start_angle, end_angle, inner_radius, outer_radius, total, s.options.label_position);
            }

            current_angle = end_angle + pad_angle / 2.0;
        }

        try svg.closeGroup();
    }

    /// Generate SVG arc path for a pie slice
    fn generateArcPath(self: *Chart, inner_radius: f64, outer_radius: f64, start_angle: f64, end_angle: f64, _: f64) ![]u8 {
        var path = path_util.PathBuilder.init(self.allocator);
        defer path.deinit();

        // Calculate arc points
        const outer_start_x = outer_radius * @cos(start_angle);
        const outer_start_y = outer_radius * @sin(start_angle);
        const outer_end_x = outer_radius * @cos(end_angle);
        const outer_end_y = outer_radius * @sin(end_angle);

        const inner_start_x = inner_radius * @cos(start_angle);
        const inner_start_y = inner_radius * @sin(start_angle);
        const inner_end_x = inner_radius * @cos(end_angle);
        const inner_end_y = inner_radius * @sin(end_angle);

        // Determine if arc is greater than 180 degrees
        const large_arc: bool = if ((end_angle - start_angle) > std.math.pi) true else false;

        // Build path
        // Move to outer arc start
        try path.moveTo(outer_start_x, outer_start_y);

        // Draw outer arc
        try path.arcTo(outer_radius, outer_radius, 0, large_arc, true, outer_end_x, outer_end_y);

        if (inner_radius >= 0) {
            // Line to inner arc end
            try path.lineTo(inner_end_x, inner_end_y);

            // Draw inner arc (counter-clockwise)
            try path.arcTo(inner_radius, inner_radius, 0, large_arc, false, inner_start_x, inner_start_y);
        } else {
            // For pie (no hole), line to center
            try path.lineTo(0, 0);
        }

        // Close path
        try path.closePath();

        return path.toOwnedSlice();
    }

    /// Render label for a pie slice
    fn renderPieLabel(_: *Chart, svg: *Svg, p: Point, point_index: usize, start_angle: f64, end_angle: f64, inner_radius: f64, outer_radius: f64, total: f64, label_position: LabelPosition) !void {
        const mid_angle = (start_angle + end_angle) / 2.0;
        const value = @abs(p.y);
        const percentage = (value / total) * 100.0;

        // Get label text
        var label_buf: [64]u8 = undefined;
        const label_text = if (p.label) |lbl|
            lbl
        else
            try std.fmt.bufPrint(&label_buf, "{d:.1}%", .{percentage});

        switch (label_position) {
            .inside => {
                // Position label at midpoint of slice
                const label_radius = (inner_radius + outer_radius) / 2.0;
                const label_x = label_radius * @cos(mid_angle);
                const label_y = label_radius * @sin(mid_angle);

                var id_buf: [64]u8 = undefined;
                const id = try std.fmt.bufPrint(&id_buf, "chart-pie-label-{d}", .{point_index});

                try svg.text(label_x, label_y, label_text, .{
                    .id = id,
                    .class = "pie-label",
                    .anchor = .middle,
                    .dominant_baseline = .middle,
                });
            },
            .outside => {
                // Position label outside with connector line
                const label_radius = outer_radius * 1.15;
                const line_end_radius = outer_radius * 1.05;

                const line_start_x = outer_radius * @cos(mid_angle);
                const line_start_y = outer_radius * @sin(mid_angle);
                const line_end_x = line_end_radius * @cos(mid_angle);
                const line_end_y = line_end_radius * @sin(mid_angle);
                const label_x = label_radius * @cos(mid_angle);
                const label_y = label_radius * @sin(mid_angle);

                // Draw connector line
                var line_id_buf: [64]u8 = undefined;
                const line_id = try std.fmt.bufPrint(&line_id_buf, "chart-pie-label-line-{d}", .{point_index});
                try svg.line(line_start_x, line_start_y, line_end_x, line_end_y, .{
                    .id = line_id,
                    .class = "pie-label-line",
                });

                // Draw label
                var id_buf: [64]u8 = undefined;
                const id = try std.fmt.bufPrint(&id_buf, "chart-pie-label-{d}", .{point_index});

                // Determine text anchor based on position
                const anchor: Svg.TextAnchor = if (mid_angle > std.math.pi / 2.0 and mid_angle < 3.0 * std.math.pi / 2.0)
                    .end
                else
                    .start;

                try svg.text(label_x, label_y, label_text, .{
                    .id = id,
                    .class = "pie-label",
                    .anchor = anchor,
                    .dominant_baseline = .middle,
                });
            },
            .none => {},
        }
    }

    /// NEW: Render stacked grouped bars (like the Nightwatch chart)
    fn renderStackedBars(self: *Chart, svg: *Svg, s: Series, series_index: usize, x_scale: Scale, y_scale: Scale, default_color: Vapor.Types.Color) !void {
        if (s.data.len == 0) return;

        // Count stacked_bar series and find this series' position
        var stacked_series_count: usize = 0;
        var stacked_series_index: usize = 0;
        for (self.series.items, 0..) |item, i| {
            if (item.type == .stacked_bar) {
                if (i == series_index) stacked_series_index = stacked_series_count;
                stacked_series_count += 1;
            }
        }

        const n_points: f64 = @floatFromInt(s.data.len);
        const n_series: f64 = @floatFromInt(stacked_series_count);

        // Calculate bar dimensions
        const total_width = x_scale.rangeMax() - x_scale.rangeMin();
        const group_width = (total_width / n_points) * 0.85;
        const bar_width = group_width / n_series;
        const actual_bar_width = bar_width * 0.90; // Gap between bars

        const baseline_y = y_scale.scale(0);

        for (s.data, 0..) |p, point_index| {
            const center_x = x_scale.scale(p.x);
            const group_start = center_x - (group_width / 2);
            const bar_x = group_start + (@as(f64, @floatFromInt(stacked_series_index)) * bar_width);

            // Render shadow bar first (behind the actual bars) if enabled
            if (s.options.show_shadow) {
                const shadow_color = s.options.shadow_color orelse Vapor.Types.Color.hex("#000000");
                const max_y = y_scale.scale(self.max_y_value);
                const shadow_height = @abs(baseline_y - max_y);

                var shadow_id_buf: [64]u8 = undefined;
                const shadow_id = try std.fmt.bufPrint(&shadow_id_buf, "chart-{d}-{d}-shadow_bar", .{
                    series_index,
                    point_index,
                });

                try svg.rect(bar_x, max_y, actual_bar_width, shadow_height, .{
                    .id = shadow_id,
                    .fill = shadow_color,
                    .opacity = s.options.shadow_opacity,
                    .rx = s.options.bar_radius,
                    .class = "shadow-bar",
                });

                try self.rendered_elements.append(.{
                    .id = .{
                        .series_name = s.name,
                        .series_index = @intCast(series_index),
                        .point_index = @intCast(point_index),
                        .element_type = .shadow_bar,
                    },
                    .attrs = .{ .rect = .{
                        .x = bar_x,
                        .y = max_y,
                        .width = actual_bar_width,
                        .height = shadow_height,
                        .fill = shadow_color,
                    } },
                });
            }

            if (p.stack) |stack| {
                // Render stacked segments
                var pos_offset: f64 = 0; // Accumulator for positive values (stack upward)
                var neg_offset: f64 = 0; // Accumulator for negative values (stack downward)

                for (stack, 0..) |seg, stack_idx| {
                    const seg_color = seg.color orelse
                        (if (s.options.stack_colors) |colors|
                            (if (stack_idx < colors.len) colors[stack_idx] else default_color)
                        else
                            default_color);

                    const value = seg.value;

                    var seg_y: f64 = undefined;
                    var seg_height: f64 = undefined;

                    if (value >= 0) {
                        // Positive: stack upward from baseline
                        const bottom_y = y_scale.scale(pos_offset);
                        const top_y = y_scale.scale(pos_offset + value);
                        seg_y = top_y;
                        seg_height = bottom_y - top_y;
                        pos_offset += value;
                    } else {
                        // Negative: stack downward from baseline
                        const top_y = y_scale.scale(neg_offset);
                        const bottom_y = y_scale.scale(neg_offset + value);
                        seg_y = top_y;
                        seg_height = bottom_y - top_y;
                        neg_offset += value;
                    }

                    // Ensure minimum visibility
                    if (seg_height < 1) seg_height = 1;

                    var id_buf: [64]u8 = undefined;
                    const id = try std.fmt.bufPrint(&id_buf, "chart-{d}-{d}-{d}-stacked_bar", .{
                        series_index,
                        point_index,
                        stack_idx,
                    });

                    try svg.rect(bar_x, seg_y, actual_bar_width, seg_height, .{
                        .id = id,
                        .fill = seg_color,
                        .rx = s.options.bar_radius,
                        .class = "stacked-bar",
                        .border = s.options.border,
                        .stroke = s.options.stroke,
                        .stroke_width = s.options.stroke_width,
                    });

                    try self.rendered_elements.append(.{
                        .id = .{
                            .series_name = s.name,
                            .series_index = @intCast(series_index),
                            .point_index = @intCast(point_index),
                            .stack_index = @intCast(stack_idx),
                            .element_type = .stacked_bar,
                        },
                        .attrs = .{ .rect = .{
                            .x = bar_x,
                            .y = seg_y,
                            .width = actual_bar_width,
                            .height = seg_height,
                            .fill = seg_color,
                        } },
                    });
                }
            } else {
                // No stack data, render as single bar
                const y = y_scale.scale(p.y);
                const height = @abs(baseline_y - y);

                var id_buf: [64]u8 = undefined;
                const id = try std.fmt.bufPrint(&id_buf, "chart-{d}-{d}-stacked_bar", .{ series_index, point_index });

                try svg.rect(bar_x, @min(y, baseline_y), actual_bar_width, height, .{
                    .id = id,
                    .fill = default_color,
                    .rx = s.options.bar_radius,
                    .class = "stacked-bar",
                });
            }
        }
    }

    fn renderLine(self: *Chart, svg: *Svg, s: Series, series_index: usize, x_scale: Scale, y_scale: Scale, series_color: Vapor.Types.Color, smooth: bool) !void {
        if (s.data.len == 0) return;

        var points = try self.allocator.alloc([2]f64, s.data.len);
        defer self.allocator.free(points);

        for (s.data, 0..) |p, i| {
            points[i] = .{ x_scale.scale(p.x), y_scale.scale(p.y) };
        }

        const path_d = if (smooth)
            try path_util.smoothLine(self.allocator, points, 1.0)
        else
            try self.straightLine(points);

        var path_id_buf: [64]u8 = undefined;
        const path_id = try std.fmt.bufPrint(&path_id_buf, "chart-{d}-line_path", .{series_index});
        try svg.path(path_d, .{
            .id = path_id,
            .class = "series-line",
            .stroke = series_color,
            .stroke_width = s.options.stroke_width,
        });

        try self.rendered_elements.append(.{
            .id = .{ .series_name = s.name, .series_index = @intCast(series_index), .element_type = .line_path },
            .attrs = .{ .path = .{ .d = path_d, .stroke = series_color, .stroke_width = s.options.stroke_width } },
        });

        if (s.options.show_dots) {
            for (points, 0..) |pt, point_index| {
                var id_buf: [64]u8 = undefined;
                const id = try std.fmt.bufPrint(&id_buf, "chart-{d}-{d}-dot", .{ series_index, point_index });

                try svg.circle(pt[0], pt[1], @floatFromInt(s.options.dot_radius), .{
                    .id = id,
                    .class = "series-dot",
                    .fill = series_color,
                });

                try self.rendered_elements.append(.{
                    .id = .{ .series_name = s.name, .series_index = @intCast(series_index), .point_index = @intCast(point_index), .element_type = .dot },
                    .attrs = .{ .circle = .{ .cx = pt[0], .cy = pt[1], .r = @floatFromInt(s.options.dot_radius), .fill = series_color } },
                });
            }
        }
    }

    fn renderArea(self: *Chart, svg: *Svg, s: Series, series_index: usize, x_scale: Scale, y_scale: Scale, series_color: Vapor.Types.Color, smooth: bool) !void {
        if (s.data.len == 0) return;

        var points = try self.allocator.alloc([2]f64, s.data.len);
        defer self.allocator.free(points);

        for (s.data, 0..) |p, i| {
            points[i] = .{ x_scale.scale(p.x), y_scale.scale(p.y) };
        }

        const baseline = y_scale.scale(y_scale.domainMin());

        var path = path_util.PathBuilder.init(self.allocator);
        defer path.deinit();

        const line_d = if (smooth)
            try path_util.smoothLine(self.allocator, points, 1.0)
        else
            try self.straightLine(points);
        defer self.allocator.free(line_d);

        try path.buffer.appendSlice(path.allocator, line_d);
        try path.lineTo(points[points.len - 1][0], baseline);
        try path.lineTo(points[0][0], baseline);
        try path.closePath();

        var path_id_buf: [64]u8 = undefined;
        const path_id = try std.fmt.bufPrint(&path_id_buf, "chart-{d}-area_path", .{series_index});
        const path_d = path.slice();
        try svg.path(path_d, .{
            .id = path_id,
            .class = "series-area",
            .fill = series_color,
        });

        try self.rendered_elements.append(.{
            .id = .{ .series_name = s.name, .series_index = @intCast(series_index), .element_type = .area_path },
            .attrs = .{ .path = .{ .d = path_d, .fill = series_color } },
        });

        try self.renderLine(svg, s, series_index, x_scale, y_scale, series_color, smooth);
    }

    fn renderBars(self: *Chart, svg: *Svg, s: Series, series_index: usize, x_scale: Scale, y_scale: Scale, series_color: Vapor.Types.Color) !void {
        if (s.data.len == 0) return;

        var bar_series_count: usize = 0;
        var bar_series_index: usize = 0;
        for (self.series.items, 0..) |item, i| {
            if (item.type == .bar) {
                if (i == series_index) bar_series_index = bar_series_count;
                bar_series_count += 1;
            }
        }

        const n_points: f64 = @floatFromInt(s.data.len);
        const n_series: f64 = @floatFromInt(bar_series_count);

        const total_width = x_scale.rangeMax() - x_scale.rangeMin();
        const group_width = (total_width / n_points) * 0.9;
        const bar_width = group_width / n_series;

        const baseline = y_scale.scale(@max(0, y_scale.domainMin()));

        for (s.data, 0..) |p, point_index| {
            const center_x = x_scale.scale(p.x);
            const group_start = center_x - (group_width / 2);
            const x = group_start + (@as(f64, @floatFromInt(bar_series_index)) * bar_width);

            const actual_bar_width = bar_width * 0.95;

            // Render shadow bar first if enabled
            if (s.options.show_shadow) {
                const shadow_color = s.options.shadow_color orelse Vapor.Types.Color.hex("#000000");
                const max_y = y_scale.scale(self.max_y_value);
                const shadow_height = @abs(baseline - max_y);

                var shadow_id_buf: [64]u8 = undefined;
                const shadow_id = try std.fmt.bufPrint(&shadow_id_buf, "{s}-{d}-{d}-shadow_bar", .{
                    s.name,
                    series_index,
                    point_index,
                });

                try svg.rect(x, max_y, actual_bar_width, shadow_height, .{
                    .id = shadow_id,
                    .fill = shadow_color,
                    .opacity = s.options.shadow_opacity,
                    .rx = s.options.bar_radius,
                    .class = "shadow-bar",
                });

                try self.rendered_elements.append(.{
                    .id = .{
                        .series_name = s.name,
                        .series_index = @intCast(series_index),
                        .point_index = @intCast(point_index),
                        .element_type = .shadow_bar,
                    },
                    .attrs = .{ .rect = .{
                        .x = x,
                        .y = max_y,
                        .width = actual_bar_width,
                        .height = shadow_height,
                        .fill = shadow_color,
                    } },
                });
            }

            const y = y_scale.scale(p.y);
            const height = @abs(baseline - y);

            var id_buf: [128]u8 = undefined;
            const id = try std.fmt.bufPrint(&id_buf, "{s}-{d}-{d}-bar", .{ s.name, series_index, point_index });
            try svg.rect(x, @min(y, baseline), actual_bar_width, height, .{
                .id = id,
                .fill = series_color,
                .rx = s.options.bar_radius,
                .class = "series-bar",
            });

            try self.rendered_elements.append(.{
                .id = .{ .series_name = s.name, .series_index = @intCast(series_index), .point_index = @intCast(point_index), .element_type = .bar },
                .attrs = .{ .rect = .{ .x = x, .y = @min(y, baseline), .width = actual_bar_width, .height = height, .fill = series_color } },
            });
        }
    }

    fn renderScatter(self: *Chart, svg: *Svg, s: Series, series_index: usize, x_scale: Scale, y_scale: Scale, series_color: Vapor.Types.Color) !void {
        for (s.data, 0..) |p, point_index| {
            const x = x_scale.scale(p.x);
            const y = y_scale.scale(p.y);

            var id_buf: [64]u8 = undefined;
            const id = try std.fmt.bufPrint(&id_buf, "chart-{d}-{d}-dot", .{ series_index, point_index });

            try svg.circle(x, y, @floatFromInt(s.options.dot_radius), .{
                .id = id,
                .class = "series-dot",
                .fill = series_color,
            });

            try self.rendered_elements.append(.{
                .id = .{ .series_name = s.name, .series_index = @intCast(series_index), .point_index = @intCast(point_index), .element_type = .dot },
                .attrs = .{ .circle = .{ .cx = x, .cy = y, .r = @floatFromInt(s.options.dot_radius), .fill = series_color } },
            });
        }
    }

    fn renderAxes(self: *Chart, svg: *Svg, x_scale: Scale, y_scale: Scale, width: f64, height: f64, x_axis_config: AxisConfig, y_axis_config: AxisConfig) !void {
        const show_x_axis_line = x_axis_config.show_axis_line;
        const show_y_axis_line = y_axis_config.show_axis_line;
        const show_x_axis_ticks = x_axis_config.show_axis_ticks;
        const show_y_axis_ticks = y_axis_config.show_axis_ticks;

        // X axis line
        if (show_x_axis_line) {
            try svg.line(0, height, width, height, .{ .class = "axis", .id = "chart-axis-x", .stroke = x_axis_config.color });
        }

        // Y axis line
        if (show_y_axis_line) {
            try svg.line(0, 0, 0, height, .{ .class = "axis", .id = "chart-axis-y", .stroke = x_axis_config.color });
        }

        // X axis ticks
        if (show_x_axis_ticks) {
            const x_tick_count: usize = if (self.x_axis_config) |c| c.tick_count else 5;
            const x_ticks = try x_scale.ticks(x_tick_count, self.allocator);
            defer self.allocator.free(x_ticks);

            for (x_ticks) |tick| {
                const x = x_scale.scale(tick);
                var id_buf: [64]u8 = undefined;
                const id = try std.fmt.bufPrint(&id_buf, "chart-axis-x-{d}", .{tick});
                try svg.line(x, height, x, height + 5, .{ .class = "axis", .id = id });

                var label_buf: [32]u8 = undefined;
                const label = try std.fmt.bufPrint(&label_buf, "{d:.0}", .{tick});
                var id_buf_text: [64]u8 = undefined;
                const id_text = try std.fmt.bufPrint(&id_buf_text, "chart-axis-x-{d}-text-label", .{tick});
                try svg.text(x, height + 18, label, .{ .class = "tick-label", .anchor = .middle, .id = id_text });
            }
        }

        // Y axis ticks
        if (show_y_axis_ticks) {
            const y_tick_count: usize = if (self.y_axis_config) |c| c.tick_count else 5;
            const y_ticks = try y_scale.ticks(y_tick_count, self.allocator);
            defer self.allocator.free(y_ticks);

            for (y_ticks) |tick| {
                const y = y_scale.scale(tick);
                var id_buf: [64]u8 = undefined;
                const id = try std.fmt.bufPrint(&id_buf, "chart-axis-y-{d}", .{tick});
                try svg.line(-5, y, 0, y, .{ .class = "axis", .id = id });

                var label_buf: [32]u8 = undefined;
                const label = try std.fmt.bufPrint(&label_buf, "{d:.0}", .{tick});
                var id_buf_text: [64]u8 = undefined;
                const id_text = try std.fmt.bufPrint(&id_buf_text, "chart-axis-y-{d}-text-label", .{tick});
                try svg.text(-10, y, label, .{ .class = "tick-label", .anchor = .end, .dominant_baseline = .middle, .id = id_text });
            }
        }

        // Axis labels
        if (self.x_axis_config) |cfg| {
            if (cfg.label) |label| {
                try svg.text(width / 2, height + 35, label, .{
                    .class = "axis-label",
                    .anchor = .middle,
                });
            }
        }

        if (self.y_axis_config) |cfg| {
            if (cfg.label) |label| {
                var transform_buf: [128]u8 = undefined;
                const t = try std.fmt.bufPrint(&transform_buf, "rotate(-90) translate({d:.2}, {d})", .{ -height / 2, -35 });
                try svg.text(0, 0, label, .{
                    .class = "axis-label",
                    .anchor = .middle,
                    .transform = t,
                });
            }
        }
    }

    fn renderLegend(self: *Chart, svg: *Svg) !void {
        const cfg = self.legend_config orelse return;
        const m = self.config.margin;

        // A row's items are as wide as their text, and the row stays over
        // the plot: right-aligned when it fits, else from the left edge,
        // wrapping onto further lines.
        const left: f64 = @floatFromInt(m.left);
        const right: f64 = @floatFromInt(self.config.width -| m.right);
        var row_width: f64 = 0;
        for (self.series.items) |s| row_width += legendItemWidth(s.name);
        for (cfg.fields) |f| row_width += legendItemWidth(f.title);

        // Starting position based on position config
        const start_x: f64 = switch (cfg.position) {
            .top_left, .bottom_left => left + 10,
            .top_right, .bottom_right => switch (cfg.direction) {
                .column => @max(left, right - 100),
                .row => @max(left, right - row_width),
            },
        };

        const start_y: f64 = switch (cfg.position) {
            .top_left, .top_right => @floatFromInt(m.top),
            .bottom_left, .bottom_right => @floatFromInt(self.config.height -| m.bottom -| 20),
        };

        var current_x = start_x;
        var current_y = start_y;

        // Render series legends
        for (self.series.items, 0..) |s, i| {
            if (cfg.direction == .row) wrapLegend(&current_x, &current_y, s.name, start_x, right, cfg.spacing);
            const series_color = s.options.color orelse Vapor.Types.Color.hex(self.config.palette.get(i));

            var id_buf: [64]u8 = undefined;
            const id = try std.fmt.bufPrint(&id_buf, "chart-legend-{d}", .{i});
            try svg.rect(current_x, current_y - 6, 12, 12, .{ .fill = series_color, .rx = 2, .id = id });

            try self.rendered_elements.append(.{
                .id = .{ .series_name = s.name, .series_index = @intCast(i), .element_type = .legend },
                .attrs = .{ .rect = .{ .x = current_x, .y = current_y - 6, .width = 12, .height = 12 } },
            });

            try svg.text(current_x + 18, current_y + 3, s.name, .{ .class = "legend-text", .fill = cfg.text_color });

            // Advance position based on direction
            switch (cfg.direction) {
                .column => current_y += cfg.spacing,
                .row => current_x += legendItemWidth(s.name),
            }
        }

        // Render custom field legends
        for (cfg.fields, self.series.items.len..) |f, i| {
            if (cfg.direction == .row) wrapLegend(&current_x, &current_y, f.title, start_x, right, cfg.spacing);
            const series_color = f.color;

            var id_buf: [64]u8 = undefined;
            const id = try std.fmt.bufPrint(&id_buf, "chart-legend-{d}", .{i});
            try svg.rect(current_x, current_y - 6, 12, 12, .{ .fill = series_color, .rx = 2, .id = id });

            try self.rendered_elements.append(.{
                .id = .{ .series_name = "", .series_index = @intCast(i), .element_type = .legend },
                .attrs = .{ .rect = .{ .x = current_x, .y = current_y - 6, .width = 12, .height = 12 } },
            });

            try svg.text(current_x + 18, current_y + 3, f.title, .{ .class = "legend-text", .fill = cfg.text_color });

            // Advance position based on direction
            switch (cfg.direction) {
                .column => current_y += cfg.spacing,
                .row => current_x += legendItemWidth(f.title),
            }
        }
    }

    /// A row legend item's width: its swatch, the gap after it, its text at
    /// the legend's 11px (about 6.5px a character) and the gap to the next.
    fn legendItemWidth(title: []const u8) f64 {
        return 18 + @as(f64, @floatFromInt(title.len)) * 6.5 + 16;
    }

    /// Moves a row legend's next item onto a new line when it would cross
    /// the plot's right edge, unless it is the first on its line.
    fn wrapLegend(x: *f64, y: *f64, title: []const u8, line_start: f64, right: f64, spacing: f64) void {
        if (x.* > line_start and x.* + legendItemWidth(title) - 16 > right) {
            x.* = line_start;
            y.* += spacing;
        }
    }

    fn straightLine(self: *Chart, points: [][2]f64) ![]u8 {
        var path = path_util.PathBuilder.init(self.allocator);
        defer path.deinit();

        if (points.len == 0) return try self.allocator.dupe(u8, "");

        try path.moveTo(points[0][0], points[0][1]);
        for (points[1..]) |pt| {
            try path.lineTo(pt[0], pt[1]);
        }

        return path.toOwnedSlice();
    }

    const HoverTarget = struct {
        id: []const u8, // slice into the caller's buffer
        attr: []const u8, // "fill" or "stroke"
    };

    fn hoverTargetFor(self: *Chart, pt: HoveredPoint, buf: []u8) ?HoverTarget {
        const s = self.series.items[pt.series_index];
        return switch (s.type) {
            .bar => .{
                .id = std.fmt.bufPrint(buf, "{s}-{d}-{d}-bar", .{ s.name, pt.series_index, pt.point_index }) catch return null,
                .attr = "fill",
            },
            .stacked_bar => .{
                .id = std.fmt.bufPrint(buf, "chart-{d}-{d}-{d}-stacked_bar", .{ pt.series_index, pt.point_index, pt.stack_index orelse 0 }) catch return null,
                .attr = "fill",
            },
            // line / area / scatter all highlight the dot at that x
            .line, .line_smooth, .area, .area_smooth, .scatter => {
                if (!s.options.show_dots) {
                    return null;
                }
                return .{
                    .id = std.fmt.bufPrint(buf, "chart-{d}-{d}-dot", .{ pt.series_index, pt.point_index }) catch return null,
                    .attr = "fill",
                };
            },
            .pie, .donut => .{
                .id = std.fmt.bufPrint(buf, "chart-{d}-{d}-pie_slice", .{ pt.series_index, pt.point_index }) catch return null,
                .attr = "fill",
            },
        };
    }

    pub fn showTooltip(self: *Chart, event: *Vapor.Event) void {
        const offsets = self.container.getBoundingClientRect() orelse return;
        self.bounds.offset_x = offsets.left;
        self.bounds.offset_y = offsets.top;

        if (self.tooltip) |*tooltip| {
            const x = event.clientX() - self.bounds.offset_x;
            const y = event.clientY() - self.bounds.offset_y;

            tooltip.left = x;
            tooltip.top = y;

            // tooltip.binded.mutateStyleString("display", "block");
            // tooltip.line_binded.mutateStyleString("display", "block");
            tooltip.binded.mutateAttribute(.{ .flex_type = .flex });
            if (self.config.show_line) tooltip.line_binded.mutateAttribute(.{ .flex_type = .flex });
            tooltip.hide = false;

            if (self.findNearestX(@floatCast(x), y)) |result| {
                defer self.allocator.free(result.points);

                if (self.old_x != result.points[0].screen_x) {
                    for (result.points, 0..) |pt, i| {
                        if (pt.data_y >= 0) {
                            tooltip.value[i].value = pt.data_y;
                            tooltip.value[i].color = pt.series_color;

                            var buf: [128]u8 = undefined;
                            if (self.hoverTargetFor(pt, &buf)) |t| {
                                self.platform.browser.setAttribute(t.id, t.attr, Svg.convertColor(pt.hovered_color));
                            }
                        } else {
                            tooltip.value[i].value = null;
                        }
                    }
                    self.old_points = self.allocator.dupe(HoveredPoint, result.points) catch null;
                }
                _ = tooltip.binded.translate3d(.{ .x = result.points[0].screen_x, .y = tooltip.top });
                self.old_x = result.points[0].screen_x;
            }
        }
    }

    pub fn updateTooltip(self: *Chart, event: *Vapor.Event) void {
        if (self.tooltip) |*tooltip| {
            const x = event.clientX() - self.bounds.offset_x;
            const y = event.clientY() - self.bounds.offset_y;

            tooltip.left = x;
            tooltip.top = y;

            if (self.findNearestX(@floatCast(x), y)) |result| {
                defer self.allocator.free(result.points);

                if (self.old_x != result.points[0].screen_x) {
                    // Reset previously hovered points back to their series color
                    if (self.old_points) |old_pts| {
                        for (old_pts) |old_pt| {
                            var buf: [128]u8 = undefined;
                            if (self.hoverTargetFor(old_pt, &buf)) |t| {
                                self.platform.browser.setAttribute(t.id, t.attr, Svg.convertColor(old_pt.series_color));
                            }
                        }
                        self.allocator.free(old_pts);
                        self.old_points = null;
                    }

                    // Apply hover color to new points
                    for (result.points, 0..) |pt, i| {
                        if (pt.data_y >= 0) {
                            tooltip.value[i].value = pt.data_y;
                            tooltip.value[i].color = pt.series_color;

                            var buf: [128]u8 = undefined;
                            if (self.hoverTargetFor(pt, &buf)) |t| {
                                self.platform.browser.setAttribute(t.id, t.attr, Svg.convertColor(pt.hovered_color));
                            }
                        } else {
                            tooltip.value[i].value = null;
                        }
                    }

                    self.old_points = self.allocator.dupe(HoveredPoint, result.points) catch null;

                    if (self.selection == null) {
                        Vapor.cycle();
                    }
                }
                tooltip.left = result.points[0].screen_x;

                if (tooltip.width + tooltip.left > self.bounds.width) {
                    tooltip.left = tooltip.left - tooltip.width;
                }

                _ = tooltip.binded.translate3d(.{ .x = tooltip.left, .y = tooltip.top });
                if (self.config.show_line) _ = tooltip.line_binded.translate3d(.{ .x = result.points[0].screen_x - 0.5 });

                self.old_x = result.points[0].screen_x;
            }
        }
    }
    fn hideTooltip(self: *Chart, _: *Vapor.Event) void {
        if (self.tooltip) |*tooltip| {
            // tooltip.binded.mutateStyleString("display", "none");
            // tooltip.line_binded.mutateStyleString("display", "none");
            tooltip.binded.mutateAttribute(.{ .flex_type = .hidden });
            if (self.config.show_line) tooltip.line_binded.mutateAttribute(.{ .flex_type = .hidden });

            tooltip.hide = true;
        }

        if (self.old_points) |old_pts| {
            for (old_pts) |old_pt| {
                var buf: [128]u8 = undefined;
                if (self.hoverTargetFor(old_pt, &buf)) |t| {
                    self.platform.browser.setAttribute(t.id, t.attr, Svg.convertColor(old_pt.series_color));
                }
            }
            self.allocator.free(old_pts);
            self.old_points = null;
        }
    }

    pub const HoveredPoint = struct {
        series_index: usize,
        point_index: usize,
        stack_index: ?usize = null, // NEW
        data_x: f64,
        data_y: f64,
        screen_x: f32,
        screen_y: f32,
        series_name: []const u8,
        series_color: Vapor.Types.Color,
        hovered_color: Vapor.Types.Color,
    };

    pub const HoverResult = struct {
        points: []HoveredPoint,
        screen_x: f32, // For drawing vertical crosshair
    };

    pub fn findNearestX(self: *Chart, mouse_x: f64, _: f64) ?HoverResult {
        const x_scale = self.x_scale orelse return null;
        const y_scale = self.y_scale orelse return null;

        const m = self.config.margin;

        // Convert mouse position to chart-local coordinates
        const chart_x = mouse_x - @as(f64, @floatFromInt(m.left));

        // Invert X scale: screen coordinate → data value
        const data_x = x_scale.invert(chart_x);

        // Find the closest X value across all series
        var closest_x: ?f64 = null;
        var closest_dist: f64 = std.math.floatMax(f64);

        for (self.series.items) |s| {
            for (s.data) |p| {
                const dist = @abs(p.x - data_x);
                if (dist < closest_dist) {
                    closest_dist = dist;
                    closest_x = p.x;
                }
            }
        }

        const target_x = closest_x orelse return null;

        // Collect all points at this X value
        var points = std.array_list.Managed(HoveredPoint).init(self.allocator);
        defer points.deinit();

        for (self.series.items, 0..) |s, series_idx| {
            for (s.data, 0..) |p, point_idx| {
                // Use small epsilon for float comparison
                if (@abs(p.x - target_x) < 0.0001) {
                    const screen_x = x_scale.scale(p.x);
                    const screen_y = y_scale.scale(p.y);
                    const color = s.options.color orelse Vapor.Types.Color.hex(self.config.palette.get(series_idx));

                    if (p.stack) |stack| {
                        for (0..self.total_item_count) |i| {
                            var value: f64 = 0;
                            var stacked_color: Vapor.Types.Color = color;
                            var stack_index: ?usize = null;
                            if (i < stack.len) {
                                value = stack[i].value;
                                stacked_color = stack[i].color orelse color;
                                stack_index = i;
                            }
                            if (value >= 0) {
                                points.append(.{
                                    .series_index = series_idx,
                                    .point_index = point_idx, // the real point, not the stack slot
                                    .stack_index = stack_index,
                                    .data_x = p.x,
                                    .data_y = value,
                                    .screen_x = @as(f32, @floatCast(screen_x)) + @as(f32, @floatFromInt(m.left)),
                                    .screen_y = @as(f32, @floatCast(screen_y)) + @as(f32, @floatFromInt(m.top)),
                                    .series_name = s.name,
                                    .series_color = stacked_color,
                                    .hovered_color = s.options.hovered_color orelse stacked_color,
                                }) catch continue;
                            }
                        }
                    } else {
                        points.append(.{
                            .series_index = series_idx,
                            .point_index = point_idx,
                            .data_x = p.x,
                            .data_y = p.y,
                            .screen_x = @as(f32, @floatCast(screen_x)) + @as(f32, @floatFromInt(m.left)),
                            .screen_y = @as(f32, @floatCast(screen_y)) + @as(f32, @floatFromInt(m.top)),
                            .series_name = s.name,
                            .series_color = color,
                            .hovered_color = s.options.hovered_color orelse color,
                        }) catch continue;
                    }
                }
            }
        }

        if (points.items.len == 0) return null;

        // Return owned slice
        const result_points = self.allocator.dupe(HoveredPoint, points.items) catch return null;

        return .{
            .points = result_points,
            .screen_x = @as(f32, @floatCast(x_scale.scale(target_x))) + @as(f32, @floatFromInt(m.left)),
        };
    }

    // Called on pointerdown
    pub fn startSelection(self: *Chart, event: *Vapor.Event) void {
        if (!self.zoom_enabled) return;

        const x = event.clientX() - self.bounds.offset_x;
        const y = event.clientY() - self.bounds.offset_y;

        // Check if within chart area
        if (x < self.bounds.x or x > self.bounds.x + self.bounds.width) return;
        if (y < self.bounds.y or y > self.bounds.y + self.bounds.height) return;

        self.selection = .{
            .start_x = x,
            .start_y = y,
            .current_x = x,
            .current_y = y,
            .is_dragging = true,
        };
    }

    // Called on pointermove (update your existing updateTooltip or add separate handler)
    pub fn updateSelection(self: *Chart, event: *Vapor.Event) void {
        if (Vapor.Kit.throttle(16)) return;
        self.updateTooltip(event);
        if (self.selection) |*sel| {
            if (!sel.is_dragging) return;

            const x = event.clientX() - self.bounds.offset_x;
            const y = event.clientY() - self.bounds.offset_y;

            // Clamp to chart bounds
            sel.current_x = @max(self.bounds.x, @min(x, self.bounds.x + self.bounds.width));
            sel.current_y = @max(self.bounds.y, @min(y, self.bounds.y + self.bounds.height));
            const min_x = @min(sel.start_x, sel.current_x);
            const min_y = @min(sel.start_y, sel.current_y);

            _ = self.selection_rect.translate3d(.{ .x = min_x, .y = min_y });
            const width = @abs(sel.current_x - sel.start_x);
            const height = @abs(sel.current_y - sel.start_y);
            self.selection_rect.mutateStyleString("width", Vapor.fmtln("{d}px", .{width}));
            self.selection_rect.mutateStyleString("height", Vapor.fmtln("{d}px", .{height}));
            // Force re-render to show selection box
        }
    }

    // Called on pointerup
    pub fn endSelection(self: *Chart, event: *Vapor.Event) void {
        _ = event;
        if (self.selection) |sel| {
            if (!sel.is_dragging) return;

            // Calculate selection bounds (handle any drag direction)
            const min_x = @min(sel.start_x, sel.current_x);
            const max_x = @max(sel.start_x, sel.current_x);
            const min_y = @min(sel.start_y, sel.current_y);
            const max_y = @max(sel.start_y, sel.current_y);

            // Minimum selection size (prevent accidental tiny selections)
            const min_size: f32 = 20;
            if ((max_x - min_x) < min_size or (max_y - min_y) < min_size) {
                self.selection = null;
                return;
            }

            // Convert screen coordinates to data coordinates
            if (self.x_scale) |x_scale| {
                if (self.y_scale) |y_scale| {
                    // Store original domains on first zoom
                    if (self.original_x_domain == null) {
                        self.original_x_domain = .{ x_scale.domainMin(), x_scale.domainMax() };
                        self.original_y_domain = .{ y_scale.domainMin(), y_scale.domainMax() };
                    }

                    // Convert to chart-local coordinates
                    const m = self.config.margin;
                    const chart_min_x = min_x - @as(f32, @floatFromInt(m.left));
                    const chart_max_x = max_x - @as(f32, @floatFromInt(m.left));
                    const chart_min_y = min_y - @as(f32, @floatFromInt(m.top));
                    const chart_max_y = max_y - @as(f32, @floatFromInt(m.top));

                    // Invert to get data values
                    const new_x_min = x_scale.invert(@floatCast(chart_min_x));
                    const new_x_max = x_scale.invert(@floatCast(chart_max_x));
                    // Note: Y is inverted (screen Y increases downward)
                    const new_y_min = y_scale.invert(@floatCast(chart_max_y));
                    const new_y_max = y_scale.invert(@floatCast(chart_min_y));

                    // Apply zoom by updating axis configs
                    self.applyZoom(new_x_min, new_x_max, new_y_min, new_y_max);
                }
            }
        }

        self.selection = null;
    }

    fn applyZoom(self: *Chart, x_min: f64, x_max: f64, y_min: f64, y_max: f64) void {
        // Update axis scale configs to use manual domain
        if (self.x_axis_config) |*cfg| {
            cfg.scale.domain = .{ .manual = .{ x_min, x_max } };
        } else {
            self.x_axis_config = .{
                .scale = .{ .domain = .{ .manual = .{ x_min, x_max } } },
            };
        }

        if (self.y_axis_config) |*cfg| {
            cfg.scale.domain = .{ .manual = .{ y_min, y_max } };
        } else {
            self.y_axis_config = .{
                .scale = .{ .domain = .{ .manual = .{ y_min, y_max } } },
            };
        }

        if (self.onendselection) |onendselection| {
            @call(.auto, onendselection, .{ x_min, x_max, y_min, y_max });
        }

        // Rebuild chart with new scales
        self.build() catch {};
        Vapor.cycle();
    }

    // Reset zoom to original view
    pub fn resetZoom(self: *Chart) void {
        if (self.original_x_domain) |x_dom| {
            if (self.x_axis_config) |*cfg| {
                cfg.scale.domain = .{ .manual = x_dom };
            }
        }
        if (self.original_y_domain) |y_dom| {
            if (self.y_axis_config) |*cfg| {
                cfg.scale.domain = .{ .manual = y_dom };
            }
        }

        self.original_x_domain = null;
        self.original_y_domain = null;

        self.build() catch {};
        Vapor.cycle();
    }

    /// --------------------------------------
    /// Rendering
    /// --------------------------------------
    fn mount(self: *Chart) void {
        const offsets = self.container.getOffsets() orelse return;
        self.bounds.offset_x = offsets.offset_left;
        self.bounds.offset_y = offsets.offset_top;

        // Get actual container dimensions
        if (self.container.getBoundingClientRect()) |rect| {
            self.config.width = @intFromFloat(rect.width);
            self.bounds = calculateBounds(self.config);
            self.build() catch {};
        }

        if (self.tooltip) |*tooltip| {
            tooltip.binded.mutateAttribute(.{ .flex_type = .hidden });
            // The line is only on the page when the chart shows one.
            if (self.config.show_line) tooltip.line_binded.mutateAttribute(.{ .flex_type = .hidden });
        }
        Vapor.cycle();
    }

    pub fn render(self: *Chart) void {
        Box()
            .width(.percent(100))
            .height(.px(@floatFromInt(self.config.height)))
            .children({
            Box()
                .ref(&self.container)
                .onMount(mount, .{self})
                // .onResize(resize, .{self})
                .pos(.relative)
                .width(.percent(100))
                .height(.percent(100))
                .cursor(.crosshair)
                .onEvent(.pointerenter, showTooltip, .{self})
                .onEvent(.pointerleave, hideTooltip, .{self})
                .onEvent(.pointerdown, startSelection, .{self}) // Add this
                .onEvent(.pointermove, updateSelection, .{self}) // Combined handler
                .onEvent(.pointerup, endSelection, .{self}) // Add this
                .children({
                if (self.tooltip) |*tooltip| {
                    if (self.config.show_line) {
                        Box()
                            .ref(&tooltip.line_binded)
                            .pos(.tl(.px(@floatFromInt(self.config.margin.top)), .px(0), .absolute))
                            .width(.px(1))
                            .transition(.{
                                .properties = &.{.transform},
                                .duration = 50,
                                .timing = .ease,
                            })
                            .height(.px(@floatFromInt(self.config.height -| self.config.margin.bottom -| self.config.margin.top)))
                            .background(.palette(.text_color))
                            .children({});
                    }
                    Box()
                        .ref(&tooltip.binded)
                        .transition(.{
                            .properties = &.{.transform},
                            .duration = 50,
                            .timing = .ease,
                        })
                        .pos(.absolute)
                        .width(.px(140))
                        .padding(.xy(4, 2))
                        .ml(if (self.config.show_line) 16 else 0)
                        .layout(.top_left)
                        .direction(.column)
                        .background(.palette(.background))
                        .border(.round(.transparent, .all(4)))
                        .shadow(.glow(4, .transparentize(.hex("#616161"), 0.1)))
                        .zIndex(1000)
                        .children({
                        Text(tooltip.x_label)
                            .inlineStyle("user-select: none;", .{})
                            .font(12, 300, .palette(.text_color)).end();
                        var total: f64 = 0;
                        for (tooltip.value) |lg| {
                            if (lg.value) |val| {
                                Box()
                                    .layout(.x_between_center)
                                    .spacing(4)
                                    .children({
                                    Box()
                                        .layout(.left_center)
                                        .spacing(4)
                                        .children({
                                        Box().width(.px(8)).height(.px(12))
                                            .border(.round(lg.color, .all(2)))
                                            .background(lg.color)
                                            .children({});
                                        Text(lg.title)
                                            .inlineStyle("user-select: none;", .{})
                                            .font(12, 300, .palette(.text_color)).end();
                                    });
                                    total += val;
                                    Vapor.Number(val)
                                        .inlineStyle("user-select: none;", .{})
                                        .font(12, 300, .palette(.text_color)).end();
                                });
                            }
                        }
                        Box()
                            .layout(.x_between_center)
                            .spacing(4)
                            .children({
                            Box()
                                .layout(.left_center)
                                .spacing(4)
                                .children({
                                Text("Total")
                                    .inlineStyle("user-select: none;", .{})
                                    .font(12, 300, .palette(.text_color)).end();
                            });
                            Vapor.Number(total)
                                .inlineStyle("user-select: none;", .{})
                                .font(12, 300, .palette(.text_color)).end();
                        });
                    });
                } else {
                    Vapor.Null();
                }

                // Selection rectangle overlay
                if (self.selection) |sel| {
                    if (sel.is_dragging) {
                        const width = @abs(sel.current_x - sel.start_x);
                        const height = @abs(sel.current_y - sel.start_y);

                        Box()
                            .pos(.absolute)
                            .ref(&self.selection_rect)
                            .width(.px(width))
                            .height(.px(height))
                            .background(.transparentize(.palette(.border_color_light), 0.7)) // Blue with transparency
                            .border(.round(.palette(.border_color_light), .all(1)))
                            .children({});
                    }
                } else {
                    Vapor.Null();
                }

                if (self.current_chart_svg) |svg_content| {
                    Vapor.Svg(.{ .svg = svg_content, .override = true })
                        .end();
                    if (self.config.show_bottom_line) {
                        const x_axis_config = self.x_axis_config orelse AxisConfig{};
                        Box()
                            .pos(.tl(.px(@floatFromInt(self.config.height -| self.config.margin.bottom)), .px(@floatFromInt(self.config.margin.left)), .absolute))
                            .width(.px(@floatFromInt(self.config.width -| self.config.margin.left -| self.config.margin.right)))
                            .height(.px(1))
                            .background(x_axis_config.color)
                            .children({});
                    }
                } else {
                    Vapor.Null();
                }
            });
        });
    }
};

fn findMin(data: []const f64) f64 {
    if (data.len == 0) return 0;
    var min = data[0];
    for (data) |v| min = @min(min, v);
    return min;
}

fn findMax(data: []const f64) f64 {
    if (data.len == 0) return 1;
    var max = data[0];
    for (data) |v| max = @max(max, v);
    return max;
}
