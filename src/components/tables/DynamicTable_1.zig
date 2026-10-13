///! DynamicTable.zig
///!
///! A generic, data-driven table component built on the Vapor UI framework.
///!
///! Features:
///!   - Dynamic columns defined at comptime via `DataColumn` descriptors
///!   - Paginated, virtualized, or full-display rendering modes
///!   - Inline cell editing with keyboard shortcuts (Enter to save, Esc to dismiss)
///!   - Per-column text search/filtering
///!   - Row selection with efficient O(1) select-all (none / some / all / all-except)
///!   - JSON export of selected rows
///!   - Optional row-level action menus
///!   - Accessibility: ARIA grid roles, keyboard navigation, live regions
///!   - **Fully instance-based styling** - each table can have its own theme
///!
///! Usage:
///!   ```zig
///!   const cols = &[_]DataColumn{
///!       .{ .name = "id",    .primary = true, .type = .uuid },
///!       .{ .name = "name",  .type = .string },
///!       .{ .name = "score", .type = .float },
///!   };
///!   const Table = DynamicTable(cols, .{});
///!   var table: Table = undefined;
///!   table.init(my_data);
///!
///!   // Customize styling per instance
///!   table.style.border_color = .hex("#333");
///!   table.style.tint = .hex("#2288ff");
///!   table.style.font_family = "Inter";
///!   table.style.row_height = 48;
///!
///!   table.render();
///!   ```
const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Row;
const Button = Vapor.Button;
const Stack = Vapor.Stack;
const Components = @import("Components.zig");
const Select = @import("../Select.zig").Select;
const Icon = Vapor.Icon;
const TextField = Vapor.TextField;
const TextFmt = Vapor.TextFmt;
const File = Vapor.FileReader;
const VirtualList = @import("Virtualize.zig").VirtualList;
const OverlayManager = @import("../OverlayManager.zig");
const Allocator = std.mem.Allocator;
const Number = Vapor.Number;
const Opaque = @import("../../components/Opaque.zig");

const save_icon: []const u8 =
    \\<svg xmlns="http://www.w3.org/2000/svg" class="bi bi-arrow-return-right" viewBox="0 0 16 16">
    \\  <path fill-rule="evenodd" d="M1.5 1.5A.5.5 0 0 0 1 2v4.8a2.5 2.5 0 0 0 2.5 2.5h9.793l-3.347 3.346a.5.5 0 0 0 .708.708l4.2-4.2a.5.5 0 0 0 0-.708l-4-4a.5.5 0 0 0-.708.708L13.293 8.3H3.5A1.5 1.5 0 0 1 2 6.8V2a.5.5 0 0 0-.5-.5"/>
    \\</svg>
;

const chevron_left: []const u8 =
    \\<svg xmlns="http://www.w3.org/2000/svg" class="bi bi-chevron-left" viewBox="0 0 16 16">
    \\  <path fill-rule="evenodd" d="M11.354 1.646a.5.5 0 0 1 0 .708L5.707 8l5.647 5.646a.5.5 0 0 1-.708.708l-6-6a.5.5 0 0 1 0-.708l6-6a.5.5 0 0 1 .708 0z"/>
    \\</svg>
;

const chevron_right: []const u8 =
    \\<svg xmlns="http://www.w3.org/2000/svg" class="bi bi-chevron-right" viewBox="0 0 16 16">
    \\  <path fill-rule="evenodd" d="M4.646 1.646a.5.5 0 0 1 .708 0l6 6a.5.5 0 0 1 0 .708l-6 6a.5.5 0 0 1-.708-.708L10.293 8 4.646 2.354a.5.5 0 0 1 0-.708z"/>
    \\</svg>
;

const search_icon: []const u8 =
    \\<svg xmlns="http://www.w3.org/2000/svg" class="bi bi-search" viewBox="0 0 16 16">
    \\  <path d="M11.742 10.344a6.5 6.5 0 1 0-1.397 1.398h-.001c.03.04.062.078.098.115l3.85 3.85a1 1 0 0 0 1.415-1.414l-3.85-3.85a1.007 1.007 0 0 0-.115-.1zM12 6.5a5.5 5.5 0 1 1-11 0 5.5 5.5 0 0 1 11 0z"/>
    \\</svg>
;

const x_lg: []const u8 =
    \\<svg xmlns="http://www.w3.org/2000/svg" class="bi bi-x-lg" viewBox="0 0 16 16">
    \\  <path fill-rule="evenodd" d="M2.146 2.854a.5.5 0 1 1 .708-.708L8 7.293l5.146-5.147a.5.5 0 0 1 .708.708L8.707 8l5.147 5.146a.5.5 0 0 1-.708.708L8 8.707 2.854 13.146a.5.5 0 1 1-.708-.708L7.293 8 2.146 2.854a.5.5 0 0 1 0-.708z"/>
    \\</svg>
;

// ---------------------------------------------------------------------------
// Style configuration
// ---------------------------------------------------------------------------

/// Complete style configuration for a `DynamicTable` instance.
///
/// Every field has a sensible default but can be overridden per-instance
/// after `init()` to create themed variants (dark mode, compact density,
/// branded accents, etc.).
pub const TableStyle = struct {
    // ── Typography ───────────────────────────────────────────────────────
    font_family: []const u8 = "Barlow",
    header_font_size: u8 = 16,
    cell_font_size: u8 = 14,
    cell_font_weight: ?u16 = null,
    header_font_weight: ?u16 = null,

    // ── Colors ───────────────────────────────────────────────────────────
    background: Vapor.Types.Color = .white,
    text_color: Vapor.Types.Color = .black,
    text_color_muted: Vapor.Types.Color = .palette(.text_muted),
    icon_color: Vapor.Types.Color = .black,
    border_color: Vapor.Types.Color = .transparentize(.black, 0.2),
    tint: Vapor.Types.Color = .transparentizeHex(.palette(.tint), 0.8),
    checkbox_icon_color: Vapor.Types.Color = .white,

    // Hover / tapped cell highlight colors
    hover_background: Vapor.Types.Color = .palette(.tint),
    hover_text_color: Vapor.Types.Color = .white,
    corner_bracket_color: Vapor.Types.Color = .hex("#222160"),

    // Edit popup
    edit_popup_background: Vapor.Types.Color = .white,
    edit_popup_border_color: Vapor.Types.Color = .transparentize(.black, 0.2),

    // ── Borders ──────────────────────────────────────────────────────────
    border: Vapor.Types.BorderGrouped = .round(.transparentize(.black, 0.2), .all(6)),
    border_radius: u8 = 6,
    /// Style of inter-cell dividers ('dashed', 'solid', etc).
    cell_divider_style: Vapor.Types.BorderStyle = .dashed,
    /// Style of outer table borders.
    outer_border_style: Vapor.Types.BorderStyle = .dashed,
    /// Thickness of column dividers (px).
    cell_divider_thickness: u8 = 1,

    // ── Dimensions ───────────────────────────────────────────────────────
    row_height: f32 = 42,
    column_width: f32 = 256,
    min_column_width: f32 = 256,
    checkbox_width: f32 = 72,
    action_width: f32 = 5,

    // ── Cell padding ─────────────────────────────────────────────────────
    cell_padding_horizontal: u8 = 8,

    // ── Interaction / animation ──────────────────────────────────────────
    /// Whether to show the decorative corner brackets on hover.
    show_corner_brackets: bool = true,
    /// Hover-animation duration in ms.
    hover_duration: u16 = 100,
    /// Whether rows shift on hover (translate effect).
    hover_translate: bool = true,
    hover_translate_amount: i16 = -4,
};

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Supported column data-types for display and editing.
pub const ColumnType = enum {
    string,
    int,
    float,
    boolean,
    uuid,
    date,
    time,
    datetime,
    array,
    json,
    jsonb,
    interval,
};

