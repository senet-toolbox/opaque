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

// Every toast's colours. They follow the theme, so toasts are light in a
// light theme and dark in a dark one.
pub var background: Vapor.Types.Color = .palette(.background);
pub var text_color: Vapor.Types.Color = .palette(.text);
pub var border_color: Vapor.Types.Color = .palette(.border_color_light);
pub var shadow: Vapor.Types.Shadow = Vapor.Types.Shadow.init().dropSpread(0, 2, 8, 0, .transparentize(.black, 0.15));

// One type's colours, over the ones above; null keeps those.
pub var success_background: ?Vapor.Types.Color = null;
pub var err_background: ?Vapor.Types.Color = null;
pub var warning_background: ?Vapor.Types.Color = null;
pub var info_background: ?Vapor.Types.Color = null;

pub var success_text_color: ?Vapor.Types.Color = null;
pub var err_text_color: ?Vapor.Types.Color = null;
pub var warning_text_color: ?Vapor.Types.Color = null;
pub var info_text_color: ?Vapor.Types.Color = null;

/// The colour of a type's icon, which tells the types apart.
pub var success_icon_color: Vapor.Types.Color = .hex("#22c55e");
pub var err_icon_color: Vapor.Types.Color = .hex("#ef4444");
pub var warning_icon_color: Vapor.Types.Color = .hex("#f59e0b");
pub var info_icon_color: Vapor.Types.Color = .palette(.tint);

/// Blurs the page behind a type's toast, for a see-through `background`.
pub var success_blur: u8 = 0;
pub var err_blur: u8 = 0;
pub var warning_blur: u8 = 0;
pub var info_blur: u8 = 0;

// Stack margin from screen edges
pub var stack_margin: f32 = 24;

const Toast = @This();
var total_height: f32 = 0;
/// Hovered, the stack spreads out and every toast shows its content;
/// otherwise only the front one does, over the edges of those behind.
var expanded: bool = false;

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

// Toasts slide in from their side of the screen and back out. They move
// without fading: while an element's opacity is below 1 the browser stops
// drawing its backdrop blur, so a blurred toast fading out lost its glass at
// once and left its text fading on its own.
const anim_enter_right = Animation.init("opaque-toast-enter-right")
    .propUnit(.translateX, 120, 0, .percent)
    .duration(300)
    .easing(.easeOut)
    .fill(.forwards);

const anim_enter_left = Animation.init("opaque-toast-enter-left")
    .propUnit(.translateX, -120, 0, .percent)
    .duration(300)
    .easing(.easeOut)
    .fill(.forwards);

const anim_exit_right = Animation.init("opaque-toast-exit-right")
    .propUnit(.translateX, 0, 120, .percent)
    .duration(200)
    .easing(.easeIn)
    .fill(.forwards);

const anim_exit_left = Animation.init("opaque-toast-exit-left")
    .propUnit(.translateX, 0, -120, .percent)
    .duration(200)
    .easing(.easeIn)
    .fill(.forwards);

