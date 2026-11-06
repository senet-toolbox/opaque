const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Box;
const Button = Vapor.Button;
const OverlayManager = @import("OverlayManager.zig");

const Alert = @This();

const animateEnter = Vapor.Animation.init("opaque-dialog-enter")
    .prop(.opacity, 0, 1)
    .prop(.scale, 0.9, 1)
    .duration(200)
    .easing(.easeInOut);

const animateExit = Vapor.Animation.init("opaque-dialog-exit")
    .prop(.opacity, 1, 0)
    .prop(.scale, 1, 0.9)
    .duration(200)
    .easing(.easeInOut);

// const animateExitBackground = Vapor.Animation.init("opaque-dialog-exit-background")
//     .prop(.opacity, 1, 0)
//     .duration(200)
//     .easing(.easeInOut);

pub fn new() void {
    animateEnter.build();
    animateExit.build();
    // animateExitBackground.build();
}

content: ?*const fn (*Alert) void = null,
closed: bool = true,
background: Vapor.Types.Color = .palette(.background),
border: Vapor.Types.Border = .round(.palette(.border_color_light), .all(12)),
/// Around the content.
padding: Vapor.Types.Padding = .all(24),
/// Its widest, in pixels; on a narrow screen it keeps 16px from each edge.
max_width: f32 = 440,
/// Over the page behind it.
backdrop: Vapor.Types.Color = .transparentize(.black, 0.4),
on_enter: ?*const fn (*Alert) void = null,
/// Called when it is dismissed: Escape, or a click outside.
on_close: ?*const fn () void = null,
/// Names it for screen readers.
label: []const u8 = "Alert",
/// The button that opens it: bind it with `.ref(&alert.trigger)` and the
/// focus goes back to it when the alert closes.
trigger: Vapor.Element = .{},
/// The alert's panel, which takes the focus when it opens.
panel: Vapor.Element = .{},

pub fn init(content: ?*const fn (*Alert) void) Alert {
    return Alert{
        .content = content,
    };
}

pub fn open(alert: *Alert) void {
    alert.closed = false;
}

pub fn close(alert: *Alert) void {
    alert.closed = true;
    // Back to the button that opened it, if it was bound.
    if (alert.trigger._get_id() != null) Vapor.onLayout(focusTrigger, .{alert});
}

fn focusTrigger(alert: *Alert) void {
    alert.trigger.focus();
}

/// Escape or a click outside: closes it and tells on_close.
fn dismiss(alert: *Alert) void {
    alert.close();
    if (alert.on_close) |on_close| on_close();
}

fn mount(alert: *Alert) void {
    OverlayManager.register(.keydown, handleKeyPress, .{alert});
    // The focus moves into the alert, so keys and screen readers are there.
    Vapor.onLayout(focusPanel, .{alert});
}

fn focusPanel(alert: *Alert) void {
    alert.panel.focus();
}

fn destroy(alert: *Alert) void {
    OverlayManager.unregister(.keydown, alert);
}

fn handleKeyPress(alert: *Alert, evt: *Vapor.Event) void {
    if (alert.closed) return;
    const key = evt.key();
    if (std.mem.eql(u8, key, "Escape")) {
        evt.preventDefault();
        alert.dismiss();
    }
    if (std.mem.eql(u8, key, "Enter")) {
        evt.preventDefault();
        if (alert.on_enter) |on_enter| {
            on_enter(alert);
        }
    }
}

pub fn render(alert: *Alert) void {
    if (alert.closed) return;
    Box()
        .onMount(mount, .{alert})
        .onDestroy(destroy, .{alert})
        .blur(1)
        .background(alert.backdrop)
        .size(.full)
        .pos(.tl(.px(0), .px(0), .fixed))
        .zIndex(999)
        .layout(.center)
        .children({});
    Box()
        .size(.full)
        .pos(.tl(.px(0), .px(0), .fixed))
        .zIndex(999)
        .animationEnter("opaque-dialog-enter")
        .animationExit("opaque-dialog-exit")
        .layout(.center)
        .children({
        // Catches a click outside; the keyboard has Escape instead.
        Button(dismiss, .{alert})
            .ariaHidden(true)
            .tabIndex(-1)
            .size(.full)
            .pos(.tl(.px(0), .px(0), .fixed))
            .size(.full)
            .layout(.center)
            .zIndex(999)
            .children({});
        Box()
            .ref(&alert.panel)
            .a11y(Vapor.Accessibility.alertDialog(alert.label))
            .tabIndex(-1)
            .inlineStyle("outline: none;", .{})
            .background(alert.background)
            .shadow(Vapor.Types.Shadow.init().dropSpread(0, 16, 48, 0, .transparentize(.black, 0.3)))
            .border(alert.border)
            .padding(alert.padding)
            .inlineStyle("width: min({d}px, calc(100vw - 32px)); box-sizing: border-box;", .{alert.max_width})
            .height(.fit)
            .direction(.column)
            .zIndex(1000)
            .children({
            if (alert.content) |content| {
                content(alert);
            }
        });
    });
}
