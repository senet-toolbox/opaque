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
border: Vapor.Types.BorderGrouped = .round(.hex("#e4e4e4"), .all(12)),
on_enter: ?*const fn (*Alert) void = null,
on_close: ?*const fn () void = null,

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
}

fn evtClose(alert: *Alert, evt: *Vapor.Event) void {
    evt.preventDefault();
    alert.closed = true;
}

fn mount(alert: *Alert) void {
    OverlayManager.register(.keydown, handleKeyPress, .{alert});
}

fn destroy(alert: *Alert) void {
    OverlayManager.unregister(.keydown, alert);
}

fn handleKeyPress(alert: *Alert, evt: *Vapor.Event) void {
    if (alert.closed) return;
    const key = evt.key();
    if (std.mem.eql(u8, key, "Escape")) {
        evt.preventDefault();
        alert.closed = true;
        if (alert.on_close) |on_close| {
            on_close();
        }
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
        Button(close, .{alert})
            .size(.full)
            .pos(.tl(.px(0), .px(0), .fixed))
            .size(.full)
            .layout(.center)
            .zIndex(999)
            .children({});
        Box()
            .background(alert.background)
            .shadow(.glow(30, .transparentizeHex(.black, 0.05)))
            .border(alert.border)
            .width(.fit)
            .height(.fit)
            .layout(.center)
            .zIndex(1000)
            .children({
            if (alert.content) |content| {
                content(alert);
            }
        });
    });
}
