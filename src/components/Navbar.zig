const std = @import("std");
const Vapor = @import("vapor");
const Static = Vapor.Static;
const println = Vapor.println;
const root = @import("../main.zig");
const Search = @import("Search.zig");
const Kit = Vapor.Kit;
const Text = Static.Text;
const Box = Static.Box;
const Link = Static.Link;
const Stack = Static.Stack;
const Image = Static.Image;
const Svg = Static.Svg;
const Center = Static.Center;
const Icon = Static.Icon;
const List = Static.List;
const ListItem = Static.ListItem;
const CtxButton = Static.CtxButton;
const RedirectLink = Static.RedirectLink;
const Button = Static.Button;
const Theme = @import("theme");
const Graphic = Static.Graphic;
const OverlayManager = @import("OverlayManager.zig");

const Ghost = @embedFile("ghost.svg");

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
const urls: [4]Url = .{
    .{
        .url = "/docs/vapor",
        .title = "[0] = Vapor",
    },
    .{
        .url = "/docs/reverb",
        .title = "[1] = Reverb",
    },
    .{
        .url = "/docs/treehouse",
        .title = "[2] = Canopy",
    },
    .{
        .url = "/docs/metal",
        .title = "Metal",
    },
};

inline fn routes() void {
    // const current_path = Kit.getWindowPath();
    for (urls) |url| {
        ListItem().style(&Styles.item).children({
            Link(.{ .url = url.url, .aria_label = url.title }).style(&.{
                .visual = .{ .text_decoration = .none },
            }).children({
                Text(url.title).style(&.{ .visual = .font(18, 300, .palette(.text_color)), .font_family = "IBM Plex Mono,monospace" }).end();
            });
        });
    }
}

pub fn init() void {
    Search.init();
    OverlayManager.register(.keydown, clickEvent, .{&local_binded});
}

pub fn closeAll(evt: *Vapor.Event) void {
    evt.preventDefault();
}

pub fn setDefault() void {}

fn openDialog() void {
    Search.toggle();
}

fn navigate(url: []const u8) void {
    Kit.navigate(url);
    menu = !menu;
}

fn toggleTheme() void {
    Theme.toggleTheme();
}

var local_binded: []const u8 = "";

pub fn clickEvent(_: *[]const u8, evt: *Vapor.Event) void {
    const key = evt.key();
    if (std.mem.eql(u8, key, "k") and evt.metaKey()) {
        openDialog();
    }

    // if (std.mem.eql(u8, key, "0")) {
    //     navigate("/docs/vapor");
    // } else if (std.mem.eql(u8, key, "1")) {
    //     navigate("/docs/reverb");
    // } else if (std.mem.eql(u8, key, "2")) {
    //     navigate("/docs/canopy");
    // }

    if (std.mem.eql(u8, key, "x") and evt.metaKey()) {
        Theme.toggleTheme();
    }
}

fn goto(url: []const u8) void {
    Vapor.Kit.navigate(url);
}

