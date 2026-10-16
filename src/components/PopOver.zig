const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Box;
const Button = Vapor.Button;
const Anchor = Vapor.Anchor;

pub var background: Vapor.Types.Color = .palette(.background);
pub var alternate_background: Vapor.Types.Color = .black;
pub var svg_color: Vapor.Types.Color = .black;
pub var border_color: Vapor.Types.Color = .hex("#e4e4e4");
var popovers: std.AutoHashMap(usize, *PopOver) = undefined;
pub var alternate_text_color: Vapor.Types.Color = .white;
pub var border: Vapor.Types.Border = .round(.transparent, .all(6));

pub const animateEnter = Vapor.Animation.init("opaque-popover-enter")
    .prop(.opacity, 0, 1)
    .prop(.scale, 0.9, 1)
    .duration(200)
    .easing(.easeInOut);

pub const animateExit = Vapor.Animation.init("opaque-popover-exit")
    .prop(.opacity, 1, 0)
    .prop(.scaleY, 1, 0.9)
    .duration(100)
    .easing(.easeInOut);

pub fn new() void {
    popovers = std.AutoHashMap(usize, *PopOver).init(Vapor.arena(.persist));
    animateEnter.build();
    animateExit.build();
}

pub const Position = enum {
    top,
    bottom,
    left,
    right,
};

fn getCornerSvg(position: Vapor.Types.AnchorPlacement) []const u8 {
    return switch (position) {
        .top =>
        \\<svg style="position:absolute;
        \\transform: translateX(-50%);
        \\bottom: -6px;
        \\left: 50%;" xmlns="http://www.w3.org/2000/svg" width="16" height="8" viewBox="0 0 16 8">
        \\  <path d="M0 0 L8 8 L16 0 Z" stroke="none"/>
        \\  <path d="M0 0 L8 8" stroke-width="1" stroke-linecap="round" fill="none"/>
        \\  <path d="M16 0 L8 8" stroke-width="1" stroke-linecap="round" fill="none"/>
        \\</svg>
        ,
        .bottom =>
        \\<svg style="position:absolute;
        \\transform: translateX(-50%);
        \\top: -6px;
        \\left: 50%;" xmlns="http://www.w3.org/2000/svg" width="16" height="8" viewBox="0 0 16 8">
        \\  <path d="M0 8 L8 0 L16 8 Z" stroke="none"/>
        \\  <path d="M0 8 L8 0" stroke-width="1" stroke-linecap="round" fill="none"/>
        \\  <path d="M16 8 L8 0" stroke-width="1" stroke-linecap="round" fill="none"/>
        \\</svg>
        ,
        .left =>
        \\<svg style="position:absolute;
        \\transform: translateY(-50%);
        \\right: -6px;
        \\top: 50%;" xmlns="http://www.w3.org/2000/svg" width="8" height="16" viewBox="0 0 8 16">
        \\  <path d="M0 0 L8 8 L0 16 Z" stroke="none"/>
        \\  <path d="M0 0 L8 8" stroke-width="1" stroke-linecap="round" fill="none"/>
        \\  <path d="M0 16 L8 8" stroke-width="1" stroke-linecap="round" fill="none"/>
        \\</svg>
        ,
        .right =>
        \\<svg style="position:absolute;
        \\transform: translateY(-50%);
        \\left: -6px;
        \\top: 50%;" xmlns="http://www.w3.org/2000/svg" width="8" height="16" viewBox="0 0 8 16">
        \\  <path d="M8 0 L0 8 L8 16 Z" stroke="none"/>
        \\  <path d="M8 0 L0 8" stroke-width="1" stroke-linecap="round" fill="none"/>
        \\  <path d="M8 16 L0 8" stroke-width="1" stroke-linecap="round" fill="none"/>
        \\</svg>
        ,
        else => return "",
    };
}

