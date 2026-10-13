const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Box;
const ButtonCtx = Vapor.CtxButton;
const Button = Vapor.Button;
const TextFmt = Vapor.TextFmt;
const TextField = Vapor.TextField;
const Stack = Vapor.Stack;
const Center = Vapor.Center;
const Icon = Vapor.Icon;
const HooksCtx = Vapor.Static.HooksCtx;

var background: Vapor.Types.Color = .white;
var border: Vapor.Types.BorderGrouped = .round(.hex("#e4e4e4"), .all(6));
var group_title_color: Vapor.Types.Color = .hex("#8C8C8C");
var text_color: Vapor.Types.Color = .black;
var font_family: []const u8 = "Montserrat";
var selected_background: Vapor.Types.Color = .transparentizeHex(.vapor_blue, 0.05);
var selected_border: Vapor.Types.BorderGrouped = .round(.vapor_blue, .all(6));

const animateEnter = Vapor.Animation.init("dialog-enter")
    .prop(.opacity, 0, 1)
    .prop(.scale, 0.9, 1)
    .duration(200)
    .easing(.easeInOut);

const animateExit = Vapor.Animation.init("dialog-exit")
    .prop(.opacity, 1, 0)
    .prop(.scaleY, 1, 0.9)
    .duration(100)
    .easing(.easeInOut);

pub fn new() void {
    animateEnter.build();
    animateExit.build();
}

