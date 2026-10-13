const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Box;
const Button = Vapor.Button;

var background: Vapor.Types.Color = .palette(.background);
var border: Vapor.Types.BorderGrouped = .l(1, .palette(.border_color_light));
var handle_bar_color: Vapor.Types.Color = .palette(.border_color_light);
var starting_width: f32 = 128 + 256;

var animateEnterRight: Vapor.Animation = undefined;
var animateExitRight: Vapor.Animation = undefined;
var animateEnterLeft: Vapor.Animation = undefined;
var animateExitLeft: Vapor.Animation = undefined;
var animateEnterTop: Vapor.Animation = undefined;
var animateExitTop: Vapor.Animation = undefined;
var animateEnterBottom: Vapor.Animation = undefined;
var animateExitBottom: Vapor.Animation = undefined;

const animateBackgroundEnter = Vapor.Animation.init("opaque-sheet-background-enter")
    .prop(.opacity, 0, 1)
    .duration(100)
    .easing(.easeInOut);

const animateBackgroundExit = Vapor.Animation.init("opaque-sheet-background-exit")
    .prop(.opacity, 1, 0)
    .duration(100)
    .easing(.easeInOut);

const SheetMode = enum {
    push,
    overlay,
};

const Sheet = @This();
closed: bool = true,
direction: SheetDirection = .right,
content: ?*const fn (*Sheet) void = null,
binded: Vapor.Binded = .{},
draggable: Vapor.Draggable = .{},
size: f32 = 128 + 256,
max_width: f32 = 512,
mode: SheetMode = .overlay,
on_close: ?*const fn (*Sheet) void = null,

pub fn new() void {
    animateEnterRight = Vapor.Animation.init("opaque-sheet-enter-right")
        .propUnit(.right, -starting_width, 0, .px)
        .duration(100)
        .easing(.easeInOut);
    animateEnterRight.build();

    animateExitRight = Vapor.Animation.init("opaque-sheet-exit-right")
        .propUnit(.right, 0, -starting_width, .px)
        .duration(100)
        .easing(.easeInOut);
    animateExitRight.build();

    animateEnterLeft = Vapor.Animation.init("opaque-sheet-enter-left")
        .propUnit(.left, -starting_width, 0, .px)
        .duration(100)
        .easing(.easeInOut);
    animateEnterLeft.build();

    animateExitLeft = Vapor.Animation.init("opaque-sheet-exit-left")
        .propUnit(.left, 0, -starting_width, .px)
        .duration(100)
        .easing(.easeInOut);
    animateExitLeft.build();

    animateBackgroundEnter.build();
    animateBackgroundExit.build();

    animateEnterTop = Vapor.Animation.init("opaque-sheet-enter-top")
        .propUnit(.top, -starting_width, 0, .px)
        .duration(100)
        .easing(.easeInOut);
    animateEnterTop.build();

    animateExitTop = Vapor.Animation.init("opaque-sheet-exit-top")
        .propUnit(.top, 0, -starting_width, .px)
        .duration(100)
        .easing(.easeInOut);
    animateExitTop.build();

    animateEnterBottom = Vapor.Animation.init("opaque-sheet-enter-bottom")
        .propUnit(.bottom, -starting_width, 0, .px)
        .duration(100)
        .easing(.easeInOut);
    animateEnterBottom.build();

    animateExitBottom = Vapor.Animation.init("opaque-sheet-exit-bottom")
        .propUnit(.bottom, 0, -starting_width, .px)
        .duration(100)
        .easing(.easeInOut);
    animateExitBottom.build();
}

pub const SheetDirection = enum {
    left,
    right,
    bottom,
    top,
};

pub fn init(direction: SheetDirection) Sheet {
    return Sheet{
        .direction = direction,
        .draggable = .{
            .on_drag = onDrag,
        },
    };
}

pub fn close(sheet: *Sheet) void {
    sheet.closed = true;
    if (sheet.on_close) |on_close| {
        on_close(sheet);
    }
}

pub fn open(sheet: *Sheet) void {
    sheet.closed = false;
}

pub fn toggle(sheet: *Sheet) void {
    sheet.closed = !sheet.closed;
}

