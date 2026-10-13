const Vapor = @import("vapor");
const std = @import("std");
const Box = Vapor.Box;
const Button = Vapor.Button;
const MainSwitch = @import("Switch.zig");

var active_color: Vapor.Types.Color = .palette(.background);
var inactive_color: Vapor.Types.Color = .palette(.background);
var inactive_background: Vapor.Types.Color = .palette(.border_color_light);
var active_background: Vapor.Types.Color = .palette(.text);

var border_radius: u8 = 4;
var duration: u32 = 100;

const SwitchComponent = @This();
container: Vapor.Builder(.pure),
button: Vapor.Builder(.pure),
options: *SwitchOptions,

const SwitchOptions = MainSwitch.SwitchOptions;

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
    _ = MainSwitch.switches.remove(hash);
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

pub fn default(sw: *const SwitchComponent, active: bool) SwitchComponent {
    var new_sw = sw.*;
    new_sw.options.active = active;
    return new_sw;
}

pub fn render(sw: *const SwitchComponent) void {
    const container = sw.container;
    const switch_options = sw.options;
    const button = sw.button;

    const background_color = if (switch_options.active) active_background else inactive_background;
    container
        .onDestroy(destroy, .{switch_options})
        .children({
        button
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

pub fn Switch(on_change: anytype, args: anytype) SwitchComponent {
    const container = Container();
    const uuid = container.getUUID();
    const hash = Vapor.utils.hashKey(uuid);
    const switch_options = MainSwitch.switches.get(hash) orelse blk: {
        const switch_options = Vapor.arena(.persist).create(SwitchOptions) catch unreachable;
        switch_options.* = .{ .id = uuid };
        MainSwitch.switches.put(hash, switch_options) catch unreachable;
        break :blk switch_options;
    };

    const button = Button(toggle, .{ switch_options, on_change, args });

    return SwitchComponent{
        .container = container,
        .button = button,
        .options = switch_options,
    };
}
