const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Row = Vapor.Row;
const Button = Vapor.Button;
const TextFmt = Vapor.TextFmt;
const TextField = Vapor.TextField;
const Stack = Vapor.Stack;
const Center = Vapor.Center;
const Icon = Vapor.Icon;
const HooksCtx = Vapor.HooksCtx;

pub var background: Vapor.Types.Color = .palette(.background);
var border: Vapor.Types.BorderGrouped = .round(.transparentize(.black, 0.2), .all(12));
var group_title_color: Vapor.Types.Color = .hex("#8C8C8C");
pub var text_color: Vapor.Types.Color = .palette(.text);
const selected_background: Vapor.Types.Color = .transparentizeHex(.palette(.tint), 0.05);
const selected_border: Vapor.Types.BorderGrouped = .round(.palette(.tint), .all(12));
const tint_color: Vapor.Types.Color = .palette(.tint);

const Position = enum { top, bottom };

pub const animateEnter = Vapor.Animation.init("opaque-select-enter")
    .prop(.opacity, 0, 1)
    .prop(.scale, 0.9, 1)
    .duration(100)
    .easing(.easeInOut);

pub const animateExit = Vapor.Animation.init("opaque-select-exit")
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
            items: []const Item,
        };

        const ClonedGroup = struct {
            title: ?[]const u8 = null,
            items: []Item,
        };

        pub const Item = struct {
            value: T,
            label: []const u8,
            icon: ?Vapor.IconType = null,
            is_selected: bool = false,
            _is_shown: bool = true,
        };

        trigger: []const u8,
        groups: Vapor.Array(ClonedGroup),
        _selected_item: ?Item = null,
        _selected_index: usize = 0,
        _closed: bool = true,
        _searchable: bool = false,
        _search_box: Vapor.Binded = .{},
        ctx: ?*anyopaque = null,
        on_select: ?*const fn (select: *Self, item: *Item) void = null,
        on_select_ctx: ?*const fn (item: *Item, ctx: ?*anyopaque) void = null,
        trigger_component: ?*const fn (self: *Self) void = null,
        render_trigger: bool = true,
        _x: f32 = 0,
        _y: f32 = 0,
        binded: Vapor.Binded = .{},
        binded_trigger: Vapor.Binded = .{},
        on_trigger: ?*const fn (select: *Self, ctx: ?*anyopaque) void = null,
        _did_initialize: bool = false,
        max_height: f32 = 256,
        is_detached: bool = false,
        _position: Position = .bottom,
        total_items: usize = 0,
        tint_color: Vapor.Types.Color = tint_color,
        border: Vapor.Types.BorderGrouped = .round(.transparentize(.black, 0.2), .all(12)),
        selected_border: Vapor.Types.BorderGrouped = .round(tint_color, .all(12)),
        // shadow: Vapor.Types.Shadow = .{ .color = .transparentizeHex(tint_color, 0.2), .spread = 3 },
        shadow: ?Vapor.Types.Shadow = .glow(3, .transparentizeHex(tint_color, 0.2)),
        height: Vapor.Types.Sizing = .px(36),
        arena: std.heap.ArenaAllocator,
        arena_allocator: std.mem.Allocator,

        pub fn init(trigger: []const u8, groups: []const Group) Self {
            var arena = std.heap.ArenaAllocator.init(Vapor.lib.allocator_global);
            const arena_allocator = arena.allocator();

            var alloc_groups = Vapor.array(ClonedGroup, .persist);

            var total_items: usize = 0;
            for (groups) |group| {
                var cloned_group: ClonedGroup = .{ .title = group.title, .items = &.{} };
                var alloc_items = Vapor.array(Item, .persist);
                for (group.items) |item| {
                    alloc_items.append(item) catch unreachable;
                    total_items += 1;
                }
                cloned_group.items = alloc_items.items;
                alloc_groups.append(cloned_group) catch unreachable;
            }

            var max_height: f32 = 256;
            if (total_items > 12) {
                max_height = 512;
            }

            return Self{
                .trigger = trigger,
                .groups = alloc_groups,
                ._did_initialize = true,
                .max_height = max_height,
                .total_items = total_items,
                .arena_allocator = arena_allocator,
                .arena = arena,
            };
        }

        pub fn fromItems(items: []const Item) Self {
            var arena = std.heap.ArenaAllocator.init(Vapor.lib.allocator_global);
            const arena_allocator = arena.allocator();

            var alloc_groups = Vapor.Array(ClonedGroup).init(arena_allocator);
            var alloc_items = Vapor.Array(Item).init(arena_allocator);

            alloc_items.appendSlice(items) catch unreachable;

            var total_items: usize = 0;
            total_items += items.len;

            var max_height: f32 = 256;
            if (total_items > 12) {
                max_height = 512;
            }

            alloc_groups.append(.{
                .items = alloc_items.items,
            }) catch unreachable;

            return Self{
                .trigger = "Select",
                .groups = alloc_groups,
                ._did_initialize = true,
                .max_height = max_height,
                .total_items = total_items,
                .arena = arena,
                .arena_allocator = arena_allocator,
            };
        }

        pub fn resetColumns(self: *Self, items: []const Item) void {
            if (!self.arena.reset(.retain_capacity)) {
                std.log.err("Failed to reset arena", .{});
                return;
            }

            const arena_allocator = self.arena.allocator();

            var alloc_groups = std.array_list.Managed(ClonedGroup).init(arena_allocator);
            var alloc_items = std.array_list.Managed(Item).init(arena_allocator);
            alloc_items.appendSlice(items) catch |err| {
                std.log.err("Failed to append items: {any}", .{err});
                return;
            };

            var total_items: usize = 0;
            total_items += items.len;

            var max_height: f32 = 256;
            if (total_items > 12) {
                max_height = 512;
            }

            alloc_groups.append(.{
                .items = alloc_items.items,
            }) catch unreachable;

            self.groups = alloc_groups;
            self.max_height = max_height;
            self.total_items = total_items;
        }

        pub fn toggle(select: *Self) void {
            select._closed = !select._closed;
        }

        pub fn close(select: *Self) void {
            select._closed = true;
        }

        pub fn default(select: *Self, selected_item: Item) void {
            for (select.groups.items) |*group| {
                inner: for (group.items, 0..) |*item, i| {
                    if (std.mem.eql(u8, item.label, selected_item.label)) {
                        item.is_selected = true;
                        select._selected_index = i;
                        continue :inner;
                    }
                    item.is_selected = false;
                }
            }
            select._selected_item = selected_item;
        }

        fn selectItem(select: *Self, selected_item: *Item) void {
            for (select.groups.items) |*group| {
                inner: for (group.items, 0..) |*item, i| {
                    if (item == selected_item) {
                        select._selected_index = i;
                        continue :inner;
                    }
                    item.is_selected = false;
                }
            }
            selected_item.is_selected = !selected_item.is_selected;
            if (!selected_item.is_selected) {
                select._selected_item = null;
            } else {
                select._selected_item = selected_item.*;
            }

            if (select.on_select) |on_select| {
                on_select(select, selected_item);
            }
            if (select.on_select_ctx) |on_select_ctx| {
                on_select_ctx(selected_item, select.ctx);
            }

            select.close();
        }

        fn renderItem(select: *Self, item: *Item) void {
            if (!item._is_shown) return;
            Button(selectItem, .{ select, item })
                .ariaLabel("Select Dropdown")
                .width(.percent(100))
                .height(select.height)
                .background(if (item.is_selected) .transparentizeHex(select.tint_color, 0.05) else background)
                .pointer()
                .layout(.left_center)
                .duration(100)
                .hoverBackground(.transparentizeHex(select.tint_color, 0.1))
                .padding(.tblr(6, 6, 6, 24))
                .border(.round(.transparent, if (select.border.radius) |radius| radius else .all(8)))
                .spacing(8)
                .children({
                if (item.icon) |icon| {
                    Icon(icon)
                        .font(14, 300, text_color)
                        .end();
                }
                Text(item.label)
                    .font(14, 300, text_color)
                    .end();
            });
        }

        fn renderGroup(select: *Self, group: *ClonedGroup) void {
            Stack()
                .width(.percent(100))
                .children({
                if (group.title) |title| {
                    Text(title)
                        .padding(.all(6))
                        .font(12, 300, group_title_color)
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

        pub fn selectedItem(select: *Self) ?Item {
            return select._selected_item;
        }

        pub fn selectedValue(select: *Self) ?T {
            const item = select._selected_item orelse return null;
            return item.value;
        }

        fn mountSearchRow(select: *Self) void {
            select._search_box.focus();
        }

        fn createBindedTrigger(_: *Self) *Vapor.Binded {
            const binded_trigger: *Vapor.Binded = Vapor.arena(.frame).create(Vapor.Binded) catch unreachable;
            binded_trigger.* = .{};
            return binded_trigger;
        }

        fn toggleWithBindedTrigger(select: *Self, binded_trigger: *Vapor.Binded) void {
            if (select.is_detached) {
                select.toggle();
                return;
            }
            const offsets = binded_trigger.getOffsets() orelse return;
            if (select._position == .top) {
                select._x = offsets.offset_left;
                select._y = offsets.offset_top - @as(f32, @floatFromInt(select.total_items)) * select.height.size.min;
            } else {
                select._x = offsets.offset_left;
                select._y = offsets.offset_top + offsets.offset_height + 4;
            }

            select.toggle();
        }

        fn toggleWithBindedTriggerVP(select: *Self, binded_trigger: *Vapor.Binded) void {
            if (select.is_detached) {
                select.toggle();
                return;
            }

            const offsets = binded_trigger.getBoundingClientRect() orelse return;
            const binded = select.binded.getBoundingClientRect() orelse return;
            const width = binded.width - offsets.width;
            if (select._position == .top) {
                select._x = offsets.left - width;
                select._y = offsets.top - @as(f32, @floatFromInt(select.total_items)) * select.height.size.min;
            } else {
                select._x = offsets.left - width;
                select._y = offsets.top + offsets.height + 4;
            }

            select.toggle();
            // Vapor.onLayout(updateBounds, .{ select, binded_trigger });
        }

        fn updateBounds(select: *Self, binded_trigger: *Vapor.Binded) void {
            const offsets = binded_trigger.getBoundingClientRect() orelse return;
            const binded = select.binded.getBoundingClientRect() orelse return;
            const width = binded.width;
            if (select._position == .top) {
                select._x = offsets.left - width;
                select._y = offsets.top - @as(f32, @floatFromInt(select.total_items)) * select.height.size.min;
            } else {
                select._x = offsets.left - width;
                select._y = offsets.top + offsets.height + 4;
            }
            Vapor.cycle();
        }

        fn toggleWithBindedTriggerVPCtx(select: *Self, binded_trigger: *Vapor.Binded, callback: anytype, args: anytype) void {
            if (select.is_detached) {
                select.toggle();
                return;
            }
            const offsets = binded_trigger.getOffsets() orelse return;
            select._x = offsets.offset_left;
            select._y = offsets.offset_top + offsets.offset_height + 4;
            select.toggle();
            @call(.auto, callback, args);
        }

        pub fn renderTriggerCtx(select: *Self, callback: anytype, args: anytype) void {
            const binded_trigger = select.createBindedTrigger();
            Row()
                .width(.percent(100))
                .height(.percent(100))
                .ref(binded_trigger).children({
                if (select.trigger_component) |trigger| {
                    Button(toggleWithBindedTriggerVPCtx, .{ select, binded_trigger, callback, args })
                        .ariaLabel("Select Dropdown")
                        .background(.transparent)
                        .width(.percent(100))
                        .height(.percent(100))
                        .children({
                        trigger(select);
                    });
                } else {
                    Button(toggleWithBindedTrigger, .{ select, binded_trigger })
                        .ariaLabel("Select Dropdown")
                        .width(.percent(100))
                        .border(if (select._closed) border else selected_border)
                        .background(background)
                        .padding(.all(8))
                        .shadow(.{
                            .color = if (select._closed) .transparent else .transparentizeHex(select.tint_color, 0.2),
                            .spread = 3,
                        })
                        .children({
                        Row()
                            .width(.percent(100))
                            .layout(.x_between_center)
                            .children({
                            Text(if (select._selected_item) |item| item.label else select.trigger)
                                .font(16, 300, group_title_color)
                                .end();
                            Icon(if (select._closed) .chevron_down else .chevron_up)
                                .font(14, 300, group_title_color)
                                .end();
                        });
                    });
                }
            });
        }

        pub fn renderTrigger(select: *Self) void {
            const binded_trigger = select.createBindedTrigger();
            Row()
                .width(.percent(100))
                .height(.percent(100))
                .ref(binded_trigger).children({
                if (select.trigger_component) |trigger| {
                    ////////////////////////////////////////////////////////////////////////////////////
                    // THIS IS THE NEW WAY i switch toggleWithBindedTriggerVP to toggleWithBindedTrigger
                    ////////////////////////////////////////////////////////////////////////////////////
                    Button(toggleWithBindedTriggerVP, .{ select, binded_trigger })
                        .ariaLabel("Select Dropdown")
                        .background(.transparent)
                        .width(.percent(100))
                        .height(.percent(100))
                        .children({
                        trigger(select);
                    });
                } else {
                    Button(toggleWithBindedTrigger, .{ select, binded_trigger })
                        .ariaLabel("Select Dropdown")
                        .width(.percent(100))
                        .height(select.height)
                        .border(if (select._closed) select.border else select.selected_border)
                        .background(background)
                        .padding(.xy(8, 0))
                        .shadow(if (!select._closed) select.shadow else .glow(3, .transparent))
                        .hover(.{
                            .border = select.selected_border,
                        })
                        .children({
                        Row()
                            .width(.percent(100))
                            .layout(.x_between_center)
                            .children({
                            Text(if (select._selected_item) |item| item.label else select.trigger)
                                .padding(.horizontal(8))
                                .border(.{
                                    .thickness = .none,
                                    .radius = .all(4),
                                })
                                .font(14, 300, group_title_color)
                                .end();
                            Icon(if (select._closed) .chevron_down else .chevron_up)
                                .font(14, 300, group_title_color)
                                .end();
                        });
                    });
                }
            });
        }

        pub fn renderSelect(select: *Self) void {
            Row()
                .pos(.tl(.px(0), .percent(0), .absolute))
                .width(.percent(100))
                .zIndex(100)
                .transform(.translate(select._x, select._y, .px))
                .ref(&select.binded)
                .children({
                if (!select._closed) {
                    Stack()
                        .onMount(mount, .{select})
                        .transformOrigin(.top_center)
                        .animationEnter("opaque-select-enter")
                        .animationExit("opaque-select-exit")
                        .width(.percent(100))
                        .border(select.border)
                        .background(background)
                        .padding(.all(4))
                        .shadow(.insetGlow(0, 4, 2, .transparentizeHex(.black, 0.05)))
                        .children({
                        Stack()
                            .height(.elastic(select.height.size.min, select.max_height))
                            .width(.percent(100))
                            .scroll(.scroll_y())
                            .children({
                            for (select.groups.items) |*group| {
                                select.renderGroup(group);
                            }
                        });
                    });
                } else {
                    // Vapor.Null();
                }
            });
            if (!select._closed) {
                Row()
                    .id("select-background")
                    .background(.transparent)
                    .size(.full)
                    .pos(.full(.fixed))
                    .zIndex(99)
                    .children({
                    Button(toggle, .{select})
                        .ariaLabel("Close Select Dropdown")
                        .size(.full)
                        .pos(.tl(.px(0), .px(0), .fixed))
                        .end();
                });
            } else {
                // Vapor.Null();
            }
        }

        fn mount(select: *Self) void {
            const height: f32 = select.height.size.min * @as(f32, @floatFromInt(select._selected_index));
            select.binded.scrollToTop(height);
        }

        fn create(select: *Self) void {
            _ = select;
            std.log.info("create", .{});
        }

        fn destroy(select: *Self) void {
            _ = select;
            std.log.info("destroy", .{});
        }

        pub fn renderPos(select: *Self, position: Position) void {
            select._position = position;
            if (!select._did_initialize) {
                Vapor.printErr("Error: Select component not initialized\n Call Select.init(...) or Select.fromItems(...) before rendering", .{});
                return;
            }
            Stack()
                .width(.percent(100))
                .spacing(4)
                .pos(.relative)
                .children({
                select.renderTrigger();
                select.renderSelect();
            });
        }

        pub fn render(select: *Self) void {
            if (!select._did_initialize) {
                Vapor.printErr("Error: Select component not initialized\n Call Select.init(...) or Select.fromItems(...) before rendering", .{});
                return;
            }
            Stack()
                .width(.expand)
                .spacing(4)
                .height(select.height)
                .pos(.relative)
                .children({
                select.renderTrigger();
                select.renderSelect();
            });
        }
        pub fn renderSelectByComponent(select: *Self, component: *const fn (select: *Self) void) void {
            Row()
                .pos(.tl(.px(0), .percent(0), .absolute))
                .zIndex(100)
                .transform(.translate(select._x, select._y, .px))
                .children({
                if (!select._closed) {
                    Stack()
                        .transformOrigin(.top_center)
                        .animationEnter("opaque-select-enter")
                        .animationExit("opaque-select-exit")
                        .border(select.border)
                        .background(background)
                        .padding(.all(4))
                        .shadow(.insetGlow(0, 4, 2, .transparentizeHex(.black, 0.05)))
                        // .{
                        //         .top = 4,
                        //         .spread = 2,
                        //         .blur = 6,
                        //         .color = .transparentizeHex(.black, 0.05),
                        //     })
                        .children({
                        Stack()
                            .height(.elastic(36, select.max_height))
                            .width(.percent(100))
                            .scroll(.scroll_y())
                            .children({
                            component(select);
                        });
                    });
                } else {
                    // Vapor.Null();
                }
            });
            if (!select._closed) {
                Row()
                    .id("select-background")
                    .background(.transparent)
                    .size(.full)
                    .pos(.full(.fixed))
                    .zIndex(99)
                    .children({
                    Button(toggle, .{select})
                        .ariaLabel("Close Select Dropdown")
                        .size(.full)
                        .pos(.tl(.px(0), .px(0), .fixed))
                        .end();
                });
            } else {
                // Vapor.Null();
            }
        }
    };
}
