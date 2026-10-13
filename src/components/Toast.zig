const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const TextArea = Vapor.TextArea;
const Stack = Vapor.Stack;
const Center = Vapor.Center;
const Icon = Vapor.Icon;
const Box = Vapor.Box;
const Animation = Vapor.Animation;
const IconTokens = @import("config").IconTokens;
const Button = Vapor.Button;
const TextFmt = Vapor.TextFmt;
var next_toast_id: usize = 0;

const spinner: Animation = Animation.init("spin")
    .easing(.easeInOut)
    .duration(100)
    .prop(.rotate, 0, 180);

// 1. Define specific Toast Types for better UX
pub const ToastType = enum {
    success,
    err,
    warning,
    info,
};

// 2. Define stack position enum
pub const StackPosition = enum {
    top_right,
    top_left,
    bottom_right,
    bottom_left,
};

// Current stack position (can be changed at runtime)
pub var stack_position: StackPosition = .top_right;

pub var toasts: Vapor.Array(Toast) = undefined;
pub var border_thickness: u8 = 1;
pub var border_radius: Vapor.Types.BorderRadius = .all(16);
pub var border_color: Vapor.Types.BorderGrouped = .white;
pub var background: Vapor.Types.Color = .transparentizeHex(.white, 0.2);
pub var shadow: Vapor.Types.Shadow = .{
    .blur = 8,
    .color = .transparentizeHex(.black, 0.15),
    .top = 2,
    .spread = 0,
};

pub var success_background: Vapor.Types.Color = .transparentizeHex(.white, 0.2);
pub var err_background: Vapor.Types.Color = .transparentizeHex(.white, 0.2);
pub var warning_background: Vapor.Types.Color = .transparentizeHex(.white, 0.2);
pub var info_background: Vapor.Types.Color = .transparentizeHex(.white, 0.2);

pub var success_text_color: Vapor.Types.Color = .black;
pub var err_text_color: Vapor.Types.Color = .black;
pub var warning_text_color: Vapor.Types.Color = .black;
pub var info_text_color: Vapor.Types.Color = .black;

pub var success_blur: u8 = 12;
pub var err_blur: u8 = 12;
pub var warning_blur: u8 = 12;
pub var info_blur: u8 = 12;

// Stack margin from screen edges
pub var stack_margin: f32 = 24;

const Toast = @This();
var text_color: Vapor.Types.Color = .black;
var total_height: f32 = 0;

// State
toast_type: ToastType = .info,
is_visible: bool = false,
auto_close: bool = true,
duration: u32 = 3000,
on_close: ?*const fn (toast: *Toast) void = null,
id: usize = 0,
offset: f32 = 24, // Generic offset (used for top or bottom depending on position)
right: f32 = 24,
width: f32 = 280,
scale_val: f16 = 1.0,
height: f32 = 52,
_title_buffer: [128]u8 = undefined,
_title_buffer_len: usize = 0,
_description_buffer: [256]u8 = undefined,
_description_buffer_len: usize = 0,

// Define animations (using your API style)
const anim_enter = Animation.init("opaque-toast-enter")
    .prop(.translateY, -20, 0)
    .prop(.opacity, 0, 1)
    .duration(300)
    .easing(.easeOut)
    .fill(.forwards);

const anim_exit = Animation.init("opaque-toast-exit")
    .prop(.opacity, 1, 0)
    .prop(.scale, 1, 0.95)
    .duration(200)
    .easing(.easeIn)
    .fill(.forwards);

// Bottom position animations (enter from bottom)
const anim_enter_bottom = Animation.init("opaque-toast-enter-bottom")
    .prop(.translateY, 20, 0)
    .prop(.opacity, 0, 1)
    .duration(300)
    .easing(.easeOut)
    .fill(.forwards);

pub fn new() void {
    anim_enter.build();
    anim_exit.build();
    anim_enter_bottom.build();
    spinner.build();
    toasts = Vapor.array(Toast, .persist);
}

pub const Options = struct {
    title: []const u8,
    description: []const u8,
};

// Helper to check if position is at bottom
fn isBottomPosition() bool {
    return stack_position == .bottom_right or stack_position == .bottom_left;
}

