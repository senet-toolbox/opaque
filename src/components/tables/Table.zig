///! DynamicTable.zig
///!
///! A generic, data-driven table component built on the Vapor UI framework.
///!
///! Features:
///!   - Dynamic columns defined at comptime via `Column(T)` descriptors
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
///!   const cols = &[_]Column(T){
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
    font_family: []const u8 = "Montserrat, sans-serif",
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
    tint: Vapor.Types.Color = .transparentize(.palette(.tint), 0.8),
    checkbox_icon_color: Vapor.Types.Color = .white,

    // Hover / tapped cell highlight colors
    hover_background: Vapor.Types.Color = .palette(.tint),
    hover_text_color: Vapor.Types.Color = .white,
    corner_bracket_color: Vapor.Types.Color = .hex("#222160"),

    // Edit popup
    edit_popup_background: Vapor.Types.Color = .white,
    edit_popup_border_color: Vapor.Types.Color = .transparentize(.black, 0.2),

    // ── Borders ──────────────────────────────────────────────────────────
    border: Vapor.Types.Border = .round(.transparentize(.black, 0.2), .all(6)),
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
    animateEnter.build();
    animateExit.build();
    animateTextArea.build();
    animateTextAreaExit.build();
}
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
        icon: ?Vapor.IconTokens = null,
        on_action: ?*const fn (item: *T) void = null,
    };
}

