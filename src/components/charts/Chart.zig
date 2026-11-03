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
    /// The value as the tooltip shows it, through the y axis's formatter.
    text: []const u8 = "",
    text_buf: [48]u8 = undefined,
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
    /// The first line: the point's label, or the x value it is at.
    header: []const u8 = "",
    header_buf: [96]u8 = undefined,
    /// Shown long enough to slide from point to point; it appears in place.
    sliding: bool = false,
    /// Where the vertical line through the hovered x is.
    line_x: f32 = 0,
    total_text: []const u8 = "",
    total_buf: [48]u8 = undefined,
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
    /// False turns zooming off, as `.zoom = .none` does.
    zoom_enabled: bool = true,

    // The axes as they were before the first zoom, for resetZoom.
    pre_zoom_axes: ?struct { x: ?AxisConfig, y: ?AxisConfig } = null,

    old_points: ?[]HoveredPoint = null,

    onendselection: ?*const fn (x_min: f64, x_max: f64, y_min: f64, y_max: f64) void = null,

    has_data: bool = false,
    /// No series has a point: the chart shows `config.empty_text`.
    is_empty: bool = false,

    /// Legend items switched off, by their place in the legend: a series,
    /// a stacked bar's segment or a pie's slice.
    hidden: std.StaticBitSet(64) = .initEmpty(),
    legend_items: []LegendItem = &.{},
    references: std.array_list.Managed(Reference),
    /// Where a pie's slices lie, for finding the one under the pointer.
    pie_slices: std.array_list.Managed(PieSliceHit),
    /// The distance between neighbouring x values, which sets a bar's width.
    x_step: f64 = 1,
    /// Builds before the chart is first on the page fade it in.
    entering: bool = true,
    /// The pie slice the tooltip is showing.
    hovered_slice: ?usize = null,

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
        /// What a drag over the plot zooms into: an x range, with the y
        /// axis fitted to the data left in it; a box on both axes; or
        /// nothing.
        zoom: ZoomMode = .x,
        /// The chart fades in when it first shows. Never for anyone who asks
        /// their system for less motion.
        animate: bool = true,
        /// Shown in place of the plot when no series has a point.
        empty_text: []const u8 = "No data",
        /// A Total row in the tooltip. Unset, only stacked bars have one.
        tooltip_total: ?bool = null,
    };

    pub const ZoomMode = enum { none, x, xy };

    /// Writes `value` into `buf` as a tick label or tooltip value would
    /// show it, and returns that: "$1.2k", "45%", "Mar 3".
    pub const Formatter = *const fn (value: f64, buf: []u8) []const u8;

    /// A line across the plot at a value, or a band between two: a target,
    /// a threshold, an average.
    pub const Reference = struct {
        /// .y lies across the plot at a y value, .x stands at an x value.
        axis: enum { x, y } = .y,
        value: f64,
        /// Set, the reference is a band from `value` to `to`.
        to: ?f64 = null,
        label: ?[]const u8 = null,
        /// Unset, the theme's text colour.
        color: ?Vapor.Types.Color = null,
        dashed: bool = true,
    };

    const PieSliceHit = struct {
        index: usize,
        series_index: usize,
        start: f64,
        end: f64,
        cx: f64,
        cy: f64,
        inner: f64,
        outer: f64,
        percent: f64,
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
        /// Writes this axis's tick labels, and for the y axis the tooltip's
        /// values; for the x axis its header. Unset, numbers show as many
        /// decimals as the ticks need, and an x value with a point label
        /// shows the label.
        formatter: ?Formatter = null,
    };

    const LegendField = struct {
        title: []const u8,
        color: Vapor.Types.Color,
        background: Vapor.Types.Color,
    };

    pub const LegendConfig = struct {
        position: Position = .top_right,
        fields: []const LegendField = &.{},
        /// .row runs along the top or bottom of the chart, .column down
        /// its side.
        direction: Vapor.Types.Direction = .row,
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
            .references = std.array_list.Managed(Reference).init(allocator),
            .pie_slices = std.array_list.Managed(PieSliceHit).init(allocator),
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
        self.references.deinit();
        self.pie_slices.deinit();
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

    /// Adds a reference line or band, drawn on every build after this.
    pub fn reference(self: *Chart, ref: Reference) !void {
        try self.references.append(ref);
    }

    /// Whether the legend's `index`th item is shown.
    pub fn isShown(self: *const Chart, index: usize) bool {
        return index >= 64 or !self.hidden.isSet(index);
    }

    /// Shows or hides the legend's `index`th item, as clicking it does, and
    /// redraws the chart with the axes fitted to what is left.
    pub fn setShown(self: *Chart, index: usize, shown: bool) void {
        if (index >= 64) return;
        self.hidden.setValue(index, !shown);
        self.hideTooltip();
        self.build() catch {};
        Vapor.cycle();
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
        self.is_empty = true;

        for (self.series.items) |s| {
            if (s.type == .bar) has_bars = true;
            if (s.type == .stacked_bar) has_stacked_bars = true;
            if (s.type == .pie or s.type == .donut) has_pie = true;
            if (s.data.len > 0) self.is_empty = false;
        }
        self.has_data = false;
        self.pie_slices.clearRetainingCapacity();

        self.total_item_count = self.series.items.len;
        if (self.legend_config) |cfg| {
            self.total_item_count += cfg.fields.len;
        }
        try self.buildLegendItems();

        // SVG Header, and a group around everything: the page keeps only
        // what is inside the <svg>. Its id lets the legend fade the other
        // items while one is pointed at; `enter` fades the chart in, once.
        try svg.openSvg(self.config.width, self.config.height);
        var svg_id_buf: [40]u8 = undefined;
        try svg.print(
            \\<g id="{s}" class="{s}">
            \\
        , .{
            self.svgId(&svg_id_buf),
            if (self.config.animate and self.entering) "chart enter" else "chart",
        });

        // Styles. The text and grid take the theme's colours. Only elements
        // with no colour of their own are coloured here: a stylesheet rule
        // beats an element's fill or stroke attribute.
        var text_buf: [64]u8 = undefined;
        var line_buf: [64]u8 = undefined;
        var page_buf: [64]u8 = undefined;
        const text = cssColor(&text_buf, .palette(.text_color));
        const line = cssColor(&line_buf, .palette(.border_color_light));
        const page = cssColor(&page_buf, .palette(.background));
        try svg.print(
            \\<style>.axis-label {{ fill: {s}; fill-opacity: 0.8; }}
            \\.grid {{ stroke: {s}; }}
            \\.tick-label {{ fill: {s}; fill-opacity: 0.6; }}
            \\.pie-label {{ fill: {s}; }}
            \\.pie-label-line {{ stroke: {s}; stroke-opacity: 0.4; }}
            \\.ref-label {{ fill: {s}; }}
            \\.series-dot {{ stroke: {s}; }}</style>
            \\
        , .{ text, line, text, text, text, text, page });
        try svg.style(
            \\.axis { stroke-width: 1; }
            \\.axis-label { font-size: 12px; }
            \\.grid { stroke-width: 1; }
            \\.tick-label { font-size: 10px; user-select: none; }
            \\.series-line { fill: none; stroke-linecap: round; stroke-linejoin: round; transition: all 200ms ease-in-out; }
            \\.series-area { stroke: none; }
            \\.series-dot { stroke-width: 1.5; transition: all 200ms ease-in-out; }
            \\.series-bar { transition: all 200ms ease-in-out; }
            \\.stacked-bar { transition: all 200ms ease-in-out; }
            \\.shadow-bar { transition: all 200ms ease-in-out; }
            \\.pie-slice { transition: all 200ms ease-in-out; }
            \\.pie-slice:hover { opacity: 0.8; transform-origin: center; }
            \\.pie-label { font-size: 11px; pointer-events: none; }
            \\.pie-label-line { stroke-width: 1; fill: none; }
            \\.chart-item { transition: opacity 150ms ease; }
            \\.ref-line { stroke-width: 1; }
            \\.ref-label { font-size: 10px; user-select: none; }
            \\@keyframes chart-fade { from { opacity: 0; } }
            \\.chart.enter { animation: chart-fade 350ms ease-out both; }
            \\@media (prefers-reduced-motion: reduce) { .chart.enter { animation: none; } }
        );
        // Pointing at a legend item fades the others.
        for (0..self.legend_items.len) |k| {
            try svg.print(
                \\<style>g[data-focus="{d}"] .chart-item:not(.item-{d}) {{ opacity: 0.15; }}</style>
                \\
            , .{ k, k });
        }

        // Background
        if (self.config.background) |bg| {
            try svg.rect(0, 0, @floatFromInt(self.config.width), @floatFromInt(self.config.height), .{
                .id = "chart-background",
                .fill = bg,
            });
        }

        if (self.is_empty) {
            // Nothing to plot: render() says so over the empty frame.
        } else if (has_pie) {
            // Render pie charts centered in the chart
            for (self.series.items, 0..) |s, i| {
                if (s.type == .pie or s.type == .donut) {
                    try self.renderPie(&svg, s, i, chart_width, chart_height);
                }
            }
        } else {
            const x_config = if (self.x_axis_config) |c| c.scale else ScaleConfig{};
            const y_config = if (self.y_axis_config) |c| c.scale else ScaleConfig{};

            // Zoomed to an x range, the y axis fits the points inside it.
            const x_window: ?[2]f64 = switch (x_config.domain) {
                .manual => |d| if (y_config.domain == .manual) null else d,
                else => null,
            };

            // Calculate scales from the shown series' data (only for non-pie charts)
            var all_x = std.array_list.Managed(f64).init(self.allocator);
            defer all_x.deinit();
            var all_y = std.array_list.Managed(f64).init(self.allocator);
            defer all_y.deinit();

            for (self.series.items, 0..) |s, series_index| {
                if (s.type != .stacked_bar and !self.isShown(series_index)) continue;
                for (s.data) |p| {
                    try all_x.append(p.x);
                    if (x_window) |w| {
                        if (p.x < w[0] or p.x > w[1]) continue;
                    }
                    self.has_data = true;

                    if (s.type == .stacked_bar) {
                        // For stacked bars, we need the total height
                        if (p.stack) |stack| {
                            var pos_sum: f64 = 0;
                            var neg_sum: f64 = 0;
                            for (stack, 0..) |seg, stack_index| {
                                if (!self.isShown(stack_index)) continue;
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
            self.x_step = xStep(self.series.items);

            // ============ X SCALE ============
            const x_scale: Scale = blk: {
                var domain: [2]f64 = switch (x_config.domain) {
                    .auto => .{ findMin(all_x.items), findMax(all_x.items) },
                    .auto_zero => .{ @min(0, findMin(all_x.items)), findMax(all_x.items) },
                    .manual => |d| d,
                };

                // Bars stand on their x value, so the axis runs half a bar
                // past the first and last.
                if ((has_bars or has_stacked_bars) and x_config.domain != .manual) {
                    domain[0] -= self.x_step * 0.5;
                    domain[1] += self.x_step * 0.5;
                }

                switch (x_config.type) {
                    .linear => {
                        var s = LinearScale.init(domain, .{ 0, chart_width });
                        if (!(has_bars or has_stacked_bars) and x_config.domain != .manual) {
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
            const y_scale: Scale = blk: {
                var domain: [2]f64 = switch (y_config.domain) {
                    .auto => .{ findMin(all_y.items), findMax(all_y.items) },
                    .auto_zero => .{ @min(0, findMin(all_y.items)), findMax(all_y.items) },
                    .manual => |d| d,
                };
                if (domain[0] == domain[1]) {
                    domain[0] -= 1;
                    domain[1] += 1;
                }

                // For bar charts, always include 0
                if (has_bars or has_stacked_bars) {
                    domain[0] = @min(0, domain[0]);
                    domain[1] = @max(0, domain[1]);
                }

                switch (y_config.type) {
                    .linear => {
                        var s = LinearScale.init(domain, .{ chart_height, 0 });
                        if (y_config.domain != .manual) {
                            if (y_config.nice) s = s.niced();
                            if (y_config.padding >= 0) s = s.padded(y_config.padding);
                        }
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

            // A set domain (a zoom, or one passed in) can leave data outside
            // the axes, so the series are clipped to the plot area. An auto
            // domain always fits the data; clipping it would halve the dots
            // that sit on an edge.
            const clip = x_config.domain == .manual or y_config.domain == .manual;
            if (clip) {
                try svg.print(
                    \\<defs><clipPath id="opaque-chart-clip-{x}"><rect x="0" y="0" width="{d}" height="{d}"/></clipPath></defs>
                    \\<g clip-path="url(#opaque-chart-clip-{x})">
                    \\
                , .{ @intFromPtr(self), chart_width, chart_height, @intFromPtr(self) });
            }

            // Bands lie under the data, lines over it.
            try self.renderReferences(&svg, x_scale, y_scale, chart_width, chart_height, true);

            // Render each series
            for (self.series.items, 0..) |s, i| {
                if (s.type != .stacked_bar and !self.isShown(i)) continue;
                const series_color = s.options.color orelse Vapor.Types.Color.hex(self.config.palette.get(i));
                try self.renderSeries(&svg, s, i, x_scale, y_scale, series_color);
            }

            try self.renderReferences(&svg, x_scale, y_scale, chart_width, chart_height, false);

            if (clip) try svg.closeGroup();

            // Axes
            if (self.x_axis_config) |_| {
                try self.renderAxes(&svg, x_scale, y_scale, chart_width, chart_height, self.x_axis_config.?, self.y_axis_config orelse AxisConfig{});
            }

            try svg.closeGroup();

            self.x_scale = x_scale;
            self.y_scale = y_scale;
        }

        try svg.closeGroup();
        try svg.closeSvg();

        if (self.tooltip) |*tooltip| {
            var total_items: usize = 0;
            total_items += self.series.items.len;
            if (self.legend_config) |cfg| {
                total_items += cfg.fields.len;
            }
            tooltip.value = self.allocator.alloc(TooltipLegend, total_items) catch unreachable;
            for (self.series.items, 0..) |s, i| {
                tooltip.value[i] = .{
                    .title = s.name,
                    .color = s.options.color orelse Vapor.Types.Color.hex(self.config.palette.get(i)),
                    .background = s.options.color orelse Vapor.Types.Color.hex(self.config.palette.get(i)),
                };
            }

            if (self.legend_config) |legend_config| {
                for (legend_config.fields, self.series.items.len..) |f, i| {
                    tooltip.value[i] = .{ .title = f.title, .color = f.color, .background = f.color };
                }
            }
            tooltip.header = "";
            tooltip.total_text = "";
        }

        self.current_chart_svg = try svg.toOwnedSlice();
    }

    /// The id of the group around the chart's drawing, unique to this chart.
    fn svgId(self: *const Chart, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "opaque-chart-{x}", .{@intFromPtr(self)}) catch "opaque-chart";
    }

    /// The smallest gap between neighbouring x values in any series.
    fn xStep(series: []const Series) f64 {
        var step: f64 = std.math.inf(f64);
        for (series) |s| {
            if (s.data.len < 2) continue;
            for (s.data[0 .. s.data.len - 1], s.data[1..]) |a, b| {
                const gap = @abs(b.x - a.x);
                if (gap > 0) step = @min(step, gap);
            }
        }
        return if (std.math.isInf(step)) 1 else step;
    }

    /// How wide one x step is on the screen: the room a bar group has.
    fn slotWidth(self: *const Chart, x_scale: Scale) f64 {
        const x0 = x_scale.domainMin();
        return @abs(x_scale.scale(x0 + self.x_step) - x_scale.scale(x0));
    }

    fn renderReferences(self: *Chart, svg: *Svg, x_scale: Scale, y_scale: Scale, width: f64, height: f64, bands: bool) !void {
        for (self.references.items, 0..) |ref, i| {
            if ((ref.to != null) != bands) continue;
            const scale = if (ref.axis == .y) y_scale else x_scale;
            const lo = @min(scale.domainMin(), scale.domainMax());
            const hi = @max(scale.domainMin(), scale.domainMax());
            const color = ref.color orelse Vapor.Types.Color.palette(.text_color);

            var id_buf: [48]u8 = undefined;
            const id = try std.fmt.bufPrint(&id_buf, "chart-ref-{d}", .{i});

            var at: f64 = undefined;
            if (ref.to) |to| {
                const a = @max(lo, @min(ref.value, to));
                const b = @min(hi, @max(ref.value, to));
                if (a >= b) continue;
                const p = scale.scale(a);
                const q = scale.scale(b);
                if (ref.axis == .y) {
                    try svg.rect(0, @min(p, q), width, @abs(p - q), .{ .id = id, .class = "ref-band", .fill = color, .opacity = 0.08 });
                    at = @min(p, q);
                } else {
                    try svg.rect(@min(p, q), 0, @abs(p - q), height, .{ .id = id, .class = "ref-band", .fill = color, .opacity = 0.08 });
                    at = @min(p, q);
                }
            } else {
                if (ref.value < lo or ref.value > hi) continue;
                at = scale.scale(ref.value);
                const opts: Svg.LineOpts = .{ .id = id, .class = "ref-line", .stroke = color, .dash = if (ref.dashed) "4 4" else null };
                if (ref.axis == .y) {
                    try svg.line(0, at, width, at, opts);
                } else {
                    try svg.line(at, 0, at, height, opts);
                }
            }

            if (ref.label) |label| {
                var label_id_buf: [48]u8 = undefined;
                const label_id = try std.fmt.bufPrint(&label_id_buf, "chart-ref-{d}-label", .{i});
                if (ref.axis == .y) {
                    try svg.text(width - 4, at - 4, label, .{ .id = label_id, .class = "ref-label", .anchor = .end, .fill = ref.color });
                } else {
                    try svg.text(at + 4, 10, label, .{ .id = label_id, .class = "ref-label", .anchor = .start, .fill = ref.color });
                }
            }
        }
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
    /// A pie slice's colour: its first stack segment's, else the palette's.
    fn sliceColor(self: *Chart, p: Point, point_index: usize) Vapor.Types.Color {
        if (p.stack) |stack| {
            if (stack.len > 0) {
                if (stack[0].color) |color| return color;
            }
        }
        return Vapor.Types.Color.hex(self.config.palette.get(point_index));
    }

    /// An element's classes: its own, and the legend item it belongs to,
    /// which pointing at that item leaves bright.
    fn itemClass(buf: []u8, class: []const u8, item: usize) []const u8 {
        return std.fmt.bufPrint(buf, "{s} chart-item item-{d}", .{ class, item }) catch class;
    }

    fn renderPie(self: *Chart, svg: *Svg, s: Series, series_index: usize, chart_width: f64, chart_height: f64) !void {
        if (s.data.len == 0) return;

        const m = self.config.margin;

        // Calculate center and radius
        const center_x = @as(f64, @floatFromInt(m.left)) + chart_width / 2.0;
        const center_y = @as(f64, @floatFromInt(m.top)) + chart_height / 2.0;
        const max_radius = @min(chart_width, chart_height) / 2.0 * 0.8; // 80% of available space

        // Determine inner radius: none for a pie unless asked, half for a
        // donut unless set.
        const inner_radius_ratio = if (s.type == .donut and s.options.inner_radius_ratio <= 0)
            0.5
        else
            s.options.inner_radius_ratio;

        const outer_radius = max_radius;
        const inner_radius = outer_radius * inner_radius_ratio;

        // Calculate total value for percentage calculations: the shown slices'.
        var total: f64 = 0;
        for (s.data, 0..) |p, point_index| {
            if (self.isShown(point_index)) total += @abs(p.y);
        }

        if (total == 0) return;
        self.has_data = true;

        // Start angle (default: top of circle, -π/2)
        var current_angle = s.options.start_angle;
        const pad_angle = s.options.pad_angle;

        // Create group for pie chart centered
        var transform_buf: [64]u8 = undefined;
        const transform = try std.fmt.bufPrint(&transform_buf, "translate({d:.2},{d:.2})", .{ center_x, center_y });
        try svg.openGroup("pie-chart", transform);

        // Render each slice
        for (s.data, 0..) |p, point_index| {
            if (!self.isShown(point_index)) continue;
            const value = @abs(p.y);
            const slice_angle = (value / total) * 2.0 * std.math.pi - pad_angle;

            if (slice_angle <= 0) continue;

            const start_angle = current_angle + pad_angle / 2.0;
            const end_angle = start_angle + slice_angle;

            const slice_color = self.sliceColor(p, point_index);

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

            try self.pie_slices.append(.{
                .index = point_index,
                .series_index = series_index,
                .start = start_angle,
                .end = end_angle,
                .cx = center_x,
                .cy = center_y,
                .inner = inner_radius,
                .outer = outer_radius,
                .percent = value / total * 100.0,
            });

            var class_buf: [64]u8 = undefined;
            try svg.path(path_d, .{
                .id = id,
                .class = itemClass(&class_buf, "pie-slice", point_index),
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

                var class_buf: [64]u8 = undefined;
                try svg.text(label_x, label_y, label_text, .{
                    .id = id,
                    .class = itemClass(&class_buf, "pie-label", point_index),
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
                var line_class_buf: [64]u8 = undefined;
                try svg.line(line_start_x, line_start_y, line_end_x, line_end_y, .{
                    .id = line_id,
                    .class = itemClass(&line_class_buf, "pie-label-line", point_index),
                });

                // Draw label
                var id_buf: [64]u8 = undefined;
                const id = try std.fmt.bufPrint(&id_buf, "chart-pie-label-{d}", .{point_index});

                // Determine text anchor based on position
                const anchor: Svg.TextAnchor = if (mid_angle > std.math.pi / 2.0 and mid_angle < 3.0 * std.math.pi / 2.0)
                    .end
                else
                    .start;

                var class_buf: [64]u8 = undefined;
                try svg.text(label_x, label_y, label_text, .{
                    .id = id,
                    .class = itemClass(&class_buf, "pie-label", point_index),
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

        const n_series: f64 = @floatFromInt(stacked_series_count);

        // Calculate bar dimensions: a group fills most of one x step.
        const group_width = self.slotWidth(x_scale) * 0.85;
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

                var shadow_class_buf: [64]u8 = undefined;
                try svg.rect(bar_x, max_y, actual_bar_width, shadow_height, .{
                    .id = shadow_id,
                    .fill = shadow_color,
                    .opacity = s.options.shadow_opacity,
                    .rx = s.options.bar_radius,
                    .class = itemClass(&shadow_class_buf, "shadow-bar", series_index),
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
                    if (!self.isShown(stack_idx)) continue;
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

                    var class_buf: [64]u8 = undefined;
                    try svg.rect(bar_x, seg_y, actual_bar_width, seg_height, .{
                        .id = id,
                        .fill = seg_color,
                        .rx = s.options.bar_radius,
                        .class = itemClass(&class_buf, "stacked-bar", stack_idx),
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

                if (!self.isShown(0)) continue;
                var class_buf: [64]u8 = undefined;
                try svg.rect(bar_x, @min(y, baseline_y), actual_bar_width, height, .{
                    .id = id,
                    .fill = default_color,
                    .rx = s.options.bar_radius,
                    .class = itemClass(&class_buf, "stacked-bar", 0),
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
        var class_buf: [64]u8 = undefined;
        try svg.path(path_d, .{
            .id = path_id,
            .class = itemClass(&class_buf, "series-line", series_index),
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

                var dot_class_buf: [64]u8 = undefined;
                try svg.circle(pt[0], pt[1], @floatFromInt(s.options.dot_radius), .{
                    .id = id,
                    .class = itemClass(&dot_class_buf, "series-dot", series_index),
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
        var class_buf: [64]u8 = undefined;
        try svg.path(path_d, .{
            .id = path_id,
            .class = itemClass(&class_buf, "series-area", series_index),
            .fill = series_color,
            .fill_opacity = s.options.fill_opacity,
        });

        try self.rendered_elements.append(.{
            .id = .{ .series_name = s.name, .series_index = @intCast(series_index), .element_type = .area_path },
            .attrs = .{ .path = .{ .d = path_d, .fill = series_color } },
        });

        try self.renderLine(svg, s, series_index, x_scale, y_scale, series_color, smooth);
    }

    fn renderBars(self: *Chart, svg: *Svg, s: Series, series_index: usize, x_scale: Scale, y_scale: Scale, series_color: Vapor.Types.Color) !void {
        if (s.data.len == 0) return;

        // A group has a slot per shown bar series.
        var bar_series_count: usize = 0;
        var bar_series_index: usize = 0;
        for (self.series.items, 0..) |item, i| {
            if (item.type == .bar and self.isShown(i)) {
                if (i == series_index) bar_series_index = bar_series_count;
                bar_series_count += 1;
            }
        }

        const n_series: f64 = @floatFromInt(bar_series_count);

        const group_width = self.slotWidth(x_scale) * 0.9;
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

                var shadow_class_buf: [64]u8 = undefined;
                try svg.rect(x, max_y, actual_bar_width, shadow_height, .{
                    .id = shadow_id,
                    .fill = shadow_color,
                    .opacity = s.options.shadow_opacity,
                    .rx = s.options.bar_radius,
                    .class = itemClass(&shadow_class_buf, "shadow-bar", series_index),
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
            var class_buf: [64]u8 = undefined;
            try svg.rect(x, @min(y, baseline), actual_bar_width, height, .{
                .id = id,
                .fill = series_color,
                .rx = s.options.bar_radius,
                .class = itemClass(&class_buf, "series-bar", series_index),
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

            var class_buf: [64]u8 = undefined;
            try svg.circle(x, y, @floatFromInt(s.options.dot_radius), .{
                .id = id,
                .class = itemClass(&class_buf, "series-dot", series_index),
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
            const x_step = tickStep(x_ticks);

            for (x_ticks) |tick| {
                const x = x_scale.scale(tick);
                var id_buf: [64]u8 = undefined;
                const id = try std.fmt.bufPrint(&id_buf, "chart-axis-x-{d}", .{tick});
                try svg.line(x, height, x, height + 5, .{ .class = "axis", .id = id });

                var label_buf: [64]u8 = undefined;
                const label = self.tickLabel(&label_buf, x_axis_config, tick, x_step, true);
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
            const y_step = tickStep(y_ticks);

            for (y_ticks) |tick| {
                const y = y_scale.scale(tick);
                var id_buf: [64]u8 = undefined;
                const id = try std.fmt.bufPrint(&id_buf, "chart-axis-y-{d}", .{tick});
                try svg.line(-5, y, 0, y, .{ .class = "axis", .id = id });

                var label_buf: [64]u8 = undefined;
                const label = self.tickLabel(&label_buf, y_axis_config, tick, y_step, false);
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

    /// A tick's label: the axis's formatter's; on the x axis, the label of
    /// a point at that x; else the number with the decimals the step needs.
    fn tickLabel(self: *Chart, buf: []u8, axis: AxisConfig, value: f64, step: f64, is_x: bool) []const u8 {
        if (axis.formatter) |format| return format(value, buf);
        if (is_x) {
            if (self.pointLabelAt(value)) |label| return label;
        }
        return formatNumber(buf, value, decimalsFor(step));
    }

    /// The label of a point at `x`, in any series but a pie.
    fn pointLabelAt(self: *Chart, x: f64) ?[]const u8 {
        for (self.series.items) |s| {
            if (s.type == .pie or s.type == .donut) continue;
            for (s.data) |p| {
                if (p.label != null and @abs(p.x - x) < 1e-9) return p.label;
            }
        }
        return null;
    }

    /// A value as the tooltip shows it: through the y axis's formatter, else
    /// with up to two decimals, and none when it is whole.
    fn valueText(self: *Chart, buf: []u8, value: f64) []const u8 {
        if (self.y_axis_config) |axis| {
            if (axis.formatter) |format| return format(value, buf);
        }
        const rounded = @round(value * 100) / 100;
        if (rounded == @trunc(rounded)) return formatNumber(buf, rounded, 0);
        if (rounded * 10 == @trunc(rounded * 10)) return formatNumber(buf, rounded, 1);
        return formatNumber(buf, rounded, 2);
    }

    const LegendItem = struct {
        title: []const u8,
        color: Vapor.Types.Color,
        id: ElementId,
        /// The title was made here (a slice with no label) and is freed with the items.
        owned: bool = false,
    };

    /// The legend's items, kept for render: one per series, except a pie
    /// or donut, which gets one per slice under the slice's label; then the
    /// custom fields. An item's place in the list is what `isShown` and
    /// `setShown` take.
    fn buildLegendItems(self: *Chart) !void {
        for (self.legend_items) |item| if (item.owned) self.allocator.free(item.title);
        self.allocator.free(self.legend_items);
        self.legend_items = &.{};

        var items = std.array_list.Managed(LegendItem).init(self.allocator);
        errdefer items.deinit();
        for (self.series.items, 0..) |s, i| {
            if (s.type == .pie or s.type == .donut) {
                for (s.data, 0..) |p, point_index| {
                    const title = p.label orelse try std.fmt.allocPrint(self.allocator, "{s} {d}", .{ s.name, point_index + 1 });
                    try items.append(.{
                        .title = title,
                        .owned = p.label == null,
                        .color = self.sliceColor(p, point_index),
                        .id = .{ .series_name = s.name, .series_index = @intCast(i), .point_index = @intCast(point_index), .element_type = .legend },
                    });
                }
            } else {
                try items.append(.{
                    .title = s.name,
                    .color = s.options.color orelse Vapor.Types.Color.hex(self.config.palette.get(i)),
                    .id = .{ .series_name = s.name, .series_index = @intCast(i), .element_type = .legend },
                });
            }
        }
        if (self.legend_config) |cfg| {
            for (cfg.fields, self.series.items.len..) |f, i| {
                try items.append(.{
                    .title = f.title,
                    .color = f.color,
                    .id = .{ .series_name = "", .series_index = @intCast(i), .element_type = .legend },
                });
            }
        }
        self.legend_items = try items.toOwnedSlice();
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
        /// A dot's radius; it grows while its point is hovered.
        radius: ?f64 = null,
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
                    .radius = @floatFromInt(s.options.dot_radius),
                };
            },
            .pie, .donut => .{
                .id = std.fmt.bufPrint(buf, "chart-{d}-{d}-pie_slice", .{ pt.series_index, pt.point_index }) catch return null,
                .attr = "fill",
            },
        };
    }

    /// The pointer's place in the chart's box.
    fn pointerAt(self: *Chart, event: *Vapor.Event) [2]f32 {
        return .{ event.clientX() - self.bounds.offset_x, event.clientY() - self.bounds.offset_y };
    }

    /// Whether a point of the chart's box is inside the axes.
    fn inPlot(self: *Chart, x: f32, y: f32) bool {
        return x >= self.bounds.x and x <= self.bounds.x + self.bounds.width and
            y >= self.bounds.y and y <= self.bounds.y + self.bounds.height;
    }

    fn hasStackedBars(self: *Chart) bool {
        for (self.series.items) |s| {
            if (s.type == .stacked_bar) return true;
        }
        return false;
    }

    /// Called as the pointer comes onto the chart.
    pub fn showTooltip(self: *Chart, event: *Vapor.Event) void {
        const rect = self.container.getBoundingClientRect() orelse return;
        self.bounds.offset_x = rect.left;
        self.bounds.offset_y = rect.top;
        self.updateTooltip(event);
    }

    /// Follows the pointer. Over the plot the tooltip shows every series'
    /// value at the nearest x, or on a pie the slice under the pointer;
    /// anywhere else, the margins and axis labels included, it hides.
    pub fn updateTooltip(self: *Chart, event: *Vapor.Event) void {
        if (self.tooltip == null or self.is_empty) return;
        const at = self.pointerAt(event);
        if (self.pie_slices.items.len > 0) return self.hoverPie(at[0], at[1]);
        if (!self.inPlot(at[0], at[1]) and self.selection == null) return self.hideTooltip();
        self.hoverX(at[0], at[1]);
    }

    fn hoverX(self: *Chart, x: f32, y: f32) void {
        const tooltip = &self.tooltip.?;
        const result = self.findNearestX(x, y) orelse return self.hideTooltip();
        defer self.allocator.free(result.points);

        if (tooltip.hide or self.old_x != result.screen_x) {
            self.clearHighlights();
            for (tooltip.value) |*row| {
                row.value = null;
                row.text = "";
            }
            var total: f64 = 0;
            for (result.points) |pt| {
                if (pt.row >= tooltip.value.len) continue;
                const row = &tooltip.value[pt.row];
                row.value = pt.data_y;
                row.color = pt.series_color;
                row.text = self.valueText(&row.text_buf, pt.data_y);
                total += pt.data_y;
                self.highlight(pt, true);
            }
            self.old_points = self.allocator.dupe(HoveredPoint, result.points) catch null;
            tooltip.header = self.headerFor(&tooltip.header_buf, result.points[0]);
            const show_total = self.config.tooltip_total orelse self.hasStackedBars();
            tooltip.total_text = if (show_total) self.valueText(&tooltip.total_buf, total) else "";
            if (self.selection == null) Vapor.cycle();
        }
        self.old_x = result.screen_x;
        // Put it in place first, then show it, so it fades in there.
        const appearing = tooltip.hide;
        if (!appearing) self.letTooltipSlide();
        self.placeTooltip(result.screen_x, y);
        if (self.config.show_line) {
            tooltip.line_x = result.screen_x - 0.5;
            _ = tooltip.line_binded.translate3d(.{ .x = tooltip.line_x });
        }
        if (appearing) self.showTooltipBox();
    }

    fn hoverPie(self: *Chart, x: f32, y: f32) void {
        const tooltip = &self.tooltip.?;
        const hit = self.sliceAt(x, y) orelse return self.hideTooltip();

        if (tooltip.hide or self.hovered_slice != hit.index) {
            const s = self.series.items[hit.series_index];
            const p = s.data[hit.index];
            for (tooltip.value) |*row| {
                row.value = null;
                row.text = "";
            }
            // One row: the slice, its value and its share of the pie.
            if (tooltip.value.len > 0) {
                const row = &tooltip.value[0];
                var value_buf: [48]u8 = undefined;
                const value = self.valueText(&value_buf, p.y);
                row.title = p.label orelse s.name;
                row.color = self.sliceColor(p, hit.index);
                row.value = p.y;
                row.text = std.fmt.bufPrint(&row.text_buf, "{s} ({d:.0}%)", .{ value, hit.percent }) catch value;
            }
            tooltip.header = std.fmt.bufPrint(&tooltip.header_buf, "{s}", .{s.name}) catch "";
            tooltip.total_text = "";
            self.hovered_slice = hit.index;
            Vapor.cycle();
        }
        const appearing = tooltip.hide;
        if (!appearing) self.letTooltipSlide();
        self.placeTooltip(x, y);
        if (appearing) self.showTooltipBox();
    }

    /// The pie slice under a point of the chart's box.
    fn sliceAt(self: *Chart, x: f32, y: f32) ?PieSliceHit {
        for (self.pie_slices.items) |hit| {
            const dx = @as(f64, x) - hit.cx;
            const dy = @as(f64, y) - hit.cy;
            const r = @sqrt(dx * dx + dy * dy);
            if (r < hit.inner or r > hit.outer) continue;
            var angle = std.math.atan2(dy, dx);
            while (angle < hit.start) angle += 2 * std.math.pi;
            while (angle >= hit.start + 2 * std.math.pi) angle -= 2 * std.math.pi;
            if (angle <= hit.end) return hit;
        }
        return null;
    }

    /// The tooltip's first line: the x axis's formatter's text for the x
    /// value, else the point's label, else the axis's name and the value.
    fn headerFor(self: *Chart, buf: []u8, pt: HoveredPoint) []const u8 {
        const axis = self.x_axis_config orelse AxisConfig{};
        if (axis.formatter) |format| return format(pt.data_x, buf);
        if (self.pointLabelAt(pt.data_x)) |label| return label;
        var num_buf: [48]u8 = undefined;
        const rounded = @round(pt.data_x * 100) / 100;
        const num = formatNumber(&num_buf, rounded, if (rounded == @trunc(rounded)) 0 else 2);
        if (axis.label) |name| return std.fmt.bufPrint(buf, "{s} {s}", .{ name, num }) catch "";
        return std.fmt.bufPrint(buf, "{s}", .{num}) catch "";
    }

    const TipState = enum { hidden, shown, sliding };

    /// The tooltip's (and its line's) fade and slide, as CSS. Hidden, it
    /// fades out and moves without a slide; just shown, it fades in where it
    /// was put; shown a moment, it slides from point to point.
    fn tipStyle(state: TipState) struct { opacity: []const u8, visibility: []const u8, transition: []const u8 } {
        return switch (state) {
            .hidden => .{ .opacity = "0", .visibility = "hidden", .transition = "opacity 120ms ease, visibility 0s linear 120ms" },
            .shown => .{ .opacity = "1", .visibility = "visible", .transition = "opacity 120ms ease" },
            .sliding => .{ .opacity = "1", .visibility = "visible", .transition = "opacity 120ms ease, transform 80ms ease-out" },
        };
    }

    fn tipState(tooltip: *const Tooltip) TipState {
        return if (tooltip.hide) .hidden else if (tooltip.sliding) .sliding else .shown;
    }

    fn applyTipState(self: *Chart, state: TipState) void {
        const tooltip = &self.tooltip.?;
        const st = tipStyle(state);
        tooltip.binded.mutateStyleString("opacity", st.opacity);
        tooltip.binded.mutateStyleString("visibility", st.visibility);
        tooltip.binded.mutateStyleString("transition", st.transition);
        if (self.config.show_line) {
            tooltip.line_binded.mutateStyleString("opacity", st.opacity);
            tooltip.line_binded.mutateStyleString("visibility", st.visibility);
            tooltip.line_binded.mutateStyleString("transition", st.transition);
        }
    }

    /// Fades the tooltip in where placeTooltip put it.
    fn showTooltipBox(self: *Chart) void {
        const tooltip = &self.tooltip.?;
        if (!tooltip.hide) return;
        tooltip.hide = false;
        self.applyTipState(.shown);
    }

    /// A tooltip already showing slides from point to point.
    fn letTooltipSlide(self: *Chart) void {
        const tooltip = &self.tooltip.?;
        if (tooltip.hide or tooltip.sliding) return;
        tooltip.sliding = true;
        self.applyTipState(.sliding);
    }

    /// Sets the tooltip beside `anchor_x`, on whichever side has room, and
    /// level with the pointer, inside the chart.
    fn placeTooltip(self: *Chart, anchor_x: f32, pointer_y: f32) void {
        const tooltip = &self.tooltip.?;
        var w: f32 = tooltip.width;
        var h: f32 = 64;
        if (tooltip.binded.getBoundingClientRect()) |r| {
            if (r.width > 0) {
                w = r.width;
                h = r.height;
            }
        }
        const chart_w: f32 = @floatFromInt(self.config.width);
        const chart_h: f32 = @floatFromInt(self.config.height);
        var left = anchor_x + 12;
        if (left + w > chart_w) left = anchor_x - 12 - w;
        left = @max(0, left);
        const top = std.math.clamp(pointer_y - h / 2, 0, @max(0, chart_h - h));
        tooltip.left = left;
        tooltip.top = top;
        _ = tooltip.binded.translate3d(.{ .x = left, .y = top });
    }

    fn highlight(self: *Chart, pt: HoveredPoint, on: bool) void {
        var buf: [128]u8 = undefined;
        const t = self.hoverTargetFor(pt, &buf) orelse return;
        self.platform.browser.setAttribute(t.id, t.attr, Svg.convertColor(if (on) pt.hovered_color else pt.series_color));
        if (t.radius) |r| {
            var r_buf: [24]u8 = undefined;
            const value = std.fmt.bufPrint(&r_buf, "{d}", .{if (on) r + 2 else r}) catch return;
            self.platform.browser.setAttribute(t.id, "r", value);
        }
    }

    fn clearHighlights(self: *Chart) void {
        const old_pts = self.old_points orelse return;
        for (old_pts) |old_pt| self.highlight(old_pt, false);
        self.allocator.free(old_pts);
        self.old_points = null;
    }

    fn hideTooltip(self: *Chart) void {
        if (self.tooltip) |*tooltip| {
            if (!tooltip.hide) {
                tooltip.hide = true;
                tooltip.sliding = false;
                self.applyTipState(.hidden);
            }
        }
        self.hovered_slice = null;
        self.clearHighlights();
    }

    fn pointerLeft(self: *Chart, _: *Vapor.Event) void {
        self.hideTooltip();
    }

    pub const HoveredPoint = struct {
        series_index: usize,
        point_index: usize,
        stack_index: ?usize = null,
        /// The tooltip row it fills: its series', or its stack segment's.
        row: usize,
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

    /// The shown points at the x value nearest `mouse_x`, among those on
    /// the axes (a zoom leaves some off them).
    pub fn findNearestX(self: *Chart, mouse_x: f64, _: f64) ?HoverResult {
        const x_scale = self.x_scale orelse return null;
        const y_scale = self.y_scale orelse return null;

        const m = self.config.margin;
        const left: f32 = @floatFromInt(m.left);
        const top: f32 = @floatFromInt(m.top);

        const data_x = x_scale.invert(mouse_x - left);
        const lo = @min(x_scale.domainMin(), x_scale.domainMax());
        const hi = @max(x_scale.domainMin(), x_scale.domainMax());

        var closest_x: ?f64 = null;
        var closest_dist: f64 = std.math.floatMax(f64);
        for (self.series.items, 0..) |s, series_idx| {
            if (s.type != .stacked_bar and !self.isShown(series_idx)) continue;
            for (s.data) |p| {
                if (p.x < lo or p.x > hi) continue;
                const dist = @abs(p.x - data_x);
                if (dist < closest_dist) {
                    closest_dist = dist;
                    closest_x = p.x;
                }
            }
        }
        const target_x = closest_x orelse return null;

        var points = std.array_list.Managed(HoveredPoint).init(self.allocator);
        defer points.deinit();

        for (self.series.items, 0..) |s, series_idx| {
            if (s.type != .stacked_bar and !self.isShown(series_idx)) continue;
            for (s.data, 0..) |p, point_idx| {
                if (@abs(p.x - target_x) >= 0.0001) continue;
                const screen_x: f32 = @as(f32, @floatCast(x_scale.scale(p.x))) + left;
                const color = s.options.color orelse Vapor.Types.Color.hex(self.config.palette.get(series_idx));

                if (p.stack) |stack| {
                    for (stack, 0..) |seg, stack_index| {
                        if (!self.isShown(stack_index)) continue;
                        const seg_color = seg.color orelse color;
                        points.append(.{
                            .series_index = series_idx,
                            .point_index = point_idx,
                            .stack_index = stack_index,
                            .row = stack_index,
                            .data_x = p.x,
                            .data_y = seg.value,
                            .screen_x = screen_x,
                            .screen_y = @as(f32, @floatCast(y_scale.scale(seg.value))) + top,
                            .series_name = s.name,
                            .series_color = seg_color,
                            .hovered_color = s.options.hovered_color orelse seg_color,
                        }) catch continue;
                    }
                } else {
                    points.append(.{
                        .series_index = series_idx,
                        .point_index = point_idx,
                        .row = series_idx,
                        .data_x = p.x,
                        .data_y = p.y,
                        .screen_x = screen_x,
                        .screen_y = @as(f32, @floatCast(y_scale.scale(p.y))) + top,
                        .series_name = s.name,
                        .series_color = color,
                        .hovered_color = s.options.hovered_color orelse color,
                    }) catch continue;
                }
            }
        }

        if (points.items.len == 0) return null;
        const result_points = self.allocator.dupe(HoveredPoint, points.items) catch return null;
        return .{
            .points = result_points,
            .screen_x = @as(f32, @floatCast(x_scale.scale(target_x))) + left,
        };
    }

    fn zoomMode(self: *const Chart) ZoomMode {
        return if (self.zoom_enabled) self.config.zoom else .none;
    }

    // Called on pointerdown
    pub fn startSelection(self: *Chart, event: *Vapor.Event) void {
        if (self.zoomMode() == .none or self.is_empty or self.pie_slices.items.len > 0) return;
        // Only the main button drags out a zoom.
        if (Vapor.Event.getEventDataNumber(event.id, "button", 6) != 0) return;

        const at = self.pointerAt(event);
        if (!self.inPlot(at[0], at[1])) return;

        // An x zoom's box runs the plot's full height.
        const x_only = self.zoomMode() == .x;
        self.selection = .{
            .start_x = at[0],
            .start_y = if (x_only) self.bounds.y else at[1],
            .current_x = at[0],
            .current_y = if (x_only) self.bounds.y + self.bounds.height else at[1],
            .is_dragging = true,
        };
    }

    // Called on pointermove: the tooltip follows, and a drag grows its box.
    pub fn updateSelection(self: *Chart, event: *Vapor.Event) void {
        if (Vapor.Kit.throttle(16)) return;
        self.updateTooltip(event);
        if (self.selection) |*sel| {
            if (!sel.is_dragging) return;

            const at = self.pointerAt(event);
            sel.current_x = std.math.clamp(at[0], self.bounds.x, self.bounds.x + self.bounds.width);
            if (self.zoomMode() == .xy) {
                sel.current_y = std.math.clamp(at[1], self.bounds.y, self.bounds.y + self.bounds.height);
            }
            const min_x = @min(sel.start_x, sel.current_x);
            const min_y = @min(sel.start_y, sel.current_y);

            // The box is drawn on the render after pointerdown; a move that
            // comes first renders it instead of moving it.
            if (self.selection_rect._get_id() == null) {
                Vapor.cycle();
                return;
            }

            _ = self.selection_rect.translate3d(.{ .x = min_x, .y = min_y });
            const width = @abs(sel.current_x - sel.start_x);
            const height = @abs(sel.current_y - sel.start_y);
            self.selection_rect.mutateStyleString("width", Vapor.fmtln("{d}px", .{width}));
            self.selection_rect.mutateStyleString("height", Vapor.fmtln("{d}px", .{height}));
        }
    }

    // Called on pointerup
    pub fn endSelection(self: *Chart, event: *Vapor.Event) void {
        const sel = self.selection orelse return;
        self.selection = null;
        if (!sel.is_dragging) return;

        const min_x = @min(sel.start_x, sel.current_x);
        const max_x = @max(sel.start_x, sel.current_x);
        const min_y = @min(sel.start_y, sel.current_y);
        const max_y = @max(sel.start_y, sel.current_y);

        // A click, or a drag too small to mean a zoom, leaves the chart be;
        // the render takes its box away.
        const min_size: f32 = 10;
        const mode = self.zoomMode();
        if (max_x - min_x < min_size or (mode == .xy and max_y - min_y < min_size)) {
            Vapor.cycle();
            return;
        }

        const x_scale = self.x_scale orelse return;
        const y_scale = self.y_scale orelse return;
        if (self.pre_zoom_axes == null) {
            self.pre_zoom_axes = .{ .x = self.x_axis_config, .y = self.y_axis_config };
        }

        // Screen to data: chart-local, then through the scales.
        const left: f32 = @floatFromInt(self.config.margin.left);
        const top: f32 = @floatFromInt(self.config.margin.top);
        const new_x_min = x_scale.invert(min_x - left);
        const new_x_max = x_scale.invert(max_x - left);
        if (mode == .x) {
            self.applyZoomX(new_x_min, new_x_max);
        } else {
            // Screen y runs down, data y up.
            self.applyZoom(new_x_min, new_x_max, y_scale.invert(max_y - top), y_scale.invert(min_y - top));
        }

        // The rebuild emptied the tooltip; fill it for the point under the
        // pointer, which hasn't moved.
        self.old_x = std.math.nan(f64);
        self.hideTooltip();
        self.updateTooltip(event);
    }

    /// Zooms into an x range; the y axis fits the data inside it.
    fn applyZoomX(self: *Chart, x_min: f64, x_max: f64) void {
        if (self.x_axis_config) |*cfg| {
            cfg.scale.domain = .{ .manual = .{ x_min, x_max } };
        } else {
            self.x_axis_config = .{ .scale = .{ .domain = .{ .manual = .{ x_min, x_max } } } };
        }
        self.build() catch {};
        if (self.onendselection) |onendselection| {
            const y = self.y_scale orelse return;
            @call(.auto, onendselection, .{ x_min, x_max, y.domainMin(), y.domainMax() });
        }
        Vapor.cycle();
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

    /// Zooms back out to the view before the first zoom. The chart's Reset
    /// zoom button and a double-click on the chart call it.
    pub fn resetZoom(self: *Chart) void {
        const axes = self.pre_zoom_axes orelse return;
        self.x_axis_config = axes.x;
        self.y_axis_config = axes.y;
        self.pre_zoom_axes = null;

        self.build() catch {};
        Vapor.cycle();
    }

    fn resetZoomOnDoubleClick(self: *Chart, _: *Vapor.Event) void {
        self.resetZoom();
    }

    fn toggleItem(self: *Chart, index: usize) void {
        self.setShown(index, !self.isShown(index));
    }

    /// Fades every item but the legend's `index`th while it is pointed at.
    fn focusItem(self: *Chart, index: usize, _: *Vapor.Event) void {
        if (!self.isShown(index)) return;
        var id_buf: [40]u8 = undefined;
        var value_buf: [16]u8 = undefined;
        const value = std.fmt.bufPrint(&value_buf, "{d}", .{index}) catch return;
        self.platform.browser.setAttribute(self.svgId(&id_buf), "data-focus", value);
    }

    fn unfocusItem(self: *Chart, _: *Vapor.Event) void {
        var id_buf: [40]u8 = undefined;
        self.platform.browser.setAttribute(self.svgId(&id_buf), "data-focus", "none");
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
        // Later builds (a zoom, a resize, a legend click) don't draw it in again.
        self.entering = false;

        // The tooltip starts hidden; render says so.
        if (self.tooltip) |*tooltip| {
            tooltip.hide = true;
            tooltip.sliding = false;
        }
        Vapor.cycle();
    }

    /// The chart follows its parent's width.
    fn resized(self: *Chart, entry: Vapor.Kit.ResizeEntry) void {
        if (entry.width < 1) return;
        // Whole pixels, as mount measures them, so the first report (the
        // size mount already used) changes nothing.
        const width: u32 = @intFromFloat(entry.width);
        if (width == self.config.width) return;
        self.config.width = width;
        self.bounds = calculateBounds(self.config);
        self.hideTooltip();
        self.build() catch {};
        Vapor.cycle();
    }

    pub fn render(self: *Chart) void {
        const cfg = self.legend_config;
        // A column legend stands beside the plot, a row above or below it.
        const beside = if (cfg) |c| c.direction == .column else false;
        const legend_first = if (cfg) |c| switch (c.position) {
            .top_left => true,
            .top_right => !beside,
            .bottom_left => beside,
            .bottom_right => false,
        } else false;

        Box()
            .width(.percent(100))
            .direction(if (beside) .row else .column)
            .spacing(8)
            .children({
            if (legend_first) self.renderLegend();
            self.renderPlot(beside);
            if (!legend_first) self.renderLegend();
        });
    }

    /// The legend: a button per item that shows or hides it, and fades the
    /// others while pointed at.
    fn renderLegend(self: *Chart) void {
        const cfg = self.legend_config orelse return;
        const beside = cfg.direction == .column;
        const right = cfg.position == .top_right or cfg.position == .bottom_right;
        const text_color = cfg.text_color orelse Vapor.Types.Color.palette(.text_color);

        Box()
            .direction(if (beside) .column else .row)
            .wrap(.wrap)
            .layout(if (beside) .top_left else if (right) .right_center else .left_center)
            .width(if (beside) .fit else .percent(100))
            .spacing(if (beside) 2 else 8)
            .padding(if (beside) .all(0) else .{ .left = @intCast(@min(self.config.margin.left, 255)), .right = @intCast(@min(self.config.margin.right, 255)) })
            .children({
            for (self.legend_items, 0..) |item, k| {
                const shown = self.isShown(k);
                Vapor.Button(toggleItem, .{ self, k })
                    .attribute("aria-pressed", if (shown) "true" else "false")
                    .onEvent(.pointerenter, focusItem, .{ self, k })
                    .onEvent(.pointerleave, unfocusItem, .{self})
                    .layout(.left_center)
                    .spacing(6)
                    .padding(.xy(6, 2))
                    .background(.transparent)
                    .border(.round(.transparent, .all(4)))
                    .cursor(.pointer)
                    .children({
                    Box()
                        .width(.px(10))
                        .height(.px(10))
                        .border(.round(item.color, .all(2)))
                        .background(if (shown) item.color else .transparent)
                        .children({});
                    Text(item.title)
                        .inlineStyle("user-select: none; text-decoration: {s};", .{if (shown) "none" else "line-through"})
                        .font(12, 400, if (shown) text_color else .transparentize(text_color, 0.5))
                        .end();
                });
            }
        });
    }

    fn renderPlot(self: *Chart, beside_legend: bool) void {
        Box()
            .pos(.relative)
            .width(.percent(100))
            // Beside a legend, the plot takes the room the legend leaves.
            .inlineStyle("flex: {s}; min-width: 0;", .{if (beside_legend) "1 1 0%" else "0 0 auto"})
            .height(.px(@floatFromInt(self.config.height)))
            .children({
            Box()
                .ref(&self.container)
                .onMount(mount, .{self})
                .onResize(resized, .{self})
                .pos(.relative)
                .width(.percent(100))
                .height(.percent(100))
                .cursor(if (self.zoomMode() == .none or self.pie_slices.items.len > 0) .default else .crosshair)
                .onEvent(.pointerenter, showTooltip, .{self})
                .onEvent(.pointerleave, pointerLeft, .{self})
                .onEvent(.pointerdown, startSelection, .{self})
                .onEvent(.pointermove, updateSelection, .{self})
                .onEvent(.pointerup, endSelection, .{self})
                .onEvent(.dblclick, resetZoomOnDoubleClick, .{self})
                .children({
                if (self.tooltip) |*tooltip| {
                    const tip = tipStyle(tipState(tooltip));
                    if (self.config.show_line) {
                        Box()
                            .ref(&tooltip.line_binded)
                            .inlineStyle("pointer-events: none; transform: translate3d({d}px, 0, 0); opacity: {s}; visibility: {s}; transition: {s};", .{ tooltip.line_x, tip.opacity, tip.visibility, tip.transition })
                            .pos(.tl(.px(@floatFromInt(self.config.margin.top)), .px(0), .absolute))
                            .width(.px(1))
                            .height(.px(@floatFromInt(self.config.height -| self.config.margin.bottom -| self.config.margin.top)))
                            .background(.palette(.text_color))
                            .children({});
                    }
                    Box()
                        .ref(&tooltip.binded)
                        // It follows the pointer; it must never catch it. A
                        // render keeps it where, and as, the pointer left it.
                        .inlineStyle("pointer-events: none; transform: translate3d({d}px, {d}px, 0); opacity: {s}; visibility: {s}; transition: {s};", .{ tooltip.left, tooltip.top, tip.opacity, tip.visibility, tip.transition })
                        .pos(.absolute)
                        .minWidth(.px(tooltip.width))
                        .padding(.xy(8, 6))
                        .layout(.top_left)
                        .direction(.column)
                        .spacing(2)
                        .background(.palette(.background))
                        .border(.round(.palette(.border_color_light), .all(6)))
                        .shadow(.glow(4, .transparentize(.hex("#616161"), 0.1)))
                        .zIndex(1000)
                        .children({
                        Text(tooltip.header)
                            .inlineStyle("user-select: none; white-space: nowrap;", .{})
                            .font(12, 500, .palette(.text_color)).end();
                        for (tooltip.value) |lg| {
                            if (lg.value != null) {
                                Box()
                                    .layout(.x_between_center)
                                    .width(.percent(100))
                                    .spacing(12)
                                    .children({
                                    Box()
                                        .layout(.left_center)
                                        .spacing(6)
                                        .children({
                                        Box().width(.px(8)).height(.px(8))
                                            .border(.round(lg.color, .all(2)))
                                            .background(lg.color)
                                            .children({});
                                        Text(lg.title)
                                            .inlineStyle("user-select: none; white-space: nowrap;", .{})
                                            .font(12, 300, .palette(.text_color)).end();
                                    });
                                    Text(lg.text)
                                        .inlineStyle("user-select: none; white-space: nowrap; font-variant-numeric: tabular-nums;", .{})
                                        .font(12, 500, .palette(.text_color)).end();
                                });
                            }
                        }
                        if (tooltip.total_text.len > 0) {
                            Box()
                                .layout(.x_between_center)
                                .width(.percent(100))
                                .spacing(12)
                                .children({
                                Text("Total")
                                    .inlineStyle("user-select: none;", .{})
                                    .font(12, 300, .palette(.text_color)).end();
                                Text(tooltip.total_text)
                                    .inlineStyle("user-select: none; font-variant-numeric: tabular-nums;", .{})
                                    .font(12, 500, .palette(.text_color)).end();
                            });
                        }
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
                            // Drawn where the drag is, not first in the corner.
                            .inlineStyle("pointer-events: none; transform: translate3d({d}px, {d}px, 0);", .{ @min(sel.start_x, sel.current_x), @min(sel.start_y, sel.current_y) })
                            .width(.px(width))
                            .height(.px(height))
                            .background(.transparentize(.palette(.border_color_light), 0.7))
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
            if (self.is_empty) {
                Box()
                    .pos(.tl(.px(0), .px(0), .absolute))
                    .width(.percent(100))
                    .height(.percent(100))
                    .layout(.center)
                    .inlineStyle("pointer-events: none;", .{})
                    .children({
                    Text(self.config.empty_text)
                        .font(13, 400, .transparentize(.palette(.text_color), 0.4))
                        .end();
                });
            }
            // Beside the plot, not in it: the pointer leaving the plot for
            // the button hides the tooltip, and a press on it starts no
            // zoom box. Top right and above the tooltip, where charts keep it.
            if (self.pre_zoom_axes != null) {
                Vapor.Button(resetZoom, .{self})
                    .ariaLabel("Reset zoom")
                    .pos(.tr(.px(@floatFromInt(self.config.margin.top + 8)), .px(@floatFromInt(self.config.margin.right + 8)), .absolute))
                    .zIndex(1001)
                    .padding(.xy(8, 4))
                    .background(.palette(.background))
                    .border(.round(.palette(.border_color_light), .all(6)))
                    .cursor(.pointer)
                    .children({
                    Text("Reset zoom")
                        .inlineStyle("user-select: none;", .{})
                        .font(12, 400, .palette(.text_color)).end();
                });
            }
        });
    }
};

/// A colour as CSS, written into `buf`.
fn cssColor(buf: []u8, color: Vapor.Types.Color) []const u8 {
    var w: Writer = undefined;
    w.init(buf);
    color.toCss(&w) catch {};
    return w.buffer[0..w.pos];
}

/// The gap between ticks; 1 when there is only one.
fn tickStep(ticks: []const f64) f64 {
    return if (ticks.len >= 2) ticks[1] - ticks[0] else 1;
}

/// The decimals a tick step needs: none for 1 and up, one for 0.5, two for 0.05.
fn decimalsFor(step: f64) u8 {
    if (!(step > 0) or step >= 1) return 0;
    return @intFromFloat(@min(6, @ceil(-std.math.log10(step) - 1e-9)));
}

fn formatNumber(buf: []u8, value: f64, decimals: u8) []const u8 {
    // No "-0" for a tick that lands a hair below zero.
    const v = if (@abs(value) < 1e-9) 0 else value;
    inline for (0..7) |d| {
        if (decimals == d) return std.fmt.bufPrint(buf, "{d:." ++ std.fmt.comptimePrint("{d}", .{d}) ++ "}", .{v}) catch "";
    }
    return std.fmt.bufPrint(buf, "{d}", .{v}) catch "";
}

test "tick labels show the decimals their step needs" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("20", formatNumber(&buf, 20, decimalsFor(10)));
    try std.testing.expectEqualStrings("0.5", formatNumber(&buf, 0.5, decimalsFor(0.5)));
    try std.testing.expectEqualStrings("0.05", formatNumber(&buf, 0.05, decimalsFor(0.05)));
    // Not "-0.0" for a tick a hair below zero.
    try std.testing.expectEqualStrings("0.0", formatNumber(&buf, -1e-12, decimalsFor(0.2)));
}

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
