// ============================================================================
// Field.zig — Opaque input field component
// ============================================================================

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
const Opaque = @import("../components/Opaque.zig");
const DatePicker = Opaque.DatePicker;
const Button = Vapor.Button;

const DatePickerConfig = struct {
    date_picker: DatePicker, // embedded, not a pointer
    show: bool = false,
    field_value: ?*Vapor.DateTime = null,
    format_str: *[]const u8 = undefined,
};

// ============================================================================
// Types
// ============================================================================

pub const FieldType = enum {
    string,
    number,
    password,
    email,
    credit_card,
    telephone,
    cvv,
    expiry,
    float,
    date,
    int64,
};

/// The value binding for a Field.
///
/// Each variant holds a *stable* pointer to the backing data.
/// See the module-level doc comment for what "stable" means.
pub const Value = union(enum) {
    string: *[]const u8,
    password: *[]const u8,
    number: *i32,
    bool: *bool,
    email: *[]const u8,
    credit_card: *[]const u8,
    telephone: *[]const u8,
    float: *f32,
    date: *Vapor.DateTime,
    int64: *i64,
};

pub const DefaultValue = union(enum) {
    string: []const u8,
    number: i32,
    bool: bool,
    float: f32,
    date: Vapor.DateTime,
    int64: i64,
};

const Callback = struct {
    value: ?Value = null,
    on_change: ?*const fn (evt: *Vapor.Event) void = null,
    on_enter: ?*const fn (evt: *Vapor.Event) void = null,
    on_focus: ?*const fn (evt: *Vapor.Event) void = null,
    on_blur: ?*const fn (evt: *Vapor.Event) void = null,
    format_str: ?*[]const u8 = null,
};

// ============================================================================
// Field struct
// ============================================================================

const Field = @This();

label: ?[]const u8 = null,
field_name: []const u8 = "",
type: FieldType = .string,
trans_label: bool = false,

/// The value binding. MUST point to a stable address — see module doc.
/// Do not use a pointer derived from a render function local or a
/// growable array element; those can move on reallocation.
value: ?Value = null,

config: Vapor.Types.TextFieldConfig = .{},
default_value: ?DefaultValue = null,
on_change: ?*const fn (evt: *Vapor.Event) void = null,
on_focus: ?*const fn (evt: *Vapor.Event) void = null,
on_blur: ?*const fn (evt: *Vapor.Event) void = null,
on_enter: ?*const fn (evt: *Vapor.Event) void = null,
_on_change: ?Vapor.lib.ErasedEventCallback = null,
id: ?[]const u8 = null,
placeholder: ?DefaultValue = null,
background: Vapor.Types.Color = .palette(.background),
text_color: Vapor.Types.Color = .palette(.text),
tint_color: Vapor.Types.Color = .palette(.tint),
_container: ?Vapor.Builder(.pure) = null,
is_focused: bool = false,
focused: bool = false,

// ============================================================================
// Global State
// ============================================================================
//
// These maps are keyed by the component's stable UUID (from the Vapor
// virtual DOM). They persist across render cycles so that focus state
// and value bindings survive re-renders.

/// Tracks which field is currently focused, keyed by stable_id.
var focus_states: ?std.StringHashMap(bool) = null;

/// Stores the Value (pointer) for each field instance.
/// Once a value is inserted for a given stable_id, it is NEVER updated —
/// the original pointer is reused on every subsequent render.
/// This is why the pointer must be stable.
var field_values: std.StringHashMap(Value) = undefined;

/// Stores allocated Field structs created via `Field.create()`.
var fields: std.StringHashMap(*Field) = undefined;

var date_pickers: std.StringHashMap(*DatePickerConfig) = undefined;

// ============================================================================
// Lifecycle
// ============================================================================

pub fn new() void {
    focus_states = std.StringHashMap(bool).init(Vapor.arena(.persist));
    field_values = std.StringHashMap(Value).init(Vapor.arena(.persist));
    fields = std.StringHashMap(*Field).init(Vapor.arena(.persist));
    date_pickers = std.StringHashMap(*DatePickerConfig).init(Vapor.arena(.persist));
}

// ============================================================================
// Focus Handling
// ============================================================================

fn handleFocus(id: []const u8, callback: Callback, evt: *Vapor.Event) void {
    if (focus_states != null) {
        focus_states.?.put(id, true) catch unreachable;
    }
    if (callback.on_focus) |on_focus| {
        on_focus(evt);
    }
}

fn handleBlur(id: []const u8, callback: Callback, evt: *Vapor.Event) void {
    if (focus_states != null) {
        focus_states.?.put(id, false) catch unreachable;
    }

    if (callback.on_blur) |on_blur| {
        on_blur(evt);
    }
}

fn toggleFocus(id: []const u8, _: *Vapor.Event) void {
    if (focus_states == null) return;
    focus_states.?.put(id, true) catch unreachable;
}

// ============================================================================
// Value Management
// ============================================================================