pub const Interval = struct {
    microseconds: i64,
    days: i32,
    months: i32,

    /// Convert to total microseconds (approximate: assumes 30 days/month)
    pub fn toMicroseconds(self: Interval) i64 {
        const month_us: i64 = @as(i64, self.months) * 30 * 24 * 3600 * 1_000_000;
        const day_us: i64 = @as(i64, self.days) * 24 * 3600 * 1_000_000;
        return month_us + day_us + self.microseconds;
    }

    /// Convert to total seconds (approximate for months/days)
    pub fn toSeconds(self: Interval) f64 {
        return @as(f64, @floatFromInt(self.toMicroseconds())) / 1_000_000.0;
    }

    /// Parse from PostgreSQL binary wire format (16 bytes, big-endian)
    /// Wire format: i64 microseconds | i32 days | i32 months
    pub fn fromBytes(data: []const u8) ?Interval {
        if (data.len < 16) return null;
        return .{
            .microseconds = @bitCast(std.mem.readInt(u64, data[0..8], .big)),
            .days = @bitCast(std.mem.readInt(u32, data[8..12], .big)),
            .months = @bitCast(std.mem.readInt(u32, data[12..16], .big)),
        };
    }

    /// Format as ISO 8601 duration string (e.g. "P1Y2M3DT4H5M6S")
    pub fn toIso8601(self: Interval, buf: []u8) []const u8 {
        var writer = std.Io.Writer.fixed(buf);

        writer.writeByte('P') catch return "";

        const years = @divTrunc(self.months, 12);
        const months = @mod(self.months, 12);

        if (years != 0) writer.print("{}Y", .{years}) catch return "";
        if (months != 0) writer.print("{}M", .{months}) catch return "";
        if (self.days != 0) writer.print("{}D", .{self.days}) catch return "";

        const total_us = if (self.microseconds < 0) -self.microseconds else self.microseconds;
        const hours = @divTrunc(total_us, 3_600_000_000);
        const mins = @divTrunc(@mod(total_us, 3_600_000_000), 60_000_000);
        const secs = @divTrunc(@mod(total_us, 60_000_000), 1_000_000);
        const frac_us = @mod(total_us, 1_000_000);

        if (hours != 0 or mins != 0 or secs != 0 or frac_us != 0) {
            writer.writeByte('T') catch return "";
            if (self.microseconds < 0) writer.writeByte('-') catch return "";
            if (hours != 0) writer.print("{}H", .{hours}) catch return "";
            if (mins != 0) writer.print("{}M", .{mins}) catch return "";
            if (secs != 0 or frac_us != 0) {
                if (frac_us != 0) {
                    writer.print("{}.{:0>6}S", .{ secs, frac_us }) catch return "";
                } else {
                    writer.print("{}S", .{secs}) catch return "";
                }
            }
        }

        // Handle zero interval
        if (writer.end == 1) writer.writeAll("T0S") catch return "";

        return buf[0..writer.end];
    }

    pub fn render(self: *Interval, field_comp: *const fn (*Opaque.Field) Vapor.Builder(.pure)) void {
        Stack().width(.expand).spacing(8).children({
            Opaque.Field.create(.{ .label = "Months", .value = .{ .number = &self.months }, .type = .number }).Component(field_comp);
            Opaque.Field.create(.{ .label = "Days", .value = .{ .number = &self.days }, .type = .number }).Component(field_comp);
            Opaque.Field.create(.{ .label = "Microseconds", .value = .{ .int64 = &self.microseconds }, .type = .int64 }).Component(field_comp);
        });
    }
};

/// Describes a single column in the table schema.
pub const DataColumn = struct {
    name: []const u8,
    primary: bool = false,
    type: ColumnType = .string,
};

/// How the table presents its rows.
pub const DisplayMode = enum {
    paginated, // Classic page navigation
    virtual, // Virtualized scrolling for large datasets
    all, // Render every row (small datasets only)
};

/// Column sort direction (currently stored but not applied — reserved for future use).
pub const Sort = enum { none, asc, desc };

/// Column content alignment.
pub const Align = enum { none, left, center, right };

// ---------------------------------------------------------------------------
// Animations
// ---------------------------------------------------------------------------

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

pub const animateTextArea = Vapor.Animation.init("opaque-table-textarea-enter")
    .prop(.opacity, 0, 1)
    .prop(.scaleY, 0.5, 1)
    .duration(80)
    .easing(.easeInOut);

pub const animateTextAreaExit = Vapor.Animation.init("opaque-table-textarea-exit")
    .prop(.opacity, 1, 0)
    .prop(.scaleY, 1, 0.5)
    .duration(80)
    .easing(.easeInOut);

/// Must be called once at startup to register CSS keyframe animations.
pub fn new() void {
    animateTextArea.build();
    animateTextAreaExit.build();
}

// ---------------------------------------------------------------------------
// Value — a loosely-typed cell value (mirrors common DB types)
// ---------------------------------------------------------------------------

pub const Value = union(enum) {
    int: ?i64,
    float: ?f64,
    string: ?[]const u8,
    boolean: ?bool,
    datetime: ?Vapor.DateTime,
    null: ?void,
    array: ?[]const Value,
    json: ?[]const u8,

    /// Convert any variant to a displayable string. Returns "" for null
    /// optionals and "null" / "array" for the corresponding sentinel types.
    pub fn toString(self: Value) []const u8 {
        return switch (self) {
            .int => |v| if (v) |vi| Vapor.fmtArena("{d}", .{vi}, .frame) else "",
            .float => |v| if (v) |vf| Vapor.fmtArena("{d}", .{vf}, .frame) else "",
            .string, .json => |v| if (v) |vs| vs else "",
            .boolean => |v| if (v) |vb| if (vb) "true" else "false" else "",
            .datetime => |v| if (v) |vd| vd.format(Vapor.arena(.frame)) catch "Error Formatting" else "",
            .null => "null",
            .array => "array",
        };
    }
};

/// A single row: maps column-name → Value.
pub const DynamicRow = std.StringHashMap(Value);

// ---------------------------------------------------------------------------
// Generic helpers
// ---------------------------------------------------------------------------

/// Column descriptor used at comptime for typed table variants (reserved).
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

/// A per-row action (displayed in the action menu).
pub fn Action(comptime T: type) type {
    return struct {
        label: []const u8,
        icon: ?*const Vapor.IconTokens = null,
        on_action: ?*const fn (item: *T) void = null,
    };
}

/// Wraps a `DynamicRow` with UI-specific metadata.
pub fn Row(comptime T: type) type {
    return struct {
        value: T,
        is_selected: bool = false,
        is_shown: bool = true,
    };
}

// ---------------------------------------------------------------------------
// Hash context for the selection set
// ---------------------------------------------------------------------------

fn DynamicTableContext(comptime Id: type) type {
    return struct {
        pub fn hash(_: @This(), key: Id) u64 {
            if (comptime (@typeInfo(Id) == .pointer and @typeInfo(Id).pointer.size == .slice)) {
                return std.hash.Wyhash.hash(0, key);
            }
            var hasher = std.hash.Wyhash.init(0);
            std.hash.autoHash(&hasher, key);
            return hasher.final();
        }

        pub fn eql(_: @This(), a: Id, b: Id) bool {
            if (comptime (@typeInfo(Id) == .pointer and @typeInfo(Id).pointer.size == .slice)) {
                return std.mem.eql(u8, a, b);
            }
            return a == b;
        }
    };
}

