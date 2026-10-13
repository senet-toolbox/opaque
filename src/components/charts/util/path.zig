const std = @import("std");

pub const PathBuilder = struct {
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PathBuilder {
        return .{
            .buffer = .empty,
            .allocator = allocator,
        };
    }

    pub fn initCapacity(allocator: std.mem.Allocator, capacity: usize) !PathBuilder {
        return .{
            .buffer = try std.ArrayList(u8).initCapacity(allocator, capacity),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PathBuilder) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn toOwnedSlice(self: *PathBuilder) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }

    pub fn slice(self: *PathBuilder) []const u8 {
        return self.buffer.items;
    }

    pub fn moveTo(self: *PathBuilder, x: f64, y: f64) !void {
        try self.buffer.print(self.allocator, "M{d:.2},{d:.2}", .{ x, y });
    }

    pub fn lineTo(self: *PathBuilder, x: f64, y: f64) !void {
        try self.buffer.print(self.allocator, "L{d:.2},{d:.2}", .{ x, y });
    }

    pub fn curveTo(self: *PathBuilder, cp1x: f64, cp1y: f64, cp2x: f64, cp2y: f64, x: f64, y: f64) !void {
        try self.buffer.print(self.allocator, "C{d:.2},{d:.2} {d:.2},{d:.2} {d:.2},{d:.2}", .{ cp1x, cp1y, cp2x, cp2y, x, y });
    }

    pub fn smoothCurveTo(self: *PathBuilder, cp2x: f64, cp2y: f64, x: f64, y: f64) !void {
        try self.buffer.print(self.allocator, "S{d:.2},{d:.2} {d:.2},{d:.2}", .{ cp2x, cp2y, x, y });
    }

    pub fn quadTo(self: *PathBuilder, cpx: f64, cpy: f64, x: f64, y: f64) !void {
        try self.buffer.print(self.allocator, "Q{d:.2},{d:.2} {d:.2},{d:.2}", .{ cpx, cpy, x, y });
    }

    pub fn arcTo(self: *PathBuilder, rx: f64, ry: f64, rotation: f64, large_arc: bool, sweep: bool, x: f64, y: f64) !void {
        try self.buffer.print(self.allocator, "A{d:.2},{d:.2} {d:.2} {d} {d} {d:.2},{d:.2}", .{
            rx,
            ry,
            rotation,
            @as(u8, if (large_arc) 1 else 0),
            @as(u8, if (sweep) 1 else 0),
            x,
            y,
        });
    }

    pub fn closePath(self: *PathBuilder) !void {
        try self.buffer.append(self.allocator, 'Z');
    }

    pub fn horizontalTo(self: *PathBuilder, x: f64) !void {
        try self.buffer.print(self.allocator, "H{d:.2}", .{x});
    }

    pub fn verticalTo(self: *PathBuilder, y: f64) !void {
        try self.buffer.print(self.allocator, "V{d:.2}", .{y});
    }
};

/// Generate a smooth curve through points using Catmull-Rom spline
pub fn smoothLine(allocator: std.mem.Allocator, points: []const [2]f64, tension: f64) ![]u8 {
    var path = PathBuilder.init(allocator);
    defer path.deinit();

    if (points.len == 0) return try allocator.dupe(u8, "");
    if (points.len == 1) {
        try path.moveTo(points[0][0], points[0][1]);
        return path.toOwnedSlice();
    }

    try path.moveTo(points[0][0], points[0][1]);

    if (points.len == 2) {
        try path.lineTo(points[1][0], points[1][1]);
        return path.toOwnedSlice();
    }

    // Catmull-Rom to Bezier conversion
    for (0..points.len - 1) |i| {
        const p0 = if (i == 0) points[0] else points[i - 1];
        const p1 = points[i];
        const p2 = points[i + 1];
        const p3 = if (i + 2 < points.len) points[i + 2] else points[points.len - 1];

        const cp1x = p1[0] + (p2[0] - p0[0]) / 6 * tension;
        const cp1y = p1[1] + (p2[1] - p0[1]) / 6 * tension;
        const cp2x = p2[0] - (p3[0] - p1[0]) / 6 * tension;
        const cp2y = p2[1] - (p3[1] - p1[1]) / 6 * tension;

        try path.curveTo(cp1x, cp1y, cp2x, cp2y, p2[0], p2[1]);
    }

    return path.toOwnedSlice();
}