/// Helper to extract a unique ID from the pointer address inside a Value.
fn getPtrId(val: Value) usize {
    return switch (val) {
        .string => |ptr| @intFromPtr(ptr),
        .number => |ptr| @intFromPtr(ptr),
        .bool => |ptr| @intFromPtr(ptr),
        .password => |ptr| @intFromPtr(ptr),
        .email => |ptr| @intFromPtr(ptr),
        .credit_card => |ptr| @intFromPtr(ptr),
        .telephone => |ptr| @intFromPtr(ptr),
        .float => |ptr| @intFromPtr(ptr),
        .date => |ptr| @intFromPtr(ptr),
        .int64 => |ptr| @intFromPtr(ptr),
    };
}

/// Inserts a Value for the given stable_id, but ONLY if one doesn't
/// already exist. This means the first pointer wins — subsequent calls
/// with a different pointer for the same stable_id are silently ignored.
///
/// This is the core reason pointers must be stable: if the first render
/// passes pointer A and a later render passes pointer B (because the
/// backing array reallocated), the Field will still use pointer A.
fn insertValue(stable_id: []const u8, value: Value) void {
    const entry = field_values.getPtr(stable_id) orelse {
        const stable_id_alloc = Vapor.arena(.persist).alloc(u8, stable_id.len) catch unreachable;
        @memcpy(stable_id_alloc, stable_id);
        field_values.put(stable_id_alloc, value) catch unreachable;
        focus_states.?.put(stable_id_alloc, false) catch unreachable;
        return;
    };
    entry.* = value;
}

/// Creates a new managed Value (with its own persist-allocated backing)
/// for fields that don't pass an external `.value` pointer.
/// Only allocates on the first call for a given stable_id; returns the
/// cached value on subsequent calls.
fn createValue(stable_id: []const u8, field_type: FieldType, default_value: ?DefaultValue) Value {
    return field_values.get(stable_id) orelse {
        const stable_id_alloc = Vapor.arena(.persist).alloc(u8, stable_id.len) catch unreachable;
        @memcpy(stable_id_alloc, stable_id);
        return switch (field_type) {
            .string, .cvv, .expiry => {
                const string_field = Vapor.arena(.persist).create([]const u8) catch unreachable;
                string_field.* = if (default_value) |default| default.string else "";
                const value = Value{ .string = string_field };
                field_values.put(stable_id_alloc, value) catch unreachable;
                focus_states.?.put(stable_id_alloc, false) catch unreachable;
                return value;
            },
            .credit_card => {
                const string_field = Vapor.arena(.persist).create([]const u8) catch unreachable;
                var formatted: []const u8 = "";
                if (default_value) |default| {
                    formatted = default.string;
                    var buf: [32]u8 = undefined;
                    formatted = Vapor.frame.fmt("{s}", .{formatCreditCard(default.string, buf[0..])});
                }
                string_field.* = formatted;
                const value = Value{ .credit_card = string_field };
                field_values.put(stable_id_alloc, value) catch unreachable;
                focus_states.?.put(stable_id_alloc, false) catch unreachable;
                return value;
            },
            .password => {
                const string_field = Vapor.arena(.persist).create([]const u8) catch unreachable;
                string_field.* = if (default_value) |default| default.string else "";
                const value = Value{ .password = string_field };
                field_values.put(stable_id_alloc, value) catch unreachable;
                focus_states.?.put(stable_id_alloc, false) catch unreachable;
                return value;
            },
            .email => {
                const string_field = Vapor.arena(.persist).create([]const u8) catch unreachable;
                string_field.* = if (default_value) |default| default.string else "";
                const value = Value{ .email = string_field };
                field_values.put(stable_id_alloc, value) catch unreachable;
                focus_states.?.put(stable_id_alloc, false) catch unreachable;
                return value;
            },
            .number => {
                const int_field = Vapor.arena(.persist).create(i32) catch unreachable;
                int_field.* = if (default_value) |default| default.number else 0;
                const value = Value{ .number = int_field };
                field_values.put(stable_id_alloc, value) catch unreachable;
                focus_states.?.put(stable_id_alloc, false) catch unreachable;
                return value;
            },
            .float => {
                const float_field = Vapor.arena(.persist).create(f32) catch unreachable;
                float_field.* = if (default_value) |default| default.float else 0;
                const value = Value{ .float = float_field };
                field_values.put(stable_id_alloc, value) catch unreachable;
                focus_states.?.put(stable_id_alloc, false) catch unreachable;
                return value;
            },
            .int64 => {
                const int64_field = Vapor.arena(.persist).create(i64) catch unreachable;
                int64_field.* = if (default_value) |default| default.int64 else 0;
                const value = Value{ .int64 = int64_field };
                field_values.put(stable_id_alloc, value) catch unreachable;
                focus_states.?.put(stable_id_alloc, false) catch unreachable;
                return value;
            },
            .telephone => {
                const telephone_field = Vapor.arena(.persist).create([]const u8) catch unreachable;
                telephone_field.* = if (default_value) |default| default.string else "";
                const value = Value{ .telephone = telephone_field };
                field_values.put(stable_id_alloc, value) catch unreachable;
                focus_states.?.put(stable_id_alloc, false) catch unreachable;
                return value;
            },
            .date => {
                const date_field = Vapor.arena(.persist).create(Vapor.DateTime) catch unreachable;
                date_field.* = if (default_value) |default| default.date else Vapor.DateTime.now();
                const value = Value{ .date = date_field };
                field_values.put(stable_id_alloc, value) catch unreachable;
                focus_states.?.put(stable_id_alloc, false) catch unreachable;
                return value;
            },
        };
    };
}

