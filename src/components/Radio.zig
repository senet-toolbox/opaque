//! Radio buttons: one choice out of a group.
//!
//!   Radio.Group("density", "default", onDensity, .{}).children({
//!       Radio.Item("default", "Default");
//!       Radio.Item("comfortable", "Comfortable");
//!   });
//!
//!   fn onDensity(value: []const u8) void { ... }
//!
//! `on_change` is called with `args` followed by the chosen value, only when
//! the choice changes. The group starts on `default_value`.

const Vapor = @import("vapor");
const std = @import("std");
const Row = Vapor.Row;
const Stack = Vapor.Stack;
const Button = Vapor.Button;
const Text = Vapor.Text;

pub var ring_color: Vapor.Types.Color = .palette(.border_color_light);
pub var checked_color: Vapor.Types.Color = .palette(.tint);

const State = struct {
    /// hashKey of the chosen value.
    selected: u32,
    /// Calls the group's on_change with `ctx` (its args) and the value.
    notify: *const fn (ctx: *const anyopaque, value: []const u8) void,
    /// The on_change args, copied into the current render's frame arena on
    /// every render, so a click between renders always finds live ones.
    ctx: *const anyopaque,
};

var groups: std.AutoHashMap(u32, *State) = undefined;

pub fn new() void {
    groups = std.AutoHashMap(u32, *State).init(Vapor.arena(.persist));
}

fn destroy(id: u32) void {
    _ = groups.remove(id);
}

/// A group of `Item`s; `name` labels it for screen readers.
pub fn Group(name: []const u8, default_value: []const u8, comptime on_change: anytype, args: anytype) Vapor.Builder(.pure) {
    const Args = @TypeOf(args);
    const Notify = struct {
        fn notify(ctx: *const anyopaque, value: []const u8) void {
            const a: *const Args = @ptrCast(@alignCast(ctx));
            @call(.auto, on_change, a.* ++ .{value});
        }
    };

    const container = Stack().spacing(12);
    const id = Vapor.utils.hashKey(container.getUUID());
    const ctx = Vapor.frame.arena().create(Args) catch return container;
    ctx.* = args;

    const state = groups.get(id) orelse blk: {
        const s = Vapor.arena(.persist).create(State) catch return container;
        s.* = .{ .selected = Vapor.utils.hashKey(default_value), .notify = Notify.notify, .ctx = ctx };
        groups.put(id, s) catch return container;
        break :blk s;
    };
    state.ctx = ctx;

    return container
        .a11y(Vapor.Accessibility.radioGroup(name))
        .onDestroy(destroy, .{id}).*;
}

fn select(state: *State, value: []const u8) void {
    const hash = Vapor.utils.hashKey(value);
    if (state.selected == hash) return;
    state.selected = hash;
    state.notify(state.ctx, value);
}

/// One choice; call it inside a `Group`'s children.
pub fn Item(value: []const u8, label: []const u8) void {
    const group_node = Vapor.lib.getCurrentNode() orelse return;
    const state = groups.get(Vapor.utils.hashKey(group_node.uuid)) orelse {
        Vapor.print(.err, "Radio.Item must be inside a Radio.Group", .{});
        return;
    };
    const checked = state.selected == Vapor.utils.hashKey(value);

    Button(select, .{ state, value })
        .a11y(Vapor.Accessibility.init()
            .setRole(.radio)
            .setChecked(if (checked) .true_val else .false_val))
        .layout(.left_center)
        .spacing(10)
        .background(.transparent)
        .cursor(.pointer)
        .children({
        Row()
            .width(.px(20))
            .height(.px(20))
            .border(.round(if (checked) checked_color else ring_color, .all(99)))
            .layout(.center)
            .children({
            if (checked) {
                Row().width(.px(10)).height(.px(10))
                    .background(checked_color)
                    .radius(.all(99))
                    .children({});
            }
        });
        Text(label)
            .font(16, 300, .palette(.text_color))
            .end();
    });
}
