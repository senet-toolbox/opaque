const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Box;
const ButtonCtx = Vapor.CtxButton;
const Stack = Vapor.Stack;
const Components = @import("Components.zig");
const TableContainer = Components.Table;
const Select = @import("../Select.zig").Select;
const Icon = Vapor.Icon;
const TextField = Vapor.TextField;
const TextFmt = Vapor.TextFmt;
const File = Vapor.FileReader;
const VirtualList = @import("Virtualize.zig").VirtualList;
const OverlayManager = @import("../OverlayManager.zig");
const Number = Vapor.Number;

pub const animateEnter = Vapor.Animation.init("opaque-table-filter-enter")
    .prop(.opacity, 0, 1)
    .prop(.scale, 0.9, 1)
    .duration(100)
    .easing(.easeInOut);

pub const animateExit = Vapor.Animation.init("opaque-table-filter-exit")
    .prop(.opacity, 1, 0)
    .prop(.scaleY, 1, 0.9)
    .duration(100)
    .easing(.easeInOut);

pub fn new() void {
    animateEnter.build();
    animateExit.build();
}

pub const DisplayMode = enum {
    paginated,
    virtual, // Virtualized scrolling
    all, // Show everything (small datasets)
};

pub const Sort = enum {
    none,
    asc,
    desc,
};

pub const Align = enum {
    none,
    left,
    center,
    right,
};

var border_color: Vapor.Types.Color = .palette(.border_color_light);
var icon_color: Vapor.Types.Color = .palette(.icon_color);
var tint: Vapor.Types.Color = .transparentizeHex(.palette(.tint), 0.8);
var checkbox_color_icon: Vapor.Types.Color = .palette(.background);
var checkbox_color: Vapor.Types.Color = .palette(.text_color);
pub var background: Vapor.Types.Color = .palette(.background);

const SelectType = Select(usize);

fn TableContext(comptime Id: type) type {
    return struct {
        pub fn hash(self: @This(), key: Id) u64 {
            _ = self;
            // Use String hashing if Id is a slice, otherwise use AutoHash
            if (comptime (@typeInfo(Id) == .pointer and @typeInfo(Id).pointer.size == .slice)) {
                return std.hash.Wyhash.hash(0, key);
            }
            var hasher = std.hash.Wyhash.init(0);
            std.hash.autoHash(&hasher, key);
            return hasher.final();
        }

        pub fn eql(self: @This(), a: Id, b: Id) bool {
            _ = self;
            if (comptime (@typeInfo(Id) == .pointer and @typeInfo(Id).pointer.size == .slice)) {
                return std.mem.eql(u8, a, b);
            }
            return a == b;
        }
    };
}

pub fn Row(comptime T: type) type {
    return struct {
        value: T,
        is_selected: bool = false,
        is_shown: bool = true,
    };
}

pub fn Column(comptime T: type) type {
    return struct {
        title: []const u8,
        key: []const u8,
        width: ?f32 = null,
        alignment: ?Align = .none,
        sort: ?Sort = null,
        render: ?*const fn (*T) void = null,
        search: bool = false,
        filter: bool = false,
    };
}

pub fn Action(comptime T: type) type {
    return struct {
        label: []const u8,
        icon: ?*const Vapor.IconTokens = null,
        on_action: ?*const fn (item: *T) void = null,
    };
}

