const std = @import("std");
const Vapor = @import("vapor");
const Box = Vapor.Box;
const Text = Vapor.Text;
const ButtonCtx = Vapor.Button;
const Icon = Vapor.Icon;
const List = Vapor.List;
const ListItem = Vapor.ListItem;
const CtxButton = Vapor.Button;
const Link = Vapor.Link;
const RedirectLink = Vapor.RedirectLink;
const Button = Vapor.Button;

const SideBar = @This();
position: Vapor.Types.Position = .{ .type = .absolute, .top = .px(0), .left = .px(0), .z_index = 999 },
on_item_click: ?*const fn (*const MenuItem) void = null,
on_group_click: ?*const fn (*const GroupItem) void = null,
selected_item: ?*const MenuItem = null,
selected_group: ?*const GroupItem = null,
show_menu: bool = false,
current_path: ?[]const u8 = null,
groups: ?[]GroupItem = null,
items: ?[]MenuItem = null,
title: []const u8 = "",
open: bool = false,

const slide_down = Vapor.Animation.init("sidebar-slide-down")
    .prop(.scaleY, 0, 1)
    .prop(.opacity, 0, 1)
    .duration(150)
    .easing(.easeOut)
    .fill(.forwards);

const slide_up = Vapor.Animation.init("sidebar-slide-up")
    .prop(.scaleY, 1, 0)
    .prop(.opacity, 1, 0)
    .duration(150)
    .easing(.easeOut)
    .fill(.forwards);

const slide_out = Vapor.Animation.init("sidebar-slide-out")
    .prop(.scaleX, 0, 1)
    .prop(.opacity, 0, 1)
    .duration(150)
    .easing(.easeOut)
    .fill(.forwards);

const slide_in = Vapor.Animation.init("sidebar-slide-in")
    .prop(.scaleX, 1, 0)
    .prop(.opacity, 1, 0)
    .duration(150)
    .easing(.easeOut)
    .fill(.forwards);

pub const MenuItem = struct {
    title: []const u8,
    link: []const u8,
    icon: Vapor.IconTokens,
};

pub const GroupItem = struct {
    title: []const u8,
    items: []const MenuItem,
    show: bool = false,
    icon: Vapor.IconTokens,
};

pub fn init() void {
    slide_down.build();
    slide_up.build();
    slide_in.build();
    slide_out.build();
    // sheet.init(&Fabric.lib.allocator_global);
    // sidebar.* = .{};
}

pub fn show() void {
    // sheet.toggle();
}

fn goto(sidebar: *SideBar, url: []const u8) void {
    sidebar.current_path = url;
    // Vapor.Kit.navigate(url);
    // sheet.toggle();
}

pub fn onItemClick(sidebar: *SideBar, item: *const MenuItem) void {
    sidebar.selected_item = item;
    sidebar.current_path = item.link;
    if (sidebar.on_item_click) |callback| {
        callback(item);
    }
}

pub fn onGroupClick(sidebar: *SideBar, group: *GroupItem) void {
    sidebar.selected_group = group;
    toggle(group);
    if (sidebar.on_group_click) |callback| {
        callback(group);
    }
}

fn toggle(group: *GroupItem) void {
    group.show = !group.show;
}

const Styles = struct {
    pub const GroupStyle = &Vapor.Style{
        .visual = .{
            .text_decoration = .none,
            .cursor = .pointer,
            .background = .transparent,
            .border = .{ .radius = .all(4) },
            .outline_color = .palette(.border_color_light),
        },
        .size = .w(.percent(100)),
        .layout = .x_between_center,
        .padding = .xy(10, 8),
    };
};

fn toggleMenu(sidebar: *SideBar) void {
    sidebar.show_menu = !sidebar.show_menu;
}

