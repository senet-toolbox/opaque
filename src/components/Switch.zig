const Vapor = @import("vapor");
const std = @import("std");
const Box = Vapor.Box;
const Button = Vapor.Button;

var active_color: Vapor.Types.Color = .palette(.background);
var inactive_color: Vapor.Types.Color = .palette(.background);
var inactive_background: Vapor.Types.Color = .palette(.border_color_light);
var active_background: Vapor.Types.Color = .palette(.text);

var border_radius: u8 = 4;
var duration: u32 = 100;

pub var switches: std.AutoHashMap(u32, *SwitchOptions) = undefined;

pub fn new() void {
    switches = std.AutoHashMap(u32, *SwitchOptions).init(Vapor.arena(.persist));
}

const Switch = @This();

pub const SwitchOptions = struct {
    id: []const u8,
    active: bool = false,
};

fn Circle(switch_options: *SwitchOptions) void {
    const trans: f32 = if (switch_options.active) 20 else 0;
    Box()
        .width(.px(20))
        .height(.px(20))
        .layer(.dot(0.5, 6, .transparentizeHex(.black, 0.3)))
        .shadow(.insetGlow(0, 2, 2, .transparentizeHex(.black, 0.1)))
        .border(.{
            .thickness = .none,
            .radius = .all(border_radius),
        })
        .background(.white)
        .inlineStyle(
            \\transform: translateX({d}px);
        , .{trans})
        .transition(.{
            .properties = &.{ .transform, .background_color },
            .duration = duration,
            .timing = .easeInCubic,
        })
        .children({});
}

fn toggle(switch_options: *SwitchOptions, callback: anytype, args: anytype) void {
    switch_options.active = !switch_options.active;
    @call(.auto, callback, args);
}

fn destroy(switch_options: *SwitchOptions) void {
    const hash = Vapor.utils.hashKey(switch_options.id);
    _ = switches.remove(hash);
}

fn Container() Vapor.Builder(.pure) {
    return Box()
        .width(.px(42))
        .border(.{
            .thickness = .none,
            .radius = .all(border_radius + 1),
        })
        .padding(.all(1))
        .layout(.center)
        .inlineStyle(
        \\background-image: linear-gradient(to bottom, #d5d5d5, #EDEDED);
        \\box-shadow: 0 1px 1px rgb(255 255 255 / .1);
    , .{});
}

pub fn default() void {}

pub fn render(aria_label: []const u8, on_change: anytype, args: anytype) void {
    const container = Container();
    const uuid = container.getUUID();
    const hash = Vapor.utils.hashKey(uuid);
    const switch_options = switches.get(hash) orelse blk: {
        const switch_options = Vapor.arena(.persist).create(SwitchOptions) catch unreachable;
        switch_options.* = .{ .id = uuid };
        switches.put(hash, switch_options) catch unreachable;
        break :blk switch_options;
    };

    const background_color = if (switch_options.active) active_background else inactive_background;
    container
        .onDestroy(destroy, .{switch_options})
        .children({
        Button(toggle, .{ switch_options, on_change, args })
            .ariaLabel(aria_label)
            .width(.percent(100))
            .border(.{
                .thickness = .none,
                .radius = .all(border_radius),
            })
            .inlineStyle(
                \\box-shadow: inset 0 0 .0625em .125em rgb(255 255 255 / .2), inset 0 .0625em .125em rgb(0 0 0 / .4);
            , .{})
            .cursor(.pointer)
            .transition(.{
                .properties = &.{.background_color},
                .duration = duration,
                .timing = .easeInOut,
            })
            .background(background_color)
            .children({
            Circle(switch_options);
        });
    });
}
