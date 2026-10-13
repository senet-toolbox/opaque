const std = @import("std");

pub const LogScale = struct {
    domain_min: f64,
    domain_max: f64,
    range_min: f64,
    range_max: f64,
    base: f64 = 10,

    pub fn init(domain: [2]f64, range: [2]f64) LogScale {
        return .{
            .domain_min = @max(domain[0], 1e-10), // log can't handle 0
            .domain_max = domain[1],
            .range_min = range[0],
            .range_max = range[1],
        };
    }

    pub fn scale(self: LogScale, value: f64) f64 {
        const log_min = @log10(self.domain_min);
        const log_max = @log10(self.domain_max);
        const log_val = @log10(@max(value, 1e-10));
        
        const normalized = (log_val - log_min) / (log_max - log_min);
        return self.range_min + normalized * (self.range_max - self.range_min);
    }

    pub fn ticks(self: LogScale, count: usize, allocator: std.mem.Allocator) ![]f64 {
        _ = count;
        // Log scales use powers: 1, 10, 100, 1000...
        var result = std.array_list.Managed(f64).init(allocator);
        
        const min_exp = @floor(@log10(self.domain_min));
        const max_exp = @ceil(@log10(self.domain_max));
        
        var exp = min_exp;
        while (exp <= max_exp) : (exp += 1) {
            const val = std.math.pow(f64, 10, exp);
            if (val >= self.domain_min and val <= self.domain_max) {
                try result.append(val);
            }
        }
        
        return result.toOwnedSlice();
    }

    pub fn invert(_: LogScale, _: f64) f64 {
        // const log_min = @log10(self.domain_min);
        // const log_max = @log10(self.domain_max);
        // const log_val = @log10(value);
        //
        // const normalized = (log_val - self.range_min) / (self.range_max - self.range_min);
        unreachable;
        // return ;
    }   
};
