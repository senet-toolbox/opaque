//! A one-time code: a row of boxes, one character in each.
//!
//!   var code: []const u8 = "";
//!   CodeInput.render(&code, .{ .label = "Verification code", .on_complete = verify });
//!
//! One field lies over the boxes and takes the typing, so pasting the code,
//! a phone filling it in from a text message (autocomplete=one-time-code),
//! and Backspace all work as in any field. The boxes draw what it holds.
//! `code` must outlive the render: a module-level var.

const std = @import("std");
const Vapor = @import("vapor");
const Focus = @import("Focus.zig");
const Box = Vapor.Box;
const Row = Vapor.Row;
const Text = Vapor.Text;
const TextField = Vapor.TextField;

pub const Options = struct {
    /// Names the field for screen readers.
    label: []const u8 = "Verification code",
    /// How many characters the code has.
    length: u8 = 6,
    /// Digits only, on a phone's number pad.
    numeric: bool = true,
    /// Called with the code once every box is filled.
    on_complete: ?*const fn (code: []const u8) void = null,
};

/// The boxes' borders: a share of the text colour, plain in both themes.
pub var border_color: Vapor.Types.Color = .transparentize(.palette(.text_color), 0.2);
pub var text_color: Vapor.Types.Color = .palette(.text_color);
/// A box's width, in pixels; its height is a little more.
pub var box_size: f32 = 44;

/// The code whose field has the focus, so its next box is marked.
var focused: ?*const []const u8 = null;

pub fn render(code: *[]const u8, options: Options) void {
    const length: usize = options.length;
    const is_focused = focused == code;
    // The box the next character goes in; the last once all are filled.
    const next = @min(code.len, length -| 1);
    const gap: f32 = 8;

    Box()
        .pos(.relative)
        .width(.fit)
        .children({
        Row()
            .ariaHidden(true)
            .spacing(@intFromFloat(gap))
            .layout(.left_center)
            .children({
            for (0..length) |i| {
                const marked = is_focused and i == next;
                Box()
                    .width(.px(box_size))
                    .height(.px(box_size + 8))
                    .layout(.center)
                    .border(.round(if (marked) text_color else border_color, .all(10)))
                    .shadow(if (marked) Vapor.Types.Shadow.insetSpread(0, 0, 0, 1, text_color) else null)
                    .duration(120)
                    .children({
                    if (i < code.len) {
                        Text(code.*[i .. i + 1])
                            .font(22, 500, text_color)
                            .fontFamily("IBM Plex Mono,monospace")
                            .end();
                    } else if (marked) {
                        // The caret, where the next character goes.
                        Box()
                            .width(.px(2))
                            .height(.px(22))
                            .background(text_color)
                            .animation("opaque-code-caret")
                            .children({});
                    }
                });
            }
        });
        TextField(.string)
            .bind(code)
            .ariaLabel(options.label)
            .attribute("inputmode", if (options.numeric) "numeric" else "text")
            .attribute("autocomplete", "one-time-code")
            .attribute("autocapitalize", "off")
            .attribute("spellcheck", "false")
            // No maxlength: it would cut a pasted "123 456" before the
            // space is cleaned out. `clean` keeps `length` characters.
            .onChange(changed, .{ code, options })
            .onEvent(.focus, setFocus, .{code})
            .onEvent(.blur, clearFocus, .{code})
            // Over the boxes, taking the clicks; its own text and caret
            // unseen, the boxes draw them. 16px: iOS zooms into smaller.
            .pos(.tl(.px(0), .px(0), .absolute))
            .width(.percent(100))
            .height(.percent(100))
            .background(.transparent)
            .border(.none)
            .outline(.none, null)
            .inlineStyle("color: transparent; caret-color: transparent; font-size: 16px; padding: 0; z-index: 1; cursor: text;", .{})
            .end();
    });
}

/// A code typed or pasted with other characters keeps only what fits: for
/// a numeric code, its digits. Returns `code` itself when it all fits.
pub fn clean(code: []const u8, numeric: bool, length: usize, buf: []u8) []const u8 {
    var n: usize = 0;
    for (code) |c| {
        if (n == length or n == buf.len) break;
        const keep = if (numeric) std.ascii.isDigit(c) else std.ascii.isAlphanumeric(c);
        if (!keep) continue;
        buf[n] = c;
        n += 1;
    }
    if (n == code.len) return code;
    return buf[0..n];
}

var clean_buf: [32]u8 = undefined;

fn changed(code: *[]const u8, options: Options, _: *Vapor.Event) void {
    code.* = clean(code.*, options.numeric, options.length, &clean_buf);
    if (code.len == options.length) {
        if (options.on_complete) |cb| cb(code.*);
    }
}

fn setFocus(code: *[]const u8, _: *Vapor.Event) void {
    focused = code;
}

fn clearFocus(code: *[]const u8, _: *Vapor.Event) void {
    if (focused == code) focused = null;
}

const caret = Vapor.Animation.init("opaque-code-caret")
    .prop(.opacity, 1, 0)
    .duration(530)
    .dir(.alternate)
    .infinite();

/// Registers the caret's blink; once, at startup (Opaque.new does it).
pub fn new() void {
    caret.build();
}

test "a pasted code keeps the characters it can hold" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("123456", clean("123 456", true, 6, &buf));
    try std.testing.expectEqualStrings("123456", clean("1234567", true, 6, &buf));
    try std.testing.expectEqualStrings("12", clean("1a2", true, 6, &buf));
    try std.testing.expectEqualStrings("AB12", clean("AB-12", false, 6, &buf));
}