fn checkLength(value: Value) bool {
    switch (value) {
        .string, .telephone, .credit_card, .email, .password => |v| {
            if (v.*.len > 0) {
                return true;
            }
        },
        .number => |v| {
            if (v.* > 0) {
                return true;
            }
        },
        .float => |v| {
            if (v.* > 0) {
                return true;
            }
        },
        .int64 => |v| {
            if (v.* > 0) {
                return true;
            }
        },
        else => {},
    }
    return false;
}

fn destroy(stable_id: []const u8) void {
    _ = focus_states.?.fetchRemove(stable_id); // Don't early return

    const field_value = field_values.fetchRemove(stable_id) orelse return;
    Vapor.arena(.persist).free(field_value.key);

    // Destroy the inner allocated pointer
    switch (field_value.value) {
        .string => |ptr| Vapor.arena(.persist).destroy(ptr),
        .password => |ptr| Vapor.arena(.persist).destroy(ptr),
        .email => |ptr| Vapor.arena(.persist).destroy(ptr),
        .credit_card => |ptr| Vapor.arena(.persist).destroy(ptr),
        .telephone => |ptr| Vapor.arena(.persist).destroy(ptr),
        .number => |ptr| Vapor.arena(.persist).destroy(ptr),
        .bool => |ptr| Vapor.arena(.persist).destroy(ptr),
        .float => |ptr| Vapor.arena(.persist).destroy(ptr),
        .date => |ptr| Vapor.arena(.persist).destroy(ptr),
        .int64 => |ptr| Vapor.arena(.persist).destroy(ptr),
    }
}

// ============================================================================
// Format Helpers
// ============================================================================

/// Format credit card: "1234567890123456" -> "1234 5678 9012 3456"
pub fn formatCreditCard(input: []const u8, buf: []u8) []u8 {
    var digits: [16]u8 = undefined;
    var digit_count: usize = 0;

    for (input) |c| {
        if (c >= '0' and c <= '9') {
            if (digit_count < 16) {
                digits[digit_count] = c;
                digit_count += 1;
            }
        }
    }

    var out_idx: usize = 0;
    for (digits[0..digit_count], 0..) |c, i| {
        if (i > 0 and i % 4 == 0) {
            buf[out_idx] = ' ';
            out_idx += 1;
        }
        buf[out_idx] = c;
        out_idx += 1;
    }

    return buf[0..out_idx];
}

pub fn formatPhone(input: []const u8, buf: []u8) []u8 {
    var digits: [10]u8 = undefined;
    var digit_count: usize = 0;

    for (input) |c| {
        if (c >= '0' and c <= '9') {
            if (digit_count < 10) {
                digits[digit_count] = c;
                digit_count += 1;
            }
        }
    }

    var out_idx: usize = 0;

    if (digit_count >= 1) {
        buf[out_idx] = '(';
        out_idx += 1;
    }

    for (digits[0..@min(digit_count, 3)]) |c| {
        buf[out_idx] = c;
        out_idx += 1;
    }

    if (digit_count >= 3) {
        buf[out_idx] = ')';
        out_idx += 1;
        buf[out_idx] = ' ';
        out_idx += 1;
    }

    if (digit_count > 3) {
        for (digits[3..@min(digit_count, 6)]) |c| {
            buf[out_idx] = c;
            out_idx += 1;
        }
    }

    if (digit_count >= 6) {
        buf[out_idx] = '-';
        out_idx += 1;
    }

    if (digit_count > 6) {
        for (digits[6..digit_count]) |c| {
            buf[out_idx] = c;
            out_idx += 1;
        }
    }

    return buf[0..out_idx];
}

// ============================================================================
// Input Callbacks
// ============================================================================

pub fn creditCardCallback(callback: Callback, evt: *Vapor.Event) void {
    const credit_card_buf = callback.value.?.credit_card;
    credit_card_buf.* = evt.text();
    const text = evt.text();
    if (text.len == 0) return;
    if (text.len > 16) return;
    var buf: [32]u8 = undefined;
    const formatted = formatCreditCard(evt.text(), buf[0..]);
    credit_card_buf.* = Vapor.fmtln("{s}", .{formatted});
}

fn telephoneCallback(callback: Callback, evt: *Vapor.Event) void {
    const telephone_buf = callback.value.?.telephone;
    telephone_buf.* = evt.text();
    const text = evt.text();
    if (text.len == 0) return;
    if (text.len > 10) return;
    var buf: [32]u8 = undefined;
    const formatted = formatPhone(evt.text(), buf[0..]);
    telephone_buf.* = Vapor.fmtln("{s}", .{formatted});
    if (callback.on_change) |on_change| {
        on_change(evt);
    }
}

