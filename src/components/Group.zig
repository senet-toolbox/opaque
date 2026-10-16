const Vapor = @import("vapor");
const std = @import("std");
const Box = Vapor.Box;
const Text = Vapor.Text;
const TextField = Vapor.TextField;
const Stack = Vapor.Stack;
const Center = Vapor.Center;
const Icon = Vapor.Icon;
const Label = Vapor.Label;
const utils = Vapor.utils;

var background: Vapor.Types.Color = .palette(.background);

const GroupValue = union(enum) {
    string: *[]const u8,
    number: *i32,
    bool: *bool,
};

// var focus_states: ?std.StringHashMap(bool) = null;

pub fn new() void {
    // focus_states = std.StringHashMap(bool).init(Vapor.arena(.persist));
    focus_states = std.AutoHashMap(usize, bool).init(Vapor.arena(.persist));
}

// Change the map type
var focus_states: ?std.AutoHashMap(usize, bool) = null;

// Helper to extract the unique ID from the input value
fn getPtrId(val: GroupValue) usize {
    return switch (val) {
        .string => |ptr| @intFromPtr(ptr),
        .number => |ptr| @intFromPtr(ptr),
        .bool => |ptr| @intFromPtr(ptr),
    };
}

fn toggleFocus(id: usize, _: *Vapor.Event) void {
    if (focus_states == null) return;
    // We only track the currently focused item, so we can just put it
    // If you want to support multi-focus, use get/put logic
    focus_states.?.put(id, true) catch unreachable;
}

const Group = @This();
label: ?[]const u8 = null,
type: Vapor.Types.InputTypes = .string,
/// Field must be a stable pointer, do not use a pointer within a render function, this is considered unsafe undefined behavior.
value: GroupValue,
icon_left: ?Vapor.IconTokens = null,
icon_right: ?Vapor.IconTokens = null,

fn handleFocus(id: usize, _: *Vapor.Event) void {
    if (focus_states) |*fs| {
        // We only track the active focus.
        // Optional: You could clear other keys here if you want strictly one focus.
        fs.put(id, true) catch unreachable;
    }
}

fn handleBlur(id: usize, _: *Vapor.Event) void {
    if (focus_states) |*fs| {
        // CRITICAL FIX: Only remove THIS specific ID.
        // Your previous code wiped the whole map, which causes race conditions
        // if a user clicks from Field A to Field B quickly.
        _ = fs.remove(id);
    }
}

fn getFieldType(field_value: GroupValue) Vapor.Types.InputTypes {
    return switch (field_value) {
        .string => .string,
        .number => .int,
        else => .string,
    };
}

fn ErasedField(field: Group) Vapor.TextFieldBuilder(.pure) {
    const field_type = getFieldType(field.value);
    return TextField(field_type)
        .fieldName(if (field.label) |label| utils.toLowerCase(label, .frame) else "")
        .font(14, 300, null)
        .padding(.xy(12, 8))
        .outline(.none, null)
        .background(.transparent)
        .fontFamily("Montserrat")
        .font(14, 300, .palette(.text_color));
}

fn destroy(stable_id: usize) void {
    _ = focus_states.?.remove(stable_id);
}

pub fn render(field: Group) void {
    const stable_id = getPtrId(field.value);

    // 1. Check focus state
    const is_focused = if (focus_states) |fs| fs.get(stable_id) orelse false else false;

    // 2. Animation / Style variables
    const trans: f32 = if (is_focused) -50 else 50;
    const scale: f32 = if (is_focused) 0.9 else 1;
    // Adjust label left position if there is a left icon so it doesn't clash
    const base_left: f32 = if (field.icon_left != null) 42 else 12;
    const label_left: f32 = if (is_focused) 12 + base_left else base_left;

    const z_index: f32 = if (is_focused) 10 else 0;
    const text_color: Vapor.Types.Color = if (is_focused) .palette(.tint) else .transparentize(.palette(.text_color), 0.5);

    // 3. Calculate Input Padding based on icons
    // We reserve ~40px of space if an icon is present
    const pad_left: u8 = if (field.icon_left != null) 40 else 12;
    const pad_right: u8 = if (field.icon_right != null) 40 else 12;

    Stack()
        .width(.percent(100))
        .spacing(8)
        .pos(.relative)
        .height(.px(36))
        .onDestroy(destroy, .{stable_id})
        .children({
        // --- 1. RENDER LEFT ICON ---
        if (field.icon_left) |ic| {
            Box()
                .font(18, 300, text_color)
                .pos(.{ .type = .absolute, .left = .px(12), .top = .px(6) })
                .children({
                Icon(ic)
                    .end();
            });
        }

        // --- 2. RENDER RIGHT ICON ---
        if (field.icon_right) |ic| {
            Box()
                .font(18, 300, text_color)
                .pos(.{ .type = .absolute, .right = .px(12), .top = .px(6) })
                .children({
                Icon(ic)
                    .end();
            });
        }

        // --- 3. RENDER LABEL ---
        if (field.label) |label| {
            Label(label)
                .background(background)
                .pos(.{ .left = .px(label_left), .type = .absolute })
                .padding(.horizontal(2))
                .transition(.{
                    .properties = &.{ .transform, .scale, .left },
                    .duration = 100,
                    .timing = .easeInOut,
                })
                .inlineStyle("transform: translateY({d}%) scale({d}); z-index: {d};", .{ trans, scale, z_index })
                .font(14, 300, text_color)
                .fontFamily("Montserrat")
                .end();
        }

        // --- 4. RENDER INPUT FIELD ---
        switch (field.value) {
            .string => {
                const text_field: Vapor.TextFieldBuilder(.pure) = ErasedField(field);
                text_field
                    // OVERRIDE Padding here to account for icons
                    .padding(.{ .top = 8, .bottom = 8, .left = pad_left, .right = pad_right })
                    .pos(.absolute)
                    .onEvent(.focus, handleFocus, .{stable_id})
                    .onEvent(.blur, handleBlur, .{stable_id})
                    .width(.percent(100))
                    .bind(field.value.string)
                    .border(.round(if (is_focused) .palette(.tint) else .palette(.border_color_light), .all(12)))
                    .shadow(Vapor.Types.Shadow.init().dropSpread(0, 0, 0, 3, if (is_focused) .transparentize(.palette(.tint), 0.2) else .transparent))
                    .end();
            },
            .number => {
                const text_field: Vapor.TextFieldBuilder(.pure) = ErasedField(field);
                text_field
                    // OVERRIDE Padding here to account for icons
                    .padding(.{ .top = 8, .bottom = 8, .left = pad_left, .right = pad_right })
                    .onEvent(.focus, handleFocus, .{stable_id})
                    .onEvent(.blur, handleBlur, .{stable_id})
                    .border(.round(if (is_focused) .palette(.tint) else .palette(.border_color_light), .all(12)))
                    .bind(field.value.number)
                    .shadow(Vapor.Types.Shadow.init().dropSpread(0, 0, 0, 2, if (is_focused) .transparentize(.palette(.tint), 0.1) else .transparent))
                    .end();
            },
            else => {},
        }
    });
}