/// Wraps a `T` with UI-specific metadata.
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
///   - `columns`:  comptime slice of `Column(T)` that defines every visible
///                 column. The *first* column is treated as the row ID for
///                 selection tracking.
///   - `config`:   optional `.actions` slice for per-row action menus, and
///                 an optional `.default_style` override for the table's
///                 initial `TableStyle`.
pub fn Table(
    comptime T: type,
    comptime columns: []const Column(T),
    config: struct {
        actions: ?[]const Action(T) = null,
        default_style: TableStyle = .{},
    },
) type {
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

    const SelectType = Select(usize);

    // How many (and which) rows are currently selected.
    const SelectionMode = enum { none, some, all, all_except };

    const EditMode = enum { None, Editing, ContextMenu };

    const Act =
        ?*const fn (Column(T)) void;

    return struct {
        const Self = @This();

        const ContextMenu = struct {
            visible: bool = false,
            x: f32 = 0,
            y: f32 = 0,
            selected_row: ?T = null,
            copied: bool = false,
        };

        const table_columns: []const Column(T) = columns;
        context_menu: ContextMenu = .{},

        // ── Instance fields ──────────────────────────────────────────────
        data: []T = undefined,
        filtered_data: Vapor.Array(T) = undefined,
        per_page: usize = 10,
        selection_mode: SelectionMode = .none,
        selection_set: std.HashMap(IdType, void, DynamicTableContext(IdType), std.hash_map.default_max_load_percentage) = undefined,
        file_name: []const u8 = "content",
        display_mode: DisplayMode = .paginated,
        show_id_column: bool = false,
        on_select: ?*const fn (item: *T) void = null,
        on_select_all: ?*const fn () void = null,
        action_select: ?SelectType = null,
        active_column: ?Column(T) = null,
        show_actions: bool = false,

        /// Per-instance styling. Mutate directly after `init()` to customize
        /// this specific table without affecting others of the same type.
        style: TableStyle = config.default_style,

        focused_row: ?usize = null,
        focused_col: ?usize = null,
        table_id: []const u8 = "data-table",
        total_width_percent: f32 = 100,
        row_background: ?Vapor.Types.Color = null,
        row_border: ?Vapor.Types.Border = null,
        row_spacing: ?u8 = null,
        x: f32 = 0,
        y: f32 = 0,
        edit_x: f32 = 0,
        edit_y: f32 = 0,
        current_value: *T = undefined,
        current_value_str: []const u8 = "",
        editMode: EditMode = .None,
        text_area: Vapor.Element = .{ .element_type = .TextArea },
        container: Vapor.Element = .{},
        clickable: bool = true,
        on_item_click: ?*const fn (*T) void = null,
        on_row_click: ?*const fn (*T) void = null,
        click_on_row: bool = false,
        on_edit_column: ?*const fn (Column(T)) void = null,

        // Per-instance (previously global) layout state
        row_width: f32 = 256,
        container_width: f32 = 256,

        // table_columns: []const Column(T) = columns,

        // ── Comptime / shared state ──────────────────────────────────────
        arena_allocator: std.mem.Allocator = undefined,
        arena: std.heap.ArenaAllocator = undefined,
        actions: []const Action(T) = config.actions orelse &.{},

        binded_cols: []Vapor.Element = &.{},
        search_box: Vapor.Element = .{},
        show_search: bool = false,
        show_filter: bool = false,
        clicked_index: usize = 0,
        /// The column the rows are sorted by, and which way.
        sort_key: ?[]const u8 = null,
        sort_dir: Sort = .none,
        active_filters: []?[]const u8 = &.{},
        enum_filters: std.StringHashMap(void) = undefined,

        search_top: f32 = 0,
        search_right: f32 = 0,
        filter_top: f32 = 0,
        filter_right: f32 = 0,
        current_page: usize = 0,

        downloading: bool = false,
        virtual_list: VirtualList(T) = undefined,
        row_index: usize = 0,
        current_hovered_id: []const u8 = "",
        current_tapped_id: []const u8 = "",

        // =================================================================
        // Lifecycle
        // =================================================================

        /// Initialise the table with an initial data slice. Allocates internal
        /// bookkeeping (rows, filters, binded-column refs) from a dedicated
        /// arena so the table can be regenerated cheaply.
        pub fn init(table: *Self, data: []T) void {
            table.* = .{};
            table.arena = std.heap.ArenaAllocator.init(Vapor.lib.allocator_global);
            table.arena_allocator = table.arena.allocator();

            table.active_filters = table.arena_allocator.alloc(?[]const u8, table_columns.len) catch |err| blk: {
                Vapor.print(.err, "Failed to allocate active_filters: {any}", .{err});
                break :blk &.{};
            };
            @memset(table.active_filters, null);

            table.allocBindedCols();
            table.enum_filters = std.StringHashMap(void).init(table.arena_allocator);

            table.data = data;
            table.filtered_data = Vapor.array(T, .persist);
            table.selection_set = std.HashMap(IdType, void, DynamicTableContext(IdType), 80).init(table.arena_allocator);
            table.row_width = table.computeRowWidth();

            table.search_box.init(table.arena_allocator);
            initActions(table);
            table.filtered_data.appendSlice(data[0..]) catch unreachable;
            initVirtualList(table);
            // Vapor.onLayout(calcBounds, .{table});
        }

        pub fn ColumnTrigger(_: *Select(Act)) void {
            // NOTE: Select's trigger signature doesn't give us the parent table
            // pointer, so this falls back to static defaults. If per-instance
            // action-trigger styling is needed, this would require extending
            // the Select API.
            const default_style = TableStyle{};
            Box()
                .width(.px(24))
                .height(.px(24))
                .cursor(.pointer)
                .background(default_style.background)
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

        /// Replace columns and data entirely. Reuses the existing arena by
        /// resetting it (avoids reallocation in the common case).
        pub fn regenerate(table: *Self, new_columns: []const Column(T), data: []T) void {
            if (!table.arena.reset(.retain_capacity)) std.log.err("Failed to reset arena", .{});
            table_columns = new_columns;
            table.current_hovered_id = "";
            table.current_tapped_id = "";

            table.allocBindedCols();
            table.row_width = table.computeRowWidth();
            table.enum_filters = std.StringHashMap(void).init(table.arena_allocator);

            table.active_filters = table.arena_allocator.alloc(?[]const u8, table_columns.len) catch |err| blk: {
                Vapor.print(.err, "Failed to allocate active_filters: {any}", .{err});
                break :blk &.{};
            };
            @memset(table.active_filters, null);

            table.data = data;
            table.filtered_data = Vapor.array(T, .persist);

            table.search_box.init(table.arena_allocator);
            initActions(table);
            table.filtered_data.appendSlice(data[0..]) catch unreachable;
            initVirtualList(table);

            // Vapor.onLayout(calcBounds, .{table});
        }

        /// Re-apply current filters after external data mutation.
        pub fn refresh(table: *Self) void {
            table.filtered_data.clearRetainingCapacity();
            table.filtered_data.appendSlice(table.data[0..]) catch unreachable;
            table.applyFilters();
        }

        /// Delete a row by its primary ID (the first configured column).
        /// Returns true when a row was found and removed.
        pub fn delete(table: *Self, id: IdType) bool {
            const delete_index = table.indexOfId(id) orelse return false;

            var new_data = table.arena_allocator.alloc(T, table.data.len - 1) catch |err| {
                Vapor.print(.err, "Failed to allocate table data after delete: {any}", .{err});
                return false;
            };

            var write_index: usize = 0;
            for (table.data, 0..) |row, read_index| {
                if (read_index == delete_index) continue;
                new_data[write_index] = row;
                write_index += 1;
            }

            table.data = new_data;
            _ = table.selection_set.remove(id);
            table.normalizeSelection();
            table.refresh();
            table.clampCurrentPage();
            initVirtualList(table);
            return true;
        }

        // =================================================================
        // Internal init helpers (deduped from init / regenerate)
        // =================================================================

        fn allocBindedCols(table: *Self) void {
            table.binded_cols = table.arena_allocator.alloc(Vapor.Element, table_columns.len) catch |err| blk: {
                Vapor.print(.err, "Failed to allocate binded cols: {any}", .{err});
                break :blk &.{};
            };
            @memset(table.binded_cols, Vapor.Element{});
        }

        fn computeRowWidth(table: *Self) f32 {
            return table.style.column_width * @as(f32, @floatFromInt(table_columns.len)) + table.style.checkbox_width;
        }

        fn initActions(table: *Self) void {
            if (config.actions) |c_actions| {
                table.actions = c_actions;
                var items = table.arena_allocator.alloc(Select(usize).Item, table.actions.len) catch unreachable;
                for (table.actions, 0..) |action, i| {
                    items[i] = .{ .value = i, .label = action.label, .icon = action.icon };
                }
                table.action_select = .fromItems(items);
                table.action_select.?.render_trigger = false;
                table.action_select.?.trigger_component = ActionTrigger;
                table.action_select.?.trigger_label = "Row actions";
                table.action_select.?.on_select = selectAction;
            }
        }

        fn initVirtualList(table: *Self) void {
            table.virtual_list = VirtualList(T).init(.{
                .data = table.data,
                .render_ctx = VirtualRow,
                .item_height = .px(table.style.row_height),
                .item_width = .percent(table.row_width),
                .buffer_size = 5,
                .container_height = @as(f32, @floatFromInt(table.per_page)) * table.style.row_height,
            });
        }

        fn indexOfId(table: *Self, id: IdType) ?usize {
            if (table_columns.len == 0) return null;
            const id_column = table_columns[0].name;
            for (table.data, 0..) |row, i| {
                const value = row.get(id_column) orelse continue;
                if (std.mem.eql(u8, value.toString(), id)) return i;
            }
            return null;
        }

        fn clampCurrentPage(table: *Self) void {
            if (table.per_page == 0 or table.filtered_data.items.len == 0) {
                table.current_page = 0;
                return;
            }

            const last_page = (table.filtered_data.items.len - 1) / table.per_page;
            if (table.current_page > last_page) table.current_page = last_page;
        }

        fn normalizeSelection(table: *Self) void {
            if (table.data.len == 0) {
                table.selection_mode = .none;
                table.selection_set.clearRetainingCapacity();
                return;
            }

            switch (table.selection_mode) {
                .none, .all => {},
                .some => {
                    if (table.selection_set.count() == 0) {
                        table.selection_mode = .none;
                    } else if (table.selection_set.count() >= table.data.len) {
                        table.selection_mode = .all;
                        table.selection_set.clearRetainingCapacity();
                    }
                },
                .all_except => {
                    if (table.selection_set.count() == 0) {
                        table.selection_mode = .all;
                    } else if (table.selection_set.count() >= table.data.len) {
                        table.selection_mode = .none;
                        table.selection_set.clearRetainingCapacity();
                    }
                },
            }
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
                    // table.saveChanges();
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
        fn selectRow(table: *Self, row: *T) void {
            const id = row.id;

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
            table.clicked_index = column_index;
            table.active_filters[table.clicked_index] = if (search_query.len > 0) search_query else null;
            table.applyFilters();
        }

        fn search(table: *Self, evt: *Vapor.Event) void {
            table.search_box.setText(evt.text());
            table.active_filters[table.clicked_index] = if (table.search_box.text.len > 0) table.search_box.text else null;
            table.applyFilters();
        }

        fn clearText(table: *Self) void {
            table.search_box.text = "";
            table.active_filters[table.clicked_index] = null;
            table.applyFilters();
        }

        fn applyFilters(table: *Self) void {
            table.filtered_data.clearRetainingCapacity();
            for (table.data) |item| {
                var matches = true;

                inline for (columns, 0..) |col, i| {
                    // 1. Check text search (Existing logic)
                    if (table.active_filters[i]) |filter_text| {
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
                                        if (table.enum_filters.get(val_str) != null) {
                                            is_filtering_this_col = true;
                                            break;
                                        }
                                    }

                                    // Only filter the row if the user has actually selected a filter
                                    // relevant to THIS specific column
                                    if (is_filtering_this_col) {
                                        if (!table.matchesFilter(col.key, item)) {
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

        fn matchesSearch(comptime key: []const u8, item: T, query: []const u8) bool {
            if (query.len == 0) return true;

            const value = @field(item, key);
            const value_str = fieldToString(value);

            return std.ascii.indexOfIgnoreCase(value_str, query) != null;
        }

        fn matchesFilter(table: *Self, comptime key: []const u8, item: T) bool {
            const value = @field(item, key);
            const value_str = fieldToString(value);
            return table.enum_filters.get(value_str) != null;
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
                        else => Vapor.print(.err, "Sorting not supported for {any}", .{@typeInfo(@TypeOf(val1))}),
                    };
                }
            }.compare;
        }

        /// Sorts by `key`: in its column's direction the first time, then the
        /// other way on each click after.
        fn sortColumn(self: *Self, sort_type: Sort, comptime key: []const u8) void {
            const same = if (self.sort_key) |k| std.mem.eql(u8, k, key) else false;
            const dir: Sort = if (same) switch (self.sort_dir) {
                .asc => .desc,
                .desc => .asc,
                .none => sort_type,
            } else sort_type;
            self.sort_key = key;
            self.sort_dir = dir;
            std.mem.sort(T, self.filtered_data.items, dir, makeSortFn(key));
        }

        /// Which way the rows are sorted by `key`, if they are.
        fn sortedBy(self: *const Self, key: []const u8) Sort {
            const k = self.sort_key orelse return .none;
            return if (std.mem.eql(u8, k, key)) self.sort_dir else .none;
        }

        fn toggleSearch(table: *Self, index: usize) void {
            if (table.clicked_index == index and table.show_search) {
                table.show_search = false;
            } else {
                table.show_search = true;
                table.clicked_index = index;
                table.search_box.text = table.active_filters[index] orelse "";
            }
            const bounds = table.binded_cols[index].getOffsets() orelse return;
            table.search_top = bounds.offset_top + bounds.offset_height;
            table.search_right = bounds.offset_left;
        }

        fn toggleFilter(table: *Self, index: usize) void {
            // If clicking same column, toggle. If different column, switch to it.
            if (table.clicked_index == index and table.show_filter) {
                table.show_filter = false;
            } else {
                table.show_filter = true;
                table.clicked_index = index;
            }

            const bounds = table.binded_cols[index].getOffsets() orelse return;
            table.filter_top = bounds.offset_top + bounds.offset_height;
            table.filter_right = bounds.offset_left;
        }

        fn onRowClick(table: *Self, row: *T, _: *Vapor.Event) void {
            if (table.on_row_click) |cb| cb(row);
        }

        fn mountTextArea(table: *Self) void {
            table.text_area.focus();
        }

        fn close(table: *Self) void {
            table.editMode = .None;
            table.current_tapped_id = "";
        }

        // =================================================================
        // Pagination
        // =================================================================

        fn prevPage(table: *Self) void {
            if (table.current_page == 0) return;
            table.current_page -= 1;
        }

        fn nextPage(table: *Self) void {
            if (table.current_page > table.data.len - 1) return;
            table.current_page += 1;
        }

        // =================================================================
        // Export
        // =================================================================

        const FileType = enum { json };

        // =================================================================
        // Layout helpers
        // =================================================================

        pub fn calcBounds(table: *Self, entry: Vapor.Kit.ResizeEntry) void {
            table.container_width = entry.width;
            const available = table.container_width - table.style.checkbox_width;
            const min_width: f32 = table.style.min_column_width;
            const calculated = available / @as(f32, @floatFromInt(table_columns.len));
            table.style.column_width = if (calculated < min_width) min_width else calculated;
            table.row_width = (table.style.column_width * @as(f32, @floatFromInt(table_columns.len))) + table.style.checkbox_width;
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
        fn renderCellValue(table: *Self, value: *T) void {
            const ff = table.style.font_family;
            const fs = table.style.cell_font_size;
            switch (@typeInfo(@TypeOf(value))) {
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

        /// Render a checkbox used for row and header selection.
        fn renderCheckbox(table: *Self, func: anytype, args: anytype, is_active: bool) void {
            Button(func, args)
                .a11y(Vapor.Accessibility.checkbox(is_active).setLabel("Select row"))
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
        fn renderRowColumns(table: *Self, row: *T, actual_index: usize) void {
            inline for (table_columns, 0..) |column, j| {
                const name = column.key;
                const value = @field(row, name);

                const col_i = j + 1;
                const id = Vapor.fmtln("table-column-row-{d}-col-{d}", .{ actual_index, col_i });
                _ = id;

                Box()
                    .width(.px(table.style.column_width))
                    // .id(id)
                    .layout(.x_between_center)
                    .border(.{ .thickness = .{ .left = table.style.cell_divider_thickness }, .color = table.style.border_color })
                    .borderStyle(table.style.cell_divider_style)
                    .height(.px(table.style.row_height))
                    .padding(.horizontal(table.style.cell_padding_horizontal))
                    .inlineStyle("user-select: none;", .{})
                    .pos(.relative)
                    .children({
                    const ff = table.style.font_family;
                    const fs = table.style.cell_font_size;

                    switch (@typeInfo(@TypeOf(value))) {
                        .float, .int => Number(value).fontFamily(ff).fontSize(fs).ellipsis(.dot).end(),
                        .@"enum" => Text(@tagName(value))
                            .fontFamily(ff).fontSize(fs)
                            .ellipsis(.dot)
                            .end(),
                        .pointer => |ptr| {
                            if (ptr.size == .slice) {
                                Text(value).fontFamily(ff).fontSize(fs).ellipsis(.dot).end();
                            }
                        },
                        .@"struct" => {
                            if (@TypeOf(value) == Vapor.DateTime) {
                                const date = value.format(Vapor.arena(.frame)) catch "Error Formatting";
                                Text(date)
                                    .fontFamily(ff).fontSize(fs)
                                    .ellipsis(.dot)
                                    .end();
                            }
                        },
                        else => {
                            Vapor.print(.err, "Type {any} not supported", .{@TypeOf(value)});
                        },
                    }

                    if (table_columns.len - 1 == j) {
                        Box()
                            .a11y(Vapor.Accessibility.init().setRole(.grid_cell))
                            // .width(.percent(table.style.action_width))
                            .layout(.right_center)
                            .height(.px(24))
                            .children({
                            // table.action_select.renderTrigger();
                            if (table.action_select) |*as| as.renderTrigger();
                        });
                    }
                });
            }
        }

        // =================================================================
        // Action menu
        // =================================================================

        fn selectAction(select: *Select(usize), item: *Select(usize).Item) void {
            const opt_select: *?Select(usize) = @ptrCast(select);
            const table: *Self = @alignCast(@fieldParentPtr("action_select", opt_select));
            const row = &table.data[table.row_index + table.current_page * table.per_page];
            if (table.actions[item.value].on_action) |on_action| on_action(row);
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

        fn hoverBtn(table: *Self, id: []const u8, _: *Vapor.Event) void {
            table.current_hovered_id = id;
        }

        fn leaveBtn(table: *Self, _: *Vapor.Event) void {
            table.current_hovered_id = "";
        }

        // =================================================================
        // Virtualized row renderer (used by VirtualList)
        // =================================================================

        fn VirtualRow(row: *T, i: usize, ctx: ?*anyopaque) void {
            if (ctx == null) return;
            const table: *Self = @ptrCast(@alignCast(ctx));
            const is_selected = table.includes(row.id);

            Box()
                .border(.{ .thickness = .{ .bottom = table.style.cell_divider_thickness }, .color = table.style.border_color })
                .height(.px(table.style.row_height))
                .width(.px(table.row_width))
                .inlineStyle("min-width: 600px", .{})
                .children({
                Box()
                    .border(.{ .thickness = .horizontal(table.style.cell_divider_thickness), .color = table.style.border_color })
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
                        .background(.red)
                        .children({
                        // table.action_select.renderTrigger();
                        if (table.action_select) |*as| as.renderTrigger();
                    });
                });
            });
        }

        fn copy(table: *Self) void {
            Vapor.Clipboard.copy(table.current_value_str);
            table.context_menu.copied = true;
            Vapor.timeout("content_menu_copied", 300, struct {
                fn toggleClose(self: *Self) void {
                    self.context_menu.copied = false;
                    self.close();
                }
            }.toggleClose, .{table});
        }

        fn renderContextAction(table: *Self, comptime on_click: anytype, label: []const u8, icon: Vapor.IconTokens) void {
            const icon_token: Vapor.IconTokens = if (table.context_menu.copied) .check else icon;
            Button(on_click, .{table})
                .pointer()
                .width(.percent(100))
                .padding(.xy(8, 6))
                .layout(.left_center)
                .hover(.{ .background = .palette(.highlight_color) })
                .spacing(8)
                .children({
                Icon(icon_token)
                    .fontSize(14)
                    .end();
                Text(label)
                    .fontSize(14)
                    .end();
            });
        }

        // =================================================================
        // Paginated / all row rendering
        // =================================================================

        fn Rows(table: *Self) void {
            if (table.filtered_data.items.len == 0) {
                Box().width(.percent(100)).padding(.vertical(48))
                    .height(.expand)
                    .layout(.center).children({
                    Stack().layout(.center).spacing(8).width(.percent(100)).children({
                        Text("No results found").font(14, 400, table.style.icon_color).end();
                    });
                });
                return;
            }

            const items_to_render = switch (table.display_mode) {
                .paginated => blk: {
                    const start = table.current_page * table.per_page;
                    const end = @min(start + table.per_page, table.filtered_data.items.len);
                    break :blk table.filtered_data.items[start..end];
                },
                .all => table.data,
                else => {
                    Vapor.print(.err, "Error: called Rows() in virtual mode", .{});
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
                Box()
                    // .inlineStyle("min-width: 128px;", .{})
                    .width(.fit)
                    .minWidth(.px(128))
                    .pos(.tl(.percent(0), .percent(0), .fixed))
                    .zIndex(9999)
                    .children({
                    if (table.action_select) |*as| as.renderSelect();
                });

                // Data rows
                for (items_to_render, 0..) |*row, i| {
                    const actual_index = table.current_page * table.per_page + i;
                    const is_focused_row = table.focused_row == actual_index;
                    // Calling return here causes a crash
                    const is_selected = table.includes(row.id);

                    const box = if (table.click_on_row) blk: {
                        break :blk Box()
                            .onEvent(.dblclick, onRowClick, .{ table, row })
                            .pointer()
                            .border(.{ .thickness = .{ .bottom = table.style.cell_divider_thickness }, .color = table.style.border_color })
                            .hover(.{ .background = table.style.hover_background, .text_color = table.style.hover_text_color });
                    } else blk: {
                        break :blk Box().border(.{ .thickness = .{ .bottom = table.style.cell_divider_thickness }, .color = table.style.border_color });
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
                            .border(.{ .thickness = .horizontal(table.style.cell_divider_thickness), .color = table.style.border_color })
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
                    .shadow(Vapor.Types.NewShadow.init().inset(0, -2, .transparentize(.black, 0.3)))
                    .children({
                    if (std.mem.eql(u8, label, "to save")) {
                        Vapor.Svg(.{ .svg = save_icon })
                            .fill(table.style.text_color)
                            .size(.squarePx(16))
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
                .shadow(Vapor.Types.Shadow.init().dropSpread(0, 4, 6, 2, .transparentize(.black, 0.05)));
        }

        fn Search(table: *Self) void {
            table.CommonFilter()
                .onMount(mountSearchBox, .{table})
                .children({
                Box().width(.percent(100)).padding(.all(4)).pointer().layout(.x_between_center).children({
                    Box()
                        .border(.round(.transparent, .all(table.style.border_radius)))
                        .width(.px(32)).height(.px(32))
                        .background(table.style.tint).layout(.center)
                        .children({
                        Vapor.Svg(.{ .svg = search_icon })
                            .fill(table.style.checkbox_icon_color)
                            .size(.squarePx(16))
                            .end();
                    });
                    TextField(.string)
                        .ref(&table.search_box)
                        .placeholder("Filter...")
                        .width(.grow).border(.none)
                        .padding(.horizontal(12)).outline(.none, null)
                        .fontFamily(table.style.font_family).background(.transparent)
                        .font(16, 300, table.style.text_color)
                        .val(&table.search_box.text)
                        .onEvent(.input, search, .{table})
                        .end();
                    Button(clearText, .{table})
                        .ariaLabel("Search Filter")
                        .background(.transparent).pointer().padding(.all(4))
                        .children({
                        Vapor.Svg(.{ .svg = x_lg })
                            .fill(table.style.icon_color)
                            .size(.squarePx(16))
                            .end();
                    });
                });
            });
        }

        fn mountSearchBox(table: *Self) void {
            table.search_box.focus();
        }

        fn handleFilter(table: *Self, comptime FT: type, value: FT) void {
            const text = fieldToString(value);
            if (table.enum_filters.get(text)) |_| {
                if (!table.enum_filters.remove(text)) Vapor.print(.err, "Failed to remove filter", .{});
            } else {
                _ = table.enum_filters.put(text, {}) catch unreachable;
            }
            table.applyFilters();
        }

        fn FilterSelect(table: *Self, comptime FT: type, comptime values: []const FT) void {
            table.CommonFilter().padding(.all(4)).spacing(8).children({
                for (values) |value| {
                    const active = table.enum_filters.get(fieldToString(value)) != null;
                    Button(handleFilter, .{ table, FT, value })
                        .ariaLabel("Select Filter")
                        .width(.percent(100)).height(.px(36))
                        .background(if (active) table.style.tint else .transparent)
                        .pointer().layout(.left_center).duration(table.style.hover_duration)
                        .hover(.{ .background = table.style.tint, .text_color = table.style.checkbox_icon_color })
                        .padding(.{ .top = 6, .bottom = 6, .left = 6, .right = 24 })
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
            const float_page: f32 = @floatFromInt(table.current_page);

            Box()
                .a11y(Vapor.Accessibility.init().setRole(.navigation).setLabel("DynamicTable pagination"))
                .width(.percent(100))
                .layout(.x_between_center)
                .padding(.xy(18, 8))
                .height(.px(table.style.row_height))
                .spacing(8)
                .pos(.relative)
                .children({
                Box().a11y(.liveRegion(.polite)).children({
                    TextFmt("Page {d} of {d}", .{ table.current_page + 1, page_count }).end();
                });
                Box().spacing(16).children({
                    if (float_page > 0) {
                        Button(prevPage, .{table})
                            .ariaLabel("Go to previous page")
                            .background(.transparent).cursor(.pointer)
                            .children({
                            Vapor.Svg(.{ .svg = chevron_left })
                                .fill(table.style.icon_color)
                                .size(.squarePx(16))
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
                                .size(.squarePx(16))
                                .end();
                        });
                    }
                });
            });
        }

        fn CommonToggleFilter(func: anytype, args: anytype) Vapor.Builder(.pure) {
            return Button(func, args)
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
                .font(14, 300, .palette(.text_color));
        }

        fn toggleEditDropdown(table: *Self, column: Column(T), id: []const u8) void {
            table.active_column = column;
            table.show_actions = !table.show_actions;
            const bounds = Vapor.getComponentBounds(id) orelse return;
            table.edit_y = bounds.top + bounds.height;
            table.edit_x = bounds.left;
        }

        fn compareValues(sort_type: Sort, a: T, b: T) bool {
            // Put nulls last regardless of direction
            const a_null = isNull(a);
            const b_null = isNull(b);
            if (a_null and b_null) return false;
            if (a_null) return false;
            if (b_null) return true;

            const val1 = if (sort_type == .asc) a else b;
            const val2 = if (sort_type == .asc) b else a;

            return switch (val1) {
                .int => |v| v.? < (val2.int orelse return false),
                .float => |v| v.? < (val2.float orelse return false),
                .boolean => |v| !v.? and (val2.boolean orelse false),
                .string => |v| std.ascii.lessThanIgnoreCase(v.?, val2.string orelse return false),
                .json => |v| std.ascii.lessThanIgnoreCase(v.?, val2.json orelse return false),
                .datetime => |v| {
                    const t1 = v.?.toTimestamp();
                    const t2 = (val2.datetime orelse return false).toTimestamp();
                    return t1 < t2;
                },
                else => false,
            };
        }

        fn isNull(v: T) bool {
            return switch (v) {
                .int => |x| x == null,
                .float => |x| x == null,
                .string => |x| x == null,
                .boolean => |x| x == null,
                .datetime => |x| x == null,
                .json => |x| x == null,
                .array => |x| x == null,
                .null => true,
            };
        }

        const SortCtx = struct {
            sort_type: Sort,
            key: []const u8,
        };

        fn sortRowsLessThan(ctx: SortCtx, a: T, b: T) bool {
            const va = a.get(ctx.key) orelse return false;
            const vb = b.get(ctx.key) orelse return true;
            return compareValues(ctx.sort_type, va, vb);
        }

        // Track current sort so refresh/regenerate can preserve it if you want

        fn sortByColumn(table: *Self, col: Column(T), dir: Sort) void {
            _ = table;
            _ = col;
            _ = dir;
            // const key = col.title;
            //
            // if (dir == .none) {
            //     // Reset to original order by re-applying filters from source data
            //     table.refresh();
            //     return;
            // }
            //
            // std.mem.sort(
            //     T,
            //     table.filtered_data.items,
            //     SortCtx{ .sort_type = dir, .key = key },
            //     sortRowsLessThan,
            // );
        }

        fn onSortAsc(table: *Self) void {
            table.sortByColumn(table.active_column.?, .asc);
            table.show_actions = false;
        }

        fn onSortDesc(table: *Self) void {
            table.sortByColumn(table.active_column.?, .desc);
            table.show_actions = false;
        }

        fn onEditColumn(table: *Self) void {
            if (table.on_edit_column) |on_edit_column| {
                on_edit_column(table.active_column.?);
            }
            // Hook for consumers — currently a no-op stub.
            // Wire to an `on_edit_column: ?*const fn(usize) void` field if you
            // want the host app to handle this.
            table.show_actions = false;
        }

        fn onDeleteColumn(table: *Self) void {
            const idx = table.active_column.?;
            table.show_actions = false;
            table.deleteColumn(idx);
        }

        fn EditColumn(table: *Self) void {
            Stack()
                .background(table.style.edit_popup_background)
                .border(.sharp(.all(1), table.style.edit_popup_border_color))
                .width(.px(table.style.column_width))
                .layout(.y_between)
                .transformOrigin(.top_center)
                .animationEnter("opaque-table-textarea-enter")
                .animationExit("opaque-table-textarea-exit")
                .children({
                editColumnRow(table, .sort_alpha_down, "Sort Ascending", onSortAsc);
                editColumnRow(table, .sort_alpha_up, "Sort Descending", onSortDesc);
                editColumnRow(table, .pencil_square, "Edit Column", onEditColumn);
            });
        }

        fn editColumnRow(
            table: *Self,
            icon: Vapor.IconTokens,
            label: []const u8,
            action: fn (*Self) void,
        ) void {
            Button(action, .{table})
                .ariaLabel(label)
                .width(.expand)
                .padding(.xy(4, 8))
                .border(.bottom(1, table.style.border_color))
                .spacing(8)
                .cursor(.pointer)
                .background(.transparent)
                .duration(table.style.hover_duration)
                .hover(.{ .background = table.style.hover_background, .text_color = table.style.hover_text_color })
                .layout(.left_center)
                .children({
                Vapor.Icon(icon).fontSize(12).end();
                Text(label).fontSize(12).fontFamily(table.style.font_family).end();
            });
        }

        fn closeActionsDropdown(table: *Self) void {
            table.show_actions = false;
        }

        // =================================================================
        // Main render entry point
        // =================================================================

        /// Render the full table widget: header, rows, and pagination.
        pub fn render(table: *Self) void {
            const height: Vapor.Types.Sizing = if (table.display_mode != .virtual)
                .px(@as(f32, @floatFromInt(table.per_page)) * table.style.row_height)
            else
                .expand;

            Stack()
                .onMount(mount, .{table})
                .onDestroy(destroy, .{table})
                .onResize(calcBounds, .{table})
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
                        .width(if (table_columns.len == 0) .percent(100) else .px(table.row_width))
                        .children({
                        // ── Header ────────────────────────────────────────
                        Box()
                            .width(if (table_columns.len == 0) .percent(100) else .px(table.row_width))
                            .border(.horizontal(1, table.style.border_color))
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
                                    .border(.vertical(1, table.style.border_color))
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

                                        const fields = @typeInfo(T).@"struct".fields;
                                        Box().width(.px(table.row_width - table.style.checkbox_width)).height(.px(table.style.row_height)).layout(.left_center).children({
                                            inline for (table_columns, 0..) |column, i| {
                                                const row: Vapor.Builder(.pure) = Vapor.Row();
                                                row
                                                    .a11y(Vapor.Accessibility.init().setRole(.column_header).setLabel(column.title))
                                                    .ref(&table.binded_cols[i])
                                                    .border(.{ .thickness = .{ .left = table.style.cell_divider_thickness }, .color = table.style.border_color })
                                                    .borderStyle(table.style.cell_divider_style)
                                                    .width(.px(table.style.column_width))
                                                    .height(.px(table.style.row_height))
                                                    .layout(.x_between_center)
                                                    .padding(.horizontal(table.style.cell_padding_horizontal))
                                                    .children({
                                                    Vapor.Row()
                                                        .width(.expand)
                                                        .layout(.left_center)
                                                        .spacing(4)
                                                        .children({
                                                        Text(column.title).fontFamily(table.style.font_family).font(table.style.header_font_size, table.style.header_font_weight, null).end();

                                                        if (column.sort) |sort_type| {
                                                            const sorted = table.sortedBy(column.key);
                                                            CommonToggleFilter(sortColumn, .{ table, sort_type, column.key })
                                                                // Names the column and how it is sorted now.
                                                                .ariaLabel(Vapor.fmtln("Sort by {s}, {s}", .{ column.title, switch (sorted) {
                                                                    .asc => "ascending",
                                                                    .desc => "descending",
                                                                    .none => "not sorted",
                                                                } }))
                                                                .hover(.{
                                                                    .background = table.style.tint,
                                                                    .text_color = table.style.checkbox_icon_color,
                                                                })
                                                                .children({
                                                                switch (if (sorted == .none) sort_type else sorted) {
                                                                    .asc => Icon(.sort_alpha_down).font(14, 700, null).end(),
                                                                    .desc => Icon(.sort_alpha_up).font(14, 700, null).end(),
                                                                    else => {},
                                                                }
                                                            });
                                                        }
                                                        if (column.search) {
                                                            CommonToggleFilter(toggleSearch, .{ table, i })
                                                                .ariaLabel(Vapor.fmtln("Search by {s} ", .{column.title}))
                                                                .hover(.{
                                                                    .background = table.style.tint,
                                                                    .text_color = table.style.checkbox_icon_color,
                                                                })
                                                                .children({
                                                                Icon(.search).font(14, 700, null).end();
                                                            });
                                                        }
                                                        if (column.filter) {
                                                            CommonToggleFilter(toggleFilter, .{ table, i })
                                                                .ariaLabel(Vapor.fmtln("Filter by {s} ", .{column.title}))
                                                                .hover(.{
                                                                    .background = table.style.tint,
                                                                    .text_color = table.style.checkbox_icon_color,
                                                                })
                                                                .children({
                                                                Icon(.funnel).font(14, 700, null).end();
                                                            });
                                                        }
                                                    });
                                                });

                                                Box()
                                                    .pos(.tl(.px(0), .percent(0), .absolute))
                                                    .width(.fit)
                                                    .zIndex(1000)
                                                    .inlineStyle("transform: translate({d}px, {d}px)", .{ table.filter_right, table.filter_top })
                                                    .children({
                                                    if (column.filter and table.show_filter and table.clicked_index == i) {
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
                                                    .inlineStyle("transform: translate({d}px, {d}px)", .{ table.search_right, table.search_top })
                                                    .children({
                                                    if (column.search and table.show_search and table.clicked_index == i) {
                                                        Search(table);
                                                    }
                                                });
                                            }
                                        });
                                    });
                                });
                            });
                        });
                        // ── Body ─────────────────────────────────────────
                        if (table.display_mode == .virtual) {
                            table.virtual_list.renderWithCtx(@ptrCast(table));
                        } else {
                            table.Rows();
                        }
                    });
                    if (table.show_actions) {
                        // Click-outside catcher
                        Button(closeActionsDropdown, .{table})
                            .pos(.tl(.px(0), .percent(0), .fixed))
                            .size(.full)
                            .zIndex(999)
                            .background(.transparent)
                            .children({});
                        Box()
                            .inlineStyle("transform: translate({d}px, {d}px)", .{ table.edit_x, table.edit_y })
                            .pos(.tl(.percent(0), .percent(0), .absolute))
                            .zIndex(1000)
                            .children({
                            EditColumn(table);
                        });
                    } else {
                        // Vapor.Null();
                    }
                });
                // ── Footer / pagination ──────────────────────────────────
                if (table.display_mode != .virtual) {
                    table.Pagination();
                }
            });
        }
    };
}
