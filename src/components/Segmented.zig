//! A row of options, one of them chosen: a view, a period, a mode.
//!
//!   var period: usize = 1;
//!   Segmented.render(&period, &.{ "Day", "Week", "Month" }, .{ .label = "Period" });
//!
//! A radio group to the keyboard and to screen readers: Tab stops once, on
//! the chosen option, and the arrow keys move the choice, wrapping round.
//! For a choice that shows a different panel, use Tabs.

const std = @import("std");
const Vapor = @import("vapor");
const Focus = @import("Focus.zig");
const Row = Vapor.Row;
const Button = Vapor.Button;
const Text = Vapor.Text;

pub const Options = struct {
    /// Names the group for screen readers.
    label: []const u8,
    /// Called with the option chosen, counted from 0.
    on_change: ?*const fn (index: usize) void = null,
    /// Stretches across its container, the options sharing the width.
    full_width: bool = false,
};

/// The track behind the options.
pub var track_color: Vapor.Types.Color = .transparentize(.palette(.text_color), 0.07);
/// The chosen option's fill.
pub var chosen_color: Vapor.Types.Color = .palette(.background);
pub var text_color: Vapor.Types.Color = .palette(.text_color);
pub var muted_color: Vapor.Types.Color = .transparentize(.palette(.text_color), 0.65);

pub fn render(chosen: *usize, labels: []const []const u8, options: Options) void {
    if (labels.len == 0) return;
    if (chosen.* >= labels.len) chosen.* = 0;
    const group = Row()
        .a11y(Vapor.Accessibility.radioGroup(options.label))
        .onEvent(.keydown, onKey, .{ chosen, labels.len, options.on_change })
        .layout(.left_center)
        .spacing(2)
        .padding(.all(3))
        .background(track_color)
        .radius(.all(10));
    (if (options.full_width) group.width(.percent(100)) else group.width(.fit)).children({
        for (labels, 0..) |label, i| {
            const on = chosen.* == i;
            Button(pick, .{ chosen, i, options.on_change })
                .id(itemId(chosen, i))
                .a11y(Vapor.Accessibility.init()
                .setRole(.radio)
                .setChecked(if (on) .true_val else .false_val))
                // One tab stop: the chosen option.
                .tabIndex(if (on) 0 else -1)
                .width(if (options.full_width) .grow else .fit)
                .padding(.xy(14, 6))
                .layout(.center)
                .radius(.all(8))
                .background(if (on) chosen_color else .transparent)
                // On the button, so its hover colour reaches the text.
                .textColor(if (on) text_color else muted_color)
                .shadow(if (on) Vapor.Types.Shadow.init().drop(0, 1, 3, .transparentize(.black, 0.15)) else null)
                .cursor(if (on) .default else .pointer)
                .duration(150)
                .hover(if (on) .{} else .{ .text_color = text_color })
                .focusVisible(Focus.ring())
                .children({
                Text(label)
                    .font(14, 500, null)
                    .inlineStyle("white-space: nowrap;", .{})
                    .end();
            });
        }
    });
}

fn itemId(chosen: *usize, i: usize) []const u8 {
    return Vapor.fmtln("segmented-{x}-{d}", .{ @intFromPtr(chosen), i });
}

fn pick(chosen: *usize, i: usize, on_change: ?*const fn (usize) void) void {
    if (chosen.* == i) return;
    chosen.* = i;
    if (on_change) |cb| cb(i);
}

/// The arrow keys move the choice, wrapping round; Home and End go to the
/// first and last. The focus follows the choice.
fn onKey(chosen: *usize, count: usize, on_change: ?*const fn (usize) void, evt: *Vapor.Event) void {
    const key = evt.key();
    const eql = std.mem.eql;
    const to: usize = if (eql(u8, key, "ArrowRight") or eql(u8, key, "ArrowDown"))
        (chosen.* + 1) % count
    else if (eql(u8, key, "ArrowLeft") or eql(u8, key, "ArrowUp"))
        (chosen.* + count - 1) % count
    else if (eql(u8, key, "Home"))
        0
    else if (eql(u8, key, "End"))
        count - 1
    else
        return;
    evt.preventDefault();
    pick(chosen, to, on_change);
    Vapor.onLayout(focusChosen, .{chosen});
}

fn focusChosen(chosen: *usize) void {
    Vapor.lib.focus(itemId(chosen, chosen.*));
}
