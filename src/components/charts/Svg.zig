const std = @import("std");
const Vapor = @import("vapor");
const Writer = Vapor.Writer;

pub const Svg = struct {
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Svg {
        return .{
            .buffer = .empty,
            .allocator = allocator,
        };
    }

    pub fn initCapacity(allocator: std.mem.Allocator, capacity: usize) !Svg {
        return .{
            .buffer = try std.ArrayList(u8).initCapacity(allocator, capacity),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Svg) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn toOwnedSlice(self: *Svg) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }

    pub fn appendSlice(self: *Svg, slice: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, slice);
    }

    pub fn print(self: *Svg, comptime fmt: []const u8, args: anytype) !void {
        try self.buffer.print(self.allocator, fmt, args);
    }

    // ============ SVG Elements ============
    pub fn openSvg(self: *Svg, width: u32, height: u32) !void {
        try self.buffer.print(self.allocator,
            \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {d} {d}">
            \\
        , .{ width, height });
    }

    pub fn closeSvg(self: *Svg) !void {
        try self.buffer.appendSlice(self.allocator, "</svg>\n");
    }

    pub fn openGroup(self: *Svg, class: ?[]const u8, transform: ?[]const u8) !void {
        try self.buffer.appendSlice(self.allocator, "<g");
        if (class) |c| try self.buffer.print(self.allocator, " class=\"{s}\"", .{c});
        if (transform) |t| try self.buffer.print(self.allocator, " transform=\"{s}\"", .{t});
        try self.buffer.appendSlice(self.allocator, ">\n");
    }

    pub fn closeGroup(self: *Svg) !void {
        try self.buffer.appendSlice(self.allocator, "</g>\n");
    }

    pub fn convertColor(color: Vapor.Types.Color) []const u8 {
        var w: Writer = undefined;
        var buffer: [4096]u8 = undefined;
        w.init(&buffer);
        color.toCss(&w) catch unreachable;
        return w.buffer[0..w.pos];
    }

    pub fn line(self: *Svg, x1: f64, y1: f64, x2: f64, y2: f64, opts: LineOpts) !void {
        try self.buffer.print(self.allocator, "<line id=\"{s}\" x1=\"{d:.2}\" y1=\"{d:.2}\" x2=\"{d:.2}\" y2=\"{d:.2}\"", .{ opts.id, x1, y1, x2, y2 });
        if (opts.class) |c| try self.buffer.print(self.allocator, " class=\"{s}\"", .{c});
        if (opts.stroke) |s| try self.buffer.print(self.allocator, " stroke=\"{s}\"", .{convertColor(s)});
        if (opts.stroke_width) |sw| try self.buffer.print(self.allocator, " stroke-width=\"{d}\"", .{sw});
        try self.buffer.appendSlice(self.allocator, "/>\n");
    }

    pub fn rect(self: *Svg, x: f64, y: f64, width: f64, height: f64, opts: RectOpts) !void {
        try self.buffer.print(self.allocator, "<rect id=\"{s}\" x=\"{d:.2}\" y=\"{d:.2}\" width=\"{d:.2}\" height=\"{d:.2}\"", .{ opts.id, x, y, width, height });
        if (opts.class) |c| try self.buffer.print(self.allocator, " class=\"{s}\"", .{c});
        if (opts.fill) |f| try self.buffer.print(self.allocator, " fill=\"{s}\"", .{convertColor(f)});
        if (opts.stroke) |s| try self.buffer.print(self.allocator, " stroke=\"{s}\"", .{convertColor(s)});
        if (opts.stroke_width) |sw| try self.buffer.print(self.allocator, " stroke-width=\"{d:.2}\"", .{sw});
        if (opts.rx) |r| try self.buffer.print(self.allocator, " rx=\"{d:.2}\"", .{r});
        if (opts.opacity) |o| try self.buffer.print(self.allocator, " opacity=\"{d:.2}\"", .{o});
        try self.buffer.appendSlice(self.allocator, "/>\n");
    }

    pub fn circle(self: *Svg, cx: f64, cy: f64, r: f64, opts: CircleOpts) !void {
        try self.buffer.print(self.allocator, "<circle id=\"{s}\" cx=\"{d:.2}\" cy=\"{d:.2}\" r=\"{d:.2}\"", .{ opts.id, cx, cy, r });
        if (opts.class) |c| try self.buffer.print(self.allocator, " class=\"{s}\"", .{c});
        if (opts.fill) |f| try self.buffer.print(self.allocator, " fill=\"{s}\"", .{convertColor(f)});
        if (opts.stroke) |s| try self.buffer.print(self.allocator, " stroke=\"{s}\"", .{convertColor(s)});
        try self.buffer.appendSlice(self.allocator, "/>\n");
    }

    pub fn path(self: *Svg, d: []const u8, opts: PathOpts) !void {
        try self.buffer.print(self.allocator, "<path id=\"{s}\" d=\"{s}\"", .{ opts.id, d });
        if (opts.class) |c| try self.buffer.print(self.allocator, " class=\"{s}\"", .{c});
        if (opts.fill) |f| try self.buffer.print(self.allocator, " fill=\"{s}\"", .{convertColor(f)});
        if (opts.stroke) |s| try self.buffer.print(self.allocator, " stroke=\"{s}\"", .{convertColor(s)});
        if (opts.stroke_width) |sw| try self.buffer.print(self.allocator, " stroke-width=\"{d}\"", .{sw});
        try self.buffer.appendSlice(self.allocator, "/>\n");
    }

    pub fn text(self: *Svg, x: f64, y: f64, content: []const u8, opts: TextOpts) !void {
        try self.buffer.print(self.allocator, "<text id=\"{s}\" x=\"{d:.2}\" y=\"{d:.2}\"", .{ opts.id, x, y });
        if (opts.class) |c| try self.buffer.print(self.allocator, " class=\"{s}\"", .{c});
        if (opts.anchor) |a| try self.buffer.print(self.allocator, " text-anchor=\"{s}\"", .{@tagName(a)});
        if (opts.dominant_baseline) |db| try self.buffer.print(self.allocator, " dominant-baseline=\"{s}\"", .{@tagName(db)});
        if (opts.font_size) |fs| try self.buffer.print(self.allocator, " font-size=\"{d}\"", .{fs});
        if (opts.fill) |f| try self.buffer.print(self.allocator, " fill=\"{s}\"", .{convertColor(f)});
        if (opts.transform) |t| try self.buffer.print(self.allocator, " transform=\"{s}\"", .{t});
        try self.buffer.print(self.allocator, ">{s}</text>\n", .{content});
    }

    pub fn style(self: *Svg, css: []const u8) !void {
        try self.buffer.print(self.allocator, "<style>{s}</style>\n", .{css});
    }

    // ... (LineOpts, RectOpts, CircleOpts, PathOpts, TextOpts, enums stay the same)

    // ============ Option Types ============

    pub const LineOpts = struct {
        id: []const u8 = "",
        class: ?[]const u8 = null,
        stroke: ?Vapor.Types.Color = null,
        stroke_width: ?f32 = null,
    };

    pub const RectOpts = struct {
        id: []const u8 = "",
        class: ?[]const u8 = null,
        fill: ?Vapor.Types.Color = null,
        stroke: ?Vapor.Types.Color = null,
        rx: ?f64 = null,
        border: ?Vapor.Types.BorderGrouped = null,
        stroke_width: ?f32 = null,
        opacity: ?f64 = null,
    };

    pub const CircleOpts = struct {
        id: []const u8 = "",
        class: ?[]const u8 = null,
        fill: ?Vapor.Types.Color = null,
        stroke: ?Vapor.Types.Color = null,
    };

    pub const PathOpts = struct {
        id: []const u8 = "",
        class: ?[]const u8 = null,
        fill: ?Vapor.Types.Color = null,
        stroke: ?Vapor.Types.Color = null,
        stroke_width: ?f32 = null,
    };

    pub const TextOpts = struct {
        id: []const u8 = "",
        class: ?[]const u8 = null,
        anchor: ?TextAnchor = null,
        dominant_baseline: ?DominantBaseline = null,
        font_size: ?u32 = null,
        fill: ?Vapor.Types.Color = null,
        transform: ?[]const u8 = null,
    };

    pub const TextAnchor = enum { start, middle, end };
    pub const DominantBaseline = enum { auto, middle, hanging };
};