// Helper to check if position is on left
fn isLeftPosition() bool {
    return stack_position == .top_left or stack_position == .bottom_left;
}

pub fn movePreviousDown() void {
    if (toasts.items.len == 0) return;
    const last = toasts.items.len - 1;
    var i: usize = toasts.items.len - 1;
    var local_total_height: f32 = toasts.items[0].height;

    while (i < toasts.items.len) : (i -= 1) {
        if (toasts.items[i].is_visible) {
            // For bottom positions, offset grows upward (negative direction visually)
            // For top positions, offset grows downward
            const stack_offset = @as(f32, @floatFromInt(last - i)) * 14.0;
            toasts.items[i].offset = stack_offset;
            toasts.items[i].scale_val = 1.0 - (@as(f16, @floatFromInt(last - i)) * 0.04);
            local_total_height += 8;
        }
        if (i == 0) break;
    }
    total_height = local_total_height;
}

fn showToast(toast: *Toast) void {
    toast.show();
    toasts.append(toast.*) catch unreachable;
    movePreviousDown();
    startToastTimeout(toast);
}

fn startToastTimeout(toast: *Toast) void {
    const id = Vapor.fmtln("remove_oldest_toast-{d}", .{toast.id});
    Vapor.lib.timeout(id, 5000, removeOldestToast, .{{}});
}

fn cancelToast(toast: *Toast) void {
    const id = Vapor.fmtln("remove_oldest_toast-{d}", .{toast.id});
    Vapor.lib.cancelTimeout(id);
}

fn clearTimeout(toast: *Toast) void {
    const id = Vapor.fmtln("remove_oldest_toast-{d}", .{toast.id});
    Vapor.lib.cancelTimeout(id);
}

pub fn success(options: Options) void {
    var toast = Toast.init(options.title, options.description, .success);
    showToast(&toast);
}

pub fn err(options: Options) void {
    var toast = Toast.init(options.title, options.description, .err);
    showToast(&toast);
}

pub fn warning(options: Options) void {
    var toast = Toast.init(options.title, options.description, .warning);
    showToast(&toast);
}

pub fn info(options: Options) void {
    var toast = Toast.init(options.title, options.description, .info);
    showToast(&toast);
}

pub fn init(title: []const u8, description: []const u8, toast_type: ToastType) Toast {
    const id = next_toast_id;
    next_toast_id += 1;

    if (title.len > 128) return {
        std.log.err("Title too long", .{});
        return Toast{
            .toast_type = toast_type,
            .id = id,
        };
    };
    if (description.len > 256) return {
        std.log.err("Description too long", .{});
        return Toast{
            .toast_type = toast_type,
            .id = id,
        };
    };

    var toast: Toast = undefined;
    toast = Toast{
        .toast_type = toast_type,
        .id = id,
        ._title_buffer_len = title.len,
        ._description_buffer_len = description.len,
    };
    @memcpy(toast._title_buffer[0..title.len], title);
    @memcpy(toast._description_buffer[0..description.len], description);
    return toast;
}

pub fn show(toast: *Toast) void {
    toast.is_visible = true;
}

pub fn hide(toast: *Toast) void {
    toast.is_visible = false;
    if (toast.on_close) |callback| {
        callback(toast);
    }
    for (toasts.items, 0..) |*t, i| {
        if (t.id == toast.id) {
            _ = toasts.orderedRemove(i);
            break; // <-- stop iterating after removal
        }
    }
    showAllToasts();
}

fn movePreviousUp() void {
    if (toasts.items.len == 0) return;
    const last = toasts.items.len - 1;
    var i: usize = 0;
    while (i < toasts.items.len) : (i += 1) {
        if (toasts.items[i].is_visible) {
            toasts.items[i].offset = @as(f32, @floatFromInt(last - i)) * 14.0;
            Vapor.print("Id {d}", .{toasts.items[i].id});
        }
        if (i == last) break;
    }
}

fn removeOldestToast(_: void) void {
    if (toasts.items.len == 0) return;
    _ = toasts.orderedRemove(0);
    movePreviousDown();
}

