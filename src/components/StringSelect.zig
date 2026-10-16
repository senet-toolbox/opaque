const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Box;
const Button = Vapor.Button;
const TextFmt = Vapor.TextFmt;
const TextField = Vapor.TextField;
const Stack = Vapor.Stack;
const Center = Vapor.Center;
const Icon = Vapor.Icon;

var background: Vapor.Types.Color = .palette(.background);
var border: Vapor.Types.Border = .round(.palette(.border_color_light), .all(12));
var group_title_color: Vapor.Types.Color = .hex("#8C8C8C");
var text_color: Vapor.Types.Color = .black;
var font_family: []const u8 = "Montserrat";
const selected_background: Vapor.Types.Color = .transparentize(.palette(.tint), 0.05);
const selected_border: Vapor.Types.Border = .round(.palette(.tint), .all(12));
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

pub const StringSelect = struct {
    const Self = @This();

    pub const Item = struct {
        value: []const u8,
        label: []const u8,
        icon: ?Vapor.IconTokens = null,
        is_selected: bool = false,
        _is_shown: bool = true,
    };

    trigger: []const u8,
    items: []Item,
    _selected_item: ?Item = null,
    _closed: bool = true,
    _searchable: bool = false,
    _search_box: Vapor.Element = .{},
    ctx: ?*anyopaque = null,
    on_select: ?*const fn (select: *Self, item: *Item) void = null,
    on_select_ctx: ?*const fn (item: *Item, ctx: ?*anyopaque) void = null,
    trigger_component: ?*const fn (self: *Self) void = null,
    render_trigger: bool = true,
    _x: f32 = 0,
    _y: f32 = 0,
    binded_select: Vapor.Element = .{},
    binded_trigger: Vapor.Element = .{},
    on_trigger: ?*const fn (select: *Self, ctx: ?*anyopaque) void = null,
    _did_initialize: bool = false,
    max_height: f32 = 256,
    is_detached: bool = false,
    _position: Position = .bottom,
    total_items: usize = 0,
    border: Vapor.Types.Border = .round(.palette(.border_color_light), .all(12)),
    selected_border: Vapor.Types.Border = .round(.palette(.tint), .all(12)),
    // shadow: Vapor.Types.Shadow = .{ .color = .transparentizeHex(.palette(.tint), 0.2), .spread = 3 },
    shadow: ?Vapor.Types.Shadow = .glow(3, .transparentize(tint_color, 0.2)),
    height: Vapor.Types.Sizing = .px(36),
    arena: std.heap.ArenaAllocator,
    arena_allocator: std.mem.Allocator,

    /// Create a StringSelect from a slice of string values.
    /// Each string is used as both the value and the label.
    pub fn init(trigger_label: []const u8, values: []const []const u8) Self {
        var arena = std.heap.ArenaAllocator.init(Vapor.lib.allocator_global);
        const arena_allocator = arena.allocator();

        var alloc_items = Vapor.Array(Item).init(arena_allocator);

        for (values) |val| {
            alloc_items.append(.{
                .value = val,
                .label = val,
            }) catch unreachable;
        }

        const total_items = values.len;
        var max_height: f32 = 256;
        if (total_items > 12) {
            max_height = 512;
        }

        return Self{
            .trigger = trigger_label,
            .items = alloc_items.items,
            ._did_initialize = true,
            .max_height = max_height,
            .total_items = total_items,
            .arena = arena,
            .arena_allocator = arena_allocator,
        };
    }

    /// Create a StringSelect from Items (for when you want custom labels or icons).
    pub fn fromItems(trigger_label: []const u8, items: []const Item) Self {
        var arena = std.heap.ArenaAllocator.init(Vapor.lib.allocator_global);
        const arena_allocator = arena.allocator();

        var alloc_items = Vapor.Array(Item).init(arena_allocator);
        alloc_items.appendSlice(items) catch unreachable;

        const total_items = items.len;
        var max_height: f32 = 256;
        if (total_items > 12) {
            max_height = 512;
        }

        return Self{
            .trigger = trigger_label,
            .items = alloc_items.items,
            ._did_initialize = true,
            .max_height = max_height,
            .total_items = total_items,
            .arena = arena,
            .arena_allocator = arena_allocator,
        };
    }

    pub fn reset(self: *Self, values: []const []const u8) void {
        if (!self.arena.reset(.retain_capacity)) {
            std.log.err("Failed to reset arena", .{});
            return;
        }

        const arena_allocator = self.arena.allocator();
        var alloc_items = std.array_list.Managed(Item).init(arena_allocator);

        for (values) |val| {
            alloc_items.append(.{
                .value = val,
                .label = val,
            }) catch |err| {
                std.log.err("Failed to append item: {any}", .{err});
                return;
            };
        }

        self.items = alloc_items.items;
        self.total_items = values.len;
        self.max_height = if (values.len > 12) 512 else 256;
    }

    pub fn toggle(select: *Self) void {
        select._closed = !select._closed;
    }

    pub fn close(select: *Self) void {
        select._closed = true;
    }

    pub fn default(select: *Self, value: []const u8) void {
        for (select.items) |*item| {
            if (std.mem.eql(u8, item.value, value)) {
                item.is_selected = true;
                select._selected_item = item.*;
            } else {
                item.is_selected = false;
            }
        }
    }

    pub fn selectedValue(select: *Self) ?[]const u8 {
        if (select._selected_item) |item| return item.value;
        return null;
    }

    pub fn selectedItem(select: *Self) ?Item {
        return select._selected_item;
    }

    fn selectItem(select: *Self, selected_item: *Item) void {
        for (select.items) |*item| {
            if (item == selected_item) continue;
            item.is_selected = false;
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
            .background(background)
            .pointer()
            .layout(.left_center)
            .duration(100)
            .hoverBackground(selected_background)
            .padding(.{ .top = 6, .bottom = 6, .left = 6, .right = 24 })
            .border(.round(.transparent, if (select.border.radius) |radius| radius else .all(8)))
            .spacing(8)
            .children({
            if (item.icon) |icon| {
                Icon(icon)
                    .font(14, 300, text_color)
                    .end();
            }
            Text(item.label)
                // .fontFamily(font_family)
                .font(14, 300, text_color)
                .end();
        });
    }

    fn search(select: *Self, evt: *Vapor.Event) void {
        const text = evt.text();
        select._search_box.text = text;
        for (select.items) |*item| {
            item._is_shown = std.ascii.startsWithIgnoreCase(item.label, text);
        }
    }

    fn clearText(select: *Self) void {
        select._search_box.text = "";
        for (select.items) |*item| {
            item._is_shown = true;
        }
    }

    fn createBindedTrigger(_: *Self) *Vapor.Element {
        const binded_trigger: *Vapor.Element = Vapor.arena(.frame).create(Vapor.Element) catch unreachable;
        binded_trigger.* = .{};
        return binded_trigger;
    }

    fn toggleWithBindedTrigger(select: *Self, binded_trigger: *Vapor.Element) void {
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

    fn toggleWithBindedTriggerVP(select: *Self, binded_trigger: *Vapor.Element) void {
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

    fn toggleWithBindedTriggerVPCtx(select: *Self, binded_trigger: *Vapor.Element, callback: anytype, args: anytype) void {
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
        Box()
            .width(.percent(100))
            .height(.percent(100))
            .ref(binded_trigger).children({
            if (select.trigger_component) |trigger_comp| {
                Button(toggleWithBindedTriggerVPCtx, .{ select, binded_trigger, callback, args })
                    .ariaLabel("Select Dropdown")
                    .background(.transparent)
                    .width(.percent(100))
                    .height(.percent(100))
                    .children({
                    trigger_comp(select);
                });
            } else {
                Button(toggleWithBindedTrigger, .{ select, binded_trigger })
                    .ariaLabel("Select Dropdown")
                    .width(.percent(100))
                    .border(if (select._closed) border else selected_border)
                    .background(background)
                    .padding(.all(8))
                    // .shadow(.{
                    //     .color = if (select._closed) .transparent else .transparentizeHex(.palette(.tint), 0.2),
                    //     .spread = 3,
                    // })
                    .shadow(.glow(3, .transparentize(.palette(.tint), 0.2)))
                    .children({
                    Box()
                        .width(.percent(100))
                        .layout(.x_between_center)
                        .children({
                        Text(if (select._selected_item) |item| item.label else select.trigger)
                            // .fontFamily(font_family)
                            .font(16, 300, group_title_color)
                            .end();
                        Icon(if (select._closed) .chevron_down else .chevron_up)
                            // .fontFamily(font_family)
                            .font(14, 300, group_title_color)
                            .end();
                    });
                });
            }
        });
    }

    pub fn renderTrigger(select: *Self) void {
        const binded_trigger = select.createBindedTrigger();
        Box()
            .width(.percent(100))
            .height(.percent(100))
            .ref(binded_trigger).children({
            if (select.trigger_component) |trigger_comp| {
                Button(toggleWithBindedTriggerVP, .{ select, binded_trigger })
                    .ariaLabel("Select Dropdown")
                    .background(.transparent)
                    .width(.percent(100))
                    .height(.percent(100))
                    .children({
                    trigger_comp(select);
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
                    Box()
                        .width(.percent(100))
                        .layout(.x_between_center)
                        .children({
                        Text(if (select._selected_item) |item| item.label else select.trigger)
                            // .fontFamily(font_family)
                            .padding(.horizontal(8))
                            .border(.{
                                .thickness = .none,
                                .radius = .all(4),
                            })
                            .font(14, 300, group_title_color)
                            .end();
                        Icon(if (select._closed) .chevron_down else .chevron_up)
                            // .fontFamily(font_family)
                            .font(14, 300, group_title_color)
                            .end();
                    });
                });
            }
        });
    }

    pub fn renderSelect(select: *Self) void {
        Box()
            .pos(.tl(.px(0), .percent(0), .absolute))
            .width(.percent(100))
            .zIndex(1000)
            .transform(.translate(select._x, select._y, .px))
            .children({
            if (!select._closed) {
                Stack()
                    .transformOrigin(.top_center)
                    .animationEnter("opaque-select-enter")
                    .animationExit("opaque-select-exit")
                    .width(.percent(100))
                    .border(select.border)
                    .background(background)
                    .padding(.all(4))
                    // .shadow(.{
                    //     .top = 4,
                    //     .spread = 2,
                    //     .blur = 6,
                    //     .color = .transparentizeHex(.black, 0.05),
                    // })
                    .shadow(Vapor.Types.Shadow.init().dropSpread(0, 4, 2, 1, .transparentize(.black, 0.05)))
                    .children({
                    Stack()
                        .height(.elastic(select.height.size.min, select.max_height))
                        .width(.percent(100))
                        .scroll(.scrollY())
                        .children({
                        for (select.items) |*item| {
                            select.renderItem(item);
                        }
                    });
                });
            } else {
                Vapor.Null();
            }
        });
        if (!select._closed) {
            Box()
                .id("select-background")
                .background(.transparent)
                .size(.full)
                .pos(.full(.fixed))
                .zIndex(999)
                .children({
                Button(toggle, .{select})
                    .ariaLabel("Close Select Dropdown")
                    .size(.full)
                    .pos(.tl(.px(0), .px(0), .fixed))
                    .end();
            });
        } else {
            Vapor.Null();
        }
    }

    pub fn renderPos(select: *Self, position: Position) void {
        select._position = position;
        if (!select._did_initialize) {
            Vapor.print(.err, "Error: StringSelect component not initialized\n Call StringSelect.init(...) or StringSelect.fromItems(...) before rendering", .{});
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
            Vapor.print(.err, "Error: StringSelect component not initialized\n Call StringSelect.init(...) or StringSelect.fromItems(...) before rendering", .{});
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
};
