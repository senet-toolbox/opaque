const std = @import("std");
const Vapor = @import("vapor");
const Static = Vapor.Static;
const Signal = Vapor.Signal;
const println = Vapor.println;
const root = @import("../main.zig");
const Search = @import("Search.zig");
const Kit = Vapor.Kit;
const Text = Vapor.Text;
const Box = Vapor.Box;
const Link = Vapor.Link;
const Stack = Vapor.Stack;
const Image = Vapor.Image;
const Svg = Vapor.Svg;
const Center = Vapor.Center;
const Icon = Vapor.Icon;
const List = Vapor.List;
const ListItem = Vapor.ListItem;
const CtxButton = Vapor.CtxButton;
const RedirectLink = Vapor.RedirectLink;
const Button = Vapor.Button;
const Theme = @import("theme");

var theme_background: Vapor.Types.Color = undefined;
var text_color: Vapor.Types.Color = undefined;
var tint: Vapor.Types.Color = undefined;

var last_time: i64 = 0;
pub fn throttle() bool {
    const current_time = std.time.milliTimestamp();
    if (current_time - last_time < 60) {
        return true;
    }
    last_time = current_time;
    return false;
}

var menu: bool = false;
fn openMenu() void {
    // if (!throttle()) {
    menu = !menu;
    //     Vapor.cycle();
    // }
}
const Url = struct {
    url: []const u8,
    title: []const u8,
};
const urls: [5]Url = .{
    .{
        .url = "/docs/vapor",
        .title = "Vapor",
    },
    .{
        .url = "/docs/reverb",
        .title = "Reverb",
    },
    .{
        .url = "/docs/treehouse",
        .title = "Treehouse",
    },
    .{
        .url = "/docs/metal",
        .title = "Metal",
    },
    .{
        .url = "/about",
        .title = "About Me",
    },
};

inline fn routes() void {
    // const current_path = Kit.getWindowPath();
    for (urls) |url| {
        ListItem.style(&Styles.item)({
            Link(.{ .url = url.url, .aria_label = url.title }).style(&.{
                .text_decoration = .none,
            })({
                Text(url.title).style(&.{ .visual = .font(20, 300, .palette(.text_color)) })({});
            });
        });
    }
    Box.style(&.{
        .style_id = "dropdown",
        .size = .square_px(300),
    })({});
}

const Self = @This();
var show_dropdown: Signal(bool) = undefined;

const svg_logo = @embedFile("../assets/logonormal.svg");

const ThemeOption = struct {
    name: []const u8,
    icon: []const u8,
};
const theme_options: []const ThemeOption = &.{
    .{
        .name = "Light",
        .icon = "bi bi-brightness-low-fill",
    },
    .{
        .name = "Dark",
        .icon = "bi bi-moon-stars-fill",
    },
};

fn showDropDown() void {
    println("SHOW DROPDOWN", .{});
    show_dropdown.set(!show_dropdown.get());
}

fn switchTheme(opt: []const u8) void {
    println("Switch Theme! {s}", .{opt});
    // if (opt[0] == 'D') {
    //     Vapor.Theme.switchTheme(.dark);
    //     return;
    // }
    // Vapor.Theme.switchTheme(.light);
    return;
}

pub fn init() void {
    show_dropdown.init(false);
    Search.init();
}
// fn activeTheme(theme: Theme) [4]f32 {
//     if (Vapor.Theme.theme == theme) {
//         return tint;
//     }
//     return .{ 0, 0, 0, 0 };
// }
// fn dropdownTextColor(theme: Theme) [4]f32 {
//     if (Vapor.Theme.theme == theme) {
//         return .{ 0, 0, 0, 255 };
//     }
//     return text_color;
// }

pub fn closeAll(evt: *Vapor.Event) void {
    evt.preventDefault();
    // show_dropdown.set(false);
}

pub fn setDefault() void {
    show_dropdown.set(false);
}

fn openDialog() void {
    Search.toggle();
}

fn navigate(url: []const u8) void {
    Kit.navigate(url);
    menu = !menu;
    Vapor.cycle();
}

fn toggleTheme() void {
    Theme.toggleTheme();
    Vapor.cycle();
}

