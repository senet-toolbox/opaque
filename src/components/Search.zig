const std = @import("std");
const Vapor = @import("vapor");
const Static = Vapor.Static;
const Binded = Vapor.Element;
const menu_items = @import("../components/DocNavbar.zig").menu_items;
const MenuItem = @import("../components/DocNavbar.zig").MenuItem;
const goto = @import("../components/DocNavbar.zig").goto;
const Theme = @import("theme");
const TextFmt = Vapor.TextFmt;
const TextField = Vapor.TextField;
const OverlayManager = @import("OverlayManager.zig");

var search_box: Vapor.Element = Vapor.Element{};
var binded: Binded = .{};
var show: bool = false;
var current_index: usize = 0;
var dynamic_menu_items: std.array_list.Managed(MenuItem) = undefined;
var uuids: Vapor.Array([]const u8) = undefined;
pub fn init() void {
    dynamic_menu_items = std.array_list.Managed(MenuItem).init(Vapor.arena(.persist));
    dynamic_menu_items.appendSlice(menu_items) catch {
        Vapor.println("Error appending menu items", .{});
    };
    uuids = Vapor.array([]const u8, .persist);
    current_item = dynamic_menu_items.items[0];
}

pub fn toggle() void {
    show = !show;
}

pub fn mount() void {
    Vapor.print("mount", .{});
    OverlayManager.register(.keydown, handleKeyPresses, .{&binded});
    search_box.focus();
}

pub fn destroy() void {
    OverlayManager.unregister(.keydown, &binded);
    current_item = dynamic_menu_items.items[0];
    Vapor.print("destroy", .{});
}

fn scrollItemIntoView(index: usize) void {
    const uuid = uuids.items[index];
    Vapor.scrollIntoView(uuid, .{ .block = .nearest });
}

fn handleKeyPresses(_: *Binded, evt: *Vapor.Event) void {
    evt.preventDefault();
    const key = evt.key();

    if (std.mem.eql(u8, key, "Escape")) {
        close();
        return;
    }

    const total_items: usize = dynamic_menu_items.items.len;

    if (std.mem.eql(u8, "ArrowDown", key)) {
        if (current_index + 1 < total_items) {
            current_index += 1;
        } else {
            current_index = 0; // Wrap to top
        }

        var flat_index: usize = 0;
        for (dynamic_menu_items.items) |item| {
            if (flat_index == current_index) {
                current_item = item;
                break;
            }
            flat_index += 1;
        }

        scrollItemIntoView(current_index);
    }

    if (std.mem.eql(u8, "ArrowUp", key)) {
        if (current_index > 0) {
            current_index -= 1;
        } else {
            current_index = total_items - 1; // Wrap to bottom
        }

        var flat_index: usize = 0;
        for (dynamic_menu_items.items) |item| {
            if (flat_index == current_index) {
                current_item = item;
                break;
            }
            flat_index += 1;
        }

        scrollItemIntoView(current_index);
    }

    if (std.mem.eql(u8, "Enter", key) or std.mem.eql(u8, "Return", key)) {
        if (current_item) |item| {
            goto(item.link);
            close();
        }
    }

    // if (std.mem.eql(u8, "Tab", key)) {
    //     if (combobox.hovered_item) |item| {
    //         combobox.selectItem(item);
    //     }
    //     combobox.close();
    // }
}

fn clear() void {
    dynamic_menu_items.clearRetainingCapacity();
    dynamic_menu_items.appendSlice(menu_items) catch {
        Vapor.println("Error appending menu items", .{});
    };
}

