const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Stack = Vapor.Stack;
const Icon = Vapor.Icon;
const Box = Vapor.Box;
const Animation = Vapor.Animation;
const IconTokens = @import("user_config").IconTokens;
const ButtonCtx = Vapor.CtxButton;

// 1. Types
pub const ToastType = enum { success, err, warning, info };

// 2. State
// We define a container for the Toasts to live in
pub var toasts: Vapor.Array(Toast) = undefined;

const Toast = @This();

title: []const u8,
description: []const u8,
toast_type: ToastType = .info,
is_visible: bool = false,
// We track if we are fully removed to clean up memory
needs_removal: bool = false,
id: usize = 0,
// We don't need 'top' or 'right' anymore; the Layout Engine handles X/Y

// 3. Animations
// Slide in from right
// Define animations (using your API style)
const anim_enter = Animation.init("slideInToast")
    .prop(.translateY, -20, 0)
    .prop(.opacity, 0, 1)
    .duration(300)
    .easing(.easeOut)
    .fill(.forwards);

const anim_exit = Animation.init("fadeOutToast")
    .prop(.opacity, 1, 0)
    .prop(.scale, 1, 0.95)
    .duration(200)
    .easing(.easeIn)
    .fill(.forwards);

pub fn new() void {
    anim_enter.build();
    anim_exit.build();
    toasts = Vapor.array(Toast, .persist);
}

pub const Options = struct {
    title: []const u8,
    description: []const u8,
};

// --- API Methods ---

pub fn add(options: Options, t_type: ToastType) void {
    // Generate a unique ID (simple counter or timestamp)
    const new_id = toasts.items.len + 1;

    const toast = Toast{
        .title = options.title,
        .description = options.description,
        .toast_type = t_type,
        .id = new_id,
        .is_visible = true, // Start visible
    };

    // Append to list. The Render Loop will pick it up next frame.
    // Depending on preference, use insert(0, toast) to push top,
    // or append() to push bottom.
    toasts.insert(0, toast) catch unreachable;
}

// Convenience wrappers
pub fn success(opts: Options) void {
    add(opts, .success);
}
pub fn err(opts: Options) void {
    add(opts, .err);
}
pub fn warning(opts: Options) void {
    add(opts, .warning);
}
pub fn info(opts: Options) void {
    add(opts, .info);
}

pub fn hide(toast: *Toast) void {
    // Trigger the exit animation visually
    toast.is_visible = false;

    for (toasts.items, 0..) |*t, i| {
        if (t.id == toast.id) {
            _ = toasts.orderedRemove(i);
            return;
        }
    }

}

// --- Rendering ---

// 1. The Container (The "Toaster")
// This is fixed to the screen and manages the stack
pub fn renderStack() void {
    if (toasts.items.len == 0) return;

    Box()
        // Fixed Position on Screen (Top Right)
        // This is the ONLY place we use absolute positioning
        .pos(.tr(.px(24), .px(24), .fixed))
        .layout(.top_center) // Stack items downwards, align left
        .spacing(12) // Gap between toasts
        .direction(.column)
        .zIndex(9999) // Ensure it floats above everything
        .children({
        // Iterate and Render
        // We use a mutable slice because we might modify state
        for (toasts.items) |*t| {
            renderToastItem(t);
        }
    });
}

// 2. The Individual Item
fn renderToastItem(toast: *Toast) void {
    // If we marked it for removal, don't render (or let the cleanup loop handle it)
    if (toast.needs_removal) return;
    Box()
        // Position: Top Right, fixed/absolute
        // .pos(.tr(.px(toast.top), .px(toast.right), .absolute))
        // Animation applied here
        .animationEnter(&anim_enter)
        .animationExit(&anim_exit)

        // Container Styling
        .width(.px(200)) // Fixed width usually looks better than % for toasts
        .background(.palette(.text_color)) // Use a Surface color (dark grey or white)
        .border(.round(.palette(.text_color), .all(6))) // Modern rounded corners

        // Improved Shadow for "Pop"
        .shadow(.{
            .blur = 12,
            .color = .transparentizeHex(.black, 0.15),
            .top = 4,
            .spread = 0,
        })

        // Layout: Row (Icon -> Content -> Close)
        .layout(.x_between_center) // Vertically center items
        .padding(.all(8))
        .spacing(8)
        .children({
        // 1. Semantic Icon
        Icon(getTypeIcon(toast.toast_type))
            .font(16, 700, .white)
            .end();

        // 2. Text Content (Stacked Vertically)
        Box()
            .spacing(8)
            .layout(.left_center)
            // .width(.grow) // Take up remaining space
            .children({
            // Title
            Text(toast.title)
                .font(14, 600, .white)
                .end();

            // Description
            Text(toast.description)
                .font(13, 400, .white)
                // .lineHeight(1.4)
                .end();
        });

        // 3. Close Button
        ButtonCtx(hide, .{toast})
            .class("toast-close")
            .cursor(.pointer)
            .padding(.all(4))
            .duration(100)
            .hover(.{
                .text_color = .transparentizeHex(.white, 0.5),
            })
            .children({
            Icon(.x_lg)
                .font(16, 700, .white)
                .inheritHover(&.{.text_color})
                .end();
        });
    });
}

// Helpers
fn getTypeColor(t: ToastType) Vapor.Types.Color {
    return switch (t) {
        .success => .hex("#10B981"),
        .err => .hex("#EF4444"),
        .warning => .hex("#F59E0B"),
        .info => .hex("#3B82F6"),
    };
}

fn getTypeIcon(t: ToastType) *const IconTokens {
    return switch (t) {
        .success => IconTokens.check_circle,
        .err => IconTokens.exclamation_circle,
        .warning => IconTokens.exclamation_circle,
        .info => IconTokens.info_circle,
    };
}