fn getTransformOrigin(position: Vapor.Types.AnchorPlacement) Vapor.Types.TransformOrigin {
    return switch (position) {
        .top => .bottom_center,
        .bottom => .top_center,
        .left => .center_right,
        .right => .center_left,
        else => unreachable,
    };
}

fn getMargin(position: Vapor.Types.AnchorPlacement) Vapor.Types.Margin {
    return switch (position) {
        .top => .{ .bottom = 2 },
        .bottom => .{ .top = 2 },
        .left => .{ .right = 2 },
        .right => .{ .left = 2 },
        .bottom_left => .{ .top = 2 },
        .bottom_right => .{ .top = 2 },
        .top_left => .{ .bottom = 2 },
        .top_right => .{ .bottom = 2 },
        else => unreachable,
    };
}

const PopOver = @This();
options: PopOverOptions,
default: bool = true,

const PopOverOptions = struct {
    stable_id: usize = 0,
    show: bool = false,
    anchor_name: []const u8 = "",
    trigger: ?*const fn () void = null,
    trigger_ctx: ?*const fn (ctx: ?*anyopaque) void = null,
    ctx: ?*anyopaque = null,
    title: []const u8 = "",
    content: []const u8 = "",
    component: ?*const fn () void = null,
    container: Vapor.Builder(.pure),
    background: Vapor.Types.Color = .black,
    stroke_color: Vapor.Types.Color = .black,
    border: Vapor.Types.Border = .round(.transparent, .all(6)),
    position: Vapor.Types.AnchorPlacement = .top,
    close_on_click_outside: bool = true,
    on_trigger: ?*const fn () void = null,
};

fn onToggle(popover: *PopOver, _: *Vapor.Event) void {
    popover.options.show = !popover.options.show;
    if (popover.options.on_trigger) |on_trigger| {
        on_trigger();
    }
}

fn onOpen(popover: *PopOver, _: *Vapor.Event) void {
    popover.options.show = true;
}

fn onClose(popover: *PopOver, _: *Vapor.Event) void {
    popover.options.show = false;
    if (popover.options.on_trigger) |on_trigger| {
        on_trigger();
    }
}

fn onClickOutside(popover: *PopOver) void {
    if (popover.options.close_on_click_outside) {
        popover.options.show = false;
    }
    if (popover.options.on_trigger) |on_trigger| {
        on_trigger();
    }
}

fn destroy(_: *PopOver) void {
    // defer Vapor.arena(.persist).destroy(popover);
    // _ = popovers.remove(popover.options.stable_id);
}

pub const Options = struct {
    id: []const u8 = "",
    title: []const u8 = "",
    content: []const u8 = "",
    trigger: ?*const fn () void = null,
    component: ?*const fn () void = null,
    ctx: ?*anyopaque = null,
    trigger_ctx: ?*const fn (ctx: ?*anyopaque) void = null,
    background: Vapor.Types.Color = .black,
    stroke_color: Vapor.Types.Color = .black,
    border: Vapor.Types.Border = .round(.transparent, .all(6)),
    position: Vapor.Types.AnchorPlacement = .top,
    close_on_click_outside: bool = true,
    on_trigger: ?*const fn () void = null,
};

fn TriggerBox() Vapor.Builder(.pure) {
    return Box();
}

pub fn create(options: Options) *PopOver {
    const trigger_box = TriggerBox();
    const uuid = trigger_box.getUUID();
    const hash = Vapor.utils.hashKey(uuid);
    const stable_id = hash;

    const popover = popovers.get(stable_id) orelse blk: {
        const popover = Vapor.arena(.persist).create(PopOver) catch unreachable;
        popover.* = .{ .options = .{
            .stable_id = stable_id,
            .show = false,
            .trigger = options.trigger,
            .trigger_ctx = options.trigger_ctx,
            .ctx = options.ctx,
            .title = options.title,
            .content = options.content,
            .component = options.component,
            .container = trigger_box,
            .background = options.background,
            .stroke_color = options.stroke_color,
            .border = options.border,
            .position = options.position,
            .close_on_click_outside = options.close_on_click_outside,
            .on_trigger = options.on_trigger,
        } };

        popovers.put(stable_id, popover) catch unreachable;
        break :blk popover;
    };

    popover.options.container = trigger_box;

    const anchor_name = if (options.id.len > 0) options.id else uuid;
    popover.options.anchor_name = anchor_name;
    return popover;
}