fn LargeMenu(sidebar: *SideBar) void {
    const current_path = sidebar.current_path orelse "";
    if (sidebar.groups) |groups| {
        for (groups) |*group| {
            ListItem()
                .pos(.relative)
                .size(.hw(.fit, .percent(100)))
                .children({
                CtxButton(onGroupClick, .{ sidebar, group })
                    .a11y(Vapor.Accessibility.init().setExpanded(group.show))
                    .style(Styles.GroupStyle)
                    .children({
                    Box()
                        .layout(.left_center)
                        .spacing(12)
                        .children({
                        Icon(group.icon).font(16, 300, .palette(.text_color)).end();
                        Text(group.title).font(14, 300, .palette(.text_color))
                            .animationEnter("opaque-fade-in")
                            .animationExit("opaque-fade-out")
                            .fontFamily("Montserrat")
                            .end();
                    });
                    Vapor.Icon(.chevron_down)
                        .transform(.rotate(if (group.show) 0 else 180))
                        .transition(.{ .properties = &.{.transform}, .duration = 150, .timing = .easeInOut })
                        .font(12, 700, .palette(.text_color))
                        .end();
                });

                List()
                    // A collapsed group is still on the page (it animates
                    // shut), so screen readers are told to skip it.
                    .a11y(Vapor.Accessibility.init().setHidden(!group.show))
                    .listStyle(.none)
                    .pos(.relative)
                    .scroll(if (group.show) .{} else .none())
                    .size(.hw(if (group.show) .fit else .px(0), .percent(100)))
                    .transition(.{ .properties = &.{ .height, .opacity, .padding }, .duration = 150, .timing = .easeOut })
                    .opacity(if (group.show) 1.0 else 0.0)
                    .padding(if (group.show) .xy(8, 10) else .all(0))
                    .border(.left(1, .palette(.text_color)))
                    .margin(.{ .left = 16 })
                    .direction(.row)
                    .layout(.left_center)
                    .spacing(12)
                    .wrap(.wrap)
                    .children({
                    for (group.items) |*item| {
                        const uuid = Vapor.fmtln("menu-{s}", .{item.link});
                        ListItem()
                            .id(uuid)
                            .pos(.relative)
                            .size(.hw(.fit, .percent(100)))
                            .duration(100)
                            .background(if (std.mem.eql(u8, current_path, item.link)) .transparentize(.palette(.text_color), 1) else .transparent)
                            .border(.solid(.all(1), if (std.mem.eql(u8, current_path, item.link)) .palette(.text_color) else .transparent, .all(12)))
                            .hover(.{
                                .background = if (std.mem.eql(u8, current_path, item.link)) .palette(.text_color) else .palette(.highlight_color),
                            })
                            .children({
                            Box().pos(.tl(.percent(50), .px(-11), .absolute))
                                .background(.palette(.text_color))
                                .radius(.all(99))
                                .width(.px(3)).height(.px(3)).children({});
                            ButtonCtx(onItemClick, .{ sidebar, item })
                                .a11y(Vapor.Accessibility.init().setPressed(if (std.mem.eql(u8, current_path, item.link)) .true_val else .false_val))
                                .tabIndex(if (group.show) 0 else -1)
                                .style(&.{
                                    .visual = Vapor.Types.Visual{
                                        .text_decoration = .none,
                                        .cursor = .pointer,
                                        .background = .transparent,
                                        .border = .{ .radius = .all(12) },
                                        .outline_color = .palette(.border_color_light),
                                    },
                                    .size = .w(.percent(100)),
                                    .layout = .left_center,
                                    .child_gap = 12,
                                    .padding = .xy(10, 8),
                                }).children({
                                Icon(item.icon).font(16, 300, if (std.mem.eql(u8, current_path, item.link)) .palette(.background) else .palette(.text_color)).end();
                                Text(item.title).style(&.{
                                    .visual = .{
                                        .text_color = if (std.mem.eql(u8, current_path, item.link)) .palette(.background) else .palette(.text_color),
                                        .font_size = 14,
                                    },
                                    .font_family = "Montserrat",
                                }).end();
                            });
                        });
                    }
                });
            });
        }
    } else if (sidebar.items) |items| {
        List()
            .listStyle(.none)
            .pos(.relative)
            .scroll(.{})
            .size(.hw(.fit, .percent(100)))
            .transition(.{ .properties = &.{ .height, .opacity, .padding }, .duration = 150, .timing = .easeOut })
            .opacity(1.0)
            .padding(.xy(8, 10))
            .border(.left(1, .palette(.text_color)))
            .margin(.{ .left = 16 })
            .direction(.row)
            .layout(.left_center)
            .spacing(12)
            .wrap(.wrap)
            .children({
            for (items) |*item| {
                const active = if (sidebar.selected_item) |selected_item| blk: {
                    if (selected_item == item) break :blk true;
                    if (std.mem.eql(u8, selected_item.link, item.link)) {
                        break :blk true;
                    }
                    break :blk false;
                } else false;
                const uuid = Vapor.fmtln("menu-{s}", .{item.link});
                ListItem()
                    .id(uuid)
                    .pos(.relative)
                    .size(.hw(.fit, .percent(100)))
                    .duration(100)
                    .background(if (active) .transparentize(.palette(.text_color), 1) else .transparent)
                    .border(.solid(.all(1), if (active) .palette(.text_color) else .transparent, .all(12)))
                    .hover(.{
                        .background = if (active) .palette(.text_color) else .palette(.highlight_color),
                    })
                    .children({
                    Box().pos(.tl(.percent(50), .px(-11), .absolute))
                        .background(.palette(.text_color))
                        .radius(.all(99))
                        .width(.px(3)).height(.px(3)).children({});
                    ButtonCtx(onItemClick, .{ sidebar, item })
                        .a11y(Vapor.Accessibility.init().setPressed(if (active) .true_val else .false_val))
                        .style(&.{
                            .visual = Vapor.Types.Visual{
                                .text_decoration = .none,
                                .cursor = .pointer,
                                .background = .transparent,
                                .border = .{ .radius = .all(12) },
                                .outline_color = .palette(.border_color_light),
                            },
                            .size = .w(.percent(100)),
                            .layout = .left_center,
                            .child_gap = 12,
                            .padding = .xy(10, 8),
                        }).children({
                        Icon(item.icon).font(16, 300, if (active) .palette(.background) else .palette(.text_color)).end();
                        Text(item.title).style(&.{
                            .visual = .{
                                .text_color = if (active) .palette(.background) else .palette(.text_color),
                                .font_size = 14,
                            },
                            .font_family = "Montserrat",
                        }).end();
                    });
                });
            }
        });
    }
}

