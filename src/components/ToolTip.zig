const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Row = Vapor.Row;
const ButtonCtx = Vapor.Button;
const Button = Vapor.Button;
const Anchor = Vapor.Anchor;

pub var background: Vapor.Types.Color = .palette(.background);
pub var alternate_background: Vapor.Types.Color = .black;
pub var svg_color: Vapor.Types.Color = .black;
pub var border_color: Vapor.Types.Color = .hex("#e4e4e4");
var tooltips: std.AutoHashMap(usize, *ToolTip) = undefined;
pub var alternate_text_color: Vapor.Types.Color = .white;
pub var border: Vapor.Types.Border = .round(.transparent, .all(6));

pub const animateEnter = Vapor.Animation.init("opaque-tooltip-enter")
    .prop(.opacity, 0, 1)
    .prop(.scale, 0.9, 1)
    .duration(200)
    .easing(.easeInOut);

pub const animateExit = Vapor.Animation.init("opaque-tooltip-exit")
    .prop(.opacity, 1, 0)
    .prop(.scaleY, 1, 0.9)
    .duration(100)
    .easing(.easeInOut);

pub const ErasedCallback = struct {
    ctx: *anyopaque,
    callFn: *const fn (*anyopaque) void,
    deinitFn: *const fn (*anyopaque) void,

    pub fn call(self: *const ErasedCallback) void {
        self.callFn(self.ctx);
    }

    pub fn deinit(self: *ErasedCallback) void {
        self.deinitFn(self.ctx);
    }

    pub fn make(allocator: std.mem.Allocator, cb: anytype, args: anytype) !ErasedCallback {
        const Args = @TypeOf(args);

        // cb is captured by the comptime closure below — not stored in the struct
        const Closure = struct {
            arguments: Args,

            fn run(ptr: *anyopaque) void {
                const self: *@This() = @ptrCast(@alignCast(ptr));
                @call(.auto, cb, self.arguments);
            }

            fn destroy(_: *anyopaque) void {
                // const self: *@This() = @ptrCast(@alignCast(ptr));
                // allocator.destroy(self);
            }
        };

        const closure = try allocator.create(Closure);
        closure.* = .{
            .arguments = args,
        };

        return .{
            .ctx = @ptrCast(closure),
            .callFn = Closure.run,
            .deinitFn = Closure.destroy,
        };
    }
};

pub var erased_registry: std.AutoHashMap(u32, ErasedCallback) = undefined;

pub fn new() void {
    tooltips = std.AutoHashMap(usize, *ToolTip).init(Vapor.arena(.persist));
    erased_registry = std.AutoHashMap(u32, ErasedCallback).init(Vapor.arena(.persist));
    animateEnter.build();
    animateExit.build();
}

pub const tooltip_service = struct {
    var active: ?*ToolTip = null;
    /// The document keydown listener for Escape, while a tooltip is open.
    var escape_listener: ?u32 = null;
    // var show_timer: TimerKey = ...;
    // var hide_timer: TimerKey = ...;

    pub fn request(tooltip: *ToolTip) void {
        Vapor.lib.cancelTimeout(tooltip.options.timeout_key);
        Vapor.lib.timeout(tooltip.options.show_timeout_key, 500, show, .{tooltip});
        // cancel hide timer, schedule show after delay
    }

    pub fn dismiss(tooltip: *ToolTip) void {
        Vapor.lib.cancelTimeout(tooltip.options.show_timeout_key);
        Vapor.lib.timeout(tooltip.options.timeout_key, 150, close, .{tooltip});
        // cancel show timer, schedule hide after delay
    }
};

