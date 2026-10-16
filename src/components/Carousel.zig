// ============================================================================
// Carousel.zig — click + swipe carousel component
// ============================================================================
//
// Usage:
//
//   Carousel.render(.{ .id = "hero" }).children({
//       for (slides) |slide| {
//           Stack().width(.px(480)).height(.px(280)).children({
//               Text(slide.title).end();
//           });
//       }
//   });
//
// A stable `id` is REQUIRED so the carousel remembers its index across renders.

const std = @import("std");
const Vapor = @import("vapor");
const Row = Vapor.Row;
const Stack = Vapor.Stack;
const Text = Vapor.Text;
const Button = Vapor.Button;
const Draggable = Vapor.Draggable;

// ============================================================================
// Types
// ============================================================================

pub const Options = struct {
    /// Stable id for state lookup. REQUIRED.
    id: []const u8,
    /// Number of slides. Needed for index clamping, dots, and arrow logic.
    /// (The user renders the slides themselves in the children block.)
    count: usize,
    /// Width of the viewport (and each slide) in pixels.
    viewport_width: f32 = 480,
    /// Height of the viewport in pixels.
    viewport_height: f32 = 280,
    /// Stride between slide starts (item_width + gap), in pixels.
    /// User must render slides with matching width and gap for this to align.
    stride: f32 = 496, // e.g. 480 + 16
    /// Wrap around at the ends.
    loop: bool = true,
    /// Show prev / next arrow buttons.
    show_arrows: bool = true,
    /// Show dot indicators below.
    show_dots: bool = true,
    /// Minimum drag distance (px) to advance one slide on release.
    swipe_threshold: f32 = 60,
    /// Snap transition duration in ms.
    transition_ms: u32 = 350,
};

// ============================================================================
// State
// ============================================================================

var carousels: std.AutoHashMap(usize, *Carousel) = undefined;

pub fn new() void {
    carousels = std.AutoHashMap(usize, *Carousel).init(Vapor.arena(.persist));
}

// ============================================================================
// Carousel struct
// ============================================================================

const Carousel = @This();

options: Options,
index: usize = 0,
drag_offset: f32 = 0,
is_dragging: bool = false,
draggable: Draggable,
track: *Vapor.Element,
container: Vapor.Builder(.pure),
viewport: Vapor.Builder(.pure),
track_row: Vapor.Builder(.pure),

// ============================================================================
// Transform helpers
// ============================================================================

fn currentOffset(c: *const Carousel) f32 {
    const idx_f: f32 = @floatFromInt(c.index);
    return -(idx_f * c.options.stride) + c.drag_offset;
}

fn applyTransform(c: *Carousel, animate: bool) void {
    const transition_str = if (animate)
        Vapor.frame.fmt("transform {d}ms cubic-bezier(0.22, 1, 0.36, 1)", .{c.options.transition_ms})
    else
        "none";
    c.track.mutateStyleString("transition", transition_str);
    c.track.mutateStyleString(
        "transform",
        Vapor.frame.fmt("translate3d({d}px, 0, 0)", .{currentOffset(c)}),
    );
}

// ============================================================================
// Drag handlers
// ============================================================================

fn onDragStart(d: *Draggable, _: *Vapor.Event) void {
    const c: *Carousel = @alignCast(@fieldParentPtr("draggable", d));
    c.is_dragging = true;
    c.drag_offset = 0;
    applyTransform(c, false);
}

fn onDrag(d: *Draggable, _: *Vapor.Event) void {
    const c: *Carousel = @alignCast(@fieldParentPtr("draggable", d));
    c.drag_offset = d.delta_x;
    applyTransform(c, false);
}

fn onDragEnd(d: *Draggable, _: *Vapor.Event) void {
    const c: *Carousel = @alignCast(@fieldParentPtr("draggable", d));
    c.is_dragging = false;

    const dx = d.delta_x;
    const last_idx = c.options.count - 1;

    if (dx <= -c.options.swipe_threshold) {
        if (c.index < last_idx) c.index += 1 else if (c.options.loop) c.index = 0;
    } else if (dx >= c.options.swipe_threshold) {
        if (c.index > 0) c.index -= 1 else if (c.options.loop) c.index = last_idx;
    }

    c.drag_offset = 0;
    d.delta_x = 0;
    d.delta_y = 0;
    d.current_x = 0;
    d.current_y = 0;
    d.x = 0;
    d.y = 0;
    applyTransform(c, true);
    Vapor.cycle();
}

// ============================================================================
// Click handlers
// ============================================================================

fn goPrev(c: *Carousel) void {
    const last_idx = c.options.count - 1;
    if (c.index > 0) c.index -= 1 else if (c.options.loop) c.index = last_idx;
    applyTransform(c, true);
}

fn goNext(c: *Carousel) void {
    const last_idx = c.options.count - 1;
    if (c.index < last_idx) c.index += 1 else if (c.options.loop) c.index = 0;
    applyTransform(c, true);
}

fn goTo(c: *Carousel, index: usize) void {
    c.index = index;
    applyTransform(c, true);
}

// ============================================================================
// Public API
// ============================================================================