fn stringCallback(field: Field, evt: *Vapor.Event) void {
    const callback = field.on_change;
    const callback_args = field._on_change;
    const string_buf = field.value.?.string;
    const text = evt.text();
    string_buf.* = text;

    if (callback) |on_change| {
        on_change(evt);
    }

    if (callback_args) |erased| {
        erased.call(evt);
    }
}

fn stringEnterCallback(callback: Callback, evt: *Vapor.Event) void {
    const key = evt.key();
    if (std.mem.eql(u8, key, "Enter")) {
        evt.preventDefault();
        evt.stopPropagation();
        if (callback.on_enter) |on_enter| {
            on_enter(evt);
        }
    }
}

fn passwordCallback(callback: Callback, evt: *Vapor.Event) void {
    const password_buf = callback.value.?.password;
    const text = evt.text();
    password_buf.* = text;

    if (callback.on_change) |on_change| {
        on_change(evt);
    }
}

fn emailCallback(callback: Callback, evt: *Vapor.Event) void {
    const email_buf = callback.value.?.email;
    const text = evt.text();
    email_buf.* = text;

    if (callback.on_change) |on_change| {
        on_change(evt);
    }
}

fn numberCallback(callback: Callback, evt: *Vapor.Event) void {
    const number_buf = callback.value.?.number;
    const number = evt.number() catch 0;
    number_buf.* = number;

    if (callback.on_change) |on_change| {
        on_change(evt);
    }
}

fn int64Callback(callback: Callback, evt: *Vapor.Event) void {
    const int64_buf = callback.value.?.int64;
    const int64 = evt.int64() catch 0;
    int64_buf.* = int64;

    if (callback.on_change) |on_change| {
        on_change(evt);
    }
}

fn floatCallback(callback: Callback, evt: *Vapor.Event) void {
    const float_buf = callback.value.?.float;
    const float = evt.float() catch 0;
    float_buf.* = float;

    if (callback.on_change) |on_change| {
        on_change(evt);
    }
}

fn toggleDatePicker(config: *DatePickerConfig) void {
    config.show = !config.show;
}

/// Format date input: "16022026" -> "16/02/2026"
/// With time: "16022026143022" -> "16/02/2026, 14:30:22"
pub fn formatDateInput(input: []const u8, buf: []u8) []u8 {
    var digits: [14]u8 = undefined;
    var digit_count: usize = 0;

    for (input) |c| {
        if (c >= '0' and c <= '9') {
            if (digit_count < 14) {
                digits[digit_count] = c;
                digit_count += 1;
            }
        }
    }

    var out_idx: usize = 0;

    // DD
    for (digits[0..@min(digit_count, 2)]) |c| {
        buf[out_idx] = c;
        out_idx += 1;
    }

    if (digit_count > 2) {
        buf[out_idx] = '/';
        out_idx += 1;
    }

    // MM
    if (digit_count > 2) {
        for (digits[2..@min(digit_count, 4)]) |c| {
            buf[out_idx] = c;
            out_idx += 1;
        }
    }

    if (digit_count > 4) {
        buf[out_idx] = '/';
        out_idx += 1;
    }

    // YYYY
    if (digit_count > 4) {
        for (digits[4..@min(digit_count, 8)]) |c| {
            buf[out_idx] = c;
            out_idx += 1;
        }
    }

    if (digit_count > 8) {
        buf[out_idx] = ',';
        out_idx += 1;
        buf[out_idx] = ' ';
        out_idx += 1;
    }

    // HH
    if (digit_count > 8) {
        for (digits[8..@min(digit_count, 10)]) |c| {
            buf[out_idx] = c;
            out_idx += 1;
        }
    }

    if (digit_count > 10) {
        buf[out_idx] = ':';
        out_idx += 1;
    }

    // mm
    if (digit_count > 10) {
        for (digits[10..@min(digit_count, 12)]) |c| {
            buf[out_idx] = c;
            out_idx += 1;
        }
    }

    if (digit_count > 12) {
        buf[out_idx] = ':';
        out_idx += 1;
    }

    // ss
    if (digit_count > 12) {
        for (digits[12..@min(digit_count, 14)]) |c| {
            buf[out_idx] = c;
            out_idx += 1;
        }
    }

    return buf[0..out_idx];
}

fn dateCallback(callback: Callback, evt: *Vapor.Event) void {
    const date_buf = callback.value.?.date;
    const text = evt.text();

    // Update the format string for display (like credit card does)
    const fmt_str = callback.format_str orelse return;

    if (text.len == 0) {
        fmt_str.* = "";
        date_buf.* = Vapor.DateTime.now();
        return;
    }

    // Format the display text and write it into the format_str buffer
    var buf: [32]u8 = undefined;
    const formatted = formatDateInput(text, buf[0..]);
    fmt_str.* = Vapor.fmtln("{s}", .{formatted});

    // Extract raw digits
    var digits: [14]u8 = undefined;
    var digit_count: usize = 0;
    for (text) |c| {
        if (c >= '0' and c <= '9') {
            if (digit_count < 14) {
                digits[digit_count] = c;
                digit_count += 1;
            }
        }
    }

    // Parse into DateTime once we have at least ddMMyyyy
    if (digit_count >= 8) {
        const day = std.fmt.parseInt(u8, digits[0..2], 10) catch return;
        const month = std.fmt.parseInt(u8, digits[2..4], 10) catch return;
        const year = std.fmt.parseInt(i32, digits[4..8], 10) catch return;

        if (month < 1 or month > 12) return;
        if (day < 1 or day > Vapor.DateTime.getDaysInMonth(month, year)) return;

        var hour: u8 = date_buf.hour;
        var minute: u8 = date_buf.minute;
        var second: u8 = date_buf.second;

        if (digit_count >= 10) {
            hour = std.fmt.parseInt(u8, digits[8..10], 10) catch return;
            if (hour > 23) return;
        }
        if (digit_count >= 12) {
            minute = std.fmt.parseInt(u8, digits[10..12], 10) catch return;
            if (minute > 59) return;
        }
        if (digit_count >= 14) {
            second = std.fmt.parseInt(u8, digits[12..14], 10) catch return;
            if (second > 59) return;
        }

        date_buf.* = Vapor.DateTime.init(year, month, day, hour, minute, second);
    }

    if (callback.on_change) |on_change| {
        on_change(evt);
    }
}