/// Get a popover by its stable_id (useful for external control)
pub fn get(stable_id: usize) ?*PopOver {
    return popovers.get(stable_id);
}

/// Toggle the popover programmatically
pub fn toggle(popover: *PopOver) void {
    popover.options.show = !popover.options.show;
}

/// Open the popover programmatically
pub fn open(popover: *PopOver) void {
    popover.options.show = true;
}

/// Close the popover programmatically
pub fn close(popover: *PopOver) void {
    popover.options.show = false;
}

/// Check if popover is currently open
pub fn isOpen(popover: *PopOver) bool {
    return popover.options.show;
}

pub fn Trigger(popover: *PopOver, trigger_fn: anytype, args: anytype) *PopOver {
    const container = popover.options.container;
    const anchor_name = popover.options.anchor_name;
    container
        .onEvent(.click, onToggle, .{popover})
        .anchorSource(anchor_name)
        .children({
        @call(.auto, trigger_fn, args);
    });
    return popover;
}

pub fn Component(popover: *PopOver, component: anytype, args: anytype) *PopOver {
    popover.default = false;
    const anchor_name = popover.options.anchor_name;
    const position = popover.options.position;
    const margin = getMargin(position);
    // const corner_svg = getCornerSvg(position);

    Anchor(anchor_name)
        .placement(position)
        .zIndex(1000)
        .onDestroy(destroy, .{popover})
        .children({
        if (popover.options.show) {
            // Click-outside overlay to close popover
            if (popover.options.close_on_click_outside) {
                Box()
                    .id(Vapor.fmtln("popover-background-{d}", .{popover.options.stable_id}))
                    .background(.transparent)
                    .size(.full)
                    .pos(.full(.fixed))
                    .zIndex(999)
                    .children({
                    Button(onClickOutside, .{popover})
                        .ariaLabel("Close Popover Dropdown")
                        .size(.full)
                        .pos(.tl(.px(0), .px(0), .fixed))
                        .end();
                });
            }

            Box()
                .width(.auto)
                .animationEnter("opaque-popover-enter")
                .animationExit("opaque-popover-exit")
                .border(.round(.transparent, .all(6)))
                .zIndex(1000)
                .layout(.center)
                .direction(.column)
                .pos(.relative)
                .margin(margin)
                .children({
                Box()
                    .width(.fit)
                    // .background(popover.options.background)
                    // .border(popover.options.border)
                    .layout(.center)
                    .direction(.column)
                    .width(.auto)
                    .children({
                    @call(.auto, component, args);
                });
                // Vapor.Svg(.{ .svg = corner_svg })
                //     .fill(popover.options.background.color.?)
                //     .stroke(popover.options.stroke_color)
                //     .end();
            });
        } else {
            Vapor.Null();
        }
    });
    return popover;
}