pub fn render(options: Options) *Carousel {
    std.debug.assert(options.id.len > 0); // id is required

    // Open the container hierarchy: container -> viewport -> track_row.
    // After this returns, track_row is the open parent — the user's
    // children block lands inside it.
    const stable_id = Vapor.utils.hashKey(options.id);

    // Look up or create persistent state
    const c = carousels.get(stable_id) orelse blk: {
        const new_c = Vapor.arena(.persist).create(Carousel) catch unreachable;
        const tb = Vapor.arena(.persist).create(Vapor.Element) catch unreachable;
        tb.* = .{};
        new_c.* = .{
            .options = options,
            .draggable = .{
                .on_drag_start = onDragStart,
                .on_drag = onDrag,
                .on_drag_end = onDragEnd,
                .config = .{ .axis = .x },
            },
            .track = tb,
            .container = undefined,
            .viewport = undefined,
            .track_row = undefined,
        };
        carousels.put(stable_id, new_c) catch unreachable;
        break :blk new_c;
    };

    // Refresh non-state options each render.
    c.options = options;

    // Clamp index if items shrank.
    if (options.count == 0) {
        c.index = 0;
    } else if (c.index >= options.count) {
        c.index = options.count - 1;
    }

    const initial_offset = currentOffset(c);

    c.container = Stack()
        .width(.px(options.viewport_width))
        .direction(.column)
        .spacing(12);

    // Note: we keep nesting open as we build down to track_row.
    // The user's children block will emit into track_row.
    // arrows + dots are emitted in `end()` after the user closes their slides.

    // Open viewport inside container
    c.viewport = Row()
        .width(.px(options.viewport_width))
        .height(.px(options.viewport_height))
        .scroll(.none())
        .pos(.relative)
        .createDraggable(&c.draggable)
        .inlineStyle("touch-action: pan-y; cursor: grab; user-select: none; overflow: hidden;", .{});

    // Open track inside viewport — this is what the user's slides land in
    c.track_row = Row()
        .ref(c.track)
        .inlineStyle(
        "transform: translate3d({d}px, 0, 0); transition: transform {d}ms cubic-bezier(0.22, 1, 0.36, 1); will-change: transform; gap: {d}px;",
        .{ initial_offset, options.transition_ms, options.stride - options.viewport_width },
    );

    return c;
}

pub fn children(self: *Carousel, _: void) void {
    self.end();
}

pub fn end(self: *Carousel) void {
    // User's slides are now in track_row. Close it.
    self.track_row.close();

    // Still inside viewport — emit arrows here so they overlay the track.
    if (self.options.show_arrows and self.options.count > 1) {
        renderArrows(self);
    }
    self.viewport.close();

    // Now inside container — emit dots below the viewport.
    if (self.options.show_dots and self.options.count > 1) {
        renderDots(self);
    }
    self.container.close();
}

// ============================================================================
// Internal rendering for arrows and dots
// ============================================================================

fn renderArrows(c: *Carousel) void {
    // Without looping, the arrow that would go past an end does nothing.
    const at_first = !c.options.loop and c.index == 0;
    const at_last = !c.options.loop and c.index + 1 >= c.options.count;
    Row()
        .pos(.absolute)
        .inlineStyle(
            "top: 50%; left: 0; right: 0; transform: translateY(-50%); pointer-events: none; padding: 0 12px; display: flex; justify-content: space-between; align-items: center;",
            .{},
        )
        .children({
        Button(goPrev, .{c})
            .a11y(Vapor.Accessibility.init().setDisabled(at_first))
            .ariaLabel("Previous slide")
            .opacity(if (at_first) 0.3 else 1)
            .inlineStyle("pointer-events: auto;", .{})
            .width(.px(40)).height(.px(40))
            .layout(.center)
            .background(.transparentize(.black, 0.4))
            .border(.round(.transparent, .all(99)))
            .pointer()
            .children({
            Text("‹").font(24, 700, .white).fontFamily("IBM Plex Sans,monospace").end();
        });
        Button(goNext, .{c})
            .a11y(Vapor.Accessibility.init().setDisabled(at_last))
            .ariaLabel("Next slide")
            .opacity(if (at_last) 0.3 else 1)
            .inlineStyle("pointer-events: auto;", .{})
            .width(.px(40)).height(.px(40))
            .layout(.center)
            .background(.transparentize(.black, 0.4))
            .border(.round(.transparent, .all(99)))
            .pointer()
            .children({
            Text("›").font(24, 700, .white).fontFamily("IBM Plex Sans,monospace").end();
        });
    });
}

fn renderDots(c: *Carousel) void {
    Row().width(.percent(100)).layout(.center).spacing(8).children({
        for (0..c.options.count) |i| {
            const active = (i == c.index);
            Button(goTo, .{ c, i })
                // The dot for the slide on show reads as pressed.
                .a11y(Vapor.Accessibility.init().setPressed(if (active) .true_val else .false_val))
                .ariaLabel(Vapor.fmtln("Go to slide {d}", .{i + 1}))
                .width(.px(if (active) 24 else 8))
                .height(.px(8))
                .background(if (active) .palette(.tint) else .palette(.border_color_light))
                .border(.round(.transparent, .all(99)))
                .pointer()
                .children({});
        }
    });
}