/// Searches the item's title and all relevant fields within its tags.
fn search(evt: *Vapor.Event) void {
    const text = evt.text();

    // Clear the list to rebuild it for the new search
    dynamic_menu_items.clearRetainingCapacity();

    // If the search box is empty, show all items
    if (text.len == 0) {
        dynamic_menu_items.appendSlice(menu_items) catch {};
        // Vapor.cycle();
        return;
    }

    // Loop through the master list of all menu items
    for (menu_items) |item| {
        var found_match = false;

        // 1. Check if the main title matches
        if (std.ascii.startsWithIgnoreCase(item.title, text)) {
            found_match = true;
        }

        // 2. If no match yet, search through the tags
        if (!found_match) {
            for (item.tags) |tag| {
                // Check tag's sub_title and description
                if (std.ascii.startsWithIgnoreCase(tag.sub_title, text) or
                    std.ascii.startsWithIgnoreCase(tag.description, text))
                {
                    found_match = true;
                    break; // Match found, no need to check other tags
                }

                // Check the tag's keywords
                for (tag.keywords) |keyword| {
                    if (std.ascii.startsWithIgnoreCase(keyword, text)) {
                        found_match = true;
                        break; // Keyword matched, break from keyword loop
                    }
                }

                // If a keyword matched, break from the outer tag loop too
                if (found_match) {
                    break;
                }
            }
        }

        // 3. If a match was found anywhere, add the item to the dynamic list
        if (found_match) {
            dynamic_menu_items.append(item) catch {};
        }
    }
}

fn closeEvent(_: *Vapor.Event) void {
    show = false;
    Vapor.cycle();
}

fn close() void {
    show = false;
    clear();
    OverlayManager.unregister(.keydown, &binded);
}

var current_item: ?MenuItem = null;
fn onHover(item: MenuItem, _: *Vapor.Event) void {
    current_item = item;
}

fn onLeave(_: *Vapor.Event) void {
    current_item = null;
}

fn navigate(url: []const u8) void {
    goto(url);
    // Vapor.Kit.navigate(url);
    close();
}

