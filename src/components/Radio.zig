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
//!
//! As a native radio group: Tab stops once, on the chosen item, and the
//! arrow keys move the choice and the focus, wrapping round.

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
    /// The group's id, which its items' ids are made from.
    id: u32,
    /// The items' values in order, gathered afresh each render.
    values: std.ArrayListUnmanaged([]const u8) = .empty,
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
        s.* = .{ .selected = Vapor.utils.hashKey(default_value), .notify = Notify.notify, .ctx = ctx, .id = id };
        groups.put(id, s) catch return container;
        break :blk s;
    };
    state.ctx = ctx;
    state.values = .empty;

    return container
        .a11y(Vapor.Accessibility.radioGroup(name))
        .onEvent(.keydown, onKey, .{state})
        .onDestroy(destroy, .{id}).*;
}

/// An item's id: its group's, and its value's.
fn itemId(state: *const State, value_hash: u32) []const u8 {
    return Vapor.fmtln("radio-{d}-{d}", .{ state.id, value_hash });
}

fn onKey(state: *State, evt: *Vapor.Event) void {
    const count = state.values.items.len;
    if (count == 0) return;
    const key = evt.key();
    const forward = std.mem.eql(u8, key, "ArrowDown") or std.mem.eql(u8, key, "ArrowRight");
    const back = std.mem.eql(u8, key, "ArrowUp") or std.mem.eql(u8, key, "ArrowLeft");
    if (!forward and !back) return;
    evt.preventDefault();

    var current: usize = 0;
    for (state.values.items, 0..) |value, i| {
        if (Vapor.utils.hashKey(value) == state.selected) current = i;
    }
    const next = if (forward) (current + 1) % count else (current + count - 1) % count;
    select(state, state.values.items[next]);
    Vapor.onLayout(focusChosen, .{state});
}

/// Focuses whichever item is chosen when it runs.
fn focusChosen(state: *State) void {
    Vapor.lib.focus(itemId(state, state.selected));
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
    const value_hash = Vapor.utils.hashKey(value);
    const checked = state.selected == value_hash;
    state.values.append(Vapor.frame.arena(), value) catch {};

    Button(select, .{ state, value })
        .id(itemId(state, value_hash))
        .a11y(Vapor.Accessibility.init()
            .setRole(.radio)
            .setChecked(if (checked) .true_val else .false_val))
        // One tab stop: the chosen item.
        .tabIndex(if (checked) 0 else -1)
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
