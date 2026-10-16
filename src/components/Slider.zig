//! A horizontal slider: drag the handle or press the track, or, once it has
//! focus, use the arrow keys, Home/End and Page Up/Down.
//!
//!   Slider.render(.{ .label = "Volume", .value = 40, .on_change = setVolume });
//!
//! Each slider keeps its own value after the first render; `value` is where
//! it starts.

const std = @import("std");
const Vapor = @import("vapor");
const Box = Vapor.Box;

const handle_size = 18;

const State = struct {
    value: f32,
    options: Slider,
    track: Vapor.Element = .{},
    /// Document pointer listeners, while a drag is under way.
    move_listener: ?u32 = null,
    up_listener: ?u32 = null,
};

var states: std.AutoHashMap(u32, *State) = undefined;

pub fn new() void {
    states = std.AutoHashMap(u32, *State).init(Vapor.arena(.persist));
}

const Slider = @This();
max: f32 = 100,
min: f32 = 0,
value: f32 = 0,
step: f32 = 1,
/// Names the slider for screen readers.
label: []const u8 = "Slider",
/// Called with the new value whenever it changes.
on_change: ?*const fn (value: f32) void = null,

/// `raw` kept within min..max and on a step.
fn snap(options: Slider, raw: f32) f32 {
    const clamped = std.math.clamp(raw, options.min, options.max);
    if (options.step <= 0) return clamped;
    const stepped = options.min + @round((clamped - options.min) / options.step) * options.step;
    return std.math.clamp(stepped, options.min, options.max);
}

fn setValue(state: *State, raw: f32) void {
    const value = snap(state.options, raw);
    if (value == state.value) return;
    state.value = value;
    if (state.options.on_change) |on_change| on_change(value);
}

/// The value under the pointer's horizontal position.
fn valueAt(state: *State, client_x: f32) ?f32 {
    const rect = state.track.getBoundingClientRect() orelse return null;
    if (rect.width <= 0) return null;
    const options = state.options;
    return options.min + (client_x - rect.left) / rect.width * (options.max - options.min);
}

fn pointerDown(state: *State, evt: *Vapor.Event) void {
    evt.preventDefault();
    if (valueAt(state, evt.clientX())) |value| setValue(state, value);
    if (state.move_listener == null) {
        state.move_listener = Vapor.addGlobalListenerCtx(.pointermove, pointerMove, .{state});
    }
    if (state.up_listener == null) {
        state.up_listener = Vapor.addGlobalListenerCtx(.pointerup, pointerUp, .{state});
    }
}

fn pointerMove(state: *State, evt: *Vapor.Event) void {
    const value = valueAt(state, evt.clientX()) orelse return;
    const before = state.value;
    setValue(state, value);
    if (state.value != before) Vapor.cycle();
}

fn pointerUp(state: *State, _: *Vapor.Event) void {
    stopDrag(state);
}

fn stopDrag(state: *State) void {
    if (state.move_listener) |id| _ = Vapor.removeGlobalListener(.pointermove, id);
    if (state.up_listener) |id| _ = Vapor.removeGlobalListener(.pointerup, id);
    state.move_listener = null;
    state.up_listener = null;
}

fn keyDown(state: *State, evt: *Vapor.Event) void {
    const key = evt.key();
    const options = state.options;
    const step = if (options.step > 0) options.step else (options.max - options.min) / 100;
    const eql = std.mem.eql;
    const target: f32 = if (eql(u8, key, "ArrowRight") or eql(u8, key, "ArrowUp"))
        state.value + step
    else if (eql(u8, key, "ArrowLeft") or eql(u8, key, "ArrowDown"))
        state.value - step
    else if (eql(u8, key, "PageUp"))
        state.value + step * 10
    else if (eql(u8, key, "PageDown"))
        state.value - step * 10
    else if (eql(u8, key, "Home"))
        options.min
    else if (eql(u8, key, "End"))
        options.max
    else
        return;
    evt.preventDefault();
    setValue(state, target);
}

fn destroy(id: u32) void {
    if (states.get(id)) |state| stopDrag(state);
    _ = states.remove(id);
}

pub fn render(options: Slider) void {
    const container = Box()
        .pos(.relative)
        .width(.percent(100))
        .height(.px(handle_size));
    const id = Vapor.utils.hashKey(container.getUUID());
    const state = states.get(id) orelse blk: {
        const s = Vapor.arena(.persist).create(State) catch return;
        s.* = .{ .value = snap(options, options.value), .options = options };
        states.put(id, s) catch return;
        break :blk s;
    };
    // Bounds and callback follow the latest render; the value is the slider's.
    state.options = options;
    const percent: f32 = if (options.max > options.min)
        (state.value - options.min) / (options.max - options.min) * 100
    else
        0;

    container
        .onEvent(.pointerdown, pointerDown, .{state})
        .onDestroy(destroy, .{id})
        .cursor(.pointer)
        .layout(.left_center)
        .children({
        Box()
            .ref(&state.track)
            .pos(.relative)
            .width(.percent(100))
            .height(.px(6))
            .radius(.all(99))
            .background(.palette(.border_color_light))
            .children({
            // The filled part, up to the handle.
            Box()
                .pos(.{ .type = .absolute, .top = .px(0), .left = .px(0) })
                .height(.percent(100))
                .width(.percent(percent))
                .radius(.all(99))
                .background(.palette(.text_color))
                .children({});
            Box()
                .a11y(Vapor.Accessibility.slider(state.value, options.min, options.max).setLabel(options.label))
                .tabIndex(0)
                .onEvent(.keydown, keyDown, .{state})
                .pos(.{ .type = .absolute, .top = .px(-6) })
                .inlineStyle("left: calc({d}% - {d}px);", .{ percent, handle_size / 2 })
                .width(.px(handle_size))
                .height(.px(handle_size))
                .border(.round(.palette(.alternate_background), .all(99)))
                .background(.white)
                .children({});
        });
    });
}