fn SmallMenu(sidebar: *SideBar) void {
    if (sidebar.groups) |groups| {
        for (groups) |*group| {
            ListItem()
                .pos(.relative)
                .size(.hw(.fit, .percent(100)))
                .padding(.xy(10, 8))
                .children({
                Box()
                    .layout(.left_center)
                    .children({
                    Icon(group.icon).font(16, 300, .palette(.text_color)).end();
                });
            });
        }
    }
}

fn mount(sidebar: *SideBar) void {
    const current_path = Vapor.currentPath();
    sidebar.current_path = current_path;
}

pub fn render(sidebar: *SideBar) void {
    const sidebar_width: Vapor.Types.Sizing = if (sidebar.show_menu) .percent(100) else .percent(40);
    const padding: Vapor.Types.Padding = if (sidebar.show_menu) .all(16) else .all(8);
    Box().pos(.relative).width(.percent(100)).height(.percent(100))
        .onMount(mount, .{sidebar})
        .children({
        Box()
            .size(.hw(.percent(100), sidebar_width))
            .direction(.column)
            .padding(.all(8))
            .layout(.top_left)
            .children({
            Box()
                .size(.hw(.fit, sidebar_width))
                .margin(.{ .left = 10 })
                .layout(.left_center)
                .spacing(8)
                .transformOrigin(.left)
                .transition(.{ .properties = &.{ .transform, .width, .opacity, .padding }, .duration = 150, .timing = .easeInOut })
                .children({
                ButtonCtx(toggleMenu, .{sidebar})
                    .a11y(Vapor.Accessibility.init().setExpanded(sidebar.show_menu))
                    .ariaLabel("Toggle menu")
                    .background(.palette(.text_color))
                    .layout(.left_center)
                    .padding(.xy(4, 2))
                    .outline(.default, .palette(.border_color_light))
                    .radius(.all(8))
                    .children({
                    Icon(.list)
                        .font(24, 700, .palette(.background))
                        .end();
                });
            });
            Box()
                .size(.hw(.percent(100), sidebar_width))
                .children({
                if (sidebar.show_menu) {
                    List()
                        .listStyle(.none)
                        .direction(.column)
                        .spacing(8)
                        .scroll(.{ .y = .scroll, .x = .hidden })
                        .size(.hw(.percent(95), sidebar_width))
                        .transformOrigin(.left)
                        .padding(padding)
                        .transition(.{ .properties = &.{ .transform, .width, .opacity, .padding }, .duration = 150, .timing = .easeInOut })
                        .layout(.top_left)
                        .children({
                        LargeMenu(sidebar);
                    });
                } else {
                    List()
                        .listStyle(.none)
                        .direction(.column)
                        .spacing(8)
                        // .scroll(.{ .y = .scroll, .x = .hidden })
                        .size(.hw(.percent(95), sidebar_width))
                        .transformOrigin(.left)
                        .padding(padding)
                        .transition(.{ .properties = &.{ .transform, .width, .opacity, .padding }, .duration = 150, .timing = .easeInOut })
                        .layout(.top_left)
                        .children({
                        SmallMenu(sidebar);
                    });
                }
            });
        });
    });
}