pub fn end(popover: *PopOver) void {
    if (!popover.default) return;
    const anchor_name = popover.options.anchor_name;
    const position = popover.options.position;
    const margin = getMargin(position);
    // const corner_svg = getCornerSvg(position);

    Anchor(anchor_name)
        .placement(position)
        .zIndex(1000)
        .onDestroy(destroy, .{popover})
        .children({
        if (popover.options.show) {
            // Click-outside overlay to close popover
            if (popover.options.close_on_click_outside) {
                Box()
                    .id(Vapor.fmtln("popover-background-{d}", .{popover.options.stable_id}))
                    .background(.transparent)
                    .size(.full)
                    .pos(.full(.fixed))
                    .zIndex(999)
                    .children({
                    Button(onClickOutside, .{popover})
                        .ariaLabel("Close Popover Dropdown")
                        .size(.full)
                        .pos(.tl(.px(0), .px(0), .fixed))
                        .end();
                });
            }

            Box()
                .width(.auto)
                .animationEnter("opaque-popover-enter")
                .animationExit("opaque-popover-exit")
                .border(.round(.transparent, .all(6)))
                .zIndex(1000)
                .layout(.center)
                .direction(.column)
                .pos(.relative)
                .margin(margin)
                .children({
                Box()
                    .background(popover.options.background)
                    .padding(.xy(12, 6))
                    .border(.round(.transparent, .all(6)))
                    .layout(.center)
                    .direction(.column)
                    .width(.auto)
                    .children({
                    Text(popover.options.content)
                        .font(14, 300, alternate_text_color).end();
                });
                // Vapor.Svg(.{ .svg = corner_svg })
                //     .fill(popover.options.background.color.?)
                //     .stroke(popover.options.stroke_color)
                //     .end();
            });
        } else {
            Vapor.Null();
        }
    });
}

pub fn simple(title: []const u8, content: []const u8) void {
    simpleWithPosition(title, content, .top);
}

pub fn simpleWithPosition(title: []const u8, content: []const u8, position: Vapor.Types.AnchorPlacement) void {
    const trigger_box = TriggerBox();
    const uuid = trigger_box.getUUID();
    const hash = Vapor.utils.hashKey(uuid);
    const stable_id = hash;

    const popover = popovers.get(stable_id) orelse blk: {
        const popover = Vapor.arena(.persist).create(PopOver) catch unreachable;
        popover.* = .{ .options = .{
            .stable_id = stable_id,
            .show = false,
            .title = title,
            .content = content,
            .container = trigger_box,
            .position = position,
        } };

        popovers.put(stable_id, popover) catch unreachable;
        break :blk popover;
    };

    const anchor_name = uuid;
    popover.options.anchor_name = anchor_name;

    const margin = getMargin(position);
    // const corner_svg = getCornerSvg(position);

    trigger_box
        .onEvent(.click, onToggle, .{popover})
        .anchorSource(anchor_name)
        .children({
        if (popover.options.trigger) |trigger_fn| {
            @call(.auto, trigger_fn, .{});
        } else if (popover.options.trigger_ctx) |trigger_fn| {
            @call(.auto, trigger_fn, .{popover.options.ctx});
        } else {
            Box()
                .padding(.xy(12, 4))
                .background(background)
                .duration(100)
                .hover(.{
                    .transform = .scale(),
                })
                .border(border)
                .children({
                Text(popover.options.title).font(14, 300, .palette(.text_color)).end();
            });
        }
    });
    Anchor(anchor_name)
        .placement(position)
        .onDestroy(destroy, .{popover})
        .zIndex(1000)
        .children({
        if (popover.options.show) {
            // Click-outside overlay to close popover
            if (popover.options.close_on_click_outside) {
                Box()
                    .id(Vapor.fmtln("popover-background-{d}", .{popover.options.stable_id}))
                    .background(.transparent)
                    .size(.full)
                    .pos(.full(.fixed))
                    .zIndex(999)
                    .children({
                    Button(onClickOutside, .{popover})
                        .ariaLabel("Close Popover Dropdown")
                        .size(.full)
                        .pos(.tl(.px(0), .px(0), .fixed))
                        .end();
                });
            }

            Box()
                .width(.auto)
                .animationEnter("opaque-popover-enter")
                .animationExit("opaque-popover-exit")
                .border(.round(.transparent, .all(6)))
                .zIndex(1000)
                .layout(.center)
                .direction(.column)
                .pos(.relative)
                .margin(margin)
                .children({
                Box()
                    .background(alternate_background)
                    .padding(.xy(12, 6))
                    .border(.round(.transparent, .all(6)))
                    .layout(.center)
                    .direction(.column)
                    .width(.auto)
                    .children({
                    if (popover.options.component) |component| {
                        @call(.auto, component, .{});
                    } else {
                        Text(popover.options.content)
                            .font(14, 300, alternate_text_color).end();
                    }
                });
                // Vapor.Svg(.{ .svg = corner_svg })
                //     .fill(svg_color)
                //     .stroke(svg_color)
                //     .end();
            });
        } else {
            Vapor.Null();
        }
    });
}