// const default = Vapor.Style{
//     .width = .percent(100),
// };
pub fn render() void {
    // Vapor.Remember(.{
    //     .file = "/routes/",
    //     .module = "",
    //     .column = 0,
    //     .fn_name = "",
    //     .line = 0,
    // })({
    if (Vapor.isDesktop()) {
        Box.style(&.{
            .id = "nav",
            .position = .nav,
            .size = .hw(.px(60), .grow),
            .layout = .x_between_center,
            .padding = .horizontal(50),
            .blur = 2,
            .z_index = 999,
        })({
            Box.style(&.{
                .size = .{ .height = .px(50) },
                .direction = .row,
                .layout = .left_center,
                .child_gap = 10,
            })({
                Link(.{ .url = "/", .aria_label = "home page of tether" }).style(&.{
                    .text_decoration = .none,
                })({
                    Center.style(&.{
                        .size = .{ .width = .px(45) },
                        .margin = .{ .right = 30 },
                        .transition = .{ .duration = 100 },
                        .interactive = .{ .hover = .{ .transform = .scale() } },
                        .visual = .{ .text_color = .palette(.text_color) },
                    })({
                        Svg(.{ .svg = svg_logo }).style(&.{
                            .size = .{ .width = .percent(100), .height = .percent(100) },
                            .visual = .{ .text_color = .palette(.text_color) },
                            .transition = .{ .duration = 100 },
                            .interactive = .{ .hover = .{
                                .text_color = .palette(.tint),
                            } },
                        })({});
                        // Image(.{ .src = "/assets/logonormal.svg" }).style(&.{
                        //     .size = .{ .width = .percent(100), .height = .percent(100) },
                        //     .visual = .{ .text_color = .hex("#5A27FF") },
                        // })({});
                    });
                });
            });
        });
    } else {
        Box.style(&.{
            .layout = .x_between_center,
            .child_gap = 8,
            .padding = .horizontal(16),
            .position = .{ .type = .fixed, .top = .px(0), .left = .percent(0), .right = .percent(0) },
            .size = .hw(.px(80), .percent(100)),
            .visual = .bg(.palette(.background)),
            .z_index = 999,
        })({
            Box.style(&.{ .layout = .left_center })({
                Link(.{ .url = "/", .aria_label = "home page of tether" }).style(&.{
                    .text_decoration = .none,
                    .size = .h(.px(48)),
                    .layout = .center,
                })({
                    Image(.{ .src = "/assets/circlelogo.webp" }).style(&.{
                        .size = .w(.px(48)),
                    })({});
                });
            });
            Box.style(&.{ .layout = .right_center })({
                Button(.{ .on_press = openMenu }).style(&.{
                    .size = .hw(.px(36), .px(48)),
                    .visual = .bg(.palette(.background)),
                })({
                    Icon("bi bi-search").style(&.{
                        .visual = .{ .font_size = 24, .text_color = .palette(.icon_color) },
                        .interactive = .{ .hover = .{ .text_color = .palette(.tint) } },
                    })({});
                });

                Button(.{ .on_press = toggleTheme }).style(&.{
                    .visual = .bg(.palette(.background)),
                    .size = .hw(.px(36), .px(48)),
                    .cursor = .pointer,
                })({
                    Icon("bi bi-cloud-moon").style(&.{
                        .visual = .{ .font_size = 24, .text_color = .palette(.icon_color) },
                    })({});
                });

                Button(.{ .on_press = openMenu }).style(&.{
                    .size = .hw(.px(36), .px(48)),
                    .visual = .bg(.palette(.background)),
                })({
                    if (menu) {
                        Icon("bi bi-x-lg").style(&.{
                            .id = "close-menu",
                            .visual = .{ .font_size = 24, .text_color = .palette(.icon_color) },
                        })({});
                    } else {
                        Icon("bi bi-list").style(&.{
                            .id = "open-menu",
                            .visual = .{ .font_size = 24, .text_color = .palette(.icon_color) },
                        })({});
                    }
                });
            });
        });
        if (menu) {
            Box.style(&.{
                .position = .{ .type = .fixed, .top = .px(80), .left = .px(0) },
                .size = .w(.percent(100)),
                .z_index = 999,
                .visual = .{ .background = Theme.background, .border = .tb(.hex("#E4E4E4")) },
            })({
                List.style(&.{
                    .list_style = .none,
                    .direction = .column,
                    .padding = .tblr(16, 16, 8, 8),
                    .child_gap = 16,
                    .size = .w(.percent(100)),
                })({
                    for (urls) |item| {
                        ListItem.style(&.{
                            .size = .w(.percent(70)),
                        })({
                            CtxButton(navigate, .{item.url}).style(&.{
                                .size = .w(.percent(100)),
                                .layout = .left_center,
                                .child_gap = 12,
                                .padding = .tblr(10, 10, 8, 8),
                                .cursor = .pointer,
                                .visual = .bg(.hex("#ffffff")),
                            })({
                                Text(item.title).style(&.{
                                    .font_family = "Montserrat",
                                    .visual = .font(18, 300, .hex("#262626")),
                                })({});
                            });
                        });
                    }
                });
            });
        }
    }
    // Search.render();
    // });
}

const Styles = struct {
    pub const item = Vapor.Style{
        .list_style = .none,
        .size = .{ .width = .elastic(50, 130), .height = .px(30) },
        .layout = .{ .y = .center, .x = .start },
        .visual = .{ .border = .bottom(.transparent) },
        // .border_color = if (std.mem.eql(u8, current_path, url.url)) text_color else .transparent,
        .interactive = .{
            .hover = .{
                .border_color = .palette(.text_color),
                .border_thickness = .{ .bottom = 1, .top = 0, .left = 0, .right = 0 },
            },
        },
    };
};
