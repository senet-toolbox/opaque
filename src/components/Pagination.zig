//! Page numbers for a long list: previous and next, the first and last
//! pages, and those beside the one you are on.
//!
//!   var page: usize = 0; // the first page
//!   Pagination.render(&page, 12, .{});
//!
//! Every page count shows the same number of buttons, so the row does not
//! change width as you move through it. Screen readers hear "Page 4", and
//! which page is the current one.

const std = @import("std");
const Vapor = @import("vapor");
const Focus = @import("Focus.zig");
const Box = Vapor.Box;
const List = Vapor.List;
const ListItem = Vapor.ListItem;
const Button = Vapor.Button;
const Text = Vapor.Text;

pub const Options = struct {
    /// Names the pages for screen readers.
    label: []const u8 = "Pagination",
    /// Pages shown on each side of the current one.
    siblings: usize = 1,
    /// Called with the new page, counted from 0.
    on_change: ?*const fn (page: usize) void = null,
};

pub var text_color: Vapor.Types.Color = .palette(.text_color);
pub var muted_color: Vapor.Types.Color = .transparentize(.palette(.text_color), 0.6);
pub var hover_background: Vapor.Types.Color = .palette(.highlight_color);
/// The current page: filled, its number in `current_text`.
pub var current_background: Vapor.Types.Color = .palette(.text_color);
pub var current_text: Vapor.Types.Color = .palette(.background);
/// A button's width and height, in pixels. At 32 the row fits a 375px
/// phone.
pub var size: f32 = 32;

/// What one slot of the row shows: a page, counted from 0, or a gap.
pub const Slot = union(enum) {
    page: usize,
    gap,
};

/// The row for `count` pages with `page` current: the first and last pages,
/// `siblings` either side of the current one, and gaps between. Always
/// `2 * siblings + 5` slots once there are that many pages.
pub fn slots(page: usize, count: usize, siblings: usize, buf: []Slot) []const Slot {
    const total = 2 * siblings + 5;
    var n: usize = 0;
    if (count <= total) {
        for (0..count) |i| {
            buf[n] = .{ .page = i };
            n += 1;
        }
        return buf[0..n];
    }
    // The window of siblings, held clear of both ends so the slot count
    // stays the same.
    const first = @max(@min(page -| siblings, count - 3 - 2 * siblings), 2);
    const last = first + 2 * siblings;
    buf[n] = .{ .page = 0 };
    n += 1;
    buf[n] = if (first > 2) .gap else .{ .page = 1 };
    n += 1;
    for (first..last + 1) |i| {
        buf[n] = .{ .page = i };
        n += 1;
    }
    buf[n] = if (last < count - 3) .gap else .{ .page = count - 2 };
    n += 1;
    buf[n] = .{ .page = count - 1 };
    n += 1;
    return buf[0..n];
}

pub fn render(page: *usize, count: usize, options: Options) void {
    if (count == 0) return;
    if (page.* >= count) page.* = count - 1;
    var buf: [64]Slot = undefined;
    const siblings = @min(options.siblings, (buf.len - 5) / 2);
    const row = slots(page.*, count, siblings, &buf);

    Box()
        .a11y(Vapor.Accessibility.init().setRole(.navigation).setLabel(options.label))
        .children({
        List()
            .layout(.left_center)
            .wrap(.wrap)
            // None: the buttons are see-through but the current page's, and
            // without it nine slots fit a 375px phone.
            .spacing(0)
            .padding(.all(0))
            .listStyle(.none)
            .children({
            ListItem().children({
                step(page, count, options, false);
            });
            for (row) |slot| {
                ListItem().children({
                    switch (slot) {
                        .page => |p| pageButton(page, p, options),
                        .gap => Box()
                            .ariaHidden(true)
                            .width(.px(size))
                            .height(.px(size))
                            .layout(.center)
                            .children({
                            Text("…").font(14, 400, muted_color).end();
                        }),
                    }
                });
            }
            ListItem().children({
                step(page, count, options, true);
            });
        });
    });
}

