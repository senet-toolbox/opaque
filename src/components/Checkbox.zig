const Vapor = @import("vapor");
const std = @import("std");
const Row = Vapor.Row;
const Button = Vapor.Button;
const Svg = Vapor.Svg;

var active_color: Vapor.Types.Color = .palette(.background);
var inactive_color: Vapor.Types.Color = .palette(.background);
var inactive_background: Vapor.Types.Color = .palette(.border_color_light);
var active_background: Vapor.Types.Color = .transparentize(.palette(.tint), 0.7);

var border_radius: u8 = 4;
var duration: u32 = 100;

var checkboxes: std.AutoHashMap(u32, *CheckboxOptions) = undefined;

pub fn new() void {
    checkboxes = std.AutoHashMap(u32, *CheckboxOptions).init(Vapor.arena(.persist));
}

const Checkbox = @This();

const CheckboxOptions = struct {
    id: []const u8,
    active: bool = false,
};

fn toggle(switch_options: *CheckboxOptions, callback: anytype, args: anytype) void {
    switch_options.active = !switch_options.active;
    @call(.auto, callback, args);
}

fn toggleWithActive(switch_options: *CheckboxOptions, callback: anytype, args: anytype) void {
    switch_options.active = !switch_options.active;
    @call(.auto, callback, args ++ .{switch_options.active});
}

fn destroy(switch_options: *CheckboxOptions) void {
    const hash = Vapor.utils.hashKey(switch_options.id);
    _ = checkboxes.remove(hash);
}

fn Container() Vapor.Builder(.pure) {
    return Row();
}

const checkbox_svg =
    \\<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-check2" viewBox="0 0 16 16">
    \\  <path d="M13.854 3.646a.5.5 0 0 1 0 .708l-7 7a.5.5 0 0 1-.708 0l-3.5-3.5a.5.5 0 1 1 .708-.708L6.5 10.293l6.646-6.647a.5.5 0 0 1 .708 0"/>
    \\</svg>
;

pub fn create(uuid: []const u8, on_change: anytype, args: anytype) Vapor.Builder(.pure) {
    const hash = Vapor.utils.hashKey(uuid);
    const switch_options = checkboxes.get(hash) orelse blk: {
        const switch_options = Vapor.arena(.persist).create(CheckboxOptions) catch unreachable;
        switch_options.* = .{ .id = uuid };
        checkboxes.put(hash, switch_options) catch unreachable;
        break :blk switch_options;
    };

    const background_color = if (switch_options.active) active_background else inactive_background;
    var button: Vapor.Builder(.pure) = undefined;
    button = Button(toggleWithActive, .{ switch_options, on_change, args })
        .a11y(.checkbox(switch_options.active))
        .id(uuid)
        .onDestroy(destroy, .{switch_options})
        .width(.px(20))
        .height(.px(20))
        .cursor(.pointer)
        .duration(100)
        .center()
        .background(background_color)
        .radius(.all(4));
    return button;
}

pub fn render(aria_label: []const u8, on_change: anytype, args: anytype) void {
    const container = Container();
    const uuid = container.getUUID();
    const hash = Vapor.utils.hashKey(uuid);
    const switch_options = checkboxes.get(hash) orelse blk: {
        const switch_options = Vapor.arena(.persist).create(CheckboxOptions) catch unreachable;
        switch_options.* = .{ .id = uuid };
        checkboxes.put(hash, switch_options) catch unreachable;
        break :blk switch_options;
    };

    const background_color = if (switch_options.active) active_background else inactive_background;
    container
        .onDestroy(destroy, .{switch_options})
        .children({
        Button(toggle, .{ switch_options, on_change, args })
            .a11y(.checkbox(switch_options.active))
            .ariaLabel(aria_label)
            .width(.px(20))
            .height(.px(20))
            .cursor(.pointer)
            .duration(100)
            .center()
            .background(background_color)
            .radius(.all(4))
            .children({
            Svg(.{ .override = true, .svg = checkbox_svg })
                .font(16, 300, if (switch_options.active) active_color else inactive_color)
                .end();
        });
    });
}
