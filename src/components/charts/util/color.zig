pub const Palette = struct {
    colors: []const []const u8,

    pub fn get(self: Palette, index: usize) []const u8 {
        return self.colors[index % self.colors.len];
    }
};

// Default palettes
pub const palettes = struct {
    pub const category10: Palette = .{
        .colors = &.{
            "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
            "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf",
        },
    };

    pub const blues: Palette = .{
        .colors = &.{
            "#eff3ff", "#c6dbef", "#9ecae1", "#6baed6",
            "#4292c6", "#2171b5", "#084594",
        },
    };

    pub const warm: Palette = .{
        .colors = &.{
            "#fee08b", "#fdae61", "#f46d43", "#d73027", "#a50026",
        },
    };

    pub const cool: Palette = .{
        .colors = &.{
            "#e0f3f8", "#abd9e9", "#74add1", "#4575b4", "#313695",
        },
    };
};