/// Helper to sync the format_str from a DateTime value (used by date picker selection)
fn syncFormatStr(fmt_str: *[]const u8, dt: Vapor.DateTime) void {
    if (dt.year != 0) {
        fmt_str.* = Vapor.fmtln("{d:0>2}/{d:0>2}/{d}, {d:0>2}:{d:0>2}:{d:0>2}", .{
            dt.day,
            dt.month,
            dt.year,
            dt.hour,
            dt.minute,
            dt.second,
        });
    } else {
        fmt_str.* = "";
    }
}

fn onDatePickerSelect(date_picker: *DatePicker, date_time: Vapor.DateTime) void {
    const config: *DatePickerConfig = @alignCast(@fieldParentPtr("date_picker", date_picker));
    if (config.field_value) |fv| {
        fv.* = date_time;
    }
    // Sync the format string so the text field updates
    syncFormatStr(config.format_str, date_time);
    config.show = false;
}

// ============================================================================
// Internal Rendering Helpers
// ============================================================================

fn getFieldType(field_value: FieldType) Vapor.Types.InputTypes {
    return switch (field_value) {
        .string => .string,
        .number => .int,
        .password => .password,
        .email => .email,
        .credit_card => .string,
        .telephone => .string,
        .float => .float,
        .date => .string,
        .int64 => .int,
        else => .string,
    };
}

fn getFieldTypeFromValue(field_value: Value) FieldType {
    return switch (field_value) {
        .email => .email,
        .string => .string,
        .telephone => .telephone,
        .number => .number,
        .password => .password,
        .credit_card => .credit_card,
        .float => .float,
        .date => .date,
        .int64 => .int64,
        else => .string,
    };
}

fn Container() Vapor.Builder(.pure) {
    return Stack()
        .width(.percent(100));
}

/// The input for `field`. `kind` is the field's type as its value gives it:
/// `field.type` keeps its default (.string) when only a value is passed.
fn ErasedField(field: Field, kind: FieldType, field_id: []const u8) Vapor.TextFieldBuilder(.pure) {
    const field_type = getFieldType(kind);

    if (!field.focused) {
        return TextField(field_type)
            .id(field_id)
            .fieldName(field.field_name)
            .height(.percent(100))
            .padding(.horizontal(12))
            .outline(.none, null)
            .background(.transparent)
            .font(14, 300, field.text_color);
    } else {
        return TextField(field_type)
            .id(field_id)
            .fieldName(field.field_name)
            .height(.percent(100))
            .padding(.horizontal(12))
            .outline(.none, null)
            .background(.transparent)
            .font(14, 300, field.text_color)
            .focus();
    }
}

fn renderLabel(
    label: []const u8,
    label_left: f32,
    trans: f32,
    scale: f32,
    z_index: f32,
    text_color: Vapor.Types.Color,
    background: Vapor.Types.Color,
) Vapor.Builder(.pure) {
    return Label(label)
        .background(background)
        .pos(.{ .left = .px(label_left), .type = .absolute, .top = if (trans == -50) .percent(50) else .percent(0) })
        .padding(.horizontal(2))
        .transition(.{
            .properties = &.{ .transform, .left, .top },
            .duration = 100,
            .timing = .easeInOut,
        })
        .font(14, 300, text_color)
        .inlineStyle("transform: translateY({d}%) scale({d}); z-index: {d}; text-align: center;", .{ -50, scale, z_index });
}

// ============================================================================
// Public API: render() — standalone usage
// ============================================================================
//
// Usage:
//   // `my_name` must be a module-level var, NOT a local or array element.
//   var my_name: []const u8 = "";
//   Field.render(.{ .label = "Name", .value = .{ .string = &my_name } });