pub fn new() void {
    anim_enter_right.build();
    anim_enter_left.build();
    anim_exit_right.build();
    anim_exit_left.build();
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

/// Each toast's own timer, named by its id, removes that toast and no other.
fn timerName(id: usize) []const u8 {
    return Vapor.fmtln("opaque-toast-timeout-{d}", .{id});
}

fn startToastTimeout(toast: *Toast) void {
    if (!toast.auto_close) return;
    Vapor.lib.timeout(timerName(toast.id), toast.duration, expire, .{toast.id});
}

fn cancelToast(toast: *Toast) void {
    Vapor.lib.cancelTimeout(timerName(toast.id));
}

fn clearTimeout(toast: *Toast) void {
    cancelToast(toast);
}

fn indexOf(id: usize) ?usize {
    for (toasts.items, 0..) |t, i| {
        if (t.id == id) return i;
    }
    return null;
}

fn expire(id: usize) void {
    const i = indexOf(id) orelse return;
    _ = toasts.orderedRemove(i);
    movePreviousDown();
}

/// Closes the toast with `id` now. The close button passes the id, not a
/// pointer: the toast array shifts as toasts come and go.
fn dismiss(id: usize) void {
    const i = indexOf(id) orelse return;
    toasts.items[i].hide();
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
    cancelToast(toast);
    if (toast.on_close) |callback| {
        callback(toast);
    }
    if (indexOf(toast.id)) |i| _ = toasts.orderedRemove(i);
    showAllToasts();
}

fn getIconColor(toast_type: ToastType) Vapor.Types.Color {
    return switch (toast_type) {
        .success => success_icon_color,
        .err => err_icon_color,
        .warning => warning_icon_color,
        .info => info_icon_color,
    };
}

fn getTypeIcon(toast_type: ToastType) Vapor.IconTokens {
    return switch (toast_type) {
        .success => IconTokens.check2_all,
        .err => IconTokens.exclamation_circle,
        .warning => IconTokens.exclamation_triangle,
        .info => IconTokens.info_circle,
    };
}

fn onHover(_: *Vapor.Event) void {
    expanded = true;
    for (toasts.items) |*t| {
        cancelToast(t);
    }
    showAllToasts();
}

fn onLeave(_: *Vapor.Event) void {
    expanded = false;
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
    } orelse background;
}

fn getTextColor(toast_type: ToastType) Vapor.Types.Color {
    return switch (toast_type) {
        .success => success_text_color,
        .err => err_text_color,
        .warning => warning_text_color,
        .info => info_text_color,
    } orelse text_color;
}

fn getBlur(toast_type: ToastType) u8 {
    return switch (toast_type) {
        .success => success_blur,
        .err => err_blur,
        .warning => warning_blur,
        .info => info_blur,
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

    const on_left = position == .top_left or position == .bottom_left;
    const content_opacity: f16 = if (expanded or index + 1 == toasts.items.len) 1 else 0;

    Box()
        .id(Vapor.fmtln("opaque-toast-{d}", .{toast.id}))
        // Errors interrupt a screen reader; the rest wait their turn.
        .a11y(if (toast.toast_type == .err) .alert() else .statusRegion())
        .shadow(
            Vapor.Types.NewShadow.init()
                .inset(0, -2, .transparentize(.black, 0.1))
                .drop(0, 1, 3, .transparentize(.black, 0.2)),
        )
        .border(.solid(.all(border_thickness), border_color, border_radius))
        .pos(toast_pos)
        .animationEnter(if (on_left) "opaque-toast-enter-left" else "opaque-toast-enter-right")
        .animationExit(if (on_left) "opaque-toast-exit-left" else "opaque-toast-exit-right")
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
        .background(getBackground(toast.toast_type))
        .layout(.x_between_center)
        .padding(.all(8))
        .spacing(8)
        .children({
        // 1. Semantic Icon
        Center()
            .width(.px(32))
            .height(.px(32))
            .opacity(content_opacity)
            .duration(150)
            .children({
            Icon(getTypeIcon(toast.toast_type))
                .font(18, 700, getIconColor(toast.toast_type))
                .end();
        });

        // 2. Text Content (Stacked Vertically)
        Box()
            .direction(.column)
            .layout(.left_center)
            .width(.grow)
            .opacity(content_opacity)
            .duration(150)
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
        Button(dismiss, .{toast.id})
            .ariaLabel("Dismiss notification")
            .class("toast-close")
            .cursor(.pointer)
            .padding(.all(4))
            .opacity(content_opacity)
            .duration(100)
            .hover(.{
                .text_color = .transparentize(getTextColor(toast.toast_type), 0.5),
            })
            .children({
            Vapor.Svg(.{ .svg = close_icon, .override = true })
                .fill(getTextColor(toast.toast_type))
                .hover(.{
                    .fill = .transparentize(getTextColor(toast.toast_type), 0.5),
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
