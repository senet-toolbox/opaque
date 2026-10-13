const std = @import("std");

/// Scale for categorical/ordinal data (like bar chart x-axis)
pub const BandScale = struct {
    labels: []const []const u8,
    range_min: f64,
    range_max: f64,
    padding_inner: f64 = 0.1,
    padding_outer: f64 = 0.1,

    pub fn init(labels: []const []const u8, range: [2]f64) BandScale {
        return .{
            .labels = labels,
            .range_min = range[0],
            .range_max = range[1],
        };
    }

    pub fn withPadding(self: BandScale, inner: f64, outer: f64) BandScale {
        var new = self;
        new.padding_inner = inner;
        new.padding_outer = outer;
        return new;
    }

    /// Get the start position for a band by index
    pub fn scale(self: BandScale, index: usize) f64 {
        const n: f64 = @floatFromInt(self.labels.len);
        const range_span = self.range_max - self.range_min;

        // Total padding
        const outer = self.padding_outer * self.bandwidth();
        const inner_total = self.padding_inner * self.bandwidth() * (n - 1);
        _ = inner_total;

        const step = (range_span - 2 * outer) / n;
        return self.range_min + outer + @as(f64, @floatFromInt(index)) * step;
    }

    /// Get the center position for a band
    pub fn scaleCenter(self: BandScale, index: usize) f64 {
        return self.scale(index) + self.bandwidth() / 2;
    }

    /// Width of each band
    pub fn bandwidth(self: BandScale) f64 {
        const n: f64 = @floatFromInt(self.labels.len);
        if (n == 0) return 0;

        const range_span = self.range_max - self.range_min;
        const total_padding = self.padding_outer * 2 + self.padding_inner * (n - 1);
        return range_span / (n + total_padding);
    }

    /// Find index by label
    pub fn indexOf(self: BandScale, label: []const u8) ?usize {
        for (self.labels, 0..) |l, i| {
            if (std.mem.eql(u8, l, label)) return i;
        }
        return null;
    }
};