fn onDrag(draggable: *Vapor.Draggable, _: *Vapor.Event) void {
    const sheet: *Sheet = @fieldParentPtr("draggable", draggable);
    if (sheet.direction == .right or sheet.direction == .left) {
        sheet.size += draggable.movement_x;
    } else if (sheet.direction == .bottom) {
        sheet.size += -draggable.movement_y;
    } else if (sheet.direction == .top) {
        sheet.size += draggable.movement_y;
    }
    if (sheet.size > sheet.max_width) sheet.size = sheet.max_width;
    if (sheet.direction == .right or sheet.direction == .left) {
        sheet.binded.mutateAttribute(.{ .width = .{ .value = sheet.size, .unit = .px } });
    } else {
        sheet.binded.mutateAttribute(.{ .height = .{ .value = sheet.size, .unit = .px } });
    }
}

fn getHandleBarPosition(sheet: *Sheet) Vapor.Types.Position {
    return switch (sheet.direction) {
        .right => .tl(.percent(45), .px(-4), .absolute),
        .left => .tr(.percent(45), .px(-4), .absolute),
        .top => .br(.px(-4), .percent(45), .absolute),
        .bottom => .tr(.px(-4), .percent(47.5), .absolute),
    };
}

fn HandleBar(sheet: *Sheet) void {
    Box()
        .createDraggable(&sheet.draggable)
        .width(if (sheet.direction == .right or sheet.direction == .left) .px(8) else .percent(5))
        .height(if (sheet.direction == .top or sheet.direction == .bottom) .px(8) else .percent(5))
        .border(.{
            .thickness = .none,
            .radius = .all(99),
        })
        .background(handle_bar_color)
        .pos(getHandleBarPosition(sheet))
        .cursor(if (sheet.direction == .right or sheet.direction == .left) .ew_resize else .ns_resize)
        // .layout(.center)
        .children({});
}

fn getAnimationEnter(sheet: *Sheet) []const u8 {
    switch (sheet.direction) {
        .right => return "opaque-sheet-enter-right",
        .left => return "opaque-sheet-enter-left",
        .top => return "opaque-sheet-enter-top",
        .bottom => return "opaque-sheet-enter-bottom",
    }
}

fn getAnimationExit(sheet: *Sheet) []const u8 {
    switch (sheet.direction) {
        .right => return "opaque-sheet-exit-right",
        .left => return "opaque-sheet-exit-left",
        .top => return "opaque-sheet-exit-top",
        .bottom => return "opaque-sheet-exit-bottom",
    }
}

fn getPosition(sheet: *Sheet) Vapor.Types.Position {
    return switch (sheet.direction) {
        .right => .tr(.percent(0), .percent(0), .fixed),
        .left => .tl(.percent(0), .percent(0), .fixed),
        .top => .tl(.percent(0), .percent(0), .fixed),
        .bottom => .bl(.percent(0), .percent(0), .fixed),
    };
}

fn mount(sheet: *Sheet) void {
    _ = Vapor.lib.addGlobalListenerCtx(.keydown, escape, .{sheet});
}

fn escape(sheet: *Sheet, evt: *Vapor.Event) void {
    const key = evt.key();
    if (std.mem.eql(u8, key, "Escape")) {
        evt.preventDefault();
        sheet.closed = true;
    }
}

pub fn render(sheet: *Sheet) void {
    if (sheet.closed) {
        Vapor.Null();
        Vapor.Null();
        return;
    }
    if (sheet.mode == .overlay) {
        Box()
            .animationEnter("opaque-sheet-background-enter")
            .animationExit("opaque-sheet-background-exit")
            .background(.transparentizeHex(.black, 0.05))
            .blur(1)
            .size(.full)
            .pos(.tl(.px(0), .px(0), .fixed))
            .zIndex(999)
            .layout(.center)
            .children({
            Button(close, .{sheet})
                // .background(.transparentizeHex(.black, 0.3))
                .size(.full)
                .pos(.tl(.px(0), .px(0), .fixed))
                .layout(.center)
                .end();
        });
    } else {
        Vapor.Null();
    }
    Box()
        .onMount(mount, .{sheet})
        .pos(getPosition(sheet))
        .ref(&sheet.binded)
        .zIndex(9999)
        .animationEnter(getAnimationEnter(sheet))
        .animationExit(getAnimationExit(sheet))
        .width(if (sheet.direction == .right or sheet.direction == .left) .px(sheet.size) else .percent(100))
        .height(if (sheet.direction == .top or sheet.direction == .bottom) .px(sheet.size) else .percent(100))
        .background(background)
        .border(border)
        .layout(.top_left)
        .zIndex(1000)
        .children({
        HandleBar(sheet);
        if (sheet.content) |content| {
            content(sheet);
        }
    });
}