pub fn render(popover_options: Options) void {
    const trigger_box = TriggerBox();
    const uuid = trigger_box.getUUID();
    const hash = Vapor.utils.hashKey(uuid);
    const stable_id = hash;

    const popover = popovers.get(stable_id) orelse blk: {
        const popover = Vapor.arena(.persist).create(PopOver) catch unreachable;
        popover.* = .{ .options = .{
            .stable_id = stable_id,
            .show = false,
            .trigger = popover_options.trigger,
            .trigger_ctx = popover_options.trigger_ctx,
            .ctx = popover_options.ctx,
            .title = popover_options.title,
            .content = popover_options.content,
            .component = popover_options.component,
            .container = trigger_box,
            .position = popover_options.position,
            .close_on_click_outside = popover_options.close_on_click_outside,
        } };

        popovers.put(stable_id, popover) catch unreachable;
        break :blk popover;
    };

    const anchor_name = if (popover_options.id.len > 0) popover_options.id else uuid;
    popover.options.anchor_name = anchor_name;

    const position = popover_options.position;
    const transform_origin = getTransformOrigin(position);
    const margin = getMargin(position);
    // const corner_svg = getCornerSvg(position);

    trigger_box
        .onEvent(.click, onToggle, .{popover})
        .anchorSource(anchor_name)
        .children({
        if (popover.options.trigger) |trigger_fn| {
            @call(.auto, trigger_fn, .{});
        } else if (popover.options.trigger_ctx) |trigger_fn| {
            @call(.auto, trigger_fn, .{popover.options.ctx});
        } else {
            Box()
                .padding(.xy(12, 4))
                .background(background)
                .duration(100)
                .hover(.{
                    .transform = .scale(),
                })
                .border(border)
                .children({
                Text(popover.options.title).font(14, 300, .palette(.text_color)).end();
            });
        }
    });
    Anchor(anchor_name)
        .transformOrigin(transform_origin)
        .onDestroy(destroy, .{popover})
        .zIndex(1000)
        .children({
        if (popover.options.show) {
            // Click-outside overlay to close popover
            if (popover.options.close_on_click_outside) {
                Box()
                    .id(Vapor.fmtln("popover-background-{d}", .{popover.options.stable_id}))
                    .background(.transparent)
                    .size(.full)
                    .pos(.full(.fixed))
                    .zIndex(999)
                    .children({
                    Button(onClickOutside, .{popover})
                        .ariaLabel("Close Popover Dropdown")
                        .size(.full)
                        .pos(.tl(.px(0), .px(0), .fixed))
                        .end();
                });
            }

            Box()
                .width(.auto)
                .transformOrigin(transform_origin)
                .animationEnter("opaque-popover-enter")
                .animationExit("opaque-popover-exit")
                .border(.round(.transparent, .all(6)))
                .zIndex(1000)
                .layout(.center)
                .direction(.column)
                .pos(.relative)
                .margin(margin)
                .children({
                Box()
                    .background(alternate_background)
                    .padding(.xy(12, 6))
                    .border(.round(.transparent, .all(6)))
                    .layout(.center)
                    .direction(.column)
                    .width(.auto)
                    .children({
                    if (popover.options.component) |component| {
                        @call(.auto, component, .{});
                    } else {
                        Text(popover.options.content)
                            .font(14, 300, alternate_text_color).end();
                    }
                });
                // Vapor.Svg(.{ .svg = corner_svg })
                //     .fill(svg_color)
                //     .stroke(svg_color)
                //     .end();
            });
        } else {
            Vapor.Null();
        }
    });
}