// ═══════════════════════════════════════════════════════════════════════════
// DynamicTable  —  the main comptime-parameterized table widget
// ═══════════════════════════════════════════════════════════════════════════

/// Construct a `DynamicTable` type for the given column schema and optional
/// action definitions.
///
/// Parameters:
///   - `columns`:  comptime slice of `DataColumn` that defines every visible
///                 column. The *first* column is treated as the row ID for
///                 selection tracking.
///   - `config`:   optional `.actions` slice for per-row action menus, and
///                 an optional `.default_style` override for the table's
///                 initial `TableStyle`.
pub fn DynamicTable(
    columns: []const DataColumn,
    config: struct {
        actions: ?[]const Action(Value) = null,
        default_style: TableStyle = .{},
    },
) type {
    const IdType = []const u8;
    const SelectType = Select(usize);

    // How many (and which) rows are currently selected.
    const SelectionMode = enum { none, some, all, all_except };

    const EditMode = enum { None, Editing };

    return struct {
        const Self = @This();

        // ── Instance fields ──────────────────────────────────────────────
        data: []DynamicRow,
        filtered_data: Vapor.Array(DynamicRow),
        per_page: usize = 10,
        selection_mode: SelectionMode = .none,
        selection_set: std.HashMap(IdType, void, DynamicTableContext(IdType), std.hash_map.default_max_load_percentage),
        file_name: []const u8 = "content",
        display_mode: DisplayMode = .paginated,
        show_id_column: bool = false,
        on_select: ?*const fn (item: *DynamicRow) void = null,
        on_select_all: ?*const fn () void = null,
        action_select: SelectType = undefined,

        /// Per-instance styling. Mutate directly after `init()` to customize
        /// this specific table without affecting others of the same type.
        style: TableStyle = config.default_style,

        focused_row: ?usize = null,
        focused_col: ?usize = null,
        table_id: []const u8 = "data-table",
        total_width_percent: f32 = 100,
        row_background: ?Vapor.Types.Color = null,
        row_border: ?Vapor.Types.BorderGrouped = null,
        row_spacing: ?u8 = null,
        x: f32 = 0,
        y: f32 = 0,
        current_value: *Value = undefined,
        current_value_str: []const u8 = "",
        editMode: EditMode = .None,
        text_area: Vapor.Binded = .{ .element_type = .TextArea },
        container: Vapor.Binded = .{},
        clickable: bool = true,
        on_item_click: ?*const fn (*Value) void = null,
        on_row_click: ?*const fn (*DynamicRow) void = null,
        click_on_row: bool = false,

        // Per-instance (previously global) layout state
        row_width: f32 = 256,
        container_width: f32 = 256,

        // ── Comptime / shared state ──────────────────────────────────────
        pub var table_columns: []const DataColumn = columns;
        var arena_allocator: std.mem.Allocator = undefined;
        var arena: std.heap.ArenaAllocator = undefined;
        var show_actions: bool = if (config.actions != null) true else false;
        var actions: []const Action(DynamicRow) = config.actions orelse &.{};

        var binded_cols: []Vapor.Binded = &.{};
        var search_box: Vapor.Binded = .{};
        var show_search: bool = false;
        var clicked_index: usize = 0;
        var search_top: f32 = 0;
        var search_right: f32 = 0;
        var current_page: usize = 0;
        var active_filters: []?[]const u8 = &.{};
        var enum_filters: std.StringHashMap(void) = undefined;
        var downloading: bool = false;
        var virtual_list: VirtualList(DynamicRow) = undefined;
        var row_index: usize = 0;
        var current_hovered_id: []const u8 = "";
        var current_tapped_id: []const u8 = "";

        // =================================================================
        // Lifecycle
        // =================================================================

        /// Initialise the table with an initial data slice. Allocates internal
        /// bookkeeping (rows, filters, binded-column refs) from a dedicated
        /// arena so the table can be regenerated cheaply.
        pub fn init(table: *Self, data: []DynamicRow) void {
            arena = std.heap.ArenaAllocator.init(Vapor.lib.allocator_global);
            arena_allocator = arena.allocator();

            active_filters = arena_allocator.alloc(?[]const u8, table_columns.len) catch |err| blk: {
                Vapor.printErr("Failed to allocate active_filters: {any}", .{err});
                break :blk &.{};
            };
            @memset(active_filters, null);

            binded_cols = allocBindedCols(arena_allocator);
            enum_filters = std.StringHashMap(void).init(arena_allocator);

            table.* = Self{
                .data = data,
                .filtered_data = Vapor.array(DynamicRow, .persist),
                .selection_set = std.HashMap(IdType, void, DynamicTableContext(IdType), 80).init(arena_allocator),
            };
            table.row_width = table.computeRowWidth();

            search_box.init(arena_allocator);
            initActions(table);
            table.filtered_data.appendSlice(data[0..]) catch unreachable;
            initVirtualList(table);
        }

        /// Replace columns and data entirely. Reuses the existing arena by
        /// resetting it (avoids reallocation in the common case).
        pub fn regenerate(table: *Self, new_columns: []const DataColumn, data: []DynamicRow) void {
            if (!arena.reset(.retain_capacity)) std.log.err("Failed to reset arena", .{});
            table_columns = new_columns;

            binded_cols = allocBindedCols(arena_allocator);
            table.row_width = table.computeRowWidth();
            enum_filters = std.StringHashMap(void).init(arena_allocator);

            table.data = data;
            table.filtered_data = Vapor.array(DynamicRow, .persist);

            search_box.init(arena_allocator);
            initActions(table);
            table.filtered_data.appendSlice(data[0..]) catch unreachable;
            initVirtualList(table);

            Vapor.onEndCtx(calcBounds, .{table});
        }

        /// Re-apply current filters after external data mutation.
        pub fn refresh(table: *Self) void {
            table.filtered_data.clearRetainingCapacity();
            table.filtered_data.appendSlice(table.data[0..]) catch unreachable;
            table.applyFilters();
        }

        // =================================================================
        // Internal init helpers (deduped from init / regenerate)
        // =================================================================

        fn allocBindedCols(alloc: Allocator) []Vapor.Binded {
            return alloc.alloc(Vapor.Binded, table_columns.len) catch |err| blk: {
                Vapor.printErr("Failed to allocate binded cols: {any}", .{err});
                break :blk &.{};
            };
        }

        fn computeRowWidth(table: *Self) f32 {
            return table.style.column_width * @as(f32, @floatFromInt(table_columns.len)) + table.style.checkbox_width;
        }

        fn initActions(table: *Self) void {
            if (config.actions) |c_actions| {
                actions = c_actions;
                var items = arena_allocator.alloc(Select(usize).Item, actions.len) catch unreachable;
                for (actions, 0..) |action, i| {
                    items[i] = .{ .value = i, .label = action.label, .icon = action.icon };
                }
                table.action_select = .fromItems(items);
                table.action_select.render_trigger = false;
                table.action_select.trigger_component = ActionTrigger;
                table.action_select.on_select = selectAction;
            }
        }

        fn initVirtualList(table: *Self) void {
            virtual_list = VirtualList(DynamicRow).init(.{
                .data = table.data,
                .render_ctx = VirtualRow,
                .item_height = .px(table.style.row_height),
                .item_width = .percent(table.row_width),
                .buffer_size = 5,
                .container_height = @as(f32, @floatFromInt(table.per_page)) * table.style.row_height,
            });
        }

        // =================================================================
        // Keyboard navigation
        // =================================================================

        fn registerKeyboardNav(table: *Self) void {
            OverlayManager.register(.keydown, handleDynamicTableKeyPress, .{table});
        }

        fn unregisterKeyboardNav(table: *Self) void {
            OverlayManager.unregister(.keydown, table);
        }

        fn handleDynamicTableKeyPress(table: *Self, evt: *Vapor.Event) void {
            const key = evt.key();
            if (table.editMode == .Editing) {
                if (std.mem.eql(u8, key, "Enter") and !evt.shiftKey()) {
                    evt.preventDefault();
                    table.saveChanges();
                    table.close();
                } else if (std.mem.eql(u8, key, "Escape")) {
                    evt.preventDefault();
                    table.close();
                }
            }
        }

        // =================================================================
        // Selection
        // =================================================================

        /// Toggle select-all / deselect-all.
        fn selectAll(table: *Self) void {
            table.selection_mode = if (table.selection_mode == .all) .none else .all;
            table.selection_set.clearRetainingCapacity();
            if (table.on_select_all) |cb| cb();
        }

        /// Toggle selection for a single row, correctly transitioning between
        /// `none ↔ some ↔ all ↔ all_except` states.
        fn selectRow(table: *Self, row: *DynamicRow) void {
            const value = row.get(table_columns[0].name) orelse return;
            const id = value.toString();

            switch (table.selection_mode) {
                .none => {
                    table.selection_mode = .some;
                    table.selection_set.put(id, {}) catch return;
                },
                .some => {
                    if (table.selection_set.contains(id)) {
                        _ = table.selection_set.remove(id);
                        if (table.selection_set.count() == 0) table.selection_mode = .none;
                    } else {
                        table.selection_set.put(id, {}) catch return;
                        if (table.selection_set.count() == table.data.len) {
                            table.selection_mode = .all;
                            table.selection_set.clearRetainingCapacity();
                        }
                    }
                },
                .all => {
                    table.selection_mode = .all_except;
                    table.selection_set.put(id, {}) catch return;
                },
                .all_except => {
                    if (table.selection_set.contains(id)) {
                        _ = table.selection_set.remove(id);
                        if (table.selection_set.count() == 0) table.selection_mode = .all;
                    } else {
                        table.selection_set.put(id, {}) catch return;
                        if (table.selection_set.count() == table.data.len) {
                            table.selection_mode = .none;
                            table.selection_set.clearRetainingCapacity();
                        }
                    }
                },
            }

            if (table.on_select) |cb| cb(row);
        }

        /// O(1) membership test that respects the current selection mode.
        fn includes(table: *Self, id: IdType) bool {
            return switch (table.selection_mode) {
                .none => false,
                .all => true,
                .some => table.selection_set.contains(id),
                .all_except => !table.selection_set.contains(id),
            };
        }

        // =================================================================
        // Search & filtering
        // =================================================================

        /// Programmatic filter: set a search query on a given column index.
        pub fn onSearch(table: *Self, search_query: []const u8, column_index: usize) void {
            clicked_index = column_index;
            active_filters[clicked_index] = if (search_query.len > 0) search_query else null;
            table.applyFilters();
        }

        fn search(table: *Self, evt: *Vapor.Event) void {
            search_box.setText(evt.text());
            active_filters[clicked_index] = if (search_box.text.len > 0) search_box.text else null;
            table.applyFilters();
        }

        fn clearText(table: *Self) void {
            search_box.text = "";
            active_filters[clicked_index] = null;
            table.applyFilters();
        }

        fn applyFilters(table: *Self) void {
            table.filtered_data.clearRetainingCapacity();
            for (table.data) |item| {
                var matches = true;
                for (table_columns, 0..) |col, i| {
                    if (active_filters[i]) |filter_text| {
                        if (!matchesSearch(col.name, item, filter_text)) {
                            matches = false;
                            break;
                        }
                    }
                }
                if (matches) {
                    table.filtered_data.append(item) catch unreachable;
                }
            }
        }

        fn matchesSearch(key: []const u8, item: DynamicRow, query: []const u8) bool {
            if (query.len == 0) return true;
            const value = item.get(key) orelse return false;
            return std.ascii.indexOfIgnoreCase(fieldToString(value), query) != null;
        }

        fn fieldToString(value: Value) []const u8 {
            return switch (value) {
                .string, .json => |v| if (v) |vs| vs else "",
                .int => |v| if (v) |vi| Vapor.fmtln("{d}", .{vi}) else "",
                else => "",
            };
        }

        fn toggleSearch(_: *Self, index: usize) void {
            if (clicked_index == index and show_search) {
                show_search = false;
            } else {
                show_search = true;
                clicked_index = index;
                search_box.text = active_filters[index] orelse "";
            }
            const bounds = binded_cols[index].getOffsets() orelse return;
            search_top = bounds.offset_top + bounds.offset_height;
            search_right = bounds.offset_left;
        }

        // =================================================================
        // Inline cell editing
        // =================================================================

        fn editRowColumn(table: *Self, id: []const u8, value: *Value, _: *Vapor.Event) void {
            if (!table.clickable) return;
            if (table.on_item_click) |cb| {
                cb(value);
                return;
            }
            const bounds = Vapor.getComponentOffsets(id) orelse return;
            current_tapped_id = Vapor.dupe(id, .scratch);
            table.y = bounds.top + bounds.height;
            table.x = bounds.left;
            table.current_value_str = value.toString();
            table.current_value = value;
            table.editMode = .Editing;
        }

        fn onRowClick(table: *Self, row: *DynamicRow, _: *Vapor.Event) void {
            if (table.on_row_click) |cb| cb(row);
        }

        fn mountTextArea(table: *Self) void {
            table.text_area.focus();
        }

        /// Persist the edited string back into the `Value` union.
        fn saveChanges(table: *Self) void {
            switch (table.current_value.*) {
                .string => |v_op| if (v_op) |v| {
                    arena_allocator.free(v);
                    table.current_value.* = .{ .string = arena_allocator.dupe(u8, table.current_value_str) catch unreachable };
                },
                .json => |v_op| if (v_op) |v| {
                    arena_allocator.free(v);
                    table.current_value.* = .{ .json = arena_allocator.dupe(u8, table.current_value_str) catch unreachable };
                },
                .int => {
                    if (table.current_value_str.len == 0) {
                        table.current_value.* = .{ .int = 0 };
                        return;
                    }
                    const parsed = std.fmt.parseInt(i64, table.current_value_str, 10) catch |err| {
                        std.log.err("Failed to parse int: {any}", .{err});
                        unreachable;
                    };
                    table.current_value.* = .{ .int = parsed };
                },
                else => {},
            }
        }

        fn close(table: *Self) void {
            table.editMode = .None;
            Vapor.arena(.scratch).free(current_tapped_id);
            current_tapped_id = "";
        }

        // =================================================================
        // Pagination
        // =================================================================

        fn prevPage(_: *Self) void {
            if (current_page == 0) return;
            current_page -= 1;
        }

        fn nextPage(table: *Self) void {
            if (current_page > table.data.len - 1) return;
            current_page += 1;
        }

        // =================================================================
        // Export
        // =================================================================

        const FileType = enum { json };

        /// Download selected rows as a JSON file.
        pub fn download(table: *Self, file_type: FileType) void {
            downloading = true;
            switch (file_type) {
                .json => {
                    var downloadable_rows = Vapor.array(DynamicRow, .persist);
                    defer downloadable_rows.deinit();

                    for (table.data) |row| {
                        const id_value = row.get(table_columns[0].name) orelse return;
                        if (table.includes(id_value.toString())) {
                            downloadable_rows.append(row) catch unreachable;
                        }
                    }

                    const content = hashMapsToJson(arena_allocator, downloadable_rows.items) catch unreachable;
                    defer arena_allocator.free(content);
                    File.downloadFile(
                        Vapor.fmtln("{s}.json", .{table.file_name}),
                        content,
                        .@"application/json",
                    );
                },
            }
        }

        pub fn hashMapsToJson(allocator: Allocator, maps: []const DynamicRow) ![]u8 {
            var out = std.Io.Writer.Allocating.init(allocator);
            defer out.deinit();

            var jw = std.json.Stringify{
                .writer = &out.writer,
                .options = .{ .whitespace = .indent_2 },
            };

            try jw.beginArray();
            for (maps) |map| {
                try jw.beginObject();
                var it = map.iterator();
                while (it.next()) |entry| {
                    try jw.objectField(entry.key_ptr.*);
                    try writeJsonValue(&jw, entry.value_ptr.*);
                }
                try jw.endObject();
            }
            try jw.endArray();
            return try out.toOwnedSlice();
        }

        /// Write a single `Value` into a JSON stream (used by export).
        fn writeJsonValue(jw: anytype, val: Value) !void {
            switch (val) {
                .string, .json => |v| try jw.write(v),
                .int => |v| try jw.write(v),
                .float => |v| try jw.write(v),
                .boolean => |v| try jw.write(v),
                .null => try jw.write("null"),
                .datetime => |v| try jw.write(v.?.format(Vapor.arena(.frame)) catch "Error Formatting"),
                .array => |arr| {
                    try jw.beginArray();
                    for (arr.?) |item| try writeJsonValue(jw, item);
                    try jw.endArray();
                },
            }
        }

        // =================================================================
        // Layout helpers
        // =================================================================

        fn calcBounds(table: *Self) void {
            if (table.container.getBoundingClientRect()) |rect| {
                table.container_width = rect.width;
                const available = table.container_width - table.style.checkbox_width;
                const min_width: f32 = table.style.min_column_width;
                const calculated = available / @as(f32, @floatFromInt(table_columns.len));
                table.style.column_width = if (calculated < min_width) min_width else calculated;
                table.row_width = (table.style.column_width * @as(f32, @floatFromInt(table_columns.len))) + table.style.checkbox_width;
            }
            Vapor.cycle();
        }

        fn mount(table: *Self) void {
            table.registerKeyboardNav();
        }

        fn destroy(table: *Self) void {
            table.unregisterKeyboardNav();
        }

        // =================================================================
        // Shared cell rendering (deduped from VirtualRow and Rows)
        // =================================================================

        /// Render the text/number content for a single cell `Value`.
        fn renderCellValue(table: *Self, value: *Value) void {
            const ff = table.style.font_family;
            const fs = table.style.cell_font_size;
            switch (value.*) {
                .float => |v_op| {
                    if (v_op) |v| Number(v).fontFamily(ff).fontSize(fs).ellipsis(.dot).end() else Text("Empty").fontFamily(ff).fontSize(fs).ellipsis(.dot).end();
                },
                .int => |v_op| {
                    if (v_op) |v| Number(v).fontFamily(ff).fontSize(fs).ellipsis(.dot).end() else Text("Empty").fontFamily(ff).fontSize(fs).ellipsis(.dot).end();
                },
                .string, .json => |v_op| {
                    if (v_op) |v| Text(v).fontFamily(ff).fontSize(fs).ellipsis(.dot).end() else Text("Empty").fontFamily(ff).fontSize(fs).ellipsis(.dot).end();
                },
                .datetime => |v_op| {
                    if (v_op) |v| Text(v.format(Vapor.arena(.frame)) catch "Error Formatting").fontFamily(ff).fontSize(fs).ellipsis(.dot).end() else Text("Empty").fontFamily(ff).fontSize(fs).ellipsis(.dot).end();
                },
                .boolean => |v_op| {
                    if (v_op) |v| Text(if (v) "true" else "false").fontFamily(ff).fontSize(fs).ellipsis(.dot).end() else Text("Empty").fontFamily(ff).fontSize(fs).ellipsis(.dot).end();
                },
                else => {
                    Text("Empty").fontFamily(ff).fontSize(fs).ellipsis(.dot).end();
                },
            }
        }

        /// Render the four decorative corner brackets that appear on
        /// hover/tap for a cell.
        fn renderCornerBrackets(table: *Self, is_hovered: bool) void {
            if (!table.style.show_corner_brackets) return;

            const corners = [_]struct {
                pos_fn: enum { tl, tr, bl, br },
                normal_border: [4]u8, // tblr thickness flags for non-hover
                hover_border: [4]u8, //  tblr thickness flags for hover
            }{
                .{ .pos_fn = .tl, .normal_border = .{ 0, 2, 0, 2 }, .hover_border = .{ 2, 0, 2, 0 } },
                .{ .pos_fn = .tr, .normal_border = .{ 0, 2, 2, 0 }, .hover_border = .{ 2, 0, 0, 2 } },
                .{ .pos_fn = .bl, .normal_border = .{ 2, 0, 0, 2 }, .hover_border = .{ 0, 2, 2, 0 } },
                .{ .pos_fn = .br, .normal_border = .{ 2, 0, 2, 0 }, .hover_border = .{ 0, 2, 0, 2 } },
            };

            inline for (corners) |corner| {
                const b = if (!is_hovered) corner.normal_border else corner.hover_border;
                const color: Vapor.Types.Color = if (!is_hovered) .transparent else table.style.corner_bracket_color;
                const offset: Vapor.Types.Pos = if (!is_hovered) .px(-6) else .px(-2);
                const border_val: Vapor.Types.BorderGrouped = .sharp(.tblr(b[0], b[1], b[2], b[3]), color);
                const pos = switch (corner.pos_fn) {
                    .tl => Vapor.Types.Position.tl(offset, offset, .absolute),
                    .tr => Vapor.Types.Position.tr(offset, offset, .absolute),
                    .bl => Vapor.Types.Position.bl(offset, offset, .absolute),
                    .br => Vapor.Types.Position.br(offset, offset, .absolute),
                };

                Box()
                    .pos(pos)
                    .width(.px(6))
                    .height(.px(6))
                    .border(border_val)
                    .zIndex(100)
                    .children({});
            }
        }

        /// Render a checkbox used for row and header selection.
        fn renderCheckbox(table: *Self, func: anytype, args: anytype, is_active: bool) void {
            Button(func, args)
                .ariaLabel("DynamicTable Row Checkbox")
                .width(.px(20))
                .height(.px(20))
                .cursor(.pointer)
                .duration(table.style.hover_duration)
                .hoverScale()
                .border(.solid(.all(1), if (is_active) table.style.tint else table.style.border_color, .all(table.style.border_radius)))
                .layout(.center)
                .children({
                if (is_active) {
                    Box()
                        .width(.px(14))
                        .height(.px(14))
                        .background(table.style.tint)
                        .border(.round(.transparent, .all(4)))
                        .hoverScale()
                        .layout(.center)
                        .children({});
                }
            });
        }

        /// Build the column cells for a single row. Shared between paginated
        /// and virtualized rendering paths.
        fn renderRowColumns(table: *Self, row: *DynamicRow, actual_index: usize) void {
            for (table_columns, 0..) |column, j| {
                const entry = row.getEntry(column.name) orelse {
                    std.log.err("Error getting entry {s}", .{column.name});
                    return;
                };
                const value = entry.value_ptr;
                const col_i = j + 1;
                const id = Vapor.fmtln("table-column-row-{d}-col-{d}", .{ actual_index, col_i });
                const is_hovered = std.mem.eql(u8, current_hovered_id, id) and !table.click_on_row;
                const is_tapped = std.mem.eql(u8, current_tapped_id, id) and !table.click_on_row;

                const col_box = if (!table.click_on_row) blk: {
                    const hover_transform: Vapor.Types.Transform = if (table.style.hover_translate) .{
                        .trans_y = @floatFromInt(table.style.hover_translate_amount),
                        .trans_x = @floatFromInt(table.style.hover_translate_amount),
                        .size_type = .px,
                        .type = &[_]Vapor.Types.TransformType{ .translateY, .translateX },
                    } else .{};

                    break :blk Box()
                        .onEvent(.dblclick, editRowColumn, .{ table, id, value })
                        .hover(.{
                            .background = table.style.hover_background,
                            .text_color = table.style.hover_text_color,
                            .transform = hover_transform,
                            .shadow = .card(.black),
                        })
                        .width(.px(table.style.column_width));
                } else Box().width(.px(table.style.column_width));

                const tapped_offset: f32 = if (table.style.hover_translate) @floatFromInt(table.style.hover_translate_amount) else 0;

                col_box
                    .id(id)
                    .shadow(if (is_tapped) .card(.black) else null)
                    .transform(.translate(if (is_tapped) tapped_offset else 0, if (is_tapped) tapped_offset else 0, .px))
                    .background(if (is_tapped) table.style.hover_background else .transparent)
                    .textColor(if (is_tapped) table.style.hover_text_color else null)
                    .layout(.left_center)
                    .onEvent(.pointerenter, hoverBtn, .{id})
                    .onEvent(.pointerleave, leaveBtn, .{""})
                    .border(.{ .thickness = .left(table.style.cell_divider_thickness), .color = table.style.border_color })
                    .borderStyle(table.style.cell_divider_style)
                    .duration(table.style.hover_duration)
                    .height(.px(table.style.row_height))
                    .padding(.horizontal(table.style.cell_padding_horizontal))
                    .pos(.relative)
                    .children({
                    table.renderCornerBrackets(is_hovered);
                    table.renderCellValue(value);
                });
            }
        }

        // =================================================================
        // Action menu
        // =================================================================

        fn selectAction(select: *Select(usize), item: *Select(usize).Item) void {
            const table: *Self = @alignCast(@fieldParentPtr("action_select", select));
            const row = &table.data[row_index + current_page * table.per_page];
            if (actions[item.value].on_action) |on_action| on_action(row);
        }

        pub fn ActionTrigger(_: *Select(usize)) void {
            // NOTE: Select's trigger signature doesn't give us the parent table
            // pointer, so this falls back to static defaults. If per-instance
            // action-trigger styling is needed, this would require extending
            // the Select API.
            const default_style = TableStyle{};
            Box()
                .width(.px(24))
                .height(.px(24))
                .cursor(.pointer)
                .background(.white)
                .hover(.{
                    .background = default_style.tint,
                    .text_color = default_style.checkbox_icon_color,
                })
                .font(14, 300, default_style.text_color)
                .duration(default_style.hover_duration)
                .border(.round(.transparent, .all(4)))
                .layout(.center)
                .children({
                Vapor.Icon(.three_dots).font(16, 300, null).end();
            });
        }

        // =================================================================
        // Hover state helpers
        // =================================================================

        fn hoverBtn(id: []const u8, _: *Vapor.Event) void {
            current_hovered_id = id;
        }

        fn leaveBtn(_: []const u8, _: *Vapor.Event) void {
            current_hovered_id = "";
        }

        // =================================================================
        // Virtualized row renderer (used by VirtualList)
        // =================================================================

        fn VirtualRow(row: *DynamicRow, i: usize, ctx: ?*anyopaque) void {
            if (ctx == null) return;
            const table: *Self = @ptrCast(@alignCast(ctx));
            const id_value = row.get(table_columns[0].name) orelse return;
            const is_selected = table.includes(id_value.toString());

            Box()
                .border(.{ .thickness = .tblr(0, table.style.cell_divider_thickness, 0, 0), .color = table.style.border_color })
                .height(.px(table.style.row_height))
                .width(.px(table.row_width))
                .inlineStyle("min-width: 600px", .{})
                .children({
                Box()
                    .border(.{ .thickness = .tblr(0, 0, table.style.cell_divider_thickness, table.style.cell_divider_thickness), .color = table.style.border_color })
                    .borderStyle(table.style.cell_divider_style)
                    .width(.percent(100))
                    .height(.px(table.style.row_height))
                    .layout(.left_center).children({
                    // Checkbox
                    Box()
                        .a11y(Vapor.Accessibility.init().setRole(.grid_cell))
                        .padding(.horizontal(table.style.cell_padding_horizontal))
                        .width(.px(table.style.checkbox_width))
                        .children({
                        table.renderCheckbox(selectRow, .{ table, row }, is_selected);
                    });
                    // Columns
                    Box()
                        .width(.px(table.row_width))
                        .layout(.left_center).children({
                        table.renderRowColumns(row, i);
                    });
                    // Action spacer
                    Box()
                        .a11y(Vapor.Accessibility.init().setRole(.grid_cell))
                        .width(.percent(table.style.action_width))
                        .layout(.right_center)
                        .height(.px(24))
                        .children({});
                });
            });
        }

        // =================================================================
        // Paginated / all row rendering
        // =================================================================

        fn Rows(table: *Self) void {
            if (table.filtered_data.items.len == 0) {
                Box().width(.percent(100)).padding(.vertical(48)).layout(.center).children({
                    Stack().layout(.center).spacing(8).width(.percent(100)).children({
                        Text("No results found").font(14, 400, table.style.icon_color).end();
                    });
                });
                return;
            }

            const items_to_render = switch (table.display_mode) {
                .paginated => blk: {
                    const start = current_page * table.per_page;
                    const end = @min(start + table.per_page, table.filtered_data.items.len);
                    break :blk table.filtered_data.items[start..end];
                },
                .all => table.data,
                else => {
                    Vapor.printErr("Error: called Rows() in virtual mode", .{});
                    unreachable;
                },
            };

            Stack()
                .width(.px(table.row_width))
                .height(.px(@as(f32, @floatFromInt(table.per_page)) * table.style.row_height))
                .spacing(if (table.row_spacing) |sp| sp else 0)
                .a11y(Vapor.Accessibility.init().setRole(.row_group))
                .height(.grow)
                .pos(.relative)
                .children({
                // Close-overlay for edit mode
                if (table.editMode == .Editing) {
                    Button(close, .{table})
                        .pos(.tl(.px(0), .percent(0), .fixed))
                        .size(.full)
                        .zIndex(999)
                        .children({});
                } else Vapor.Null();

                // Inline edit text-area popup
                Stack()
                    .pos(.tl(.px(0), .percent(0), .absolute))
                    .zIndex(1000)
                    .inlineStyle("transform: translate({d}px, {d}px)", .{ table.x - 4, table.y - 4 })
                    .children({
                    if (table.editMode == .Editing) {
                        Vapor.HooksCtx(.mounted, mountTextArea, .{table})({
                            table.renderEditPopup();
                        });
                    }
                });

                // Data rows
                for (items_to_render, 0..) |*row, i| {
                    const actual_index = current_page * table.per_page + i;
                    const is_focused_row = table.focused_row == actual_index;
                    const id_value = row.get(table_columns[0].name) orelse return;
                    const is_selected = table.includes(id_value.toString());

                    const box = if (table.click_on_row) blk: {
                        break :blk Box()
                            .onEventCtx(.dblclick, onRowClick, .{ table, row })
                            .pointer()
                            .border(.{ .thickness = .tblr(0, table.style.cell_divider_thickness, 0, 0), .color = table.style.border_color })
                            .hover(.{ .background = table.style.hover_background, .text_color = table.style.hover_text_color });
                    } else blk: {
                        break :blk Box().border(.{ .thickness = .tblr(0, table.style.cell_divider_thickness, 0, 0), .color = table.style.border_color });
                    };

                    box
                        .a11y(Vapor.Accessibility.init()
                            .setRole(.row)
                            .setRowIndex(@intCast(actual_index + 1))
                            .setSelected(is_selected))
                        .height(.px(table.style.row_height))
                        .width(.px(table.row_width))
                        .inlineStyle("min-width: 600px", .{})
                        .children({
                        Box()
                            .border(.{ .thickness = .tblr(0, 0, table.style.cell_divider_thickness, table.style.cell_divider_thickness), .color = table.style.border_color })
                            .borderStyle(table.style.cell_divider_style)
                            .width(.percent(100))
                            .height(.px(table.style.row_height))
                            .layout(.left_center).children({
                            // Checkbox
                            Box()
                                .a11y(Vapor.Accessibility.init().setRole(.grid_cell))
                                .padding(.horizontal(table.style.cell_padding_horizontal))
                                .tabIndex(if (is_focused_row and table.focused_col == 0) 0 else -1)
                                .width(.px(table.style.checkbox_width))
                                .children({
                                table.renderCheckbox(selectRow, .{ table, row }, is_selected);
                            });
                            // Columns
                            Box()
                                .width(.px(table.row_width - table.style.checkbox_width))
                                .layout(.left_center).children({
                                table.renderRowColumns(row, actual_index);
                            });
                        });
                    });
                }
            });
        }

        // =================================================================
        // Edit popup widget
        // =================================================================

        fn renderEditPopup(table: *Self) void {
            Stack()
                .background(table.style.edit_popup_background)
                .border(.sharp(.all(1), table.style.edit_popup_border_color))
                .width(.px(table.style.column_width))
                .height(.px(table.style.column_width))
                .layout(.y_between)
                .shadow(.card(.black))
                .textColor(.white)
                .transformOrigin(.top_center)
                .animationEnter("opaque-table-textarea-enter")
                .animationExit("opaque-table-textarea-exit")
                .children({
                Vapor.TextArea()
                    .ref(&table.text_area)
                    .padding(.all(8))
                    .resize(.none)
                    .width(.percent(100))
                    .height(.grow)
                    .border(.none)
                    .outline(.none, null)
                    .fontFamily(table.style.font_family)
                    .font(16, 300, table.style.text_color)
                    .bind(&table.current_value_str)
                    .background(table.style.edit_popup_background)
                    .end();
                Box()
                    .background(table.style.edit_popup_background)
                    .width(.percent(100))
                    .border(.top(1, table.style.border_color))
                    .padding(.all(8))
                    .spacing(16)
                    .layout(.left_center)
                    .zIndex(1000)
                    .children({
                    table.renderKeyHint(saveChanges, null, "to save");
                    table.renderKeyHint(saveChanges, null, "to dismiss");
                });
            });
        }

        /// Render a "⏎ to save" / "esc to dismiss" hint button.
        fn renderKeyHint(table: *Self, action: anytype, _: ?*const Vapor.IconTokens, label: []const u8) void {
            Button(action, .{table})
                .layout(.left_center)
                .spacing(8)
                .children({
                Box()
                    .center()
                    .border(table.style.border)
                    .background(table.style.background)
                    .height(.px(26))
                    .width(.px(36))
                    .newShadow(Vapor.Types.NewShadow.init().inset(0, -2, .transparentizeHex(.black, 0.3)))
                    .children({
                    if (std.mem.eql(u8, label, "to save")) {
                        Vapor.Svg(.{ .svg = save_icon })
                            .fill(table.style.text_color)
                            .size(.px(16))
                            .end();
                    } else {
                        Text("esc").font(14, 300, table.style.text_color).fontFamily(table.style.font_family).end();
                    }
                });
                Text(label).font(14, 300, table.style.text_color).fontFamily(table.style.font_family).end();
            });
        }

        // =================================================================
        // Search / filter UI widgets
        // =================================================================

        fn CommonFilter(table: *Self) Vapor.Builder(.pure) {
            return Stack()
                .animationEnter("opaque-table-filter-enter")
                .animationExit("opaque-table-filter-exit")
                .width(.percent(100))
                .layout(.center)
                .background(table.style.background)
                .height(.fit)
                .border(.round(table.style.border_color, .all(table.style.border_radius)))
                .shadow(.{
                .top = 4,
                .spread = 2,
                .blur = 6,
                .color = .transparentizeHex(.black, 0.05),
            });
        }

        fn Search(table: *Self) void {
            table.CommonFilter().children({
                Vapor.HooksCtx(.mounted, mountSearchBox, .{table})({
                    Box().width(.percent(100)).padding(.all(4)).pointer().layout(.x_between_center).children({
                        Box()
                            .border(.round(.transparent, .all(table.style.border_radius)))
                            .width(.px(32)).height(.px(32))
                            .background(table.style.tint).layout(.center)
                            .children({
                            Vapor.Svg(.{ .svg = search_icon })
                                .fill(table.style.checkbox_icon_color)
                                .size(.px(16))
                                .end();
                        });
                        TextField(.string)
                            .ref(&search_box)
                            .placeholder("Filter...")
                            .width(.grow).border(.none)
                            .padding(.horizontal(12)).outline(.none, null)
                            .fontFamily(table.style.font_family).background(.transparent)
                            .font(16, 300, table.style.icon_color)
                            .val(&search_box.text)
                            .onEventCtx(.input, search, .{table})
                            .end();
                        Button(clearText, .{table})
                            .ariaLabel("Search Filter")
                            .background(.transparent).pointer().padding(.all(4))
                            .children({
                            Vapor.Svg(.{ .svg = x_lg })
                                .fill(table.style.icon_color)
                                .size(.px(16))
                                .end();
                        });
                    });
                });
            });
        }

        fn mountSearchBox(_: *Self) void {
            search_box.focus();
        }

        fn handleFilter(table: *Self, comptime FT: type, value: FT) void {
            const text = fieldToString(value);
            if (enum_filters.get(text)) |_| {
                if (!enum_filters.remove(text)) Vapor.printErr("Failed to remove filter", .{});
            } else {
                _ = enum_filters.put(text, {}) catch unreachable;
            }
            table.applyFilters();
        }

        fn FilterSelect(table: *Self, comptime FT: type, comptime values: []const FT) void {
            table.CommonFilter().padding(.all(4)).spacing(8).children({
                for (values) |value| {
                    const active = enum_filters.get(fieldToString(value)) != null;
                    Button(handleFilter, .{ table, FT, value })
                        .ariaLabel("Select Filter")
                        .width(.percent(100)).height(.px(36))
                        .background(if (active) table.style.tint else .transparent)
                        .pointer().layout(.left_center).duration(table.style.hover_duration)
                        .hover(.{ .background = table.style.tint, .text_color = table.style.checkbox_icon_color })
                        .padding(.tblr(6, 6, 6, 24))
                        .border(.round(.transparent, .all(table.style.border_radius)))
                        .font(14, 300, if (active) table.style.checkbox_icon_color else table.style.text_color)
                        .children({
                        Text(value).fontFamily(table.style.font_family).end();
                    });
                }
            });
        }

        // =================================================================
        // Pagination widget
        // =================================================================

        fn Pagination(table: *Self) void {
            if (table.filtered_data.items.len == 0) return;
            const page_count: f32 = @floatFromInt(@divTrunc(table.filtered_data.items.len, table.per_page) + 1);
            const float_page: f32 = @floatFromInt(current_page);

            Box()
                .a11y(Vapor.Accessibility.init().setRole(.navigation).setLabel("DynamicTable pagination"))
                .width(.percent(100))
                .layout(.x_between_center)
                .padding(.tblr(8, 8, 18, 18))
                .height(.px(table.style.row_height))
                .spacing(8)
                .pos(.relative)
                .children({
                Box().a11y(.liveRegion(.polite)).children({
                    TextFmt("Page {d} of {d}", .{ current_page + 1, page_count }).end();
                });
                Box()
                    .pos(.tl(.percent(90), .percent(60), .absolute))
                    .width(.percent(60)).height(.px(32))
                    .layer(.dot(2, 12, table.style.text_color))
                    .children({});
                Box().spacing(16).children({
                    if (float_page > 0) {
                        Button(prevPage, .{table})
                            .ariaLabel("Go to previous page")
                            .background(.transparent).cursor(.pointer)
                            .children({
                            Vapor.Svg(.{ .svg = chevron_left })
                                .fill(table.style.icon_color)
                                .size(.px(16))
                                .end();
                        });
                    }
                    if (float_page < page_count - 1) {
                        Button(nextPage, .{table})
                            .ariaLabel("Go to next page")
                            .background(.transparent).cursor(.pointer)
                            .children({
                            Vapor.Svg(.{ .svg = chevron_right })
                                .fill(table.style.icon_color)
                                .size(.px(16))
                                .end();
                        });
                    }
                });
            });
        }

        // =================================================================
        // Main render entry point
        // =================================================================

        /// Render the full table widget: header, rows, and pagination.
        pub fn render(table: *Self) void {
            if (table_columns.len == 0) return;

            const height: Vapor.Types.Sizing = if (table.display_mode != .virtual)
                .px(@as(f32, @floatFromInt(table.per_page)) * table.style.row_height)
            else
                .expand;

            Stack()
                .width(.expand)
                .ref(&table.container)
                .height(.expand)
                .children({
                Stack()
                    .height(height)
                    .scroll(.{ .y = .hidden, .x = .scroll })
                    .a11y(Vapor.Accessibility.init()
                        .setRole(.grid)
                        .setLabel(table.file_name)
                        .setActiveDescendant(if (table.focused_row) |row|
                        Vapor.fmtln("row-{d}-col-{d}", .{ row, table.focused_col orelse 0 })
                    else
                        null))
                    .tabIndex(0)
                    .children({
                    Stack()
                        .height(height)
                        .width(.px(table.row_width))
                        .children({
                        // ── Header ────────────────────────────────────────
                        Box()
                            .width(if (table_columns.len == 0) .percent(100) else .px(table.row_width))
                            .border(.lr(table.style.border_color))
                            .borderStyle(table.style.outer_border_style)
                            .pos(.relative)
                            .children({
                            Box()
                                .a11y(Vapor.Accessibility.init().setRole(.row_group))
                                .width(if (table_columns.len == 0) .percent(100) else .px(table.row_width))
                                .height(.px(table.style.row_height))
                                .layout(.x_between_center)
                                .children({
                                Box()
                                    .a11y(Vapor.Accessibility.init().setRole(.row))
                                    .height(.px(table.style.row_height))
                                    .width(.percent(100))
                                    .border(.tb(table.style.border_color))
                                    .inlineStyle("min-width: 600px", .{})
                                    .children({
                                    Box().width(.percent(100)).height(.px(table.style.row_height)).layout(.x_between_center).children({
                                        // Select-all checkbox
                                        Box()
                                            .padding(.horizontal(table.style.cell_padding_horizontal))
                                            .a11y(Vapor.Accessibility.init().setRole(.column_header))
                                            .width(.px(table.style.checkbox_width))
                                            .children({
                                            const all_active = table.selection_mode == .all;
                                            Button(selectAll, .{table})
                                                .ariaLabel("DynamicTable Row Checkbox")
                                                .width(.px(20)).height(.px(20))
                                                .cursor(.pointer).duration(table.style.hover_duration).hoverScale()
                                                .a11y(Vapor.Accessibility.checkbox(all_active).setLabel("Select all"))
                                                .border(.solid(.all(1), if (all_active) table.style.tint else table.style.border_color, .all(table.style.border_radius)))
                                                .layout(.center)
                                                .children({
                                                if (all_active) {
                                                    Box()
                                                        .width(.px(14)).height(.px(14))
                                                        .background(table.style.tint)
                                                        .border(.round(.transparent, .all(4)))
                                                        .hoverScale().layout(.center).children({});
                                                }
                                            });
                                        });
                                        // Column headers
                                        Box().width(.px(table.row_width - table.style.checkbox_width)).height(.px(table.style.row_height)).layout(.left_center).children({
                                            for (table_columns, 0..) |column, i| {
                                                Box()
                                                    .a11y(Vapor.Accessibility.init().setRole(.column_header).setLabel(column.name))
                                                    .ref(&binded_cols[i])
                                                    .border(.{ .thickness = .left(table.style.cell_divider_thickness), .color = table.style.border_color })
                                                    .borderStyle(table.style.cell_divider_style)
                                                    .width(.px(table.style.column_width))
                                                    .height(.px(table.style.row_height))
                                                    .layout(.left_center)
                                                    .padding(.horizontal(table.style.cell_padding_horizontal))
                                                    .spacing(4)
                                                    .children({
                                                    Text(column.name).fontFamily(table.style.font_family).font(table.style.header_font_size, table.style.header_font_weight, null).end();
                                                    Text(@tagName(column.type)).fontFamily(table.style.font_family).font(table.style.header_font_size, table.style.header_font_weight, table.style.text_color_muted).end();
                                                });
                                            }
                                        });
                                    });
                                });
                            });
                        });
                        // ── Body ─────────────────────────────────────────
                        if (table.display_mode == .virtual) {
                            virtual_list.renderWithCtx(@ptrCast(table));
                        } else {
                            table.Rows();
                        }
                    });
                });
                // ── Footer / pagination ──────────────────────────────────
                if (table.display_mode != .virtual) {
                    table.Pagination();
                }
            });

            // Lifecycle hooks
            Vapor.HooksCtx(.mounted, mount, .{table})({
                Vapor.HooksCtx(.destroy, destroy, .{table})({});
            });
        }
    };
}