pub fn render(field: Field) void {
    const container = Container();
    const stable_id = container.getUUID();
    var value: Value = undefined;
    if (field.value) |v| {
        insertValue(stable_id, v);
        value = v;
    } else {
        value = createValue(stable_id, field.type, field.default_value);
    }
    var field_type = field.type;
    if (field.value) |v| {
        field_type = getFieldTypeFromValue(v);
    }

    // 1. Check focus state
    const is_focused = if (focus_states) |fs| fs.get(stable_id) orelse blk: {
        std.log.info("stable_id {s} doesnt exist", .{stable_id});
        break :blk false;
    } else blk: {
        break :blk false;
    };

    const background = field.background;
    // 2. Animation / Style variables
    const trans: f32 = if (is_focused or field.trans_label or checkLength(value) or field.placeholder != null) -150 else -50;
    const scale: f32 = if (is_focused or field.trans_label or checkLength(value) or field.placeholder != null) 0.9 else 1;
    const label_left: f32 = if (is_focused or field.trans_label) 12 + 12 else 12;

    const z_index: f32 = if (is_focused) 10 else 0;
    const text_color: Vapor.Types.Color = if (is_focused) field.tint_color else .transparentize(field.text_color, 0.5);

    container
        .height(.px(36))
        .spacing(8)
        .pos(.relative)
        .border(.round(if (is_focused) .palette(.tint) else .palette(.border_color_light), .all(12)))
        .background(background)
        .shadow(.glow(3, if (is_focused) .transparentize(.palette(.tint), 0.2) else .transparent))
        .children({
        const field_id = Vapor.fmtln("{s}_{s}", .{ @tagName(field_type), stable_id });
        var label_component: ?Vapor.Builder(.pure) = null;
        if (field.label) |label| {
            label_component = renderLabel(label, label_left, trans, scale, z_index, text_color, background);
            label_component.?.fieldName(field_id).end();
        }

        const text_field: Vapor.TextFieldBuilder(.pure) = ErasedField(field, field_type, field_id);
        // 3. Render the appropriate input type
        switch (field_type) {
            .string => {
                text_field
                    .pos(.absolute)
                    .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                    .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                    .onEvent(.input, stringCallback, .{field})
                    .onEvent(.keydown, stringEnterCallback, .{Callback{ .value = value, .on_enter = field.on_enter }})
                    .border(.none)
                    .width(.percent(100))
                    .val(value.string)
                    .placeholder(if (field.placeholder) |placeholder| placeholder.string else "")
                    .end();
            },
            .telephone => {
                text_field
                    .pos(.absolute)
                    .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                    .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                    .border(.none)
                    .width(.percent(100))
                    .onEvent(.input, telephoneCallback, .{Callback{ .value = value, .on_change = field.on_change }})
                    .val(value.telephone)
                    .placeholder(if (field.placeholder) |placeholder| placeholder.string else "")
                    .end();
            },
            .credit_card => {
                text_field
                    .pos(.absolute)
                    .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                    .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                    .border(.none)
                    .width(.percent(100))
                    .onEvent(.input, creditCardCallback, .{Callback{ .value = value, .on_change = field.on_change }})
                    .val(value.credit_card)
                    .config(.{ .max = 19 })
                    .placeholder(if (field.placeholder) |placeholder| placeholder.string else "")
                    .end();
            },
            .email => {
                text_field
                    .pos(.absolute)
                    .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                    .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                    .width(.percent(100))
                    .onEvent(.input, emailCallback, .{Callback{ .value = value, .on_change = field.on_change }})
                    .border(.none)
                    .val(value.email)
                    .placeholder(if (field.placeholder) |placeholder| placeholder.string else "")
                    .end();
            },
            .password => {
                text_field
                    .pos(.absolute)
                    .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                    .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                    .width(.percent(100))
                    .onEvent(.input, passwordCallback, .{Callback{ .value = value, .on_change = field.on_change }})
                    .border(.none)
                    .val(value.password)
                    .placeholder(if (field.placeholder) |placeholder| placeholder.string else "")
                    .end();
            },
            .number => {
                text_field
                    .pos(.absolute)
                    .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                    .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                    .border(.none)
                    .width(.percent(100))
                    .onEvent(.input, numberCallback, .{Callback{ .value = value, .on_change = field.on_change }})
                    .border(.none)
                    .config(field.config)
                    .placeholder(if (field.placeholder) |placeholder| placeholder.number else 0)
                    .val(value.number)
                    .end();
            },
            .int64 => {
                text_field
                    .pos(.absolute)
                    .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                    .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                    .border(.none)
                    .width(.percent(100))
                    .onEvent(.input, int64Callback, .{Callback{ .value = value, .on_change = field.on_change }})
                    .border(.none)
                    .config(field.config)
                    .placeholder(if (field.placeholder) |placeholder| placeholder.number else 0)
                    .val(value.int64)
                    .end();
            },
            .float => {
                text_field
                    .pos(.absolute)
                    .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                    .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                    .border(.none)
                    .width(.percent(100))
                    .onEvent(.input, floatCallback, .{Callback{ .value = value, .on_change = field.on_change }})
                    .border(.none)
                    .config(field.config)
                    .placeholder(if (field.placeholder) |placeholder| placeholder.float else 0)
                    .val(value.float)
                    .end();
            },
            .date => {
                text_field
                    .pos(.absolute)
                    .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                    .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                    .onEvent(.input, stringCallback, .{field})
                    .onEvent(.keydown, stringEnterCallback, .{Callback{ .value = value, .on_enter = field.on_enter }})
                    .border(.none)
                    .width(.percent(100))
                    .val(value.date)
                    .placeholder(if (field.placeholder) |placeholder| placeholder.string else "")
                    .end();
            },
            else => {},
        }
    });
}