pub fn Table(comptime T: type, comptime columns: []const Column(T), config: struct { actions: ?[]const Action(T) = null }) type {
    comptime {
        if (!@hasField(T, "id")) {
            @compileError("Table requires a field named 'id'");
        }
    }

    const IdType = comptime blk: {
        const fields = @typeInfo(T).@"struct".fields;
        for (fields) |field| {
            if (std.mem.eql(u8, field.name, "id")) {
                break :blk field.type;
            }
        }
        unreachable;
    };

    const SelectionMode = enum { none, some, all, all_except };

    return struct {
        const Self = @This();
        data: []T,
        rows: []Row(T) = undefined,
        filtered_data: Vapor.Array(T),
        per_page: usize = 10,
        // selected_rows: std.AutoHashMap(IdType, void),
        // selected_rows: std.DynamicBitSet,
        // Replace selected_rows with:
        selection_mode: SelectionMode = .none,
        // selection_set: std.AutoHashMap(IdType, void), // meaning depends on mode
        selection_set: std.HashMap(IdType, void, TableContext(IdType), std.hash_map.default_max_load_percentage),
        file_name: []const u8 = "content",
        display_mode: DisplayMode = .paginated,
        scroll_offset: usize = 0,
        visible_row_count: usize = 20, // For virtual mode
        show_id_column: bool = false,
        on_select: ?*const fn (item: *T) void = null,
        on_select_all: ?*const fn () void = null,
        action_select: SelectType = undefined,

        // Add to your Table struct
        focused_row: ?usize = null,
        focused_col: ?usize = null,
        table_id: []const u8 = "data-table",
        total_width_percent: f32 = 100,
        row_background: ?Vapor.Types.Color = null,
        row_border: ?Vapor.Types.BorderGrouped = null,
        row_spacing: ?u8 = null,

        const table_columns: []const Column(T) = columns;
        var action_width: f32 = 5;
        var row_height: f32 = 48;
        var row_width: f32 = 90;
        var checkbox_width: f32 = 5;
        var show_actions: bool = if (config.actions != null) true else false;

        var actions: []const Action(T) = config.actions orelse &.{};

        var action_top_pos: f16 = 0;
        var action_right_pos: f16 = 0;
        var binded_action: Vapor.Binded = .{};
        var search_box: Vapor.Binded = .{};
        var binded_cols: []Vapor.Binded = &.{};
        var show_search: bool = false;
        var clicked_index: usize = 0;
        var search_top: f32 = 0;
        var search_right: f32 = 0;
        var filter_top: f32 = 0;
        var filter_right: f32 = 0;
        var show_filter: bool = false;
        var current_page: usize = 0;
        var current_search_text: []const u8 = "";
        var active_filters: [columns.len]?[]const u8 = [_]?[]const u8{null} ** columns.len;
        var enum_filters: std.StringHashMap(void) = undefined;
        var downloading: bool = false;
        var virtual_list: VirtualList(T) = undefined;
        var row_index: usize = 0;

        const TriggerCtx = struct {
            index: usize,
            table: *Self,
        };

        // Add keyboard handler registration in init or render
        fn registerKeyboardNav(table: *Self) void {
            OverlayManager.register(.keydown, handleTableKeyPress, .{table});
        }

        fn unregisterKeyboardNav(table: *Self) void {
            OverlayManager.unregister(.keydown, table);
        }

        fn handleTableKeyPress(table: *Self, evt: *Vapor.Event) void {
            const key = evt.key();

            const row_count = table.filtered_data.items.len;
            const col_count = table_columns.len + 2; // +1 for checkbox, +1 for actions

            if (row_count == 0) return;

            // Initialize focus if not set
            if (table.focused_row == null) {
                table.focused_row = 0;
                table.focused_col = 0;
            }

            const row = table.focused_row.?;
            const col = table.focused_col.?;

            if (std.mem.eql(u8, key, "ArrowDown")) {
                evt.preventDefault();
                std.log.info("Key pressed: {s}", .{key});
                if (row + 1 < row_count) {
                    table.focused_row = row + 1;
                }
            } else if (std.mem.eql(u8, key, "ArrowUp")) {
                evt.preventDefault();
                if (row > 0) {
                    table.focused_row = row - 1;
                }
            } else if (std.mem.eql(u8, key, "ArrowRight")) {
                evt.preventDefault();
                if (col + 1 < col_count) {
                    table.focused_col = col + 1;
                }
            } else if (std.mem.eql(u8, key, "ArrowLeft")) {
                evt.preventDefault();
                if (col > 0) {
                    table.focused_col = col - 1;
                }
            } else if (std.mem.eql(u8, key, "Home")) {
                evt.preventDefault();
                if (evt.ctrlKey()) {
                    table.focused_row = 0; // Go to first row
                }
                table.focused_col = 0; // Go to first column
            } else if (std.mem.eql(u8, key, "End")) {
                evt.preventDefault();
                if (evt.ctrlKey()) {
                    table.focused_row = row_count - 1;
                }
                table.focused_col = col_count - 1;
            } else if (std.mem.eql(u8, key, "Space") or std.mem.eql(u8, key, "Enter")) {
                evt.preventDefault();
                // If on checkbox column (col 0), toggle selection
                if (col == 0) {
                    const data_row = &table.filtered_data.items[row];
                    table.selectRow(data_row);
                }
            } else if (std.mem.eql(u8, key, "PageDown")) {
                evt.preventDefault();
                const jump = table.per_page;
                table.focused_row = @min(row + jump, row_count - 1);
            } else if (std.mem.eql(u8, key, "PageUp")) {
                evt.preventDefault();
                const jump = table.per_page;
                table.focused_row = if (row >= jump) row - jump else 0;
            }
        }

        pub fn init(table: *Self, data: []T) void {
            var rows: []Row(T) = undefined;
            rows = Vapor.arena(.persist).alloc(Row(T), data.len) catch |err| blk: {
                Vapor.printErr("Failed to allocate rows: {any}", .{err});
                break :blk &.{};
            };
            for (rows, 0..) |*row, i| {
                row.* = Row(T){ .value = data[i] };
            }

            binded_cols = Vapor.arena(.persist).alloc(Vapor.Binded, table_columns.len) catch |err| blk: {
                Vapor.printErr("Failed to allocate binded cols: {any}", .{err});
                break :blk &.{};
            };
            var total_percent_width: f32 = 100;
            for (0..table_columns.len) |i| {
                binded_cols[i] = .{};
                if (table_columns[i].width) |w| {
                    total_percent_width -= w;
                }
            }

            enum_filters = std.StringHashMap(void).init(Vapor.arena(.persist));

            table.* = Self{
                .data = data,
                .rows = rows,
                .filtered_data = Vapor.array(T, .persist),
                .total_width_percent = total_percent_width,
                // .selected_rows = std.AutoHashMap(IdType, void).init(Vapor.arena(.persist)),
                // .selected_rows = try std.DynamicBitSet.initEmpty(Vapor.arena(.persist), data.len),
                // .selection_set = std.AutoHashMap(IdType, void).init(Vapor.arena(.persist)),
                .selection_set = std.HashMap(IdType, void, TableContext(IdType), 80).init(Vapor.arena(.persist)),
            };

            search_box.init(Vapor.arena(.persist));

            if (config.actions) |c_actions| {
                actions = c_actions;
                var items = Vapor.arena(.persist).alloc(Select(usize).Item, actions.len) catch unreachable;
                for (actions, 0..) |action, i| {
                    items[i] = .{ .value = i, .label = action.label, .icon = action.icon };
                }
                table.action_select = .fromItems(items);
                table.action_select.render_trigger = false;
                table.action_select.trigger_component = ActionTrigger;
                table.action_select.on_select = selectAction;
            }

            table.filtered_data.appendSlice(data[0..]) catch unreachable;
            virtual_list = VirtualList(T).init(.{
                .data = table.data,
                .render_ctx = VirtualRow,
                .item_height = .px(row_height),
                .item_width = .percent(row_width),
                .buffer_size = 5,
            });
        }

        pub fn refresh(table: *Self) void {
            table.filtered_data.clearRetainingCapacity(); // Clear the old data
            table.filtered_data.appendSlice(table.data[0..]) catch unreachable; // Append the new data
            table.applyFilters(); // Apply the filters
        }

        fn selectAction(select: *Select(usize), item: *Select(usize).Item) void {
            const table: *Self = @alignCast(@fieldParentPtr("action_select", select));
            const row = &table.data[row_index + current_page * table.per_page];
            if (actions[item.value].on_action) |on_action| {
                on_action(row);
            }
        }

        fn VirtualRow(row: T, i: usize, ctx: ?*anyopaque) void {
            if (ctx == null) return;
            const table: *Self = @ptrCast(@alignCast(ctx));
            const last_row = virtual_list.data.len - 1 == i;
            Box()
                .width(.percent(100))
                .height(.px(row_height))
                .padding(.horizontal(8))
                .border(.bottom(1, if (!last_row) border_color else .transparent))
                .layout(.x_between_center).children({
                Box()
                    .width(.percent(checkbox_width))
                    .children({
                    // Box()
                    CheckBox(selectRow, .{ table, &table.data[i] })
                        .background(if (table.includes(row.id)) tint else .transparent)
                        .border(.round(if (table.includes(row.id)) .transparent else border_color, .all(4)))
                        .hoverScale()
                        .layout(.center)
                        .children({
                        Icon(.check)
                            .font(16, 300, checkbox_color_icon)
                            .end();
                    });
                });
                Box()
                    .width(.percent(row_width))
                    .layout(.x_between_center).children({
                    inline for (table_columns, 0..) |column, col_i| {
                        const cell_col = col_i + 1; // +1 because checkbox is col 0
                        const name = column.key;
                        const value = @field(row, name);
                        // _ = cell_col;
                        Box()
                            .a11y(Vapor.Accessibility.init()
                                .setRole(.grid_cell)
                                .setColIndex(@intCast(cell_col)))
                            // .id(id) // vice versa for this aswell apparently have both uncommented causes issue
                            // .tabIndex(if (is_focused_row and table.focused_col == col_i + 1) 0 else -1)
                            .width(.percent(100 / table_columns.len))
                            .layout(.left_center)
                            .children({
                            switch (@typeInfo(@TypeOf(value))) {
                                .float => Number(value)
                                    .ellipsis(.dot)
                                    .end(),
                                .int => Number(value)
                                    .ellipsis(.dot)
                                    .end(),
                                .@"enum" => Text(@tagName(value))
                                    .ellipsis(.dot)
                                    .end(),
                                .pointer => |ptr| {
                                    if (ptr.size == .slice) {
                                        Text(value)
                                            .ellipsis(.dot)
                                            .end();
                                    }
                                },
                                else => {
                                    Vapor.printErr("Type {any} not supported", .{@TypeOf(value)});
                                },
                            }
                        });
                    }
                });
                Box()
                    .width(.percent(action_width))
                    .layout(.right_center)
                    .height(.px(24))
                    .children({
                    if (show_actions) {
                        table.action_select.renderTrigger();
                    }
                });
            });
        }

        // ============ Search Functions ============
        fn matchesSearch(comptime key: []const u8, item: T, query: []const u8) bool {
            if (query.len == 0) return true;

            const value = @field(item, key);
            const value_str = fieldToString(value);

            return std.ascii.indexOfIgnoreCase(value_str, query) != null;
        }

        fn matchesFilter(comptime key: []const u8, item: T) bool {
            const value = @field(item, key);
            const value_str = fieldToString(value);
            return enum_filters.get(value_str) != null;
        }

        fn fieldToString(value: anytype) []const u8 {
            return switch (@typeInfo(@TypeOf(value))) {
                .pointer => |ptr| {
                    if (ptr.size == .slice and ptr.child == u8) {
                        return value;
                    }
                    return "";
                },
                .@"enum" => @tagName(value),
                .int => blk: {
                    break :blk Vapor.fmtln("{d}", .{value});
                },
                else => "",
            };
        }

        fn applyFilters(table: *Self) void {
            table.filtered_data.clearRetainingCapacity();

            for (table.data) |item| {
                var matches = true;

                inline for (columns, 0..) |col, i| {
                    // 1. Check text search (Existing logic)
                    if (active_filters[i]) |filter_text| {
                        if (!matchesSearch(col.key, item, filter_text)) {
                            matches = false;
                            break;
                        }
                    }

                    // 2. Check enum filter (Fixed logic)
                    // We only apply the filter logic if this specific column allows filtering
                    if (col.filter) {
                        // We need to look up the field type at comptime to get its enum values
                        const fields = @typeInfo(T).@"struct".fields;

                        inline for (fields) |field| {
                            if (comptime std.mem.eql(u8, field.name, col.key)) {

                                // Ensure this is actually an enum field
                                if (@typeInfo(field.type) == .@"enum") {
                                    const all_enum_values = std.enums.values(field.type);
                                    var is_filtering_this_col = false;

                                    // Check if ANY value belonging to this column's enum type is currently selected
                                    for (all_enum_values) |val| {
                                        const val_str = fieldToString(val);
                                        if (enum_filters.get(val_str) != null) {
                                            is_filtering_this_col = true;
                                            break;
                                        }
                                    }

                                    // Only filter the row if the user has actually selected a filter
                                    // relevant to THIS specific column
                                    if (is_filtering_this_col) {
                                        if (!matchesFilter(col.key, item)) {
                                            matches = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // If matches became false inside the inner inline loop, break the outer column loop
                    if (!matches) break;
                }

                if (matches) {
                    table.filtered_data.append(item) catch unreachable;
                }
            }
        }

        pub fn onSearch(table: *Self, search_query: []const u8, column_index: usize) void {
            clicked_index = column_index;
            active_filters[clicked_index] = search_query;
            // Store filter for the clicked column
            active_filters[clicked_index] = if (search_query.len > 0) search_query else null;

            table.applyFilters();
        }

        fn search(table: *Self, evt: *Vapor.Event) void {
            search_box.setText(evt.text());

            // Store filter for the clicked column
            active_filters[clicked_index] = if (search_box.text.len > 0) search_box.text else null;
            std.log.info("search {any}", .{active_filters[0]});

            table.applyFilters();
        }

        fn clearText(table: *Self) void {
            search_box.text = "";
            active_filters[clicked_index] = null;
            table.applyFilters();
        }

        pub fn ActionTrigger(_: *Select(usize)) void {
            Box()
                .width(.px(24))
                .height(.px(24))
                .cursor(.pointer)
                .background(.palette(.background))
                .hover(.{
                    .background = tint,
                    .text_color = checkbox_color_icon,
                })
                .font(14, 300, .palette(.text_color))
                .duration(200)
                .border(.round(.transparent, .all(4)))
                .layout(.center)
                .children({
                Vapor.Icon(.three_dots)
                    .font(16, 300, null)
                    .end();
            });
        }

        fn Rows(table: *Self) void {
            if (table.filtered_data.items.len == 0) {
                Box()
                    .width(.percent(100))
                    .padding(.vertical(48))
                    .layout(.center)
                    .children({
                    Stack()
                        .layout(.center)
                        .spacing(8)
                        .width(.percent(100))
                        .children({
                        Icon(.inbox)
                            .font(32, 300, icon_color)
                            .end();
                        Text("No results found")
                            .font(14, 400, icon_color)
                            .end();
                    });
                });
                return;
            }

            const items_to_render = switch (table.display_mode) {
                .paginated => blk: {
                    const start_index = current_page * table.per_page;
                    var end_index = start_index + table.per_page;
                    if (end_index > table.filtered_data.items.len) {
                        end_index = table.filtered_data.items.len;
                    }
                    break :blk table.filtered_data.items[start_index..end_index];
                },
                .all => table.data,
                else => {
                    Vapor.printErr("Error called virtualize on Rows", .{});
                    unreachable;
                },
            };

            Stack()
                .scroll(.scroll_x()) // Allow horizontal scroll
                .width(.percent(100))
                .spacing(if (table.row_spacing) |sp| sp else 0)
                .a11y(Vapor.Accessibility.init().setRole(.row_group)) // ✓ You have this
                .children({
                // If we remove the outer box we get very strange behaviour
                Box()
                    .inlineStyle(
                        \\min-width: 128px;
                        \\width: max-content;
                    , .{})
                    .pos(.tl(.percent(0), .percent(0), .absolute)) // Position absolute to the top left
                    .children({
                    if (show_actions) {
                        table.action_select.renderSelect();
                    }
                });
                for (items_to_render, 0..) |*row, i| {
                    const last_row = table.rows.len - 1 == i;

                    const actual_index = current_page * table.per_page + i;
                    const is_focused_row = table.focused_row == actual_index;
                    const is_selected = table.includes(row.id);

                    Box()
                        .a11y(Vapor.Accessibility.init()
                            .setRole(.row)
                            .setRowIndex(@intCast(actual_index + 1)) // Add row index (1-based)
                            .setSelected(is_selected))
                        .height(.px(row_height))
                        .width(.percent(100))
                        .background(if (table.row_background) |bg| bg else background)
                        .border(if (table.row_border) |bg| bg else .bottom(1, if (!last_row) border_color else .transparent))
                        .inlineStyle("min-width: 600px", .{}) // Minimum table width
                        .layout(.x_between_center)
                        .children({
                        Box()
                            .padding(.horizontal(18))
                            .width(.percent(100))
                            .height(.px(row_height))
                            .layout(.x_between_center).children({
                            Box()
                                .a11y(Vapor.Accessibility.init().setRole(.grid_cell))
                                // .id(Vapor.fmtln("checkbox-row-{d}-col-0", .{actual_index}))
                                .tabIndex(if (is_focused_row and table.focused_col == 0) 0 else -1)
                                .width(.percent(checkbox_width))
                                .children({
                                CheckBox(selectRow, .{ table, row })
                                    .a11y(Vapor.Accessibility.checkbox(is_selected)
                                        .setLabel(Vapor.fmtln("Select row {d}", .{actual_index + 1})))
                                    .border(.solid(.all(1), if (table.includes(row.id)) .transparentizeHex(.palette(.tint), 0.8) else border_color, .all(6)))
                                    .hoverScale()
                                    .layout(.center)
                                    .children({
                                    if (table.includes(row.id)) {
                                        Box()
                                            .width(.px(14))
                                            .height(.px(14))
                                            .background(if (table.includes(row.id)) .transparentizeHex(.palette(.tint), 0.8) else .transparent)
                                            .border(.round(if (table.includes(row.id)) .transparent else border_color, .all(4)))
                                            .hoverScale()
                                            .layout(.center)
                                            .children({});
                                    }
                                });
                            });
                            Box()
                                .width(.percent(row_width))
                                .layout(.x_between_center).children({
                                inline for (table_columns, 0..) |column, col_i| {
                                    const cell_col = col_i + 1; // +1 because checkbox is col 0
                                    const name = column.key;
                                    const value = @field(row, name);
                                    const width = if (column.width) |w| w else table.total_width_percent / table_columns.len;
                                    // const id = Vapor.fmtln("table-column-row-{d}-col-{d}", .{ actual_index, col_i });
                                    Box()
                                        .a11y(Vapor.Accessibility.init()
                                            .setRole(.grid_cell)
                                            .setColIndex(@intCast(cell_col)))
                                        // .id(id) // vice versa for this aswell apparently have both uncommented causes issue
                                        .tabIndex(if (is_focused_row and table.focused_col == col_i + 1) 0 else -1)
                                        .width(.percent(width))
                                        .layout(.left_center)
                                        .children({
                                        if (column.render) |col_render| {
                                            @call(.auto, col_render, .{row});
                                        } else {
                                            switch (@typeInfo(@TypeOf(value))) {
                                                .float => Number(value)
                                                    .ellipsis(.dot)
                                                    .end(),
                                                .int => Number(value)
                                                    .ellipsis(.dot)
                                                    .end(),
                                                .@"enum" => Text(@tagName(value))
                                                    .ellipsis(.dot)
                                                    .end(),
                                                .pointer => |ptr| {
                                                    if (ptr.size == .slice) {
                                                        Text(value)
                                                            .ellipsis(.dot)
                                                            .end();
                                                    }
                                                },
                                                .@"struct" => {
                                                    if (@TypeOf(value) == Vapor.DateTime) {
                                                        const date = value.format(Vapor.arena(.frame)) catch "Error Formatting";
                                                        Text(date)
                                                            .ellipsis(.dot)
                                                            .end();
                                                    }
                                                },
                                                else => {
                                                    Vapor.printErr("Type {any} not supported", .{@TypeOf(value)});
                                                },
                                            }
                                        }
                                    });
                                }
                            });
                            Box()
                                .a11y(Vapor.Accessibility.init().setRole(.grid_cell))
                                // .id(Vapor.fmtln("action-row-{d}-col-{d}", .{ actual_index, table_columns.len + 1 }))
                                .tabIndex(if (is_focused_row and table.focused_col == table_columns.len + 1) 0 else -1)
                                .width(.percent(action_width))
                                .layout(.right_center)
                                .height(.px(24))
                                .children({
                                if (show_actions) {
                                    table.action_select.renderTriggerCtx(setRow, .{i});
                                }
                            });
                        });
                    });
                }
            });
        }

        fn setRow(index: usize) void {
            row_index = index;
        }

        fn makeSortFn(comptime key: []const u8) fn (Sort, T, T) bool {
            return struct {
                fn compare(sort_type: Sort, a: T, b: T) bool {
                    const value_a = @field(a, key);
                    const value_b = @field(b, key);
                    const val1 = if (sort_type == .asc) value_a else value_b;
                    const val2 = if (sort_type == .asc) value_b else value_a;
                    return switch (@typeInfo(@TypeOf(value_a))) {
                        .pointer => |ptr| {
                            if (ptr.size == .slice) {
                                return std.ascii.lessThanIgnoreCase(val1, val2);
                            }
                            return false;
                        },
                        .@"enum" => @intFromEnum(val1) < @intFromEnum(val2),
                        .int, .float => val1 < val2,
                        else => Vapor.printErr("Sorting not supported for {any}", .{@typeInfo(@TypeOf(val1))}),
                    };
                }
            }.compare;
        }

        fn sortColumn(self: *Self, comptime sort_type: Sort, comptime key: []const u8) void {
            std.mem.sort(T, self.filtered_data.items, sort_type, makeSortFn(key));
        }

        fn mountSearchBox(_: *Self) void {
            search_box.focus();
        }

        fn handleFilter(table: *Self, comptime FT: type, value: FT) void {
            const text = fieldToString(value);
            if (enum_filters.get(text)) |_| {
                if (!enum_filters.remove(text)) {
                    Vapor.printErr("Failed to remove filter", .{});
                }
            } else {
                _ = enum_filters.put(text, {}) catch unreachable;
            }
            table.applyFilters();
        }

        fn CommonFilter() Vapor.Builder(.pure) {
            return Stack()
                .animationEnter("opaque-table-filter-enter")
                .animationExit("opaque-table-filter-exit")
                .width(.percent(100))
                .layout(.center)
                .background(.palette(.background))
                .height(.fit)
                .border(.round(border_color, .all(6)))
                .shadow(.{
                .top = 4,
                .spread = 2,
                .blur = 6,
                .color = .transparentizeHex(.black, 0.05),
            });
        }

        fn FilterSelect(table: *Self, comptime FT: type, comptime values: []const FT) void {
            CommonFilter()
                .padding(.all(4))
                .spacing(8)
                .children({
                for (values) |value| {
                    ButtonCtx(handleFilter, .{ table, FT, value })
                        .ariaLabel("Select Filter")
                        .width(.percent(100))
                        .height(.px(36))
                        .background(if (enum_filters.get(fieldToString(value)) != null) tint else .transparent)
                        .pointer()
                        .layout(.left_center)
                        .duration(100)
                        .hover(.{
                            .background = tint,
                            .text_color = checkbox_color_icon,
                        })
                        .padding(.tblr(6, 6, 6, 24))
                        .border(.round(.transparent, .all(6)))
                        .font(14, 300, if (enum_filters.get(fieldToString(value)) != null) checkbox_color_icon else .palette(.text_color))
                        .children({
                        Text(value)
                            .fontFamily("Montserrat")
                            .end();
                    });
                }
            });
        }
        fn Search(table: *Self) void {
            CommonFilter()
                .children({
                Vapor.Static.HooksCtx(.mounted, mountSearchBox, .{table})({
                    Box()
                        .width(.percent(100))
                        .padding(.all(4))
                        .pointer()
                        .layout(.x_between_center)
                        .children({
                        Box()
                            .border(.round(.transparent, .all(6)))
                            .width(.px(32))
                            .height(.px(32))
                            .background(tint)
                            .layout(.center)
                            .children({
                            Icon(.search)
                                .font(18, 300, checkbox_color_icon)
                                .end();
                        });
                        TextField(.string)
                            .ref(&search_box)
                            // .bind(&search_box.text)
                            .placeholder("Filter...")
                            .width(.grow)
                            .border(.none)
                            .padding(.horizontal(12))
                            .outline(.none)
                            .fontFamily("Montserrat")
                            .background(.transparent)
                            .font(16, 300, icon_color)
                            .val(&search_box.text)
                            .onEventCtx(.input, search, .{table})
                            .end();
                        ButtonCtx(clearText, .{table})
                            .ariaLabel("Search Filter")
                            .background(.transparent)
                            .pointer()
                            .padding(.all(4))
                            .children({
                            Icon(.x_lg)
                                .font(14, 300, icon_color)
                                .end();
                        });
                    });
                });
            });
        }

        fn toggleFilter(_: *Self, index: usize) void {
            // If clicking same column, toggle. If different column, switch to it.
            if (clicked_index == index and show_filter) {
                show_filter = false;
            } else {
                show_filter = true;
                clicked_index = index;
            }

            const bounds = binded_cols[index].getOffsets() orelse return;
            filter_top = bounds.offset_top + bounds.offset_height;
            filter_right = bounds.offset_left;
        }

        fn toggleSearch(_: *Self, index: usize) void {
            // If clicking same column, toggle. If different column, switch to it.
            if (clicked_index == index and show_search) {
                show_search = false;
            } else {
                show_search = true;
                clicked_index = index;

                // Load existing filter for this column
                search_box.text = active_filters[index] orelse "";
            }

            const bounds = binded_cols[index].getOffsets() orelse return;
            search_top = bounds.offset_top + bounds.offset_height;
            search_right = bounds.offset_left;
        }

        fn Pagination(table: *Self) void {
            if (table.filtered_data.items.len == 0) return;
            const page_count: f32 = @floatFromInt(@divTrunc(table.filtered_data.items.len, table.per_page) + 1);
            const float_current_page: f32 = @floatFromInt(current_page);

            Box()
                .a11y(Vapor.Accessibility.init().setRole(.navigation).setLabel("Table pagination"))
                .width(.percent(100))
                .layout(.x_between_center)
                .padding(.tblr(8, 8, 18, 18))
                .height(.px(row_height))
                .layout(.x_between_center)
                .spacing(8)
                .children({
                // Page info as live region
                Box()
                    .a11y(.liveRegion(.polite))
                    .children({
                    TextFmt("Page {d} of {d}", .{ current_page + 1, page_count })
                        .end();
                });

                Box()
                    .spacing(16)
                    .children({
                    if (float_current_page > 0) {
                        ButtonCtx(prevPage, .{table})
                            .ariaLabel("Go to previous page")
                            .background(.transparent)
                            .cursor(.pointer)
                            .children({
                            Icon(.chevron_left)
                                .font(16, 300, icon_color)
                                .end();
                        });
                    }
                    if (float_current_page < page_count - 1) {
                        ButtonCtx(nextPage, .{table})
                            .ariaLabel("Go to next page")
                            .background(.transparent)
                            .cursor(.pointer)
                            .children({
                            Icon(.chevron_right)
                                .font(16, 300, icon_color)
                                .end();
                        });
                    }
                });
            });
        }

        fn prevPage(_: *Self) void {
            if (current_page == 0) return;
            current_page -= 1;
        }

        fn nextPage(table: *Self) void {
            if (current_page > table.data.len - 1) return;
            current_page += 1;
        }

        // fn selectAll(table: *Self) void {
        //     if (table.selected_rows.count() == table.data.len) {
        //         table.selected_rows.clearRetainingCapacity();
        //         return;
        //     }
        //     for (table.data) |row| {
        //         table.selected_rows.put(row.id, {}) catch |err| {
        //             Vapor.printErrSrc("Failed to put row {any} into selected_rows: {any}", .{ row.id, err }, @src());
        //             return;
        //         };
        //     }
        //
        //     if (table.on_select_all) |on_select_all| {
        //         on_select_all();
        //     }
        // }

        // // selectAll becomes O(n/64):
        // fn selectAll(table: *Self) void {
        //     if (table.selected_rows.count() == table.data.len) {
        //         table.selected_rows.setRangeValue(.{ .start = 0, .end = table.data.len }, false);
        //     } else {
        //         table.selected_rows.setRangeValue(.{ .start = 0, .end = table.data.len }, true);
        //     }
        //     if (table.on_select_all) |on_select_all| {
        //         on_select_all();
        //     }
        // }

        fn selectAll(table: *Self) void {
            // O(1) - just flip the mode
            table.selection_mode = if (table.selection_mode == .all) .none else .all;
            table.selection_set.clearRetainingCapacity();

            if (table.on_select_all) |on_select_all| {
                on_select_all();
            }
        }

        fn selectRow(table: *Self, row: *T) void {
            const id = row.id;

            switch (table.selection_mode) {
                .none => {
                    // Start selecting individual rows
                    table.selection_mode = .some;
                    table.selection_set.put(id, {}) catch return;
                },
                .some => {
                    if (table.selection_set.contains(id)) {
                        _ = table.selection_set.remove(id);
                        if (table.selection_set.count() == 0) {
                            table.selection_mode = .none;
                        }
                    } else {
                        table.selection_set.put(id, {}) catch return;
                        // Check if we've selected everything
                        if (table.selection_set.count() == table.data.len) {
                            table.selection_mode = .all;
                            table.selection_set.clearRetainingCapacity();
                        }
                    }
                },
                .all => {
                    // Deselecting from "all" - switch to all_except
                    table.selection_mode = .all_except;
                    table.selection_set.put(id, {}) catch return;
                },
                .all_except => {
                    if (table.selection_set.contains(id)) {
                        // Re-selecting an excluded row
                        _ = table.selection_set.remove(id);
                        if (table.selection_set.count() == 0) {
                            table.selection_mode = .all;
                        }
                    } else {
                        // Excluding another row
                        table.selection_set.put(id, {}) catch return;
                        // Check if we've deselected everything
                        if (table.selection_set.count() == table.data.len) {
                            table.selection_mode = .none;
                            table.selection_set.clearRetainingCapacity();
                        }
                    }
                },
            }

            if (table.on_select) |on_select| {
                on_select(row);
            }
        }

        fn includes(table: *Self, id: IdType) bool {
            return switch (table.selection_mode) {
                .none => false,
                .all => true,
                .some => table.selection_set.contains(id),
                .all_except => !table.selection_set.contains(id),
            };
        }

        // Helper to get actual count
        fn selectedCount(table: *Self) usize {
            return switch (table.selection_mode) {
                .none => 0,
                .all => table.data.len,
                .some => table.selection_set.count(),
                .all_except => table.data.len - table.selection_set.count(),
            };
        }

        const FileType = enum {
            // csv,
            json,
        };

        fn download(table: *Self, file_type: FileType) void {
            downloading = true;

            switch (file_type) {
                .json => {
                    const allocator = Vapor.arena(.persist);
                    var out: std.io.Writer.Allocating = .init(allocator);
                    var downloadable_rows: Vapor.Array(T) = Vapor.array(T, .persist);

                    for (table.data) |row| {
                        if (table.includes(row.id)) {
                            downloadable_rows.append(row) catch unreachable;
                        }
                    }

                    std.json.Stringify.value(downloadable_rows.items, .{ .whitespace = .indent_2 }, &out.writer) catch unreachable;
                    var arr = out.toArrayList();
                    defer arr.deinit(allocator);

                    const content = arr.toOwnedSlice(allocator) catch unreachable;
                    defer allocator.free(content);
                    const name = Vapor.fmtln("{s}.json", .{table.file_name});
                    File.downloadFile(name, content, .@"application/json");
                },
            }
        }

        fn CommonToggleFilter(func: anytype, args: anytype) Vapor.ButtonBuilder(.pure) {
            return ButtonCtx(func, args)
                .ariaLabel("Toggle Filter")
                .cursor(.pointer)
                .border(.round(.transparent, .all(4)))
                .padding(.all(4))
                .height(.px(24))
                .width(.px(24))
                .border(.round(.transparent, .all(4)))
                .duration(100)
                .layout(.left_center)
                .width(.fit)
                .spacing(8)
                .font(14, 300, .palette(.text_color))
                .hover(.{
                .background = tint,
                .text_color = checkbox_color_icon,
            });
        }
        fn CheckBox(func: anytype, args: anytype) Vapor.ButtonBuilder(.pure) {
            return ButtonCtx(func, args)
                .ariaLabel("Table Row Checkbox")
                .width(.px(20))
                .height(.px(20))
                .cursor(.pointer)
                .duration(100)
                .hoverScale();
        }

        fn mount(table: *Self) void {
            table.registerKeyboardNav();
        }

        fn destroy(table: *Self) void {
            table.unregisterKeyboardNav();
        }

        pub fn render(table: *Self) void {
            // const total_rows = table.filtered_data.items.len;
            // const selected_count = table.selectedCount();

            Stack()
                .width(.percent(100))
                .height(.fit)
                .direction(.column)
                .children({
                Vapor.Static.HooksCtx(.mounted, mount, .{table})({
                    Vapor.Static.HooksCtx(.destroy, destroy, .{table})({
                        Stack()
                            .width(.percent(100))
                            .height(.fit)
                            .direction(.column)
                            .a11y(Vapor.Accessibility.init()
                                .setRole(.grid) // or .table if non-interactive
                                .setLabel(table.file_name)
                                .setActiveDescendant(if (table.focused_row) |row|
                                Vapor.fmtln("row-{d}-col-{d}", .{ row, table.focused_col orelse 0 })
                            else
                                null))
                            .tabIndex(0) // Make table focusable
                            .children({

                            // // Live region for announcements
                            // Box()
                            //     .a11y(.liveRegion(.polite))
                            //     .inlineStyle("position: absolute; width: 1px; height: 1px; overflow: hidden;", .{})
                            //     .children({
                            //     TextFmt("{d} rows, {d} selected", .{ total_rows, selected_count })
                            //         .end();
                            // });

                            Box()
                                .width(.percent(100))
                                .pos(.relative)
                                .children({
                                Box()
                                    .a11y(Vapor.Accessibility.init().setRole(.row_group))
                                    .scroll(.scroll_x()) // Allow horizontal scroll
                                    .width(.percent(100))
                                    .height(.px(row_height))
                                    .layout(.x_between_center)
                                    .children({
                                    Box()
                                        .a11y(Vapor.Accessibility.init().setRole(.row))
                                        .height(.px(row_height))
                                        .width(.percent(100))
                                        .inlineStyle("min-width: 600px", .{}) // Minimum table width
                                        .children({
                                        Box()
                                            .padding(.horizontal(18))
                                            .width(.percent(100))
                                            .height(.px(row_height))
                                            .layout(.x_between_center).children({
                                            Box()
                                                .a11y(Vapor.Accessibility.init()
                                                    .setRole(.column_header))
                                                .width(.percent(checkbox_width))
                                                .children({
                                                const active = table.selection_mode == .all;
                                                CheckBox(selectAll, .{table})
                                                    .a11y(Vapor.Accessibility.checkbox(table.selection_mode == .all)
                                                        .setLabel("Select all"))
                                                    .hoverScale()
                                                    .border(.solid(.all(1), if (active) .transparentizeHex(.palette(.tint), 0.8) else border_color, .all(6)))
                                                    .layout(.center)
                                                    .children({
                                                    if (active) {
                                                        Box()
                                                            .width(.px(14))
                                                            .height(.px(14))
                                                            .background(if (active) .transparentizeHex(.palette(.tint), 0.8) else .transparent)
                                                            .border(.round(if (active) .transparent else border_color, .all(4)))
                                                            .hoverScale()
                                                            .layout(.center)
                                                            .children({});
                                                    }
                                                });
                                            });
                                            const fields = @typeInfo(T).@"struct".fields;
                                            Box()
                                                .width(.percent(row_width))
                                                .height(.px(row_height))
                                                .layout(.x_between_center).children({
                                                inline for (table_columns, 0..) |*column, i| {
                                                    const width = if (column.width) |w| w else table.total_width_percent / table_columns.len;
                                                    Box()
                                                        .a11y(Vapor.Accessibility.init()
                                                            .setRole(.column_header)
                                                            .setLabel(column.title))
                                                        .ref(&binded_cols[i])
                                                        .width(.percent(width))
                                                        .height(.px(row_height))
                                                        .layout(.left_center)
                                                        .spacing(4)
                                                        .children({
                                                        Text(column.title)
                                                            .fontFamily("Montserrat")
                                                            .font(16, null, null).end();

                                                        if (column.sort) |sort_type| {
                                                            CommonToggleFilter(sortColumn, .{ table, sort_type, column.key })
                                                                .ariaLabel(Vapor.fmtln("Sort by {s} {s}", .{ column.title, if (sort_type == .asc) "ascending" else "descending" }))
                                                                .children({
                                                                switch (sort_type) {
                                                                    .asc => Icon(.sort_alpha_down).font(14, 700, null).end(),
                                                                    .desc => Icon(.sort_alpha_up).font(14, 700, null).end(),
                                                                    else => {},
                                                                }
                                                            });
                                                        }
                                                        if (column.search) {
                                                            CommonToggleFilter(toggleSearch, .{ table, i })
                                                                .ariaLabel(Vapor.fmtln("Search by {s} ", .{column.title}))
                                                                .children({
                                                                Icon(.search).font(14, 700, null).end();
                                                            });
                                                        }
                                                        if (column.filter) {
                                                            CommonToggleFilter(toggleFilter, .{ table, i })
                                                                .ariaLabel(Vapor.fmtln("Filter by {s} ", .{column.title}))
                                                                .children({
                                                                Icon(.funnel).font(14, 700, null).end();
                                                            });
                                                        }
                                                        Box()
                                                            .pos(.tl(.px(0), .percent(0), .absolute))
                                                            .width(.fit)
                                                            .zIndex(1000)
                                                            .inlineStyle("transform: translate({d}px, {d}px)", .{ filter_right, filter_top })
                                                            .children({
                                                            if (column.filter and show_filter and clicked_index == i) {
                                                                inline for (fields) |field| {
                                                                    const name = field.name;
                                                                    const field_type = field.type;
                                                                    if (std.mem.eql(u8, column.key, name)) {
                                                                        if (@typeInfo(field_type) == .@"enum") {
                                                                            FilterSelect(table, field_type, std.enums.values(field_type));
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        });

                                                        Box()
                                                            .pos(.tl(.px(0), .percent(0), .absolute))
                                                            .width(.fit)
                                                            .zIndex(1000)
                                                            .inlineStyle("transform: translate({d}px, {d}px)", .{ search_right, search_top })
                                                            .children({
                                                            if (column.search and show_search and clicked_index == i) {
                                                                Search(table);
                                                            }
                                                        });
                                                    });
                                                }
                                            });
                                            Box()
                                                .a11y(Vapor.Accessibility.init().setRole(.column_header).setLabel("Actions"))
                                                .width(.percent(action_width))
                                                .layout(.right_center)
                                                .height(.px(24))
                                                .children({
                                                Box()
                                                    .width(.percent(100))
                                                    .height(.percent(100))
                                                    .layout(.left_center)
                                                    .spacing(8)
                                                    .children({
                                                    CommonToggleFilter(download, .{ table, .json })
                                                        .layout(.center)
                                                        .cursor(.pointer)
                                                        .padding(.all(0))
                                                        .children({
                                                        Vapor.Icon(.filetype_json)
                                                            .font(18, 300, null)
                                                            .end();
                                                    });
                                                });
                                            });
                                        });
                                    });
                                });
                            });
                            if (table.display_mode == .virtual) {
                                virtual_list.renderWithCtx(@ptrCast(table));
                                Box()
                                    .width(.percent(14))
                                    .pos(.tl(.percent(0), .percent(0), .absolute))
                                    .children({
                                    if (show_actions) {
                                        table.action_select.renderSelect();
                                    }
                                });
                            } else {
                                table.Rows();
                            }
                        });
                        table.Pagination();
                    });
                });
            });
        }
    };
}