fn getTypeColor(toast_type: ToastType) Vapor.Types.Color {
    return switch (toast_type) {
        .success => text_color,
        .err => text_color,
        .warning => text_color,
        .info => text_color,
    };
}

fn getTypeIcon(toast_type: ToastType) Vapor.IconType {
    return switch (toast_type) {
        .success => IconTokens.check2_all,
        .err => IconTokens.exclamation_circle,
        .warning => IconTokens.exclamation_triangle,
        .info => IconTokens.info_circle,
    };
}

fn onHover(_: *Vapor.Event) void {
    for (toasts.items) |*t| {
        cancelToast(t);
    }
    showAllToasts();
}

fn onLeave(_: *Vapor.Event) void {
    movePreviousDown();
    for (toasts.items) |*t| {
        startToastTimeout(t);
    }
}

fn showAllToasts() void {
    if (toasts.items.len == 0) return;
    const last = toasts.items.len - 1;
    var i: usize = 0;
    var local_total_height: f32 = 0;

    while (i < toasts.items.len) : (i += 1) {
        if (toasts.items[i].is_visible) {
            // When expanded, stack toasts with full height + spacing
            const expanded_offset = @as(f32, @floatFromInt(last - i)) * (toasts.items[i].height + 8);
            toasts.items[i].offset = expanded_offset;
            toasts.items[i].scale_val = 1;
        }
        local_total_height += toasts.items[i].height + 8;
        if (i == last) break;
    }
    total_height = local_total_height;
}

// Set the stack position before rendering
pub fn setPosition(position: StackPosition) void {
    stack_position = position;
}

// Main render function - renders stack at current position
pub fn renderStack() void {
    renderStackAt(stack_position);
}

pub fn clearToasts() void {
    for (toasts.items) |*t| {
        t.is_visible = false;
        t.clearTimeout();
    }
    toasts.clearRetainingCapacity();
}

// Render stack at a specific position
pub fn renderStackAt(position: StackPosition) void {
    const margin_px = Vapor.Types.Pos.px(stack_margin);
    const width_val = if (toasts.items.len > 0) toasts.items[0].width else 0;

    // Determine layout direction based on position
    // Top positions: stack grows downward (column)
    // Bottom positions: stack grows upward (column_reverse)
    const layout_alignment: Vapor.Types.Layout = switch (position) {
        .top_right => .top_center,
        .top_left => .top_center,
        .bottom_right => .bottom_center,
        .bottom_left => .bottom_center,
    };

    // Get the appropriate fixed position
    const fixed_pos = switch (position) {
        .top_right => Vapor.Types.Position.tr(margin_px, margin_px, .fixed),
        .top_left => Vapor.Types.Position.tl(margin_px, margin_px, .fixed),
        .bottom_right => Vapor.Types.Position.br(margin_px, margin_px, .fixed),
        .bottom_left => Vapor.Types.Position.bl(margin_px, margin_px, .fixed),
    };

    Box()
        .id("opaque-toast-stack")
        .pos(fixed_pos)
        .layout(layout_alignment)
        .spacing(12)
        .direction(.column)
        .background(.transparent)
        .width(.px(width_val))
        .height(.px(total_height))
        .onHover(onHover, .{})
        .onLeave(onLeave, .{})
        .zIndex(9999)
        .children({
        for (toasts.items, 0..) |*t, i| {
            renderToast(t, i, position);
        }
    });
}

fn getBackground(toast_type: ToastType) Vapor.Types.Color {
    return switch (toast_type) {
        .success => success_background,
        .err => err_background,
        .warning => warning_background,
        .info => info_background,
    };
}

fn getTextColor(toast_type: ToastType) Vapor.Types.Color {
    return switch (toast_type) {
        .success => success_text_color,
        .err => err_text_color,
        .warning => warning_text_color,
        .info => info_text_color,
    };
}

fn getBlur(toast_type: ToastType) u8 {
    return switch (toast_type) {
        .success => success_blur,
        .err => err_blur,
        .warning => warning_blur,
        .info => info_blur,
    };
}