// ============================================================================
// Public API: create() + Component() — custom container usage
// ============================================================================
//
// Usage:
//   // `my_url` must be a module-level var, NOT a local or array element.
//   var my_url: []const u8 = "";
//
//   Field.create(.{
//       .label = "URL",
//       .value = .{ .string = &my_url },  // ← stable pointer
//       .on_change = onUrlChange,
//   }).Component(MyFieldComp);
//
// The `.value` pointer is stored once (on first render for this DOM node)
// and reused forever. If the pointer moves, you get undefined behavior.

pub fn create(field: Field) *Field {
    const container = Container();
    const stable_id = container.getUUID();
    const alloc_field = fields.get(stable_id) orelse blk: {
        const new_field = Vapor.arena(.persist).create(Field) catch unreachable;
        new_field.* = field;
        const stable_id_alloc = Vapor.arena(.persist).alloc(u8, stable_id.len) catch unreachable;
        @memcpy(stable_id_alloc, stable_id);

        fields.put(stable_id_alloc, new_field) catch unreachable;
        break :blk new_field;
    };

    // Sync mutable props every frame
    alloc_field.value = field.value;
    alloc_field.on_change = field.on_change;
    alloc_field.on_enter = field.on_enter;
    alloc_field.label = field.label;
    alloc_field.placeholder = field.placeholder;
    alloc_field._container = container;
    return alloc_field;
}

pub fn onChange(field: *Field, callback: anytype, args: anytype) *Field {
    const erased = Vapor.lib.ErasedEventCallback.make(Vapor.arena(.frame), .input, callback, args) catch |err| {
        std.log.err("Failed to create erased callback: {any}", .{err});
        return field;
    };
    field._on_change = erased;
    return field;
}

