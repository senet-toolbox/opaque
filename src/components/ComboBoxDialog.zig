const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Box;
const ButtonCtx = Vapor.Button;
const Button = Vapor.Button;
const TextFmt = Vapor.TextFmt;
const TextField = Vapor.TextField;
const Stack = Vapor.Stack;
const Center = Vapor.Center;
const Icon = Vapor.Icon;
const OverlayManager = @import("OverlayManager.zig");
const OpaqueTypes = @import("OpaqueTypes.zig");

var background: Vapor.Types.Color = .palette(.background);
var border: Vapor.Types.Border = .round(.palette(.border_color_light), .all(6));
var border_color: Vapor.Types.Color = .palette(.border_color_light);
var group_title_color: Vapor.Types.Color = .hex("#8C8C8C");
var text_color: Vapor.Types.Color = .palette(.text_color);
var font_family: []const u8 = "IBM Plex Sans,monospace";
var selected_background: Vapor.Types.Color = .transparentize(.palette(.tint), 0.05);
var selected_border: Vapor.Types.Border = .round(.palette(.tint), .all(6));
var checkbox_color_icon: Vapor.Types.Color = .palette(.background);
var checkbox_color: Vapor.Types.Color = .palette(.text_color);
var tint: Vapor.Types.Color = .palette(.tint);

pub const animateEnter = Vapor.Animation.init("opaque-combobox-enter")
    .prop(.opacity, 0, 1)
    .prop(.scale, 0.9, 1)
    .duration(100)
    .easing(.easeInOut);

pub const animateExit = Vapor.Animation.init("opaque-combobox-exit")
    .prop(.opacity, 1, 0)
    .prop(.scaleY, 1, 0.9)
    .duration(100)
    .easing(.easeInOut);

pub fn new() void {
    animateEnter.build();
    animateExit.build();
}