fn getBorderColor(toast_type: ToastType) Vapor.Types.Color {
    return switch (toast_type) {
        .success => success_background,
        .err => err_background,
        .warning => warning_background,
        .info => info_background,
    };
}

// Renamed from render to renderToast for clarity
fn renderToast(toast: *Toast, index: usize, position: StackPosition) void {
    const z_index: i16 = @as(i16, @intCast(100 + index));

    // Determine the toast position within the stack based on stack position
    const toast_pos = switch (position) {
        // Top positions: offset from top
        .top_right => Vapor.Types.Position.tr(.px(toast.offset), .px(0), .absolute),
        .top_left => Vapor.Types.Position.tl(.px(toast.offset), .px(0), .absolute),
        // Bottom positions: offset from bottom
        .bottom_right => Vapor.Types.Position.br(.px(toast.offset), .px(0), .absolute),
        .bottom_left => Vapor.Types.Position.bl(.px(toast.offset), .px(0), .absolute),
    };

    // Choose animation based on position
    const enter_anim = if (position == .bottom_right or position == .bottom_left)
        "opaque-toast-enter-bottom"
    else
        "opaque-toast-enter";

    Box()
        .id(Vapor.fmtln("opaque-toast-{d}", .{toast.id}))
        .shadow(
            Vapor.Types.NewShadow.init()
                .inset(0, -2, .transparentizeHex(.black, 0.1))
                .drop(0, 1, 3, .transparentizeHex(.black, 0.2)),
        )
        .border(.solid(.all(border_thickness), getBorderColor(toast.toast_type), border_radius))
        // .border(.simple(.black))
        .pos(toast_pos)
        .animationEnter(enter_anim)
        .animationExit("opaque-toast-exit")
        .zIndex(z_index)
        .transition(.{
            .properties = &.{ .top, .bottom, .scale, .opacity, .transform },
            .duration = 200,
            .timing = .easeInOut,
        })
        .scale(toast.scale_val)
        .height(.px(toast.height))
        .blur(getBlur(toast.toast_type))
        .inlineStyle("min-width: {d}px", .{toast.width})
        // .width(.px(toast.width))
        // .background(getBackground(toast.toast_type))
        .background(background)
        .layout(.x_between_center)
        .padding(.all(8))
        .spacing(8)
        .children({
        // 1. Semantic Icon
        Center()
            .width(.px(32))
            .height(.px(32))
            .children({
            Icon(getTypeIcon(toast.toast_type))
                .font(18, 700, getTextColor(toast.toast_type))
                .end();
        });

        // 2. Text Content (Stacked Vertically)
        Box()
            .direction(.column)
            .layout(.left_center)
            .width(.grow)
            .children({
            Text(toast._title_buffer[0..toast._title_buffer_len])
                .font(14, 600, getTextColor(toast.toast_type))
                .end();
            Text(toast._description_buffer[0..toast._description_buffer_len])
                .ellipsis(.dot)
                .font(13, 400, getTextColor(toast.toast_type))
                .end();
        });

        // 3. Close Button
        Button(hide, .{toast})
            .class("toast-close")
            .cursor(.pointer)
            .padding(.all(4))
            .duration(100)
            .hover(.{
                .text_color = .transparentizeHex(getTextColor(toast.toast_type), 0.5),
            })
            .children({
            Vapor.Svg(.{ .svg = close_icon, .override = true })
                .fill(getTextColor(toast.toast_type))
                .hover(.{
                    .fill = .transparentizeHex(getTextColor(toast.toast_type), 0.5),
                })
                .end();
        });
    });
}

const close_icon =
    \\<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-x-lg" viewBox="0 0 16 16">
    \\  <path d="M2.146 2.854a.5.5 0 1 1 .708-.708L8 7.293l5.146-5.147a.5.5 0 0 1 .708.708L8.707 8l5.147 5.146a.5.5 0 0 1-.708.708L8 8.707l-5.146 5.147a.5.5 0 0 1-.708-.708L7.293 8z"/>
    \\</svg>
;

// Keep the original render function for backwards compatibility
pub fn render(toast: *Toast, index: usize) void {
    renderToast(toast, index, stack_position);
}