pub fn Component(field: *Field, component: ?*const fn (*Field) Vapor.Builder(.pure)) void {
    const container = field._container orelse return;
    const stable_id = container.getUUID();
    var value: Value = undefined;
    if (field.value) |v| {
        // NOTE: insertValue only stores on first call for this stable_id.
        // The pointer inside `v` must remain valid for the lifetime of
        // this component. See module doc for safe patterns.
        insertValue(stable_id, v);
        value = v;
    } else {
        value = createValue(stable_id, field.type, field.default_value);
    }
    var field_type = field.type;
    if (field.value) |v| {
        field_type = getFieldTypeFromValue(v);
    }

    // 1. Check focus state
    const is_focused = if (focus_states) |fs| fs.get(stable_id) orelse blk: {
        std.log.info("stable_id {s} doesnt exist", .{stable_id});
        break :blk false;
    } else blk: {
        break :blk false;
    };

    const background = field.background;
    // 2. Animation / Style variables
    const trans: f32 = if (is_focused or field.trans_label or checkLength(value) or field.placeholder != null) -150 else -50;
    const scale: f32 = if (is_focused or field.trans_label or checkLength(value) or field.placeholder != null) 0.9 else 1;
    const label_left: f32 = if (is_focused or field.trans_label) 12 + 12 else 12;

    const z_index: f32 = if (is_focused) 10 else 0;
    const text_color: Vapor.Types.Color = if (is_focused) field.tint_color else .transparentize(.palette(.text_color), 0.5);

    field.is_focused = is_focused;

    container
        .layout(.left_center)
        .width(.percent(100))
        .pos(.relative)
        .children({
        var comp: Vapor.Builder(.pure) = undefined;
        if (component) |c| {
            comp = c(field);
        } else {
            comp = Vapor.Row()
                .height(.px(36))
                .width(.percent(100))
                .spacing(8)
                .pos(.relative)
                .border(.round(if (is_focused) .palette(.tint) else .palette(.border_color_light), .all(12)))
                .background(background)
                .shadow(.glow(3, if (is_focused) .transparentize(.palette(.tint), 0.2) else .transparent));
        }
        comp
            .children({
            const field_id = Vapor.fmtln("{s}_{s}", .{ @tagName(field_type), stable_id });
            var label_component: ?Vapor.Builder(.pure) = null;
            if (field.label) |label| {
                label_component = renderLabel(label, label_left, trans, scale, z_index, text_color, background);
                label_component.?.fieldName(field_id).end();
            }

            const text_field: Vapor.TextFieldBuilder(.pure) = ErasedField(field.*, field_type, field_id);

            // 3. Render the appropriate input type
            switch (field_type) {
                .string => {
                    text_field
                        .pos(.absolute)
                        .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                        .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                        .onEvent(.input, stringCallback, .{field.*})
                        .onEvent(.keydown, stringEnterCallback, .{Callback{ .value = value, .on_enter = field.on_enter }})
                        .border(.none)
                        .width(.percent(100))
                        .val(value.string)
                        .placeholder(if (field.placeholder) |placeholder| placeholder.string else "")
                        .end();
                },
                .telephone => {
                    text_field
                        .pos(.absolute)
                        .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                        .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                        .border(.none)
                        .width(.percent(100))
                        .onEvent(.input, telephoneCallback, .{Callback{ .value = value, .on_change = field.on_change }})
                        .val(value.telephone)
                        .placeholder(if (field.placeholder) |placeholder| placeholder.string else "")
                        .end();
                },
                .credit_card => {
                    text_field
                        .pos(.absolute)
                        .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                        .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                        .border(.none)
                        .width(.percent(100))
                        .onEvent(.input, creditCardCallback, .{Callback{ .value = value, .on_change = field.on_change }})
                        .val(value.credit_card)
                        .config(.{ .max = 19 })
                        .placeholder(if (field.placeholder) |placeholder| placeholder.string else "")
                        .end();
                },
                .email => {
                    text_field
                        .pos(.absolute)
                        .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                        .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                        .width(.percent(100))
                        .onEvent(.input, emailCallback, .{Callback{ .value = value, .on_change = field.on_change }})
                        .border(.none)
                        .val(value.email)
                        .placeholder(if (field.placeholder) |placeholder| placeholder.string else "")
                        .end();
                },
                .password => {
                    text_field
                        .pos(.absolute)
                        .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                        .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                        .width(.percent(100))
                        .onEvent(.input, passwordCallback, .{Callback{ .value = value, .on_change = field.on_change }})
                        .border(.none)
                        .val(value.password)
                        .placeholder(if (field.placeholder) |placeholder| placeholder.string else "")
                        .end();
                },
                .number => {
                    text_field
                        .pos(.absolute)
                        .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                        .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                        .border(.none)
                        .width(.percent(100))
                        .onEvent(.input, numberCallback, .{Callback{ .value = value, .on_change = field.on_change }})
                        .border(.none)
                        .config(field.config)
                        .placeholder(if (field.placeholder) |placeholder| placeholder.number else 0)
                        .val(value.number)
                        .end();
                },
                .int64 => {
                    text_field
                        .pos(.absolute)
                        .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                        .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                        .border(.none)
                        .width(.percent(100))
                        .onEvent(.input, int64Callback, .{Callback{ .value = value, .on_change = field.on_change }})
                        .border(.none)
                        .config(field.config)
                        .placeholder(if (field.placeholder) |placeholder| placeholder.number else 0)
                        .val(value.int64)
                        .end();
                },
                .float => {
                    text_field
                        .pos(.absolute)
                        .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                        .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                        .border(.none)
                        .width(.percent(100))
                        .onEvent(.input, floatCallback, .{Callback{ .value = value, .on_change = field.on_change }})
                        .border(.none)
                        .config(field.config)
                        .placeholder(if (field.placeholder) |placeholder| placeholder.float else 0)
                        .val(value.float)
                        .end();
                },
                .date => {
                    const date_config = date_pickers.get(stable_id) orelse blk: {
                        const new_date_picker_config = Vapor.arena(.persist).create(DatePickerConfig) catch unreachable;

                        // Allocate the persistent format string buffer
                        const fmt_str = Vapor.arena(.persist).create([]const u8) catch unreachable;
                        fmt_str.* = "";

                        new_date_picker_config.* = .{
                            .date_picker = .{ .current_date = Vapor.DateTime.now() },
                            .show = false,
                            .field_value = value.date,
                            .format_str = fmt_str,
                        };
                        new_date_picker_config.date_picker.init();
                        new_date_picker_config.date_picker.on_date_select = onDatePickerSelect;

                        // Initialize format_str from default DateTime value
                        syncFormatStr(fmt_str, value.date.*);

                        const stable_id_alloc = Vapor.arena(.persist).alloc(u8, stable_id.len) catch unreachable;
                        @memcpy(stable_id_alloc, stable_id);

                        date_pickers.put(stable_id_alloc, new_date_picker_config) catch unreachable;
                        break :blk new_date_picker_config;
                    };

                    // Keep field_value in sync each frame
                    date_config.field_value = value.date;

                    text_field
                        .pos(.absolute)
                        .onEvent(.focus, handleFocus, .{ stable_id, Callback{ .on_focus = field.on_focus } })
                        .onEvent(.blur, handleBlur, .{ stable_id, Callback{ .on_blur = field.on_blur } })
                        .onEvent(.input, dateCallback, .{Callback{ .value = value, .on_change = field.on_change, .format_str = date_config.format_str }})
                        .border(.none)
                        .width(.percent(100))
                        .val(date_config.format_str)
                        .placeholder(if (field.placeholder) |placeholder| placeholder.string else "dd/mm/yyyy, HH:mm:ss")
                        .end();

                    Button(toggleDatePicker, .{date_config})
                        .pos(.tr(.px(0), .px(0), .absolute))
                        .width(.px(32))
                        .height(.px(32))
                        .layout(.center)
                        .pointer()
                        .children({
                        Icon(.calendar)
                            .fontSize(20)
                            .end();
                    });

                    if (date_config.show) {
                        Box()
                            .pos(.tr(.px(36), .px(0), .absolute))
                            .zIndex(1000)
                            .children({
                            date_config.date_picker.render();
                        });
                    }
                },

                else => {},
            }
        });
    });
}