pub fn TooltipLayer() void {
    Vapor.Layer(.tooltip).children({
        if (tooltip_service.active) |tooltip| {
            const anchor_name = tooltip.options.anchor_name;
            const position = tooltip.options.position;
            const margin = getMargin(position);
            const corner_svg = getCornerSvg(position);

            Anchor(anchor_name)
                .animationEnter("opaque-tooltip-enter")
                .animationExit("opaque-tooltip-exit")
                .placement(position)
                .zIndex(1000)
                .onEvent(.pointerenter, onHover, .{tooltip})
                .onEvent(.pointerleave, onLeave, .{tooltip})
                .onDestroy(destroy, .{tooltip})
                .children({
                // if (tooltip.options.show) {
                Row()
                    .width(.auto)
                    .border(.round(.transparent, .all(6)))
                    .zIndex(1000)
                    .layout(.center)
                    .direction(.column)
                    .pos(.relative)
                    .margin(margin)
                    .children({
                    Row()
                        .a11y(.tooltip())
                        .width(.fit)
                        .background(tooltip.options.background)
                        .border(tooltip.options.border)
                        .layout(.center)
                        .direction(.column)
                        .width(.auto)
                        .children({
                        if (tooltip.options.erased_callback) |callback| {
                            callback.call();
                        } else {
                            defaultContent(tooltip);
                        }
                    });
                    if (corner_svg.len > 0) {
                        Vapor.Svg(.{ .svg = corner_svg })
                            .fill(tooltip.options.background)
                            .stroke(tooltip.options.stroke_color)
                            .end();
                    }
                });
                // }
            });
        }
    });
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
        \\bottom: -7px;
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

fn getPositionStyle(position: Position) []const u8 {
    return switch (position) {
        .top => "position-area: top; position: absolute;",
        .bottom => "position-area: bottom; position: absolute;",
        .left => "position-area: left; position: absolute;",
        .right => "position-area: right; position: absolute;",
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

const ToolTip = @This();
options: TooltipOptions,
default: bool = true,

const TooltipOptions = struct {
    stable_id: usize = 0,
    show: bool = false,
    timeout_key: []const u8 = "",
    show_timeout_key: []const u8 = "",
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
    erased_callback: ?ErasedCallback = null,
};

fn onHover(tooltip: *ToolTip, _: *Vapor.Event) void {
    tooltip_service.request(tooltip);
}

fn show(tooltip: *ToolTip) void {
    tooltip_service.active = tooltip;
    if (tooltip_service.escape_listener == null) {
        tooltip_service.escape_listener = Vapor.lib.addGlobalListenerCtx(.keydown, escapeKey, .{});
    }
}

/// Escape hides the tooltip without moving the pointer (WCAG 1.4.13).
fn escapeKey(evt: *Vapor.Event) void {
    if (std.mem.eql(u8, evt.key(), "Escape")) hideActive();
}

fn hideActive() void {
    tooltip_service.active = null;
    if (tooltip_service.escape_listener) |id| {
        _ = Vapor.lib.removeGlobalListener(.keydown, id);
        tooltip_service.escape_listener = null;
    }
}

/// A trigger left the page; its tooltip must not outlive it.
fn forget(tooltip: *ToolTip) void {
    if (tooltip_service.active == tooltip) hideActive();
}

/// What a tooltip without a `Component` shows: its `component` fn, or its
/// text.
fn defaultContent(tooltip: *ToolTip) void {
    Row()
        .padding(.xy(12, 6))
        .children({
        if (tooltip.options.component) |component| {
            @call(.auto, component, .{});
        } else {
            Text(tooltip.options.content)
                .font(14, 300, alternate_text_color)
                .end();
        }
    });
}

fn onLeave(tooltip: *ToolTip, _: *Vapor.Event) void {
    tooltip_service.dismiss(tooltip);
    // _ = tooltip;
    // Vapor.lib.cancelTimeout(tooltip.options.show_timeout_key);
    // Vapor.lib.timeout(tooltip.options.timeout_key, 150, close, .{&tooltip.options});
}

fn close(_: *ToolTip) void {
    hideActive();
}

fn destroy(_: *ToolTip) void {
    // defer Vapor.arena(.persist).destroy(tooltip);
    // _ = tooltips.remove(tooltip.options.stable_id);
}

const Options = struct {
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
};

fn HoverRow() Vapor.Builder(.pure) {
    return Row();
}

pub fn create(options: Options) *ToolTip {
    const hover_box = HoverRow();
    const uuid = hover_box.getUUID();
    const hash = Vapor.utils.hashKey(uuid);
    const stable_id = hash;

    const timeout_key = Vapor.fmtln("tt_timer_{d}", .{stable_id});
    const show_timeout_key = Vapor.fmtln("show_tt_timer_{d}", .{stable_id});

    const tooltip = tooltips.get(stable_id) orelse blk: {
        const tooltip = Vapor.arena(.persist).create(ToolTip) catch unreachable;
        tooltip.* = .{ .options = .{
            .stable_id = stable_id,
            .show = false,
            .timeout_key = timeout_key,
            .show_timeout_key = show_timeout_key,
            .trigger = options.trigger,
            .trigger_ctx = options.trigger_ctx,
            .ctx = options.ctx,
            .title = options.title,
            .content = options.content,
            .component = options.component,
            .container = hover_box,
            .background = options.background,
            .stroke_color = options.stroke_color,
            .border = options.border,
            .position = options.position,
        } };

        tooltips.put(stable_id, tooltip) catch unreachable;
        break :blk tooltip;
    };

    tooltip.options.container = hover_box;

    const anchor_name = if (options.id.len > 0) options.id else uuid;
    tooltip.options.anchor_name = anchor_name;
    return tooltip;
}

pub fn Trigger(tooltip: *ToolTip, trigger: anytype, args: anytype) *ToolTip {
    const container = tooltip.options.container;
    const anchor_name = tooltip.options.anchor_name;
    container
        .width(.fit)
        .onEvent(.pointerenter, onHover, .{tooltip})
        .onEvent(.pointerleave, onLeave, .{tooltip})
        .onEvent(.focusin, onHover, .{tooltip})
        .onEvent(.focusout, onLeave, .{tooltip})
        .onDestroy(forget, .{tooltip})
        .anchorSource(anchor_name)
        .children({
        @call(.auto, trigger, args);
    });
    return tooltip;
}

pub fn Component(tooltip: *ToolTip, component: anytype, args: anytype) *ToolTip {
    tooltip.default = false;
    const erased_callback = ErasedCallback.make(Vapor.frame.arena(), component, args) catch |err| {
        std.log.err("Could not create Tooltip callback Error: {any}", .{err});
        return tooltip;
    };
    tooltip.options.erased_callback = erased_callback;

    // const anchor_name = tooltip.options.anchor_name;
    // const position = tooltip.options.position;
    // const margin = getMargin(position);
    // const corner_svg = getCornerSvg(position);
    //
    // Vapor.Layer(.tooltip).children({
    //     Anchor(anchor_name)
    //         .anchorPlacement(position)
    //         .zIndex(1000)
    //         .onEvent(.pointerenter, onHover, .{tooltip})
    //         .onEvent(.pointerleave, onLeave, .{tooltip})
    //         .onDestroy(destroy, .{tooltip})
    //         .children({
    //         if (tooltip.options.show) {
    //             Row()
    //                 .width(.auto)
    //                 .animationEnter("opaque-tooltip-enter")
    //                 .animationExit("opaque-tooltip-exit")
    //                 .border(.round(.transparent, .all(6)))
    //                 .zIndex(1000)
    //                 .layout(.center)
    //                 .direction(.column)
    //                 .pos(.relative)
    //                 .margin(margin)
    //                 .children({
    //                 Row()
    //                     .width(.fit)
    //                     .background(tooltip.options.background)
    //                     .border(tooltip.options.border)
    //                     .layout(.center)
    //                     .direction(.column)
    //                     .width(.auto)
    //                     .children({
    //                     @call(.auto, component, args);
    //                 });
    //                 if (corner_svg.len > 0) {
    //                     Vapor.Svg(.{ .svg = corner_svg })
    //                         .fill(tooltip.options.background)
    //                         .stroke(tooltip.options.stroke_color)
    //                         .end();
    //                 }
    //             });
    //         } else {
    //             Vapor.Null();
    //         }
    //     });
    // });
    return tooltip;
}

/// Finishes a `create(...).Trigger(...)` chain; the tooltip layer
/// (`TooltipLayer`) draws the popup.
pub fn end(tooltip: *ToolTip) void {
    _ = tooltip;
}

pub fn simple(title: []const u8, content: []const u8) void {
    simpleWithPosition(title, content, .top);
}

pub fn simpleWithPosition(title: []const u8, content: []const u8, position: Vapor.Types.AnchorPlacement) void {
    const hover_box = HoverRow();
    const uuid = hover_box.getUUID();
    const hash = Vapor.utils.hashKey(uuid);
    const stable_id = hash;

    const timeout_key = Vapor.fmtln("tt_timer_{d}", .{stable_id});
    const show_timeout_key = Vapor.fmtln("show_tt_timer_{d}", .{stable_id});

    const tooltip = tooltips.get(stable_id) orelse blk: {
        const tooltip = Vapor.arena(.persist).create(ToolTip) catch unreachable;
        tooltip.* = .{ .options = .{
            .stable_id = stable_id,
            .show = false,
            .timeout_key = timeout_key,
            .show_timeout_key = show_timeout_key,
            .title = title,
            .content = content,
            .container = hover_box,
            .position = position,
        } };

        tooltips.put(stable_id, tooltip) catch unreachable;
        break :blk tooltip;
    };

    const anchor_name = uuid;
    tooltip.options.anchor_name = anchor_name;

    hover_box
        .onEvent(.pointerenter, onHover, .{tooltip})
        .onEvent(.pointerleave, onLeave, .{tooltip})
        .onEvent(.focusin, onHover, .{tooltip})
        .onEvent(.focusout, onLeave, .{tooltip})
        .onDestroy(forget, .{tooltip})
        .anchorSource(anchor_name)
        .children({
        if (tooltip.options.trigger) |trigger| {
            @call(.auto, trigger, .{});
        } else if (tooltip.options.trigger_ctx) |trigger| {
            @call(.auto, trigger, .{tooltip.options.ctx});
        } else {
            Row()
                .tabIndex(0)
                .padding(.xy(12, 4))
                .background(background)
                .duration(100)
                .hover(.{
                    .transform = .scale(),
                })
                .border(border)
                .children({
                Text(tooltip.options.title).font(14, 300, .palette(.text_color)).end();
            });
        }
    });
}

pub fn render(tooltip_options: Options) void {
    const hover_box = HoverRow();
    const uuid = hover_box.getUUID();
    const hash = Vapor.utils.hashKey(uuid);
    const stable_id = hash;

    const timeout_key = Vapor.fmtln("tt_timer_{d}", .{stable_id});
    const show_timeout_key = Vapor.fmtln("show_tt_timer_{d}", .{stable_id});

    const tooltip = tooltips.get(stable_id) orelse blk: {
        const tooltip = Vapor.arena(.persist).create(ToolTip) catch unreachable;
        tooltip.* = .{ .options = .{
            .stable_id = stable_id,
            .show = false,
            .timeout_key = timeout_key,
            .show_timeout_key = show_timeout_key,
            .trigger = tooltip_options.trigger,
            .trigger_ctx = tooltip_options.trigger_ctx,
            .ctx = tooltip_options.ctx,
            .title = tooltip_options.title,
            .content = tooltip_options.content,
            .component = tooltip_options.component,
            .container = hover_box,
            .position = tooltip_options.position,
        } };

        tooltips.put(stable_id, tooltip) catch unreachable;
        break :blk tooltip;
    };

    const anchor_name = if (tooltip_options.id.len > 0) tooltip_options.id else uuid;
    tooltip.options.anchor_name = anchor_name;

    hover_box
        .onEvent(.pointerenter, onHover, .{tooltip})
        .onEvent(.pointerleave, onLeave, .{tooltip})
        .onEvent(.focusin, onHover, .{tooltip})
        .onEvent(.focusout, onLeave, .{tooltip})
        .onDestroy(forget, .{tooltip})
        .anchorSource(anchor_name)
        .children({
        if (tooltip.options.trigger) |trigger| {
            @call(.auto, trigger, .{});
        } else if (tooltip.options.trigger_ctx) |trigger| {
            @call(.auto, trigger, .{tooltip.options.ctx});
        } else {
            Row()
                .tabIndex(0)
                .padding(.xy(12, 4))
                .background(background)
                .duration(100)
                .hover(.{
                    .transform = .scale(),
                })
                .border(border)
                .children({
                Text(tooltip.options.title).font(14, 300, .palette(.text_color)).end();
            });
        }
    });
}