pub fn Select(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const Group = struct {
            title: ?[]const u8 = null,
            items: []Item,
        };

        pub const Item = struct {
            value: T,
            label: []const u8,
            is_selected: bool = false,
            _is_shown: bool = true,
        };

        trigger: []const u8,
        groups: Vapor.Array(Group),
        _selected_item: ?*Item = null,
        _closed: bool = true,
        _searchable: bool = false,
        _search_box: Vapor.Binded = .{},
        ctx: ?*anyopaque = null,
        on_select: ?*const fn (ctx: ?*anyopaque, item: *Item) void = null,
        trigger_component: ?*const fn (self: *Self) void = null,
        render_trigger: bool = true,

        pub fn init(trigger: []const u8, groups: []const Group) Self {
            var alloc_groups = Vapor.array(Group, .persist);
            alloc_groups.appendSlice(groups) catch unreachable;
            return Self{
                .trigger = trigger,
                .groups = alloc_groups,
            };
        }

        pub fn fromItems(items: []const Item) Self {
            var alloc_groups = Vapor.array(Group, .persist);
            var alloc_items = Vapor.array(Item, .persist);

            alloc_items.appendSlice(items) catch unreachable;

            alloc_groups.append(.{
                .items = alloc_items.items,
            }) catch unreachable;

            return Self{
                .trigger = "Select",
                .groups = alloc_groups,
            };
        }

        pub fn toggle(select: *Self) void {
            select._closed = !select._closed;
        }

        pub fn close(select: *Self) void {
            select._closed = true;
        }

        fn selectItem(select: *Self, selected_item: *Item) void {
            for (select.groups.items) |*group| {
                for (group.items) |*item| {
                    if (item == selected_item) continue;
                    item.is_selected = false;
                }
            }
            selected_item.is_selected = !selected_item.is_selected;
            if (!selected_item.is_selected) {
                select._selected_item = null;
            } else {
                select._selected_item = selected_item;
            }

            if (select.on_select) |on_select| {
                on_select(select.ctx, selected_item);
            }

            select.close();
        }

        fn renderItem(select: *Self, item: *Item) void {
            if (!item._is_shown) return;
            ButtonCtx(selectItem, .{ select, item })
                .width(.percent(100))
                .height(.px(36))
                .background(if (item.is_selected) selected_background else background)
                .pointer()
                .layout(.left_center)
                .duration(100)
                .hoverBackground(selected_background)
                .padding(.all(6))
                .border(.round(.transparent, .all(6)))
                .children({
                Text(item.label)
                    .fontFamily(font_family)
                    .font(14, 300, text_color)
                    .end();
            });
        }

        fn renderGroup(select: *Self, group: *Group) void {
            Stack()
                .width(.percent(100))
                .spacing(8)
                .children({
                if (group.title) |title| {
                    Text(title)
                        .pl(6)
                        .font(14, 300, group_title_color)
                        .end();
                }
                Stack()
                    .width(.percent(100))
                    .children({
                    for (group.items) |*item| {
                        select.renderItem(item);
                    }
                });
            });
        }

        fn search(select: *Self, evt: *Vapor.Event) void {
            const text = evt.text();
            select._search_box.text = text;
            for (select.groups.items) |*group| {
                for (group.items) |*item| {
                    Vapor.print("Searching {s}", .{item.label});
                    if (std.ascii.startsWithIgnoreCase(item.label, text)) {
                        item._is_shown = true;
                    } else {
                        item._is_shown = false;
                    }
                }
            }
        }

        fn clearText(select: *Self) void {
            select._search_box.text = "";
            for (select.groups.items) |*group| {
                for (group.items) |*item| {
                    item._is_shown = true;
                }
            }
        }

        fn mountSearchBox(select: *Self) void {
            select._search_box.focus();
        }

        pub fn renderTrigger(select: *Self) void {
            ButtonCtx(toggle, .{select})
                .width(.percent(100))
                .border(if (select._closed) border else selected_border)
                .background(background)
                .padding(.all(8))
                .shadow(.{
                    .color = if (select._closed) .transparent else .transparentizeHex(.vapor_blue, 0.1),
                    .spread = 2,
                })
                .children({
                Box()
                    .width(.percent(100))
                    .layout(.x_between_center)
                    .children({
                    Text(if (select._selected_item) |item| item.label else select.trigger)
                        .fontFamily(font_family)
                        .font(16, 300, group_title_color)
                        .end();
                    Icon(if (select._closed) .chevron_down else .chevron_up)
                        .fontFamily(font_family)
                        .font(14, 300, group_title_color)
                        .end();
                });
            });
        }

        pub fn render(select: *Self) void {
            Stack()
                .width(.percent(100))
                .spacing(4)
                .pos(.relative)
                .children({
                if (select.render_trigger) {
                    renderTrigger(select);
                }
                if (!select._closed) {
                    Stack()
                        .pos(.tl(.px(0), .percent(0), .absolute))
                        .transformOrigin(.top_center)
                        .animationEnter(&animateEnter)
                        .animationExit(&animateExit)
                        .width(.percent(100))
                        .border(border)
                        .background(background)
                        .padding(.all(8))
                        .shadow(.{
                            .top = 4,
                            .spread = 2,
                            .blur = 6,
                            .color = .transparentizeHex(.black, 0.05),
                        })
                        .children({
                        if (select._searchable) {
                            HooksCtx(.mounted, mountSearchBox, .{select})({
                                Box()
                                    .width(.percent(100))
                                    .padding(.tblr(6, 14, 6, 6))
                                    .pointer()
                                    .layout(.x_between_center)
                                    .children({
                                    Icon(.search)
                                        .font(14, 300, group_title_color)
                                        .end();
                                    TextField(.string)
                                        .ref(&select._search_box)
                                        .val(&select._search_box.text)
                                        .placeholder("Search...")
                                        .width(.percent(100))
                                        .border(.none)
                                        .padding(.horizontal(12))
                                        .outline(.none)
                                        .fontFamily(font_family)
                                        .font(16, 300, group_title_color)
                                        .onEventCtx(.input, search, select)
                                        .end();
                                    ButtonCtx(clearText, .{select})
                                        .background(.transparent)
                                        .pointer()
                                        .children({
                                        Icon(.x_lg)
                                            .font(14, 300, group_title_color)
                                            .end();
                                    });
                                });
                            });
                        }
                        Stack()
                            .height(.elastic(36, 256))
                            .width(.percent(100))
                            .scroll(.scroll_y())
                            .children({
                            for (select.groups.items) |*group| {
                                select.renderGroup(group);
                            }
                        });
                    });
                }
            });
        }
    };
}