fn goTo(page: *usize, to: usize, on_change: ?*const fn (usize) void) void {
    if (page.* == to) return;
    page.* = to;
    if (on_change) |cb| cb(to);
}

fn pageButton(page: *usize, p: usize, options: Options) void {
    const current = page.* == p;
    const button = Button(goTo, .{ page, p, options.on_change })
        .ariaLabel(Vapor.fmtln("Page {d}", .{p + 1}))
        .width(.fit)
        .minWidth(.px(size))
        .height(.px(size))
        .padding(.horizontal(6))
        .layout(.center)
        .radius(.all(8))
        .cursor(if (current) .default else .pointer)
        .background(if (current) current_background else .transparent)
        .duration(120)
        .focusVisible(Focus.ring());
    (if (current) button.attribute("aria-current", "page") else button.hover(.{ .background = hover_background })).children({
        Text(Vapor.fmtln("{d}", .{p + 1}))
            .font(14, if (current) 600 else 400, if (current) current_text else text_color)
            .inlineStyle("font-variant-numeric: tabular-nums;", .{})
            .end();
    });
}

/// Previous, or with `forward` next: dimmed and out of reach at the end.
fn step(page: *usize, count: usize, options: Options, forward: bool) void {
    const at_end = if (forward) page.* + 1 >= count else page.* == 0;
    const to = if (at_end) page.* else if (forward) page.* + 1 else page.* - 1;
    Button(goTo, .{ page, to, options.on_change })
        .a11y(Vapor.Accessibility.init().setDisabled(at_end))
        .ariaLabel(if (forward) "Next page" else "Previous page")
        .width(.px(size))
        .height(.px(size))
        .layout(.center)
        .radius(.all(8))
        .opacity(if (at_end) 0.4 else 1)
        .cursor(if (at_end) .default else .pointer)
        .duration(120)
        .hover(if (at_end) .{} else .{ .background = hover_background })
        .focusVisible(Focus.ring())
        .children({
        Text(if (forward) "›" else "‹").ariaHidden(true).font(20, 400, text_color).end();
    });
}

fn pages(row: []const Slot, out: []u8) []const u8 {
    var n: usize = 0;
    for (row, 0..) |slot, i| {
        if (i > 0) {
            out[n] = ' ';
            n += 1;
        }
        const s = switch (slot) {
            .page => |p| std.fmt.bufPrint(out[n..], "{d}", .{p + 1}) catch unreachable,
            .gap => std.fmt.bufPrint(out[n..], "…", .{}) catch unreachable,
        };
        n += s.len;
    }
    return out[0..n];
}

test "the row keeps the first and last pages, the current one's neighbours, and its width" {
    var buf: [64]Slot = undefined;
    var out: [128]u8 = undefined;
    try std.testing.expectEqualStrings("1 2 3 4 5", pages(slots(0, 5, 1, &buf), &out));
    try std.testing.expectEqualStrings("1 2 3 4 5 6 7", pages(slots(3, 7, 1, &buf), &out));
    try std.testing.expectEqualStrings("1 2 3 4 5 … 12", pages(slots(0, 12, 1, &buf), &out));
    try std.testing.expectEqualStrings("1 2 3 4 5 … 12", pages(slots(3, 12, 1, &buf), &out));
    try std.testing.expectEqualStrings("1 … 4 5 6 … 12", pages(slots(4, 12, 1, &buf), &out));
    try std.testing.expectEqualStrings("1 … 8 9 10 11 12", pages(slots(8, 12, 1, &buf), &out));
    try std.testing.expectEqualStrings("1 … 8 9 10 11 12", pages(slots(11, 12, 1, &buf), &out));
    try std.testing.expectEqualStrings("1 … 4 5 6 7 8 … 20", pages(slots(5, 20, 2, &buf), &out));
}
