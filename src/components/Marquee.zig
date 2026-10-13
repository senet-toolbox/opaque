const std = @import("std");
const Vapor = @import("vapor");
const Row = Vapor.Row;
const Stack = Vapor.Stack;
const Text = Vapor.Text;

// ============================================================================
// Types
// ============================================================================

pub const Direction = enum { left, right, up, down };

pub const MarqueeItem = struct {
    title: []const u8,
    subtitle: []const u8 = "",
    color: Vapor.Types.Color = .palette(.tint),
};

pub const Options = struct {
    /// Optional stable id for state lookup — defaults to the container UUID
    direction: Direction = .left,
    /// Animation duration in milliseconds — lower = faster scroll
    speed_ms: u32 = 8000,
    /// Gap between items in pixels
    gap: u8 = 16,
    repeat: usize = 4,
};

// ============================================================================
// Animations
// ============================================================================
//
// Items are duplicated 2×, so the track is always twice the content length.
// Translating by -50% on the scroll axis moves exactly one full set of items,
// producing a seamless loop regardless of item count, size, or gap.

pub const animateLeft = Vapor.Animation.init("marquee-left")
    .propUnit(.translateX, 0, -100, .percent)
    .easing(.linear)
    .infinite();

pub const animateRight = Vapor.Animation.init("marquee-right")
    .propUnit(.translateX, -100, 0, .percent)
    .easing(.linear)
    .infinite();

pub const animateUp = Vapor.Animation.init("marquee-up")
    .propUnit(.translateY, 0, -100, .percent)
    .easing(.linear)
    .infinite();

pub const animateDown = Vapor.Animation.init("marquee-down")
    .propUnit(.translateY, -100, 0, .percent)
    .easing(.linear)
    .infinite();

// ============================================================================
// State
// ============================================================================

var marquees: std.AutoHashMap(usize, *Marquee) = undefined;

pub fn new() void {
    marquees = std.AutoHashMap(usize, *Marquee).init(Vapor.arena(.persist));
    animateLeft.build();
    animateRight.build();
    animateUp.build();
    animateDown.build();
    // Vapor.injectCSS(
    //     \\.marquee-viewport:hover .marquee-group {
    //     \\  animation-play-state: paused;
    //     \\}
    // );
}

// ============================================================================
// Marquee struct
// ============================================================================

const Marquee = @This();

options: Options,
container: Vapor.Builder(.pure),
strip: Vapor.Builder(.pure),
group: Vapor.Builder(.pure),

pub fn render(options: Options) *Marquee {
    const is_vertical = options.direction == .up or options.direction == .down;

    const container = Row()
        .width(.percent(100))
        .height(.percent(100))
        .center()
        .hoverTarget("marquee-group", .{
            .animation_play_state = .paused,
        })
        .scroll(.none());

    const strip = if (is_vertical) Stack() else Row();

    const group = blk: {
        const g = (if (is_vertical) Stack() else Row())
            .class("marquee-group")
            .inlineStyle("animation-duration: {d}ms; flex-shrink: 0; animation-name: {s}; flex-direction: {s}; padding-right: {d}px; padding-bottom:{d}px;", .{
                options.speed_ms,
                animName(options.direction),
                if (is_vertical) "column" else "row",
                if (!is_vertical) options.gap else 0,
                if (is_vertical) options.gap else 0,
            })
            .animation(animName(options.direction))
            .spacing(options.gap);
        break :blk g;
    };

    const m = Vapor.arena(.persist).create(Marquee) catch unreachable;
    m.* = .{
        .options = options,
        .container = container,
        .strip = strip,
        .group = group,
    };
    return m;
}

pub fn children(self: *const Marquee, _: void) void {
    self.end();
}

/// Finalize the marquee with the default item renderer. Only runs when
/// Component() was not called.
pub fn end(self: *const Marquee) void {
    // User's children block has finished — first group is fully populated
    self.group.close();
    // Now clone the first group N-1 more times into the strip
    const extras = if (self.options.repeat > 0) self.options.repeat - 1 else 0;
    for (0..extras) |_| {
        self.group.clone();
    }
    self.strip.close();
    self.container.close();
}

// ============================================================================
// Internal: shared layout computation
// ============================================================================

fn animName(direction: Direction) []const u8 {
    return switch (direction) {
        .left => "marquee-left",
        .right => "marquee-right",
        .up => "marquee-up",
        .down => "marquee-down",
    };
}
