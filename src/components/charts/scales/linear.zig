const std = @import("std");

pub const LinearScale = struct {
    domain_min: f64,
    domain_max: f64,
    range_min: f64,
    range_max: f64,
    nice: bool = false,

    pub fn init(domain: [2]f64, range: [2]f64) LinearScale {
        return .{
            .domain_min = domain[0],
            .domain_max = domain[1],
            .range_min = range[0],
            .range_max = range[1],
        };
    }

    /// Create scale from data, auto-calculating domain
    pub fn fromData(data: []const f64, range: [2]f64) LinearScale {
        if (data.len == 0) {
            return init(.{ 0, 1 }, range);
        }

        var min = data[0];
        var max = data[0];
        for (data) |v| {
            min = @min(min, v);
            max = @max(max, v);
        }

        // Prevent zero-range
        if (min == max) {
            min -= 1;
            max += 1;
        }

        return init(.{ min, max }, range);
    }

    /// Map a domain value to range value
    pub fn scale(self: LinearScale, value: f64) f64 {
        const domain_span = self.domain_max - self.domain_min;
        const range_span = self.range_max - self.range_min;
        const normalized = (value - self.domain_min) / domain_span;
        return self.range_min + normalized * range_span;
    }

    /// Inverse: map range value back to domain
    pub fn invert(self: LinearScale, value: f64) f64 {
        const domain_span = self.domain_max - self.domain_min;
        const range_span = self.range_max - self.range_min;
        const normalized = (value - self.range_min) / range_span;
        return self.domain_min + normalized * domain_span;
    }

    /// Generate nice tick values
    pub fn ticks(self: LinearScale, count: usize, allocator: std.mem.Allocator) ![]f64 {
        const span = self.domain_max - self.domain_min;
        const step = niceStep(span / @as(f64, @floatFromInt(count)));

        const start = @ceil(self.domain_min / step) * step;
        const end = @floor(self.domain_max / step) * step;

        const n: usize = @intFromFloat(@floor((end - start) / step) + 1);
        var result = try allocator.alloc(f64, n);

        for (0..n) |i| {
            result[i] = start + @as(f64, @floatFromInt(i)) * step;
        }

        return result;
    }

    /// Make domain "nice" (round to clean numbers)
    pub fn niced(self: LinearScale) LinearScale {
        const span = self.domain_max - self.domain_min;
        const step = niceStep(span / 10);
        return .{
            .domain_min = @floor(self.domain_min / step) * step,
            .domain_max = @ceil(self.domain_max / step) * step,
            .range_min = self.range_min,
            .range_max = self.range_max,
            .nice = true,
        };
    }

    /// Add padding to domain (percentage)
    pub fn padded(self: LinearScale, padding: f64) LinearScale {
        const span = self.domain_max - self.domain_min;
        const pad = span * padding;
        return .{
            .domain_min = self.domain_min - pad,
            .domain_max = self.domain_max + pad,
            .range_min = self.range_min,
            .range_max = self.range_max,
            .nice = self.nice,
        };
    }
};

/// Calculate a "nice" step value (1, 2, 5, 10, 20, 50, etc.)
fn niceStep(rough_step: f64) f64 {
    const exp = @floor(std.math.log10(rough_step));
    const pow = std.math.pow(f64, 10, exp);
    const frac = rough_step / pow;

    const nice_frac: f64 = if (frac <= 1.5)
        1
    else if (frac <= 3)
        2
    else if (frac <= 7)
        5
    else
        10;

    return nice_frac * pow;
}
