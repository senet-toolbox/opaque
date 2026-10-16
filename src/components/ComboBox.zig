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

var background: Vapor.Types.Color = .palette(.background);
var border: Vapor.Types.Border = .round(.palette(.border_color_light), .all(12));
var group_title_color: Vapor.Types.Color = .hex("#8C8C8C");
var text_color: Vapor.Types.Color = .palette(.text_color);
var font_family: []const u8 = "Montserrat";
var selected_background: Vapor.Types.Color = .transparentize(.palette(.tint), 0.05);
var selected_border: Vapor.Types.Border = .round(.palette(.tint), .all(12));
var checkbox_color_icon: Vapor.Types.Color = .palette(.background);
var checkbox_color: Vapor.Types.Color = .palette(.text_color);
var tint: Vapor.Types.Color = .palette(.tint);

pub fn ComboBox(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const Group = struct {
            title: ?[]const u8 = null,
            items: []Item,
        };

        pub const Item = struct {
            value: T,
            label: []const u8,
            icon: ?Vapor.IconTokens = null,
            is_selected: bool = false,
            _is_shown: bool = true,
        };

        _selected_count: usize = 0,
        trigger: []const u8,
        groups: Vapor.Array(Group),
        _selected_items: std.AutoHashMap(*Item, void),
        _closed: bool = true,
        /// The document keydown listener for Escape, while the list is open.
        _escape_listener: ?u32 = null,
        _search_box: Vapor.Element = .{},
        ctx: ?*anyopaque = null,
        on_select: ?*const fn (item: *Item) void = null,
        on_select_ctx: ?*const fn (item: *Item, ctx: ?*anyopaque) void = null,
        trigger_component: ?*const fn (self: *Self) void = null,
        render_trigger: bool = true,
        _x: f32 = 0,
        _y: f32 = 0,
        _width: f32 = 0,
        binded_combobox: Vapor.Element = .{},
        binded_trigger: Vapor.Element = .{},
        on_trigger: ?*const fn (combobox: *Self, ctx: ?*anyopaque) void = null,
        // binded_triggers_ptrs: Vapor.Array(Vapor.Binded),

        pub fn init(trigger: []const u8, groups: []const Group) Self {
            var alloc_groups = Vapor.array(Group, .persist);
            alloc_groups.appendSlice(groups) catch unreachable;
            return Self{
                .trigger = trigger,
                .groups = alloc_groups,
                ._selected_items = std.AutoHashMap(*Item, void).init(Vapor.arena(.persist)),
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
                .trigger = "Search",
                .groups = alloc_groups,
                ._selected_items = std.AutoHashMap(*Item, void).init(Vapor.arena(.persist)),
            };
        }

        pub fn toggle(combobox: *Self) void {
            combobox._closed = !combobox._closed;
        }

        pub fn close(combobox: *Self) void {
            combobox._closed = true;
        }

        pub fn default(combobox: *Self, selected_item: Item) void {
            for (combobox.groups.items) |*group| {
                for (group.items) |*item| {
                    if (std.mem.eql(u8, item.label, selected_item.label)) continue;
                    item.is_selected = false;
                }
            }
            combobox._selected_item = selected_item;
        }

        fn selectItem(combobox: *Self, item: *Item) void {
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

        fn renderItem(combobox: *Self, item: *Item) void {
            if (!item._is_shown) return;
            ButtonCtx(selectItem, .{ combobox, item })
                .a11y(Vapor.Accessibility.init().setRole(.option).setSelected(item.is_selected))
                .width(.percent(100))
                .height(.px(36))
                // .background(if (item.is_selected) selected_background else background)
                .pointer()
                .layout(.left_center)
                .duration(100)
                .hoverBackground(selected_background)
                .padding(.{ .top = 6, .bottom = 6, .left = 6, .right = 24 })
                .border(.round(.transparent, .all(8)))
                .spacing(8)
                .children({
                CheckBox(item.is_selected);
                if (item.icon) |icon| {
                    Icon(icon)
                        .font(14, 300, text_color)
                        .end();
                }
                Text(item.label)
                    .fontFamily(font_family)
                    .font(14, 300, text_color)
                    .end();
            });
        }

        fn renderGroup(combobox: *Self, group: *Group) void {
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
                    .spacing(8)
                    .children({
                    for (group.items) |*item| {
                        combobox.renderItem(item);
                    }
                });
            });
        }

        fn search(combobox: *Self, evt: *Vapor.Event) void {
            const text = evt.text();
            combobox._search_box.text = text;
            for (combobox.groups.items) |*group| {
                for (group.items) |*item| {
                    if (std.ascii.startsWithIgnoreCase(item.label, text)) {
                        item._is_shown = true;
                    } else {
                        item._is_shown = false;
                    }
                }
            }
        }

        fn clearText(combobox: *Self) void {
            combobox._search_box.text = "";
            for (combobox.groups.items) |*group| {
                for (group.items) |*item| {
                    item._is_shown = true;
                }
            }
        }

        fn mountSearchBox(combobox: *Self) void {
            combobox._search_box.focus();
            if (combobox._escape_listener == null) {
                combobox._escape_listener = Vapor.lib.addGlobalListenerCtx(.keydown, escapeKey, .{combobox});
            }
        }

        /// The list left the page, however it was closed.
        fn unmountSearchBox(combobox: *Self) void {
            if (combobox._escape_listener) |id| {
                _ = Vapor.lib.removeGlobalListener(.keydown, id);
                combobox._escape_listener = null;
            }
        }

        fn escapeKey(combobox: *Self, evt: *Vapor.Event) void {
            if (std.mem.eql(u8, evt.key(), "Escape")) {
                evt.preventDefault();
                combobox.close();
            }
        }

        /// A trigger tells screen readers it opens a listbox, and whether it
        /// is open; its text (the choice, or the placeholder) names it.
        fn triggerA11y(combobox: *Self) Vapor.Accessibility {
            return Vapor.Accessibility.init()
                .setHasPopup(.listbox)
                .setExpanded(!combobox._closed);
        }

        /// Several options can be chosen at once.
        fn listA11y(combobox: *Self) Vapor.Accessibility {
            var a11y = Vapor.Accessibility.listbox(combobox.trigger);
            a11y.multiselectable = true;
            return a11y;
        }

        fn createBindedTrigger(_: *Self) *Vapor.Element {
            const binded_trigger: *Vapor.Element = Vapor.arena(.frame).create(Vapor.Element) catch unreachable;
            binded_trigger.* = .{};
            return binded_trigger;
        }

        fn toggleWithBindedTrigger(combobox: *Self, binded_trigger: *Vapor.Element) void {
            // const bounds = binded_trigger.getBoundingClientRect() orelse return;
            // combobox._x = 0;
            // combobox._y = bounds.height + 4;
            // combobox.toggle();

            const offsets = binded_trigger.getOffsets() orelse return;
            combobox._x = offsets.offset_left;
            combobox._y = offsets.offset_top + offsets.offset_height + 4;
            combobox._width = offsets.offset_width;
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

        pub fn renderTriggerCtx(combobox: *Self, ctx: ?*anyopaque) void {
            const binded_trigger = combobox.createBindedTrigger();
            Box()
                .width(.percent(100))
                .height(.percent(100))
                .ref(binded_trigger).children({
                if (combobox.trigger_component) |trigger| {
                    ButtonCtx(toggleWithBindedTriggerCtx, .{ combobox, binded_trigger, ctx })
                        .a11y(combobox.triggerA11y())
                        .background(.transparent)
                        .width(.percent(100))
                        .height(.percent(100))
                        .children({
                        trigger(combobox);
                    });
                } else {
                    ButtonCtx(toggleWithBindedTrigger, .{ combobox, binded_trigger })
                        .a11y(combobox.triggerA11y())
                        .width(.percent(100))
                        .border(if (combobox._closed) border else selected_border)
                        .background(background)
                        .padding(.all(8))
                        .shadow(.glow(2, if (combobox._closed) .transparentize(.black, 0.05) else .transparentize(.palette(.tint), 0.2))
                            // .{
                            //         .color = if (combobox._closed) .trasnparent else .transparentize(.palette(.tint), 0.1),
                            //         .spread = 2,
                            //
                            // }
                        )
                        .children({
                        Box()
                            .width(.percent(100))
                            .layout(.x_between_center)
                            .children({
                            Text(if (combobox._selected_item) |item| item.label else combobox.trigger)
                                .fontFamily(font_family)
                                .font(16, 300, group_title_color)
                                .end();
                            Icon(if (combobox._closed) .chevron_down else .chevron_up)
                                .fontFamily(font_family)
                                .font(14, 300, group_title_color)
                                .end();
                        });
                    });
                }
            });
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

        pub fn renderTrigger(combobox: *Self) void {
            const binded_trigger = combobox.createBindedTrigger();
            Box()
                .width(.percent(100))
                .height(.percent(100))
                .ref(binded_trigger).children({
                if (combobox.trigger_component) |trigger| {
                    ButtonCtx(toggleWithBindedTrigger, .{ combobox, binded_trigger })
                        .a11y(combobox.triggerA11y())
                        .background(.transparent)
                        .width(.percent(100))
                        .height(.percent(100))
                        .children({
                        trigger(combobox);
                    });
                } else {
                    ButtonCtx(toggleWithBindedTrigger, .{ combobox, binded_trigger })
                        .a11y(combobox.triggerA11y())
                        .width(.percent(100))
                        .border(if (combobox._closed) border else selected_border)
                        .background(background)
                        .padding(.all(8))
                        .shadow(Vapor.Types.Shadow.init().dropSpread(if (combobox._closed) 2 else 0, 0, if (combobox._closed) 0 else 2, if (combobox._closed) 0 else 1, if (combobox._closed) .transparentize(.black, 0.05) else .transparentize(.palette(.tint), 0.2)))
                        //             Vapor.Types.NewShadow.init()
                        // pub fn dropSpread(self: Shadow, x: i16, y: i16, blur: u16, spread: i16, color: Color) Shadow {
                        //     return self.add(Layer.init(color).off(x, y).setBlur(blur).setSpread(spread));
                        // }
                        //                     .{
                        //                             .color = if (combobox._closed) .transparentizeHex(.black, 0.05) else .transparentize(.palette(.tint), 0.2),
                        //                             .spread = if (combobox._closed) 0 else 2,
                        //                             .blur = if (combobox._closed) 0 else 2,
                        //                             .top = if (combobox._closed) 2 else 0,
                        //                         })
                        .hover(.{
                            .border = selected_border,
                        })
                        .children({
                        Box()
                            .width(.expand)
                            .layout(.x_between_center)
                            .children({
                            if (combobox._selected_items.count() == 0) {
                                Box()
                                    .width(.expand)
                                    .layout(.left_center)
                                    .children({
                                    Text(combobox.trigger)
                                        .fontFamily(font_family)
                                        .padding(.horizontal(8))
                                        .border(.{
                                            .thickness = .none,
                                            .radius = .all(4),
                                        })
                                        .font(14, 300, group_title_color)
                                        .end();
                                });
                            } else {
                                Box()
                                    .width(.expand)
                                    .spacing(8)
                                    .layout(.left_center)
                                    .scroll(.scrollX())
                                    .children({
                                    var itr = combobox._selected_items.keyIterator();
                                    while (itr.next()) |item| {
                                        Text(item.*.label)
                                            .fontFamily(font_family)
                                            .padding(.horizontal(8))
                                            .border(.{
                                                .thickness = .none,
                                                .radius = .all(4),
                                            })
                                            .background(.transparentize(.vapor_blue, 0.05))
                                            .font(14, 300, text_color)
                                            .end();
                                    }
                                });
                            }
                            Icon(if (combobox._closed) .chevron_down else .chevron_up)
                                .fontFamily(font_family)
                                .font(14, 300, group_title_color)
                                .end();
                        });
                    });
                }
            });
        }

        pub fn renderComboBox(combobox: *Self) void {
            Box()
                .pos(.tl(.px(0), .percent(0), .absolute))
                .inlineStyle("transform: translate({d}px, {d}px); width: {d}px", .{ combobox._x, combobox._y, combobox._width })
                .children({
                if (!combobox._closed) {
                    Stack()
                        .transformOrigin(.top_center)
                        .animationEnter("opaque-combobox-enter")
                        .animationExit("opaque-combobox-exit")
                        .width(.percent(100))
                        .border(border)
                        .background(background)
                        .padding(.all(4))
                        .shadow(Vapor.Types.Shadow.init().dropSpread(4, 0, 2, 1, .transparentize(.black, 0.05)))
                        // .shadow(.{
                        //     .top = 4,
                        //     .spread = 2,
                        //     .blur = 6,
                        //     .color = .transparentizeHex(.black, 0.05),
                        // })
                        .children({
                        Box()
                            .onMount(mountSearchBox, .{combobox})
                            .onDestroy(unmountSearchBox, .{combobox})
                            .width(.percent(100))
                            .padding(.{ .top = 6, .bottom = 14, .left = 6, .right = 6 })
                            .pointer()
                            .layout(.x_between_center)
                            .children({
                            Icon(.search)
                                .font(14, 300, group_title_color)
                                .end();
                            TextField(.string)
                                .ref(&combobox._search_box)
                                .val(&combobox._search_box.text)
                                .placeholder("Search...")
                                .ariaLabel("Search options")
                                .width(.percent(100))
                                .border(.none)
                                .padding(.horizontal(12))
                                .outline(.none, null)
                                .background(.transparent)
                                .fontFamily(font_family)
                                .font(14, 300, group_title_color)
                                .onEvent(.input, search, .{combobox})
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
                        Stack()
                            .a11y(combobox.listA11y())
                            .height(.elastic(36, 256))
                            .width(.percent(100))
                            .scroll(.scrollY())
                            .children({
                            for (combobox.groups.items) |*group| {
                                combobox.renderGroup(group);
                            }
                        });
                    });
                }
            });
        }

        pub fn render(combobox: *Self) void {
            Stack()
                .width(.expand)
                .spacing(4)
                .zIndex(99)
                .pos(.relative)
                .children({
                combobox.renderTrigger();
                renderComboBox(combobox);
            });
            if (!combobox._closed) {
                Box()
                    .id("combobox-background")
                    .background(.transparent)
                    .size(.full)
                    .pos(.full(.fixed))
                    .zIndex(50)
                    .children({
                    ButtonCtx(toggle, .{combobox})
                        .ariaLabel("Close")
                        .tabIndex(-1)
                        .size(.full)
                        .pos(.tl(.px(0), .px(0), .fixed))
                        .end();
                });
            } else {
                Vapor.Null();
            }
        }
    };
}