pub fn render() void {
    if (Vapor.isDesktop()) {
        Box().id("nav").style(&.{
            .position = .nav,
            .size = .hw(.px(60), .grow),
            .layout = .x_between_center,
            .padding = .horizontal(50),
            .visual = .{ .blur = 2 },
        }).children({
            Box().style(&.{
                .size = .{ .height = .px(50) },
                .direction = .row,
                .layout = .left_center,
                .child_gap = 10,
            }).children({
                CtxButton(goto, .{"/"})
                    .ariaLabel("home page of tether")
                    .style(&.{
                        .visual = .{ .text_decoration = .none },
                    }).children({
                    Center().style(&.{
                        .size = .{ .width = .px(45) },
                        .margin = .{ .right = 30 },
                        .transition = .{ .duration = 100 },
                        .interactive = .{ .hover = .{ .transform = .scale() } },
                        .visual = .{ .text_color = .palette(.text_color) },
                    }).children({
                        Graphic(.{ .src = "/src/assets/logonormal.svg" }).style(&.{
                            .size = .{ .width = .percent(100), .height = .percent(100) },
                            .visual = .{ .fill = .palette(.text_color), .stroke = .palette(.text_color) },
                            .transition = .{ .duration = 100 },
                            .interactive = .{ .hover = .{
                                .fill = .palette(.tint),
                                .stroke = .palette(.tint),
                            } },
                        }).end();
                    });
                });
                List().style(&.{
                    .child_gap = 60,
                    .layout = .center,
                    .size = .hw(.percent(100), .percent(100)),
                }).children({
                    routes();
                });
            });

            Center().style(&.{
                .child_gap = 24,
                .size = .w(.percent(30)),
            }).children({
                Button(openDialog)
                    .ariaLabel("Search Dialog")
                    .style(&.{
                        .layout = .x_between_center,
                        .size = .hw(.px(38), .percent(70)),
                        .padding = .tblr(4, 4, 8, 8),
                        .visual = .{ .border = .simple(.hex("#E1E1E1")), .cursor = .pointer, .background = .palette(.background) },
                        .interactive = .{ .hover = .{
                            .border = .simple(.palette(.tint)),
                        } },
                    }).children({
                    Box().style(&.{ .layout = .left_center, .child_gap = 24 }).children({
                        Icon(.search).style(&.{
                            .visual = .{ .font_size = 16, .text_color = .palette(.icon_color) },
                        }).end();
                        Text("Search...").style(&.{
                            .visual = .font(16, 500, .palette(.icon_color)),
                            .font_family = "IBM Plex Mono,monospace",
                        }).end();
                    });
                    Icon(.command).style(&.{
                        .visual = .{ .font_size = 16, .text_color = .palette(.icon_color) },
                    }).end();
                });
                RedirectLink(.{ .url = "https://github.com/vic-Rokx/vapor", .aria_label = "redirect link to tether github repo" }).style(&.{
                    .visual = .{ .text_decoration = .none },
                }).children({
                    Icon(.github).style(&.{
                        .visual = .{ .font_size = 24, .text_color = .palette(.icon_color) },
                        .interactive = .{ .hover = .{ .text_color = .palette(.tint) } },
                    }).end();
                });
                RedirectLink(.{ .url = "https://github.com/vic-Rokx/vapor", .aria_label = "redirect link to discord" }).style(&.{
                    .visual = .{ .text_decoration = .none },
                }).children({
                    Icon(.discord).style(&.{
                        .visual = .{ .font_size = 24, .text_color = .palette(.icon_color) },
                        .interactive = .{ .hover = .{ .text_color = .palette(.tint) } },
                    }).end();
                });
                RedirectLink(.{ .url = "https://ziglang.org/", .aria_label = "redirect link to ziglang" }).style(&.{
                    .visual = .{ .text_decoration = .none },
                }).children({
                    Graphic(.{ .src = "/assets/zig_simple.svg" }).style(&.{
                        .size = .{ .height = .px(24), .width = .px(24) },
                        .visual = .{ .fill = .palette(.icon_color) },
                        .interactive = .{ .hover = .{ .fill = .palette(.tint) } },
                    }).end();
                });
                Button(toggleTheme)
                    .ariaLabel("toggle theme")
                    .style(&.{
                        .visual = .{
                            .background = .transparent,
                            .cursor = .pointer,
                        },
                        .padding = .all(0),
                        .margin = .all(0),
                    }).children({
                    // Vapor.Svg(.{ .svg = Ghost, .override = true })
                    //     .class("ghost")
                    //     .hover(.{
                    //         .animation = "look-around",
                    //     })
                    //     .size(.hw_px(24, 24))
                    //     .end();
                    Icon(.cloud_moon).style(&.{
                        .visual = .{ .font_size = 24, .text_color = .palette(.icon_color) },
                        .interactive = .{ .hover = .{ .text_color = .palette(.tint) } },
                    }).end();
                });
            });
        });
        Search.render();
    } else {
        Box().style(&.{
            .layout = .x_between_center,
            .child_gap = 8,
            .padding = .horizontal(16),
            .position = .{ .type = .fixed, .top = .px(0), .left = .percent(0), .right = .percent(0), .z_index = 999 },
            .size = .hw(.px(80), .percent(100)),
            .visual = .{
                .background = .palette(.background),
            },
        }).children({
            Box().style(&.{ .layout = .left_center }).children({
                Link(.{ .url = "/", .aria_label = "home page of tether" }).style(&.{
                    .visual = .{ .text_decoration = .none },
                    .size = .h(.px(48)),
                    .layout = .center,
                }).children({
                    Image(.{ .src = "/assets/circlelogo.webp", .alt = "tether logo" }).style(&.{
                        .size = .w(.px(48)),
                    }).end();
                });
            });
            Box().style(&.{ .layout = .right_center }).children({
                Button(openMenu).style(&.{
                    .size = .hw(.px(36), .px(48)),
                    .visual = .bg(.palette(.background)),
                }).children({
                    Icon(.search).style(&.{
                        .visual = .{ .font_size = 24, .text_color = .palette(.icon_color) },
                        .interactive = .{ .hover = .{ .text_color = .palette(.tint) } },
                    }).end();
                });

                Button(toggleTheme).style(&.{
                    .visual = .{ .cursor = .pointer, .background = .palette(.background) },
                    .size = .hw(.px(36), .px(48)),
                }).children({
                    Icon(.cloud_moon).style(&.{
                        .visual = .{ .font_size = 24, .text_color = .palette(.icon_color) },
                    }).end();
                });

                Button(openMenu).style(&.{
                    .size = .hw(.px(36), .px(48)),
                    .visual = .bg(.palette(.background)),
                }).children({
                    if (menu) {
                        Icon(.x_lg).style(&.{
                            .id = "close-menu",
                            .visual = .{ .font_size = 24, .text_color = .palette(.icon_color) },
                        }).end();
                    } else {
                        Icon(.list).style(&.{
                            .id = "open-menu",
                            .visual = .{ .font_size = 24, .text_color = .palette(.icon_color) },
                        }).end();
                    }
                });
            });
        });
        if (menu) {
            Box().style(&.{
                .position = .{ .type = .fixed, .top = .px(80), .left = .px(0), .z_index = 999 },
                .size = .w(.percent(100)),
                // .visual = .{ .background = Theme.background, .border = .tb(.hex("#E4E4E4")) },
            }).children({
                List().style(&.{
                    .list_style = .none,
                    .direction = .column,
                    .padding = .tblr(16, 16, 8, 8),
                    .child_gap = 16,
                    .size = .w(.percent(100)),
                }).children({
                    for (urls) |item| {
                        ListItem().style(&.{
                            .size = .w(.percent(70)),
                        }).children({
                            CtxButton(navigate, .{item.url}).style(&.{
                                .size = .w(.percent(100)),
                                .layout = .left_center,
                                .child_gap = 12,
                                .padding = .tblr(10, 10, 8, 8),
                                .visual = .{ .cursor = .pointer, .background = .white },
                            }).children({
                                Text(item.title).style(&.{
                                    .font_family = "Montserrat",
                                    .visual = .font(16, 300, .hex("#262626")),
                                }).end();
                            });
                        });
                    }
                });
            });
        }
    }
}

const Styles = struct {
    pub const item = Vapor.Style{
        .list_style = .none,
        .size = .{ .height = .px(30) },
        .layout = .{ .y = .center, .x = .start },
        .visual = .{ .border = .bottom(1, .transparent) },
        .interactive = .{
            .hover = .{
                .border = .bottom(1, .palette(.text_color)),
            },
        },
    };
};