pub fn render() void {
    if (show) {
        Static.HooksCtx(.mounted, mount, .{})({
            Static.HooksCtx(.destroy, destroy, .{})({
                Static.Center().style(&.{
                    .position = .{
                        .type = .fixed,
                        .top = .percent(0),
                        .bottom = .percent(0),
                        .left = .percent(0),
                        .right = .percent(0),
                        .z_index = 1100,
                    },
                    .size = .squarePercent(100),
                    .direction = .row,
                }).children({
                    // Static.Box().bind(&background).style(&.{
                    Static.Button(close)
                        .style(&.{
                            .position = .{
                                .type = .fixed,
                                .top = .px(0),
                                .right = .px(0),
                                .left = .px(0),
                                .bottom = .px(0),
                                .z_index = 1100,
                            },
                            .visual = .{ .background = .transparentize(.hex("#000000"), if (Theme.mode == .light) 0.1 else 0.7) },
                        }).children({});
                    Static.Box()
                        // .ref(&binded)
                        .style(&.{
                            .size = .{ .width = .mobileDesktopPercent(90, 40), .height = .percent(80) },
                            .visual = .{
                                .border = .thin(.palette(.text_color)),
                                // .border_radius = .all(8),
                                .background = .palette(.background),
                            },
                            .padding = .all(12),
                            .direction = .column,
                            .layout = .top_center,
                            .child_gap = 8,
                            .position = .{ .type = .relative, .z_index = 1101 },
                        }).children({
                        Static.Box().style(&.{
                            .size = .{ .width = .percent(100) },
                            .layout = .x_between_center,
                            .padding = .horizontal(12),
                            .interactive = .{
                                .hover = .{
                                    .border = .thin(.palette(.tint)),
                                },
                            },
                            .visual = .{ .border = .thin(.hex("#E1E1E1")), .cursor = .pointer, .background = .palette(.background) },
                        }).children({
                            Static.Icon(.search).style(&.{
                                .visual = .{ .font_size = 16 },
                            }).end();
                            TextField(.string)
                                .ref(&search_box)
                                .onChange(search).style(&.{
                                    .size = .hw(.px(38), .grow),
                                    .padding = .xy(8, 4),
                                    .visual = .{
                                        .border = .none,
                                        .font_size = 18,
                                        .background = .transparent,
                                        .text_color = .palette(.text_color),
                                        .outline = .none,
                                    },
                                    .font_family = "IBM Plex Mono,monospace",
                                }).end();
                            Static.Icon(.command).style(&.{
                                .visual = .{ .font_size = 16 },
                            }).end();
                        });

                        TextFmt("Results {d}", .{3}).style(&.{
                            .visual = .{ .font_weight = 700, .font_size = 14 },
                            .size = .{ .width = .percent(100) },
                            .margin = .{ .top = 20 },
                        }).end();
                        Static.List().style(&.{
                            .direction = .column,
                            .size = .{ .width = .percent(100), .height = .percent(100) },
                            .list_style = .none,
                            .padding = .all(0),
                            .scroll = .scrollY(),
                            .child_gap = 16,
                        }).children({
                            uuids.clearRetainingCapacity();
                            for (dynamic_menu_items.items, 0..) |item, j| {
                                const border: Vapor.Types.Border = if (j != 0) .sharp(.all(1), .palette(.text_color)) else .thin(.palette(.text_color));
                                var list_item: Vapor.Builder(.static) = Static.ListItem();
                                uuids.append(list_item.getUUID()) catch unreachable;
                                list_item
                                    .onHoverCtx(onHover, item)
                                    .onLeave(onLeave)
                                    .style(&.{
                                        .size = .{ .width = .percent(100), .height = .fit },
                                        .visual = .{
                                            .cursor = .pointer,
                                            .border = border,
                                        },
                                        .margin = .{ .bottom = -1 },
                                        .padding = .all(8),
                                        .interactive = .{
                                            .hover = .{
                                                .border = .thin(.palette(.tint)),
                                            },
                                            .hover_position = .{ .z_index = 1000, .type = .relative },
                                        },
                                    }).children({
                                    const text_color: Vapor.Types.Color = if (current_item) |c_item| if (std.mem.eql(u8, c_item.id, item.id)) .palette(.tint) else .palette(.text_color) else .palette(.text_color);
                                    // Static.Link(.{ .url = item.link, .aria_label = item.title })
                                    //     .textDecoration(.none)
                                    //     .body()({
                                    Static.CtxButton(navigate, .{item.link})
                                        .width(.full)
                                        .layout(.left_center)
                                        .direction(.column)
                                        .pointer()
                                        .textDecoration(.none
                                            // &.{
                                            // .size = .{ .width = .percent(100), .height = .px(60) },
                                            // .visual = .{
                                            //     .border_radius = .top_bottom(4, 0),
                                            //     .border_color = .transparent,
                                            //     .border_thickness = .all(2),
                                            //     .cursor = .pointer,
                                            //     .text_decoration = .none,
                                            // },
                                            // .padding = .horizontal(8),
                                            // .direction = .column,
                                            // .interactive = .{
                                            //     .hover = .{
                                            //         .border_color = .hex("#5A27FF"),
                                            //         .border_thickness = .all(2),
                                            //     },
                                            // },
                                            // }
                                        ).children({
                                        Static.Text(item.title).style(&.{
                                            .visual = .{ .font_size = 18, .text_color = text_color, .font_weight = 700 },
                                            .font_family = "IBM Plex Mono,monospace",
                                        }).end();
                                        Static.Text(item.link).style(&.{
                                            .visual = .{ .font_size = 12, .text_color = text_color },
                                            .font_family = "IBM Plex Mono,monospace",
                                        }).end();
                                        // });
                                        for (item.tags) |tag| {
                                            Static.Link(.{ .aria_label = tag.sub_title, .url = tag.url }).style(&.{
                                                .layout = .left_center,
                                                .size = .{ .width = .fit, .height = .fit },
                                                .visual = .{
                                                    .cursor = .pointer,
                                                    .text_decoration = .none,
                                                    .border = .bottom(1, .transparent),
                                                },
                                                .direction = .column,
                                                .font_family = "Montserrat",
                                                // .padding = .horizontal(8),
                                                .interactive = .{
                                                    .hover = .{
                                                        .border = .bottom(1, .palette(.tint)),
                                                    },
                                                },
                                            }).children({
                                                Static.Text(tag.sub_title).style(&.{
                                                    .visual = .{ .font_size = 14, .font_weight = 700, .text_color = text_color },
                                                }).end();
                                                Static.Text(tag.description).style(&.{
                                                    .visual = .{ .font_size = 14, .text_color = text_color },
                                                }).end();
                                            });
                                        }
                                    });
                                });
                            }
                        });
                    });
                });
            });
        });
    } else {
        Static.Null();
    }
}
