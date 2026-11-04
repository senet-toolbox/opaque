//! A small label: a status, a tag, a count.
//!
//!   Badge.render(.{ .text = "Active", .tone = .success, .dot = true });
//!   Badge.count(unread, "unread messages");
//!
//! A count over `max_count` reads "99+"; screen readers hear the full
//! number and what it counts.

const std = @import("std");
const Vapor = @import("vapor");
const Row = Vapor.Row;
const Box = Vapor.Box;
const Text = Vapor.Text;
const Icon = Vapor.Icon;

pub const Tone = enum {
    neutral,
    tint,
    success,
    warning,
    danger,
    /// No fill: a border in the text colour.
    outline,
};

pub const Options = struct {
    text: []const u8,
    tone: Tone = .neutral,
    icon: ?Vapor.IconTokens = null,
    /// A dot before the text, in the tone's colour.
    dot: bool = false,
};

pub var success_color: Vapor.Types.Color = .hex("#16a34a");
pub var warning_color: Vapor.Types.Color = .hex("#d97706");
pub var danger_color: Vapor.Types.Color = .hex("#dc2626");
/// The largest count shown in full; above it, "99+".
pub var max_count: usize = 99;

fn toneColor(tone: Tone) Vapor.Types.Color {
    return switch (tone) {
        .neutral, .outline => .palette(.text_color),
        .tint => .palette(.tint),
        .success => success_color,
        .warning => warning_color,
        .danger => danger_color,
    };
}

pub fn render(options: Options) void {
    const color = toneColor(options.tone);
    Row()
        .layout(.center)
        .spacing(5)
        .padding(.xy(8, 2))
        .background(switch (options.tone) {
        .neutral => .palette(.border_color_light),
        .outline => .transparent,
        else => .transparentize(color, 0.15),
    })
        .border(.round(if (options.tone == .outline) .palette(.border_color_light) else .transparent, .all(99)))
        .inlineStyle("width: fit-content; white-space: nowrap;", .{})
        .children({
        if (options.dot) {
            Box()
                .ariaHidden(true)
                .width(.px(6))
                .height(.px(6))
                .background(color)
                .radius(.all(99))
                .children({});
        }
        if (options.icon) |icon| {
            Icon(icon)
                .font(12, 500, color)
                .end();
        }
        Text(options.text)
            .font(12, 500, color)
            .end();
    });
}

/// A number in a tinted pill: "99+" past `max_count`. `what` says what it
/// counts, for screen readers: "3 unread messages".
pub fn count(n: usize, what: []const u8) void {
    var buf: [24]u8 = undefined;
    const shown = countText(n, &buf);
    Row()
        .a11y(Vapor.Accessibility.init().setRole(.status).setLabel(Vapor.fmtln("{d} {s}", .{ n, what })))
        .layout(.center)
        .padding(.xy(6, 1))
        .inlineStyle("min-width: 20px; height: 20px; box-sizing: border-box; width: fit-content;", .{})
        .background(.palette(.tint))
        .radius(.all(99))
        .children({
        Text(Vapor.fmtln("{s}", .{shown}))
            .ariaHidden(true)
            .font(11, 700, .palette(.background))
            .end();
    });
}

/// "7", or "99+" past `max_count`.
pub fn countText(n: usize, buf: []u8) []const u8 {
    if (n > max_count) return std.fmt.bufPrint(buf, "{d}+", .{max_count}) catch "";
    return std.fmt.bufPrint(buf, "{d}", .{n}) catch "";
}

test "a count past the most shown reads as that, plus" {
    var buf: [24]u8 = undefined;
    try std.testing.expectEqualStrings("7", countText(7, &buf));
    try std.testing.expectEqualStrings("99", countText(99, &buf));
    try std.testing.expectEqualStrings("99+", countText(100, &buf));
}
