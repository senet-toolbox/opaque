const Vapor = @import("vapor");

// vapor/types.zig
pub fn Item(comptime T: type) type {
    return struct {
        value: T,
        label: []const u8,
        icon: ?Vapor.IconType = null,
        description: ?[]const u8 = null, // Added for richer UI
        link: ?[]const u8 = null, // Added for richer UI
        is_shown: bool = true,
        is_selected: bool = false,
    };
}