pub fn ComboBoxDialog(comptime T: type) type {
    return struct {
        const Self = @This();
        const listbox_id = "combobox-listbox";
        pub const Group = struct {
            title: ?[]const u8 = null,
            items: []ItemT,
        };

        pub const ItemT = OpaqueTypes.Item(T);
        // pub const Item = struct {
        //     value: T,
        //     label: []const u8,
        //     icon: ?*const Vapor.IconTokens = null,
        //     is_selected: bool = false,
        //    .is_shown: bool = true,
        // };

        _selected_count: usize = 0,
        trigger: []const u8,
        groups: Vapor.Array(Group),
        _selected_items: std.AutoHashMap(*ItemT, void),
        _closed: bool = true,
        _is_open: bool = false,
        _search_box: Vapor.Element = .{},
        _text_search: []const u8 = "",
        ctx: ?*anyopaque = null,
        on_select: ?*const fn (item: *ItemT) void = null,
        on_select_ctx: ?*const fn (item: *ItemT, ctx: ?*anyopaque) void = null,
        on_close: ?*const fn () void = null,
        on_mount: ?*const fn () void = null,
        on_close_ctx: ?*const fn (ctx: ?*anyopaque) void = null,
        row_component: ?*const fn (self: *Self, item: *ItemT) void = null,
        render_trigger: bool = true,
        hovered_item: ?*ItemT = null,
        current_index: usize = 0,
        _x: f32 = 0,
        _y: f32 = 0,
        _width: f32 = 0,
        binded_combobox: Vapor.Element = .{},
        binded_trigger: Vapor.Element = .{},
        on_trigger: ?*const fn (combobox: *Self, ctx: ?*anyopaque) void = null,
        visible_items: usize = 0,
        /// Shown items rendered so far this render: the same order the
        /// arrow keys walk, so option ids match `current_index`.
        _render_index: usize = 0,
        max_items: usize = 0,

        pub fn init(trigger: []const u8, groups: []const Group) Self {
            var alloc_groups = Vapor.array(Group, .persist);
            alloc_groups.appendSlice(groups) catch unreachable;
            return Self{
                .trigger = trigger,
                .groups = alloc_groups,
                ._selected_items = std.AutoHashMap(*ItemT, void).init(Vapor.arena(.persist)),
            };
        }

        pub fn fromItems(items: []const ItemT) Self {
            var alloc_groups = Vapor.array(Group, .persist);
            var alloc_items = Vapor.array(ItemT, .persist);

            for (items) |item| {
                alloc_items.append(item) catch unreachable;
            }

            // alloc_items.appendSlice(items) catch unreachable;

            alloc_groups.append(.{
                .items = alloc_items.items,
            }) catch unreachable;

            return Self{
                .trigger = "Search",
                .groups = alloc_groups,
                ._selected_items = std.AutoHashMap(*ItemT, void).init(Vapor.arena(.persist)),
                .hovered_item = &alloc_items.items[0],
                .max_items = alloc_items.items.len,
            };
        }

        pub fn toggle(combobox: *Self) void {
            combobox._closed = !combobox._closed;
        }

        pub fn close(combobox: *Self) void {
            OverlayManager.unregister(.keydown, combobox);
            combobox._closed = true;
            combobox._is_open = false;
            if (combobox.on_close) |callback| {
                @call(.auto, callback, .{});
            }
        }

        pub fn open(combobox: *Self) void {
            combobox._closed = false;
        }

        pub fn default(combobox: *Self, selected_item: ItemT) void {
            for (combobox.groups.items) |*group| {
                for (group.items) |*item| {
                    if (std.mem.eql(u8, item.label, selected_item.label)) continue;
                    item.is_selected = false;
                }
            }
            combobox._selected_item = selected_item;
        }

        pub fn selectItem(combobox: *Self, item: *ItemT) void {
            // TOGGLE logic
            item.is_selected = !item.is_selected;

            if (item.is_selected) {
                combobox._selected_count += 1;
                combobox._selected_items.put(item, {}) catch unreachable;
            } else {
                combobox._selected_count -= 1;
                _ = combobox._selected_items.remove(item);
            }

            if (combobox.on_select) |on_select| {
                on_select(item);
            }
            if (combobox.on_select_ctx) |on_select_ctx| {
                on_select_ctx(item, combobox.ctx);
            }
        }

        fn renderItem(combobox: *Self, item: *ItemT) void {
            if (!item.is_shown) return;
            const index = combobox._render_index;
            combobox._render_index += 1;
            const is_active = combobox.hovered_item == item;

            if (combobox.row_component) |row_component| {
                row_component(combobox, item);
                return;
            }

            const background_color: Vapor.Types.Color = if (item.is_selected) blk: {
                break :blk selected_background;
            } else blk: {
                break :blk background;
            };

            const selected_border_color: Vapor.Types.Color = if (combobox.hovered_item == item) blk: {
                break :blk .transparentize(.palette(.tint), 1);
            } else blk: {
                break :blk .transparent;
            };
            ButtonCtx(selectItem, .{ combobox, item })
                .id(optionId(index))
                .a11y(.option(item.is_selected, @intCast(index + 1), @intCast(combobox.visible_items)))
                .tabIndex(if (is_active) 0 else -1)
                .width(.percent(100))
                .height(.px(44))
                .background(background_color)
                .pointer()
                .layout(.left_center)
                .hover(.{
                    .background = .transparentize(.palette(.tint), 0.1),
                })
                .padding(.{ .top = 6, .bottom = 6, .left = 6, .right = 24 })
                .border(.round(selected_border_color, .all(6)))
                .spacing(8)
                .children({
                if (item.icon) |icon| {
                    Icon(icon)
                        .font(14, 300, .transparentize(.palette(.text_color), 0.7))
                        .end();
                }
                Text(item.label)
                    .fontFamily(font_family)
                    .font(14, 300, .transparentize(.palette(.text_color), 0.7))
                    .end();
            });
        }

        /// The id of the `index`th shown option, which the search box names
        /// as its aria-activedescendant.
        fn optionId(index: usize) []const u8 {
            return Vapor.fmtln("{s}-item-{d}", .{ listbox_id, index });
        }

        fn renderGroup(combobox: *Self, group: *Group) void {
            Stack()
                .width(.percent(100))
                .spacing(8)
                .a11y(Vapor.Accessibility.init().setRole(.group).setLabel(group.title orelse ""))
                .children({
                if (group.title) |title| {
                    Text(title)
                        .pl(6)
                        .font(14, 300, group_title_color)
                        .end();
                }
                Stack()
                    .width(.percent(100))
                    .spacing(12)
                    .children({
                    for (group.items) |*item| {
                        combobox.renderItem(item);
                    }
                });
            });
        }

        fn search(combobox: *Self, evt: *Vapor.Event) void {
            if (Vapor.Kit.throttle(60)) return;
            const text = evt.text();
            combobox.visible_items = combobox.max_items;
            combobox._text_search = text;
            combobox.current_index = 0; // Reset to first match
            combobox.hovered_item = null;

            for (combobox.groups.items) |*group| {
                for (group.items) |*item| {
                    if (std.ascii.indexOfIgnoreCase(item.label, text) != null) {
                        item.is_shown = true;
                        if (combobox.hovered_item == null) {
                            combobox.hovered_item = item; // Auto-select first match
                        }
                    } else {
                        item.is_shown = false;
                        combobox.visible_items -= 1;
                    }
                }
            }
        }

        pub fn clearText(combobox: *Self) void {
            combobox.visible_items = combobox.max_items;
            combobox._text_search = "";
            for (combobox.groups.items) |*group| {
                for (group.items) |*item| {
                    item.is_shown = true;
                    if (combobox.hovered_item == null) {
                        combobox.hovered_item = item; // Auto-select first match
                    }
                }
            }
        }

        pub fn selectAll(combobox: *Self) void {
            for (combobox.groups.items) |*group| {
                for (group.items) |*item| {
                    if (item.is_shown and !item.is_selected) {
                        combobox.selectItem(item);
                    }
                }
            }
        }

        pub fn clearAll(combobox: *Self) void {
            var iter = combobox._selected_items.keyIterator();
            while (iter.next()) |item_ptr| {
                item_ptr.*.is_selected = false;
            }
            combobox._selected_items.clearRetainingCapacity();
            combobox._selected_count = 0;
        }

        fn mountSearchBox(combobox: *Self) void {
            OverlayManager.register(.keydown, handleKeyPresses, .{combobox});
            combobox._search_box.focus();
            if (combobox.on_mount) |on_mount| {
                on_mount();
            }
            combobox._is_open = true;
        }

        fn scrollItemIntoView(combobox: *Self, index: usize) void {
            const item_height: u32 = 56;
            const visible_height: u32 = 392;
            const padding: u32 = 8;

            const item_top: u32 = @intCast(index * item_height);
            const item_bottom: u32 = item_top + item_height;
            const scroll_top: u32 = @intFromFloat(combobox.binded_combobox.scroll_top);

            if (item_top < scroll_top + padding) {
                // Saturating sub: if item_top < padding, result is 0
                combobox.binded_combobox.scrollToTop(@as(f32, @floatFromInt(item_top -| padding)));
            } else if (item_bottom > scroll_top + visible_height - padding) {
                combobox.binded_combobox.scrollToTop(@as(f32, @floatFromInt(item_bottom - visible_height + padding)));
            }
        }

        fn handleKeyPresses(combobox: *Self, evt: *Vapor.Event) void {
            const key = evt.key();

            if (std.mem.eql(u8, key, "Escape")) {
                evt.preventDefault();
                combobox.close();
                if (combobox.on_close) |callback| {
                    @call(.auto, callback, .{});
                }
                return;
            }

            // Count total items first
            var total_items: usize = 0;
            for (combobox.groups.items) |*group| {
                for (group.items) |*item| {
                    if (item.is_shown) total_items += 1;
                }
            }

            if (total_items == 0) return;

            if (std.mem.eql(u8, "ArrowDown", key)) {
                evt.preventDefault();
                if (combobox.current_index + 1 < total_items) {
                    combobox.current_index += 1;
                } else {
                    combobox.current_index = 0; // Wrap to top
                }

                var flat_index: usize = 0;
                outer: for (combobox.groups.items) |*group| {
                    for (group.items) |*item| {
                        if (!item.is_shown) continue;
                        if (flat_index == combobox.current_index) {
                            combobox.hovered_item = item;
                            break :outer;
                        }
                        flat_index += 1;
                    }
                }

                combobox.scrollItemIntoView(combobox.current_index);
            }

            if (std.mem.eql(u8, "ArrowUp", key)) {
                evt.preventDefault();
                if (combobox.current_index > 0) {
                    combobox.current_index -= 1;
                } else {
                    combobox.current_index = total_items - 1; // Wrap to bottom
                }

                var flat_index: usize = 0;
                outer: for (combobox.groups.items) |*group| {
                    for (group.items) |*item| {
                        if (!item.is_shown) continue;
                        if (flat_index == combobox.current_index) {
                            combobox.hovered_item = item;
                            break :outer;
                        }
                        flat_index += 1;
                    }
                }

                combobox.scrollItemIntoView(combobox.current_index);
            }

            if (std.mem.eql(u8, "Enter", key) or std.mem.eql(u8, "Return", key)) {
                evt.preventDefault();
                if (combobox.hovered_item) |item| {
                    combobox.selectItem(item);
                }
            }

            if (std.mem.eql(u8, "Tab", key)) {
                evt.preventDefault();
                if (combobox.hovered_item) |item| {
                    combobox.selectItem(item);
                }
                combobox.close();
            }
        }

        fn createBindedTrigger(_: *Self) *Vapor.Element {
            const binded_trigger: *Vapor.Element = Vapor.arena(.frame).create(Vapor.Element) catch unreachable;
            binded_trigger.* = .{};
            return binded_trigger;
        }

        fn toggleWithBindedTrigger(combobox: *Self, binded_trigger: *Vapor.Element) void {
            const bounds = binded_trigger.getBoundingClientRect() orelse return;
            combobox._x = bounds.left;
            combobox._y = bounds.top + bounds.height + 4;
            combobox._width = bounds.width;
            combobox.toggle();
        }

        fn toggleWithBindedTriggerCtx(combobox: *Self, binded_trigger: *Vapor.Element, ctx: ?*anyopaque) void {
            const bounds = binded_trigger.getBoundingClientRect() orelse return;
            combobox._x = bounds.left;
            combobox._y = bounds.top + bounds.height + 4;
            combobox._width = bounds.width;
            combobox.toggle();
            if (combobox.on_trigger) |on_trigger| {
                on_trigger(combobox, ctx);
            }
        }

        fn CheckBox(selected: bool) void {
            Box()
                .width(.px(18))
                .height(.px(18))
                .border(.round(.palette(.border_color_light), .all(4)))
                .cursor(.pointer)
                .duration(100)
                .hoverScale()
                .background(if (selected) tint else background)
                .hoverScale()
                .layout(.center)
                .children({
                Icon(.check)
                    .font(16, 300, checkbox_color_icon)
                    .end();
            });
        }

        pub fn renderComboBoxDialog(combobox: *Self) void {
            Box()
                .a11y(Vapor.Accessibility.dialog("Command Palette"))
                .zIndex(999)
                .width(.percent(100))
                .children({
                Stack()
                    .width(.percent(100))
                    .padding(.{ .top = 8 })
                    .onMount(mountSearchBox, .{combobox})
                    .children({
                    Box()
                        .width(.percent(100))
                        .padding(.{ .top = 6, .bottom = 14, .left = 12, .right = 12 })
                        .pointer()
                        .border(.bottom(1, border_color))
                        .layout(.x_between_center)
                        .children({
                        Icon(.search)
                            .font(14, 300, group_title_color)
                            .end();
                        TextField(.string)
                            .ref(&combobox._search_box)
                            .val(&combobox._text_search)
                            .background(background)
                            .placeholder("Search...")
                            .width(.percent(100))
                            .border(.none)
                            .padding(.horizontal(12))
                            .outline(.none, null)
                            .fontFamily(font_family)
                            .font(14, 300, group_title_color)
                            .onEvent(.input, search, .{combobox})
                            .a11y(Vapor.Accessibility.combobox(true, listbox_id)
                                .setActiveDescendant(if (combobox.hovered_item) |_|
                                    optionId(combobox.current_index)
                                else
                                    null)
                                .setLabel("Search options"))
                            .end();
                        ButtonCtx(clearText, .{combobox})
                            .ariaLabel("Clear search")
                            .background(.transparent)
                            .pointer()
                            .children({
                            Icon(.x_lg)
                                .font(14, 300, group_title_color)
                                .end();
                        });
                    });
                    Box()
                        .a11y(.liveRegion(.polite))
                        .width(.percent(100))
                        .padding(.xy(12, 8))
                        .layout(.right_center)
                        .spacing(16)
                        // .visuallyHidden() // You'd add this style helper
                        .children({
                        TextFmt("Results: {d}", .{combobox.visible_items})
                            .font(12, 300, .palette(.text_color))
                            .fontFamily(font_family)
                            .end();
                    });

                    Stack()
                        .id(listbox_id) // or however you set HTML id in Vapor
                        .a11y(.listbox("Select an option"))
                        .ref(&combobox.binded_combobox)
                        .height(.elastic(36, 392))
                        .width(.percent(100))
                        .scroll(.scrollY())
                        .padding(.all(8))
                        .children({
                        var has_visible = false;
                        combobox._render_index = 0;
                        for (combobox.groups.items) |*group| {
                            for (group.items) |*item| {
                                if (item.is_shown) has_visible = true;
                            }
                            combobox.renderGroup(group);
                        }

                        if (!has_visible) {
                            Box()
                                .width(.percent(100))
                                .padding(.all(24))
                                .layout(.center)
                                .children({
                                Text("No results found")
                                    .font(14, 300, group_title_color)
                                    .end();
                            });
                        }
                    });
                    Box()
                        .width(.percent(100))
                        .height(.px(42))
                        .padding(.horizontal(12))
                        .border(.top(1, border_color))
                        .layout(.right_center)
                        .spacing(16)
                        .children({
                        Box()
                            .layout(.left_center)
                            .spacing(8)
                            .children({
                            Box()
                                .layout(.x_between_center)
                                .border(border)
                                .background(background)
                                .padding(.xy(6, 2))
                                .duration(100)
                                .shadow(Vapor.Types.NewShadow.init()
                                    .inset(0, -2, .transparentize(.black, 0.3)))
                                .children({
                                Text("esc")
                                    .font(14, 300, .palette(.text_color))
                                    .fontFamily(font_family)
                                    .end();
                            });
                            Text("to dismiss")
                                .font(14, 300, .palette(.text_color))
                                .fontFamily(font_family)
                                .end();
                        });
                        Box()
                            .layout(.left_center)
                            .spacing(8)
                            .children({
                            Box()
                                .layout(.x_between_center)
                                .border(border)
                                .background(background)
                                .padding(.xy(6, 2))
                                .duration(100)
                                .shadow(Vapor.Types.NewShadow.init()
                                    .inset(0, -2, .transparentize(.black, 0.3)))
                                .children({
                                Text("↑ ↓")
                                    .font(14, 300, .palette(.text_color))
                                    .fontFamily(font_family)
                                    .end();
                            });
                            Text("to navigate")
                                .font(14, 300, .palette(.text_color))
                                .fontFamily(font_family)
                                .end();
                        });
                        Box()
                            .layout(.left_center)
                            .spacing(8)
                            .children({
                            Box()
                                .layout(.x_between_center)
                                .border(border)
                                .background(background)
                                .padding(.xy(6, 2))
                                .duration(100)
                                .shadow(Vapor.Types.NewShadow.init()
                                    .inset(0, -2, .transparentize(.black, 0.3)))
                                .children({
                                Text("return")
                                    .font(14, 300, .palette(.text_color))
                                    .fontFamily(font_family)
                                    .end();
                            });
                            Text("to select")
                                .font(14, 300, .palette(.text_color))
                                .fontFamily(font_family)
                                .end();
                        });
                    });
                });
            });
        }

        pub fn render(combobox: *Self) void {
            if (combobox._closed) {
                Vapor.Null();
                Vapor.Null();
                return;
            }
            Box()
                .blur(1)
                .size(.full)
                .pos(.full(.fixed))
                .zIndex(9999)
                .children({
                ButtonCtx(close, .{combobox})
                    .size(.full)
                    .pos(.tl(.px(0), .px(0), .fixed))
                    .end();
            });
            Box()
                .pos(.tl(.percent(10), .percent(32), .fixed))
                .zIndex(999)
                .animationEnter(if (!combobox._is_open) "opaque-combobox-enter" else null)
                .animationExit("opaque-combobox-exit")
                .width(.percent(34))
                .background(background)
                .shadow(.glow(30, .transparentize(.black, 0.1)))
                .border(.round(.transparent, .all(6)))
                .layout(.top_left)
                .zIndex(9999)
                .children({
                renderComboBoxDialog(combobox);
            });
        }
    };
}
