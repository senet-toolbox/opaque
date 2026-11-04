//! A person's picture: their photo, or their initials on a colour picked
//! from their name.
//!
//!   Avatar.render(.{ .name = "Sarah Chen", .src = "/sarah.webp", .status = .online });
//!   Avatar.group(&.{ .{ .name = "Sarah Chen" }, .{ .name = "Mike Johnson" } }, 3);
//!
//! The photo is drawn over the initials, so one that fails to load leaves
//! the initials showing rather than a broken image.

const std = @import("std");
const Vapor = @import("vapor");
const Box = Vapor.Box;
const Row = Vapor.Row;
const Text = Vapor.Text;

pub const Status = enum {
    online,
    away,
    busy,
    offline,

    fn color(status: Status) Vapor.Types.Color {
        return switch (status) {
            .online => .hex("#22c55e"),
            .away => .hex("#f59e0b"),
            .busy => .hex("#ef4444"),
            .offline => .hex("#94a3b8"),
        };
    }
};

pub const Shape = enum { circle, rounded };

pub const Options = struct {
    /// Who it is: read out by screen readers, and the initials when there
    /// is no photo.
    name: []const u8,
    /// The photo's URL.
    src: ?[]const u8 = null,
    /// Its width and height, in pixels.
    size: f32 = 40,
    shape: Shape = .circle,
    /// A dot at the corner; screen readers hear it after the name.
    status: ?Status = null,
    /// Behind the initials; unset, a colour picked from the name, the same
    /// one every time.
    background: ?Vapor.Types.Color = null,
};

/// The initials' backgrounds: mid tones white text reads on.
pub var colors: []const Vapor.Types.Color = &.{
    .hex("#6366f1"), .hex("#0ea5e9"), .hex("#14b8a6"), .hex("#22a35a"),
    .hex("#d97706"), .hex("#e11d48"), .hex("#9333ea"), .hex("#475569"),
};
/// The ring that parts avatars in a group, and frames a status dot.
pub var ring_color: Vapor.Types.Color = .palette(.background);

/// Up to two letters: the first of the first and last words.
pub fn initials(name: []const u8, buf: *[8]u8) []const u8 {
    var it = std.mem.tokenizeScalar(u8, name, ' ');
    var first: ?u8 = null;
    var last: ?u8 = null;
    while (it.next()) |word| {
        if (first == null) first = word[0] else last = word[0];
    }
    var len: usize = 0;
    if (first) |c| {
        buf[len] = std.ascii.toUpper(c);
        len += 1;
    }
    if (last) |c| {
        buf[len] = std.ascii.toUpper(c);
        len += 1;
    }
    return buf[0..len];
}

/// The same colour for the same name.
pub fn colorFor(name: []const u8) Vapor.Types.Color {
    if (colors.len == 0) return .palette(.tint);
    return colors[@intCast(std.hash.Wyhash.hash(0, name) % colors.len)];
}

fn label(options: Options) []const u8 {
    if (options.status) |status| return Vapor.fmtln("{s} ({s})", .{ options.name, @tagName(status) });
    return options.name;
}

pub fn render(options: Options) void {
    var buf: [8]u8 = undefined;
    const text = Vapor.fmtln("{s}", .{initials(options.name, &buf)});
    const radius: u16 = @intFromFloat(if (options.shape == .circle) options.size / 2 else options.size / 5);

    Box()
        .a11y(Vapor.Accessibility.init().setRole(.img).setLabel(label(options)))
        .pos(.relative)
        .width(.px(options.size))
        .height(.px(options.size))
        .inlineStyle("flex-shrink: 0;", .{})
        .children({
        Box()
            .ariaHidden(true)
            .width(.percent(100))
            .height(.percent(100))
            .layout(.center)
            .background(options.background orelse colorFor(options.name))
            .radius(.all(radius))
            .children({
            Text(text)
                .font(@intFromFloat(@min(255, options.size * 0.4)), 600, .white)
                .inlineStyle("user-select: none; letter-spacing: 0.02em;", .{})
                .end();
        });
        if (options.src) |src| {
            // Over the initials; if it fails to load they still show.
            Box()
                .ariaHidden(true)
                .pos(.tl(.px(0), .px(0), .absolute))
                .width(.percent(100))
                .height(.percent(100))
                .radius(.all(radius))
                .inlineStyle("background-image: url(\"{s}\"); background-size: cover; background-position: center;", .{src})
                .children({});
        }
        if (options.status) |status| {
            const dot = @max(8, options.size * 0.28);
            Box()
                .ariaHidden(true)
                .pos(.br(.px(0), .px(0), .absolute))
                .width(.px(dot))
                .height(.px(dot))
                .background(status.color())
                .border(.round(ring_color, .all(99)))
                .inlineStyle("border-width: 2px; box-sizing: border-box;", .{})
                .children({});
        }
    });
}

/// Avatars overlapping in a row, up to `max`, then a "+N" for the rest.
pub fn group(avatars: []const Options, max: usize) void {
    const shown = @min(avatars.len, max);
    const size: f32 = if (avatars.len > 0) avatars[0].size else 40;
    Row()
        .a11y(Vapor.Accessibility.init().setRole(.group).setLabel(Vapor.fmtln("{d} people", .{avatars.len})))
        .layout(.left_center)
        .children({
        for (avatars[0..shown], 0..) |avatar, i| {
            Box()
                .inlineStyle("margin-left: {d}px;", .{if (i == 0) 0 else -size / 4})
                .border(.round(ring_color, .all(99)))
                .inlineStyle("border-width: 2px; border-radius: 9999px;", .{})
                .children({
                render(avatar);
            });
        }
        if (avatars.len > shown) {
            const rest = avatars.len - shown;
            Box()
                .a11y(Vapor.Accessibility.init().setRole(.img).setLabel(Vapor.fmtln("{d} more", .{rest})))
                .inlineStyle("margin-left: {d}px; border-width: 2px; flex-shrink: 0;", .{-size / 4})
                .width(.px(size + 4))
                .height(.px(size + 4))
                .layout(.center)
                .background(.palette(.border_color_light))
                .border(.round(ring_color, .all(99)))
                .children({
                Text(Vapor.fmtln("+{d}", .{rest}))
                    .ariaHidden(true)
                    .font(@intFromFloat(@min(255, size * 0.35)), 600, .palette(.text_color))
                    .end();
            });
        }
    });
}

test "initials take the first and last words' letters" {
    var buf: [8]u8 = undefined;
    try std.testing.expectEqualStrings("SC", initials("Sarah Chen", &buf));
    try std.testing.expectEqualStrings("MW", initials("mary jane watson", &buf));
    try std.testing.expectEqualStrings("A", initials("  Ada ", &buf));
    try std.testing.expectEqualStrings("", initials("", &buf));
}
