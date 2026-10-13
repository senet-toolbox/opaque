// ============================================================================
// Kanban Board — Teenage Engineering EP-133 Edition
// ============================================================================
//
// Playful retro aesthetic: chunky borders, bright accent pops, grid-heavy,
// monospace typography, boxy elements with sharp corners.
// Combines rich UI (tooltips, sheets, modals, progress, animations)
// with Sortable collections for cross-column drag-and-drop reordering.

const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Box;
const Stack = Vapor.Stack;
const Center = Vapor.Center;
const Icon = Vapor.Icon;
const TextFmt = Vapor.TextFmt;
const TextField = Vapor.TextField;
const Animation = Vapor.Animation;
const Opaque = @import("../../components/Opaque.zig");
const Button = Opaque.Button;
const Alert = Opaque.Alert;
const ButtonCtx = Vapor.CtxButton;
const DateTime = Vapor.DateTime;
const ProgressCircle = Opaque.ProgressCircle;
const ProgressBar = Opaque.ProgressBar;
const Sortable = Opaque.Sortable;

// Import UI Components
const SelectStruct = @import("../../components/Select.zig");
const ToastStruct = @import("../../components/Toast.zig");
const SheetStruct = @import("../../components/Sheet.zig");
const FieldStruct = @import("../../components/Field.zig");
const TooltipStruct = @import("../../components/Tooltip.zig");
const SwitchStruct = @import("../../components/Switch.zig");
const GroupStruct = @import("../../components/Group.zig");

// ============================================================================
// TYPE ALIASES
// ============================================================================

pub const Select = SelectStruct.Select;
pub const Toast = ToastStruct;
pub const Sheet = SheetStruct;
pub const Field = FieldStruct;
pub const Tooltip = TooltipStruct;
pub const Switch = SwitchStruct;
pub const Group = GroupStruct;

// ============================================================================
// DATA TYPES
// ============================================================================

pub const TaskPriority = enum {
    low,
    medium,
    high,
    urgent,

    pub fn color(self: TaskPriority) Vapor.Types.Color {
        return switch (self) {
            .low => .hex("#00C2FF"), // cool cyan
            .medium => .hex("#FFE600"), // TE yellow
            .high => .hex("#FF6B00"), // TE signature orange
            .urgent => .hex("#FF2D55"), // hot pink/red
        };
    }

    pub fn label(self: TaskPriority) []const u8 {
        return switch (self) {
            .low => "LOW",
            .medium => "MED",
            .high => "HIGH",
            .urgent => "URGENT",
        };
    }

    pub fn icon(self: TaskPriority) *const Vapor.IconTokens {
        return switch (self) {
            .low => .flag,
            .medium => .flag_fill,
            .high => .exclamation_circle,
            .urgent => .exclamation_triangle_fill,
        };
    }
};

pub const TaskStatus = enum {
    backlog,
    todo,
    in_progress,
    review,
    done,

    pub fn label(self: TaskStatus) []const u8 {
        return switch (self) {
            .backlog => "BACKLOG",
            .todo => "TO DO",
            .in_progress => "IN PROGRESS",
            .review => "REVIEW",
            .done => "DONE",
        };
    }

    pub fn color(self: TaskStatus) Vapor.Types.Color {
        return switch (self) {
            .backlog => .hex("#888888"),
            .todo => .hex("#00C2FF"),
            .in_progress => .hex("#FF6B00"),
            .review => .hex("#FFE600"),
            .done => .hex("#00FF87"),
        };
    }

    pub fn icon(self: TaskStatus) *const Vapor.IconTokens {
        return switch (self) {
            .backlog => .inbox,
            .todo => .circle,
            .in_progress => .play_circle,
            .review => .eye,
            .done => .check_circle_fill,
        };
    }
};

pub const Task = struct {
    id: usize,
    title: []const u8,
    description: []const u8,
    status: TaskStatus,
    priority: TaskPriority,
    assignee: ?[]const u8,
    tags: []const []const u8,
    due_date: ?Vapor.DateTime,
    created_at: []const u8,
    progress: ?ProgressCircle = null,
    percent: f64 = 0,
    position: []const u8 = "n",
};

// ============================================================================
// SORTABLE COLLECTION TYPE
// ============================================================================

const TaskCollection = Sortable.Collection(Task, .{
    .id_field = "id",
    .direction = .vertical,
    .on_reorder = onReorder,
    .on_transfer = onTransfer,
    .show_drag_overlay = false,
    .gap_render = gapRender,
});

// ============================================================================
// STATE
// ============================================================================

var drag_ctx: Sortable.DragContext = .{};

var backlog_col: TaskCollection = undefined;
var todo_col: TaskCollection = undefined;
var in_progress_col: TaskCollection = undefined;
var review_col: TaskCollection = undefined;
var done_col: TaskCollection = undefined;

var next_task_id: usize = 100;
var show_completed: bool = true;
var search_query: []const u8 = "";
var filter_priority: ?TaskPriority = null;
var selected_task: ?*const Task = null;

var new_task_title: []const u8 = "";
var new_task_description: []const u8 = "";
var new_task_priority: TaskPriority = .medium;
var new_task_status: TaskStatus = .todo;

var detail_sheet: Sheet = undefined;
var priority_filter: Select(TaskPriority) = undefined;
var status_select: Select(TaskStatus) = undefined;
var alert: Alert = undefined;

var priority_options = [_]Select(TaskPriority).Item{
    .{ .value = .low, .label = "LOW" },
    .{ .value = .medium, .label = "MED" },
    .{ .value = .high, .label = "HIGH" },
    .{ .value = .urgent, .label = "URGENT" },
};

var status_options = [_]Select(TaskStatus).Item{
    .{ .value = .backlog, .label = "BACKLOG" },
    .{ .value = .todo, .label = "TO DO" },
    .{ .value = .in_progress, .label = "IN PROGRESS" },
    .{ .value = .review, .label = "REVIEW" },
    .{ .value = .done, .label = "DONE" },
};

// ============================================================================
// THEME — Teenage Engineering EP-133 Palette
// ============================================================================
// Chunky, playful, grid-precise. Bright pops on dark panels.
// Sharp corners, thick borders, monospace everything.

const TE = struct {
    // Monospace font for that hardware-label feel
    const font = "IBM Plex Mono,monospace";

    // Core palette — uses theme tokens where possible
    const bg_base = Vapor.Types.Color.palette(.background);
    const bg_card = Vapor.Types.Color.palette(.alternate_background);
    const bg_elevated = Vapor.Types.Color.palette(.code_background);

    // TE signature colors (bright pops)
    const orange = Vapor.Types.Color.hex("#FF6B00");
    const yellow = Vapor.Types.Color.hex("#FFE600");
    const cyan = Vapor.Types.Color.hex("#00C2FF");
    const pink = Vapor.Types.Color.hex("#FF2D55");
    const green = Vapor.Types.Color.hex("#00FF87");
    const white = Vapor.Types.Color.hex("#FAFAFA");

    // Text hierarchy
    const text = Vapor.Types.Color.palette(.text_color);
    const text_secondary = Vapor.Types.Color.hex("#999999");
    const text_muted = Vapor.Types.Color.hex("#666666");

    // Borders — chunky and visible
    const border = Vapor.Types.Color.palette(.border_color);
    const border_light = Vapor.Types.Color.palette(.border_color_light);

    // Accent uses the theme tint
    const accent = Vapor.Types.Color.palette(.tint);

    // Functional
    const success = Vapor.Types.Color.hex("#00FF87");
    const warning = Vapor.Types.Color.hex("#FF6B00");
    const err = Vapor.Types.Color.palette(.danger);

    // Chunky border radius — sharp but slightly softened
    const radius_sm: u8 = 2;
    const radius_md: u8 = 4;
    const radius_lg: u8 = 6;

    // Thick borders
    const border_w: u8 = 2;
};

// ============================================================================
// ANIMATIONS — snappier, more mechanical
// ============================================================================

const pulse_glow = Animation.init("te-pulse")
    .prop(.opacity, 1, 0.4)
    .duration(800)
    .dir(.alternate)
    .infinite();

const slide_up = Animation.init("te-slide-up")
    .prop(.translateY, 12, 0)
    .prop(.opacity, 0, 1)
    .duration(150)
    .easing(.easeOut)
    .fill(.forwards);

const fade_scale = Animation.init("te-fade-scale")
    .prop(.scale, 0.97, 1)
    .prop(.opacity, 0, 1)
    .duration(120)
    .easing(.easeOut)
    .fill(.forwards);

const card_enter = Animation.init("te-card-enter")
    .prop(.translateY, 6, 0)
    .prop(.opacity, 0, 1)
    .duration(120)
    .easing(.easeOut)
    .fill(.forwards);

const modal_enter = Animation.init("te-modal-enter")
    .prop(.scale, 0.96, 1)
    .prop(.opacity, 0, 1)
    .duration(150)
    .easing(.easeOut)
    .fill(.forwards);

// ============================================================================
// SAMPLE DATA
// ============================================================================

fn createProgressCircle() ProgressCircle {
    return ProgressCircle.init(Vapor.arena(.persist), .{
        .size = 14,
        .stroke_width = 3,
        .track_color = .palette(.border_color_light),
        .color = TE.orange,
        .clockwise = false,
        .show_label = false,
        .rounded_caps = false,
    });
}

var rand = std.Random.DefaultPrng.init(0);

fn makeTask(
    id: usize,
    title: []const u8,
    description: []const u8,
    status: TaskStatus,
    priority: TaskPriority,
    assignee: ?[]const u8,
    tags: []const []const u8,
    due_date: ?Vapor.DateTime,
    created_at: []const u8,
    position: []const u8,
) Task {
    var progress_circle = createProgressCircle();
    const rand_value: f64 = @floatFromInt(rand.random().intRangeAtMost(u32, 0, 100));
    progress_circle.setProgress(rand_value / 100);
    return Task{
        .id = id,
        .title = title,
        .description = description,
        .status = status,
        .priority = priority,
        .assignee = assignee,
        .tags = tags,
        .due_date = due_date,
        .created_at = created_at,
        .progress = progress_circle,
        .percent = rand_value,
        .position = position,
    };
}

// ============================================================================
// SORTABLE CALLBACKS
// ============================================================================

fn onReorder(event: Sortable.ReorderEvent(Task)) void {
    Vapor.print("Reorder: '{s}' from {d} to {d}, position key: {s}\n", .{
        event.item.title,
        event.from_index,
        event.to_index,
        event.position,
    });
}

fn onTransfer(event: Sortable.TransferEvent(Task)) void {
    const new_status: ?TaskStatus = columnToStatus(event.to_collection);
    if (new_status) |status| {
        event.item.status = status;
    }

    Vapor.print("Transfer: '{s}' from {s} to {s} at index {d}, position key: {s}\n", .{
        event.item.title,
        event.from_collection,
        event.to_collection,
        event.to_index,
        event.position,
    });

    Toast.info(.{
        .title = "TASK MOVED",
        .description = if (new_status) |s| s.label() else "Moved to new column",
    });
}

fn columnToStatus(collection_id: []const u8) ?TaskStatus {
    if (std.mem.eql(u8, collection_id, "backlog")) return .backlog;
    if (std.mem.eql(u8, collection_id, "todo")) return .todo;
    if (std.mem.eql(u8, collection_id, "in_progress")) return .in_progress;
    if (std.mem.eql(u8, collection_id, "review")) return .review;
    if (std.mem.eql(u8, collection_id, "done")) return .done;
    return null;
}

fn collectionForStatus(status: TaskStatus) *TaskCollection {
    return switch (status) {
        .backlog => &backlog_col,
        .todo => &todo_col,
        .in_progress => &in_progress_col,
        .review => &review_col,
        .done => &done_col,
    };
}

// ============================================================================
// EVENT HANDLERS
// ============================================================================

fn openAddModal() void {
    new_task_title = "";
    new_task_description = "";
    new_task_priority = .medium;
    new_task_status = .todo;
    alert.open();
}

fn closeAddModal() void {
    alert.close();
}

fn addTask() void {
    if (new_task_title.len == 0) return;

    const task = makeTask(
        next_task_id,
        Vapor.arena(.persist).dupe(u8, new_task_title) catch return,
        Vapor.arena(.persist).dupe(u8, new_task_description) catch return,
        new_task_status,
        new_task_priority,
        null,
        &.{},
        null,
        "Today",
        "z",
    );

    const col = collectionForStatus(new_task_status);
    col.append(task) catch return;

    next_task_id += 1;
    closeAddModal();
    Toast.success(.{ .title = "TASK CREATED", .description = "Added to board" });
}

fn deleteTaskFromCollection(task: *Task) void {
    const col = collectionForStatus(task.status);
    _ = col.removeByPtr(task);
    Toast.warning(.{ .title = "DELETED", .description = "Task removed" });
}

fn handleViewTask(task: *Task) void {
    selected_task = task;
    detail_sheet.open();
}

fn closeDetailSheet() void {
    detail_sheet.close();
    selected_task = null;
}

fn toggleCompleted() void {
    show_completed = !show_completed;
    if (show_completed) {
        Toast.info(.{ .title = "SHOWING DONE", .description = "Completed tasks visible" });
    } else {
        Toast.info(.{ .title = "HIDING DONE", .description = "Completed tasks hidden" });
    }
}

fn setFilterPriority(_: *Select(TaskPriority), item: *Select(TaskPriority).Item) void {
    if (filter_priority == item.value) {
        filter_priority = null;
    } else {
        filter_priority = item.value;
    }
}

fn handleExport() void {
    Toast.info(.{ .title = "EXPORTING", .description = "Preparing data..." });
}

fn handleRefresh() void {
    Toast.success(.{ .title = "REFRESHED", .description = "Board is up to date" });
}

fn addTaskToColumn(status: TaskStatus) void {
    new_task_status = status;
    openAddModal();
}

fn selectPriority(priority: TaskPriority) void {
    new_task_priority = priority;
}

fn selectStatus(status: TaskStatus) void {
    new_task_status = status;
}

fn moveTaskLeft(task: *Task) void {
    const old_status = task.status;
    const new_status: TaskStatus = switch (old_status) {
        .backlog => .backlog,
        .todo => .backlog,
        .in_progress => .todo,
        .review => .in_progress,
        .done => .review,
    };
    if (old_status != new_status) {
        task.status = new_status;
        const from_col = collectionForStatus(old_status);
        const to_col = collectionForStatus(new_status);
        from_col.transferTo(to_col, task);
    }
}

fn moveTaskRight(task: *Task) void {
    const old_status = task.status;
    const new_status: TaskStatus = switch (old_status) {
        .backlog => .todo,
        .todo => .in_progress,
        .in_progress => .review,
        .review => .done,
        .done => .done,
    };
    if (old_status != new_status) {
        task.status = new_status;
        const from_col = collectionForStatus(old_status);
        const to_col = collectionForStatus(new_status);
        from_col.transferTo(to_col, task);
    }
}

fn canMoveLeft(status: TaskStatus) bool {
    return status != .backlog;
}

fn canMoveRight(status: TaskStatus) bool {
    return status != .done;
}

// ============================================================================
// HELPERS
// ============================================================================

fn totalTaskCount() usize {
    return backlog_col.count() + todo_col.count() + in_progress_col.count() + review_col.count() + done_col.count();
}

fn matchesFilter(task: *const Task) bool {
    if (filter_priority) |priority| {
        if (task.priority != priority) return false;
    }
    if (search_query.len > 0) {
        const title_lower = std.ascii.allocLowerString(Vapor.arena(.frame), task.title) catch return true;
        const query_lower = std.ascii.allocLowerString(Vapor.arena(.frame), search_query) catch return true;
        if (std.mem.indexOf(u8, title_lower, query_lower) == null) return false;
    }
    return true;
}

// ============================================================================
// INITIALIZATION
// ============================================================================

var bar: ProgressBar = undefined;
var progress_bar_tooltip: ProgressBar = undefined;

const total_completed: f64 = 0.34;

pub fn init() void {
    pulse_glow.build();
    slide_up.build();
    fade_scale.build();
    card_enter.build();
    modal_enter.build();

    Sortable.new();
    SelectStruct.new();
    ToastStruct.new();
    SheetStruct.new();
    FieldStruct.new();
    TooltipStruct.new();
    SwitchStruct.new();
    GroupStruct.new();

    drag_ctx.init();

    backlog_col.initNamed(&drag_ctx, "backlog", &.{
        makeTask(5, "Database schema review", "Review and optimize current database schema", .backlog, .medium, null, &.{ "backend", "database" }, null, "Jan 10", "f"),
        makeTask(8, "Performance audit", "Run Lighthouse and optimize critical metrics", .backlog, .low, null, &.{"performance"}, null, "Jan 12", "n"),
    });

    todo_col.initNamed(&drag_ctx, "todo", &.{
        makeTask(4, "API documentation", "Document all REST endpoints with examples", .todo, .low, "Alex", &.{ "docs", "api" }, DateTime.fromDayMonthYear(21, 1, 2026), "Jan 20", "d"),
        makeTask(6, "Mobile responsive layout", "Ensure all pages work on mobile devices", .todo, .high, "Sarah", &.{ "frontend", "mobile" }, DateTime.fromDayMonthYear(12, 8, 2026), "Jan 7", "h"),
        makeTask(9, "Notification system", "Build real-time notification infrastructure", .todo, .high, "Alex", &.{ "backend", "realtime" }, DateTime.fromDayMonthYear(3, 6, 2026), "Jan 10", "l"),
    });

    in_progress_col.initNamed(&drag_ctx, "in_progress", &.{
        makeTask(2, "User authentication flow", "Implement login, signup, and password reset", .in_progress, .urgent, "Mike", &.{ "backend", "security" }, DateTime.fromDayMonthYear(13, 1, 2026), "Jan 8", "f"),
        makeTask(7, "Unit test coverage", "Increase test coverage to 80%", .in_progress, .medium, "Mike", &.{ "testing", "quality" }, DateTime.fromDayMonthYear(17, 4, 2026), "Jan 11", "n"),
    });

    review_col.initNamed(&drag_ctx, "review", &.{
        makeTask(3, "Dashboard wireframes", "Create low-fidelity wireframes for main dashboard", .review, .medium, "Sarah", &.{"design"}, DateTime.fromDayMonthYear(8, 1, 2026), "Jan 6", "f"),
        makeTask(10, "Settings page", "User preferences and account settings UI", .review, .medium, "Sarah", &.{ "frontend", "ui" }, DateTime.fromDayMonthYear(28, 4, 2026), "Jan 8", "n"),
    });

    done_col.initNamed(&drag_ctx, "done", &.{
        makeTask(1, "Design system setup", "Create color tokens, typography scale, and spacing system", .done, .high, "Sarah", &.{ "design", "foundation" }, DateTime.fromDayMonthYear(1, 1, 2026), "Jan 5", "n"),
    });

    priority_filter = .fromItems(&priority_options);
    priority_filter.trigger = "PRIORITY";
    priority_filter.on_select = setFilterPriority;
    priority_filter.tint_color = TE.orange;
    priority_filter.border = .sharp(.all(1), .palette(.border_color_light));
    priority_filter.selected_border = .sharp(.all(1), TE.orange);
    priority_filter.shadow = .{ .color = .transparentizeHex(TE.orange, 0.2), .spread = 3 };

    status_select = .fromItems(&status_options);
    status_select.trigger = "STATUS";

    detail_sheet = Sheet.init(.right);
    detail_sheet.content = renderDetailSheetContent;
    alert = .init(renderAddModal);

    // Progress bar — chunky TE style
    bar = ProgressBar.init(Vapor.arena(.persist), .{
        .width = 120,
        .height = 8,
        .color = TE.orange,
        .background = .transparentize(.palette(.text_color), 0.1),
    });
    bar.setProgress(total_completed);

    progress_bar_tooltip = ProgressBar.init(Vapor.arena(.persist), .{
        .width = 100,
        .height = 6,
        .color = TE.orange,
        .background = .transparentize(.palette(.text_color), 0.1),
    });
    progress_bar_tooltip.setProgress(0);
}

// ============================================================================
// COMPONENTS — TE EP-133 STYLED
// ============================================================================

fn renderNavigation() void {
    Stack()
        .width(.px(220))
        .height(.percent(100))
        .padding(.all(16))
        .spacing(20)
        .border(.right(TE.border_w, TE.border))
        .children({

        // Logo — chunky hardware label style
        Box()
            .layout(.left_center)
            .spacing(10)
            .children({
            // Chunky square icon block
            Box()
                .width(.px(36))
                .height(.px(36))
                .background(.{ .color = TE.orange })
                .border(.solid(.all(TE.border_w), TE.border, .all(TE.radius_sm)))
                .layout(.center)
                .children({
                Icon(.kanban)
                    .font(18, 700, .hex("#000000"))
                    .end();
            });
            Stack()
                .spacing(0)
                .children({
                Text("KANBAN")
                    .font(16, 700, TE.text)
                    .fontFamily(TE.font)
                    .end();
                Text("BOARD v1.0")
                    .font(9, 500, TE.text_muted)
                    .fontFamily(TE.font)
                    .end();
            });
        });

        // Divider line
        Box()
            .width(.percent(100))
            .height(.px(TE.border_w))
            .background(.{ .color = TE.border })
            .children({});

        // Navigation Items
        Stack()
            .width(.percent(100))
            .spacing(2)
            .children({
            Text("VIEWS")
                .font(9, 700, TE.text_muted)
                .fontFamily(TE.font)
                .margin(.b(6))
                .end();

            renderNavButton("BOARD", .kanban, true);
            renderNavButton("LIST", .list_ul, false);
            renderNavButton("CALENDAR", .calendar, false);
            renderNavButton("TIMELINE", .bar_chart_line, false);
        });

        // Divider
        Box()
            .width(.percent(100))
            .height(.px(TE.border_w))
            .background(.{ .color = TE.border })
            .children({});

        // Stats Section — grid display style
        Stack()
            .width(.percent(100))
            .spacing(2)
            .children({
            Text("STATS")
                .font(9, 700, TE.text_muted)
                .fontFamily(TE.font)
                .margin(.b(6))
                .end();

            renderStatRow("TOTAL", totalTaskCount());
            renderStatRow("ACTIVE", in_progress_col.count());
            renderStatRow("DONE", done_col.count());
        });

        // Spacer
        Box().height(.grow).children({});

        // Divider
        Box()
            .width(.percent(100))
            .height(.px(TE.border_w))
            .background(.{ .color = TE.border })
            .children({});

        // User profile — hardware label style
        Box()
            .width(.percent(100))
            .padding(.all(8))
            .layout(.left_center)
            .spacing(10)
            .children({
            // User indicator dot
            Box()
                .width(.px(8))
                .height(.px(8))
                .background(.{ .color = TE.green })
                .border(.round(TE.green, .all(99)))
                .animation("te-pulse")
                .children({});
            Stack()
                .spacing(0)
                .width(.grow)
                .children({
                Text("VIC ROKX")
                    .font(11, 700, TE.text)
                    .fontFamily(TE.font)
                    .end();
                Text("PROJECT MGR")
                    .font(9, 400, TE.text_muted)
                    .fontFamily(TE.font)
                    .end();
            });
            Icon(.chevron_expand)
                .font(12, 400, TE.text_muted)
                .end();
        });
    });
}

fn renderNavButton(label_text: []const u8, nav_icon: *const Vapor.IconTokens, is_active: bool) void {
    Box()
        .width(.percent(100))
        .padding(.xy(10, 6))
        .background(if (is_active) .transparentizeHex(TE.orange, 0.15) else .transparent)
        .border(.solid(.all(if (is_active) TE.border_w else 0), if (is_active) TE.orange else .transparent, .all(TE.radius_sm)))
        .layout(.left_center)
        .spacing(10)
        .pointer()
        .duration(100)
        .hover(.{
            .background = if (is_active) .transparentizeHex(TE.orange, 0.15) else .palette(.highlight_color),
        })
        .children({
        Box()
            .width(.px(28))
            .height(.px(28))
            .layout(.center)
            .children({
            Icon(nav_icon)
                .font(14, 400, if (is_active) TE.orange else TE.text_secondary)
                .end();
        });
        Text(label_text)
            .font(11, if (is_active) @as(u32, 700) else @as(u32, 500), if (is_active) TE.orange else TE.text_secondary)
            .fontFamily(TE.font)
            .end();
    });
}

fn renderStatRow(label_text: []const u8, count: usize) void {
    Box()
        .width(.percent(100))
        .padding(.xy(10, 6))
        .border(.solid(.all(1), TE.border_light, .all(TE.radius_sm)))
        .layout(.x_between_center)
        .children({
        Text(label_text)
            .font(10, 500, TE.text_secondary)
            .fontFamily(TE.font)
            .end();
        // Chunky number display
        Box()
            .padding(.xy(6, 2))
            .background(.{ .color = TE.border_light })
            .border(.round(TE.border_light, .all(TE.radius_sm)))
            .children({
            TextFmt("{d}", .{count})
                .font(11, 700, TE.text)
                .fontFamily(TE.font)
                .end();
        });
    });
}

fn CustomField(field: *Field) Vapor.Builder(.pure) {
    const is_focused = field.is_focused;
    field.tint_color = TE.orange;
    return Stack()
        .width(.percent(100))
        .spacing(8)
        .pos(.relative)
        .height(.px(36))
        .border(.sharp(.all(1), if (is_focused) TE.orange else .palette(.border_color_light)))
        .background(field.background);
}

fn renderHeader() void {
    Box()
        .width(.percent(100))
        .height(.px(64))
        .padding(.horizontal(24))
        .background(TE.bg_base)
        .border(.bottom(TE.border_w, TE.border))
        .layout(.x_between_center)
        .children({
        // Left: Title — bold, uppercase, hardware style
        Box()
            .layout(.left_center)
            .spacing(12)
            .children({
            Text("KANBAN")
                .font(22, 800, TE.text)
                .fontFamily(TE.font)
                .end();
            // Version badge
            Box()
                .padding(.xy(6, 3))
                .background(.{ .color = TE.orange })
                .border(.round(TE.orange, .all(TE.radius_sm)))
                .children({
                Text("EP-133")
                    .font(9, 700, .hex("#000000"))
                    .fontFamily(TE.font)
                    .end();
            });
        });

        // Right: Controls — chunky buttons
        Box()
            .layout(.right_center)
            .spacing(8)
            .children({

            // Search — boxed input
            Box()
                .width(.px(180))
                .layout(.left_center)
                .spacing(6)
                .children({
                Field.create(.{ .label = "SEARCH...", .value = .{ .string = &search_query } })
                    .Component(CustomField);
            });

            // Priority filter
            Box()
                .width(.px(120))
                .children({
                priority_filter.renderPos(.bottom);
            });

            // Toggle completed — chunky button
            Button(toggleCompleted, .{})
                .padding(.xy(10, 7))
                .border(.solid(.all(TE.border_w), if (show_completed) TE.green else TE.border_light, .all(TE.radius_sm)))
                .children({
                if (show_completed) {
                    Box()
                        .width(.px(6))
                        .height(.px(6))
                        .background(.{ .color = TE.green })
                        .border(.round(TE.green, .all(99)))
                        .animation("te-pulse")
                        .children({});
                }
                Text(if (show_completed) "DONE:ON" else "DONE:OFF")
                    .font(10, 700, if (show_completed) TE.green else TE.text_secondary)
                    .fontFamily(TE.font)
                    .end();
            });

            Button(handleExport, .{})
                .padding(.xy(10, 7))
                .border(.solid(.all(TE.border_w), TE.border_light, .all(TE.radius_sm)))
                .children({
                Icon(.download)
                    .font(12, 400, TE.text)
                    .end();
                Text("EXPORT")
                    .font(10, 700, TE.text)
                    .fontFamily(TE.font)
                    .end();
            });

            // Refresh — square button
            Button(handleRefresh, .{})
                .width(.px(36))
                .height(.px(36))
                .border(.solid(.all(TE.border_w), TE.border_light, .all(TE.radius_sm)))
                .layout(.center)
                .pointer()
                .children({
                Icon(.arrow_clockwise)
                    .inheritHover(&.{.text_color})
                    .font(16, 700, TE.text)
                    .end();
            });

            // Add task — signature orange button
            Button(openAddModal, .{})
                .padding(.xy(12, 7))
                .background(.{ .color = TE.orange })
                .border(.solid(.all(TE.border_w), TE.orange, .all(TE.radius_sm)))
                .children({
                Icon(.plus)
                    .font(12, 800, .hex("#000000"))
                    .end();
                Text("NEW TASK")
                    .font(10, 800, .hex("#000000"))
                    .fontFamily(TE.font)
                    .end();
            });
        });
    });

    // Progress bar strip — like a hardware status indicator
    Box()
        .width(.percent(100))
        .padding(.xy(24, 8))
        .border(.bottom(1, TE.border_light))
        .layout(.left_center)
        .spacing(12)
        .children({
        Box()
            .spacing(8)
            .padding(.xy(12, 5))
            .border(.solid(.all(TE.border_w), TE.border_light, .all(TE.radius_sm)))
            .layout(.left_center)
            .children({
            Text("PROGRESS").font(9, 700, TE.text_muted).fontFamily(TE.font).end();
            bar.render();
            TextFmt("{d}%", .{total_completed * 100})
                .font(11, 700, TE.orange)
                .fontFamily(TE.font)
                .end();
        });
    });
}

// ============================================================================
// BOARD RENDERING — GRID HEAVY TE STYLE
// ============================================================================

fn renderBoard() void {
    const has_active_filter = filter_priority != null or search_query.len > 0;
    for (std.enums.values(TaskStatus)) |status| {
        const col = collectionForStatus(status);
        if (has_active_filter) {
            col.setFilter(&matchesFilter);
        } else {
            col.clearFilter();
        }
    }

    Box()
        .height(.fit)
        .padding(.all(20))
        .layout(.top_left)
        .spacing(12)
        .scroll(.scroll_x())
        .children({
        for (std.enums.values(TaskStatus)) |status| {
            if (status == .done and !show_completed) continue;
            renderColumn(status, collectionForStatus(status));
        }
    });
}

fn renderColumn(status: TaskStatus, collection: *TaskCollection) void {
    const visible = collection.visibleCount();

    Box()
        .width(.percent(19))
        .direction(.column)
        .border(.solid(.all(TE.border_w), TE.border, .all(TE.radius_md)))
        .spacing(0)
        .children({

        // Column header — chunky panel header with color indicator
        Box()
            .layout(.x_between_center)
            .padding(.xy(12, 8))
            .border(.bottom(TE.border_w, TE.border))
            .children({
            Box()
                .layout(.left_center)
                .spacing(8)
                .children({
                // Status color indicator — small square block
                Box()
                    .width(.px(10))
                    .height(.px(10))
                    .background(.{ .color = status.color() })
                    .border(.round(status.color(), .all(1)))
                    .children({});
                Text(status.label())
                    .font(10, 800, TE.text)
                    .fontFamily(TE.font)
                    .end();
                // Count badge
                Box()
                    .padding(.xy(5, 2))
                    .background(.{ .color = TE.border_light })
                    .border(.round(TE.border_light, .all(TE.radius_sm)))
                    .children({
                    TextFmt("{d}", .{visible})
                        .font(9, 700, TE.text_secondary)
                        .fontFamily(TE.font)
                        .end();
                });
            });

            ButtonCtx(addTaskToColumn, .{status})
                .width(.px(24))
                .height(.px(24))
                .layout(.center)
                .duration(100)
                .border(.solid(.all(1), TE.border_light, .all(TE.radius_sm)))
                .textColor(TE.text_muted)
                .pointer()
                .hover(.{
                    .text_color = TE.orange,
                })
                .children({
                Icon(.plus)
                    .fontSize(14)
                    .end();
            });
        });

        // Sortable surface — task list area
        Box()
            .width(.percent(100))
            .padding(.all(6))
            .children({
            var surface = collection.surface();
            surface.container = surface.container
                .width(.percent(100))
                .height(.grow)
                .spacing(6)
                .scroll(.scroll_y());
            surface
                .render(renderTaskCard);
        });

        // Empty state
        if (visible == 0) {
            Center()
                .height(.px(80))
                .children({
                Stack()
                    .layout(.center)
                    .spacing(6)
                    .children({
                    Text("---")
                        .font(16, 400, TE.text_muted)
                        .fontFamily(TE.font)
                        .end();
                    Text(if (collection.count() > 0) "NO MATCH" else "EMPTY")
                        .font(9, 700, TE.text_muted)
                        .fontFamily(TE.font)
                        .end();
                });
            });
        }
    });
}

// ============================================================================
// TASK CARD — TE EP-133 STYLE
// ============================================================================
// Chunky borders, uppercase labels, monospace type, bright color pops

fn TooltipContent(task: *Task) void {
    progress_bar_tooltip.setProgress(task.percent / 100.0);
    Box()
        .width(.px(260))
        .padding(.all(12))
        .background(TE.bg_card)
        .border(.solid(.all(TE.border_w), TE.border, .all(TE.radius_md)))
        .direction(.column)
        .spacing(10)
        .animationEnter("te-fade-scale")
        .children({
        // Header
        Box()
            .layout(.x_between_center)
            .children({
            Text(task.title)
                .font(12, 700, TE.text)
                .fontFamily(TE.font)
                .width(.px(160))
                .ellipsis(.dot)
                .end();
            Box()
                .padding(.xy(6, 3))
                .background(.transparentizeHex(task.priority.color(), 0.2))
                .border(.solid(.all(1), task.priority.color(), .all(TE.radius_sm)))
                .children({
                Text(task.priority.label())
                    .font(8, 800, task.priority.color())
                    .fontFamily(TE.font)
                    .end();
            });
        });

        // Divider
        Box()
            .width(.percent(100))
            .height(.px(1))
            .background(.{ .color = TE.border })
            .children({});

        // Details
        Stack()
            .width(.percent(100))
            .spacing(6)
            .children({
            if (task.due_date) |due| {
                Box()
                    .width(.percent(100))
                    .layout(.x_between_center)
                    .children({
                    Box()
                        .layout(.left_center)
                        .spacing(4)
                        .children({
                        Icon(.calendar)
                            .font(10, 400, TE.text_muted)
                            .end();
                        Text("DUE")
                            .font(9, 700, TE.text_muted)
                            .fontFamily(TE.font)
                            .end();
                    });
                    Text(due.formatDate(Vapor.arena(.frame)) catch "")
                        .font(10, 500, TE.text)
                        .fontFamily(TE.font)
                        .end();
                });
            }

            Box()
                .width(.percent(100))
                .layout(.x_between_center)
                .children({
                Box()
                    .layout(.left_center)
                    .spacing(4)
                    .children({
                    Icon(.clock)
                        .font(10, 400, TE.text_muted)
                        .end();
                    Text("CREATED")
                        .font(9, 700, TE.text_muted)
                        .fontFamily(TE.font)
                        .end();
                });
                Text(task.created_at)
                    .font(10, 500, TE.text)
                    .fontFamily(TE.font)
                    .end();
            });

            if (task.assignee) |assignee| {
                Box()
                    .width(.percent(100))
                    .layout(.x_between_center)
                    .children({
                    Text("ASSIGNEE")
                        .font(9, 700, TE.text_muted)
                        .fontFamily(TE.font)
                        .end();
                    Text(assignee)
                        .font(10, 500, TE.text)
                        .fontFamily(TE.font)
                        .end();
                });
            }
        });

        // Progress — chunky indicator
        Box()
            .width(.percent(100))
            .padding(.all(8))
            .border(.solid(.all(1), TE.border_light, .all(TE.radius_sm)))
            .layout(.x_between_center)
            .children({
            Text("PROGRESS")
                .font(9, 700, TE.text_muted)
                .fontFamily(TE.font)
                .end();
            Box()
                .layout(.right_center)
                .spacing(8)
                .children({
                progress_bar_tooltip.render();
                TextFmt("{d}%", .{task.percent})
                    .font(10, 700, TE.orange)
                    .fontFamily(TE.font)
                    .end();
            });
        });
    });
}

fn TooltipTrigger(_: []const u8) void {
    Vapor.Image(.{ .src = "/assets/me.webp" })
        .width(.px(24))
        .height(.px(24))
        .radius(.all(TE.radius_sm))
        .end();
}

/// Render function for each task card in the sortable surface.
fn renderTaskCard(task: *Task, index: usize, state: Sortable.ItemState) void {
    _ = index;

    Box()
        .width(.percent(100))
        .padding(.all(10))
        .animationEnter("te-card-enter")
        .border(.solid(
            .all(TE.border_w),
            if (state.is_dragging) TE.orange else TE.border_light,
            .all(TE.radius_md),
        ))
        .opacity(if (state.is_placeholder) 0.3 else 1.0)
        .background(if (state.is_dragging) .transparent else TE.bg_card)
        .direction(.column)
        .spacing(8)
        .pointer()
        .duration(80)
        .hover(.{
            .shadow = .{
                .color = .transparentize(TE.orange, 0.08),
                .blur = 0,
                .top = 0,
                .spread = 2,
            },
        })
        .children({
        // Title row with priority badge
        Box()
            .layout(.x_between_center)
            .children({
            Text(task.title)
                .ellipsis(.dot)
                .font(11, 700, .white)
                .fontFamily(TE.font)
                .width(.percent(65))
                .end();
            // Priority — bold color chip
            Box()
                .padding(.xy(5, 2))
                .background(.transparentizeHex(task.priority.color(), 0.2))
                .border(.solid(.all(1), task.priority.color(), .all(TE.radius_sm)))
                .children({
                Text(task.priority.label())
                    .font(8, 800, task.priority.color())
                    .fontFamily(TE.font)
                    .end();
            });
        });

        // Description — compact
        if (task.description.len > 0) {
            Text(task.description)
                .font(10, 400, TE.text_secondary)
                .fontFamily(TE.font)
                .end();
        }

        // Due date — small label
        if (task.due_date) |due| {
            Box()
                .layout(.left_center)
                .spacing(4)
                .children({
                Icon(.calendar)
                    .font(9, 400, TE.text_muted)
                    .end();
                Text(due.formatDate(Vapor.arena(.frame)) catch "")
                    .font(9, 500, TE.text_muted)
                    .fontFamily(TE.font)
                    .end();
            });
        }

        // Footer — thick top border separator
        Box()
            .width(.percent(100))
            .layout(.x_between_center)
            .padding(.t(6))
            .border(.top(TE.border_w, TE.border_light))
            .children({
            Box()
                .layout(.left_center)
                .spacing(8)
                .width(.px(32))
                .height(.px(28))
                .children({
                if (task.assignee) |assignee| {
                    Tooltip.create(.{
                        .background = .palette(.background),
                        .stroke_color = TE.border,
                    })
                        .Trigger(TooltipTrigger, .{assignee})
                        .Component(TooltipContent, .{task})
                        .end();
                }
            });

            // Actions — compact icon row
            Box()
                .layout(.right_center)
                .spacing(2)
                .children({
                // Progress — numeric + circle
                Box()
                    .height(.px(24))
                    .layout(.center)
                    .background(.transparent)
                    .pointer()
                    .textColor(TE.text_muted)
                    .spacing(4)
                    .children({
                    TextFmt("{d}%", .{task.percent})
                        .fontFamily(TE.font)
                        .font(9, 700, TE.orange)
                        .end();
                    if (task.progress) |*progress| {
                        progress.render();
                    }
                });

                // View
                ButtonCtx(handleViewTask, .{task})
                    .width(.px(22))
                    .height(.px(22))
                    .layout(.center)
                    .background(.transparent)
                    .pointer()
                    .textColor(TE.text_muted)
                    .hover(.{ .text_color = TE.cyan })
                    .children({
                    Icon(.eye)
                        .font(11, 400, null)
                        .end();
                });

                // Move left
                if (canMoveLeft(task.status)) {
                    ButtonCtx(moveTaskLeft, .{task})
                        .width(.px(22))
                        .height(.px(22))
                        .layout(.center)
                        .background(.transparent)
                        .pointer()
                        .textColor(TE.text_muted)
                        .hover(.{ .text_color = TE.yellow })
                        .children({
                        Icon(.chevron_left)
                            .font(11, 400, null)
                            .end();
                    });
                }

                // Move right
                if (canMoveRight(task.status)) {
                    ButtonCtx(moveTaskRight, .{task})
                        .width(.px(22))
                        .height(.px(22))
                        .layout(.center)
                        .background(.transparent)
                        .pointer()
                        .textColor(TE.text_muted)
                        .hover(.{ .text_color = TE.green })
                        .children({
                        Icon(.chevron_right)
                            .font(11, 400, null)
                            .end();
                    });
                }

                // Delete
                ButtonCtx(deleteTaskFromCollection, .{task})
                    .width(.px(22))
                    .height(.px(22))
                    .layout(.center)
                    .background(.transparent)
                    .pointer()
                    .textColor(TE.text_muted)
                    .hover(.{ .text_color = TE.pink })
                    .children({
                    Icon(.trash)
                        .font(11, 400, null)
                        .end();
                });
            });
        });
    });
}

fn gapRender(dir: Sortable.DragContext.Direction) void {
    Vapor.Box()
        .width(if (dir == .horizontal) .px(4) else .percent(100))
        .height(if (dir == .vertical) .px(4) else .percent(100))
        .background(.transparentize(TE.orange, 1))
        // .border(.round(TE.orange, .all(TE.radius_sm)))
        .duration(100)
        .children({});
}

/// Custom drag overlay — TE style floating card
fn renderDragOverlay(task: ?*Task, delta_x: f32, delta_y: f32) void {
    if (task) |t| {
        Box()
            .pos(.tl(.px(delta_y), .px(delta_x), .fixed))
            .zIndex(9999)
            .width(.px(260))
            .padding(.all(12))
            .background(TE.bg_card)
            // .border(.solid(.all(1), TE.orange, .all(TE.radius_md)))
            .direction(.column)
            .spacing(6)
            .children({
            // Title + priority
            Box()
                .layout(.x_between_center)
                .children({
                Text(t.title)
                    .font(11, 700, .white)
                    .fontFamily(TE.font)
                    .width(.px(160))
                    .ellipsis(.dot)
                    .end();
                Box()
                    .padding(.xy(5, 2))
                    .background(.transparentizeHex(t.priority.color(), 0.2))
                    .border(.solid(.all(1), t.priority.color(), .all(TE.radius_sm)))
                    .children({
                    Text(t.priority.label())
                        .font(8, 800, t.priority.color())
                        .fontFamily(TE.font)
                        .end();
                });
            });

            if (t.description.len > 0) {
                Text(t.description)
                    .font(9, 400, TE.text_secondary)
                    .fontFamily(TE.font)
                    .end();
            }

            // Status badge
            Box()
                .padding(.xy(6, 3))
                .background(.transparentizeHex(t.status.color(), 0.15))
                .border(.solid(.all(1), t.status.color(), .all(TE.radius_sm)))
                .children({
                Text(t.status.label())
                    .font(8, 800, t.status.color())
                    .fontFamily(TE.font)
                    .end();
            });
        });
    } else {
        Vapor.Null();
    }
}

// ============================================================================
// MODALS & SHEETS — TE STYLE
// ============================================================================

fn CheckBox(func: anytype, args: anytype) Vapor.ButtonBuilder(.pure) {
    return ButtonCtx(func, args)
        .ariaLabel("Table Row Checkbox")
        .width(.px(20))
        .height(.px(20))
        .cursor(.pointer)
        .duration(80);
}

fn renderAddModal(_: *Alert) void {
    Box()
        .width(.px(460))
        .padding(.all(20))
        .direction(.column)
        .spacing(16)
        .border(.solid(.all(3), TE.orange, .all(TE.radius_md)))
        .animationEnter("te-modal-enter")
        .children({
        // Header — TE panel style
        Box()
            .layout(.x_between_center)
            .padding(.b(12))
            .border(.bottom(TE.border_w, TE.border))
            .children({
            Box()
                .layout(.left_center)
                .spacing(8)
                .children({
                Box()
                    .width(.px(12))
                    .height(.px(12))
                    .background(.{ .color = TE.orange })
                    .border(.round(TE.orange, .all(1)))
                    .children({});
                Text("NEW TASK")
                    .font(16, 800, TE.text)
                    .fontFamily(TE.font)
                    .end();
            });
            ButtonCtx(closeAddModal, .{})
                .width(.px(32))
                .height(.px(32))
                .layout(.center)
                .pointer()
                .border(.solid(.all(TE.border_w), TE.border_light, .all(TE.radius_sm)))
                .children({
                Icon(.x_lg)
                    .font(14, 400, TE.text_secondary)
                    .end();
            });
        });

        // Form
        Stack()
            .spacing(14)
            .children({
            // Title
            Stack()
                .spacing(4)
                .children({
                Text("TITLE")
                    .font(9, 800, TE.text_muted)
                    .fontFamily(TE.font)
                    .end();
                Box()
                    .width(.percent(100))
                    .layout(.left_center)
                    .children({
                    Field.render(.{ .label = "TASK NAME", .value = .{ .string = &new_task_title } });
                });
            });

            // Description
            Stack()
                .spacing(4)
                .children({
                Text("DESCRIPTION")
                    .font(9, 800, TE.text_muted)
                    .fontFamily(TE.font)
                    .end();
                Box()
                    .width(.percent(100))
                    .height(.px(90))
                    .children({
                    Vapor.TextArea()
                        .background(.palette(.background))
                        .bind(&new_task_description)
                        .ariaLabel("Text Area")
                        .width(.percent(100))
                        .height(.percent(100))
                        .outline(.none)
                        .border(.solid(.tblr(TE.border_w, 4, TE.border_w, TE.border_w), TE.border, .all(TE.radius_sm)))
                        .padding(.all(8))
                        .font(12, 400, .palette(.text_color))
                        .fontFamily(TE.font)
                        .resize(.none)
                        .end();
                });
            });

            // Priority selector
            Stack()
                .spacing(4)
                .children({
                Text("PRIORITY")
                    .font(9, 800, TE.text_muted)
                    .fontFamily(TE.font)
                    .end();
                Box()
                    .layout(.left_center)
                    .spacing(6)
                    .children({
                    for (std.enums.values(TaskPriority)) |priority| {
                        const is_selected = new_task_priority == priority;
                        CheckBox(selectPriority, .{priority})
                            .border(.solid(.all(TE.border_w), if (is_selected) priority.color() else TE.border_light, .all(TE.radius_sm)))
                            .layout(.center)
                            .pointer()
                            .children({
                            Box()
                                .width(.px(14))
                                .height(.px(14))
                                .background(.{ .color = if (is_selected) priority.color() else .transparent })
                                .border(.round(.transparent, .all(TE.radius_sm)))
                                .layout(.center)
                                .children({});
                        });
                        Text(priority.label())
                            .font(9, if (is_selected) @as(u32, 800) else @as(u32, 500), if (is_selected) priority.color() else TE.text_secondary)
                            .fontFamily(TE.font)
                            .end();
                    }
                });
            });

            // Status selector
            Stack()
                .spacing(4)
                .children({
                Text("STATUS")
                    .font(9, 800, TE.text_muted)
                    .fontFamily(TE.font)
                    .end();
                Box()
                    .layout(.left_center)
                    .spacing(6)
                    .wrap(.wrap)
                    .children({
                    for (std.enums.values(TaskStatus)) |status| {
                        const is_selected = new_task_status == status;
                        CheckBox(selectStatus, .{status})
                            .border(.solid(.all(TE.border_w), if (is_selected) status.color() else TE.border_light, .all(TE.radius_sm)))
                            .layout(.center)
                            .pointer()
                            .children({
                            Box()
                                .width(.px(14))
                                .height(.px(14))
                                .background(.{ .color = if (is_selected) status.color() else .transparent })
                                .border(.round(.transparent, .all(TE.radius_sm)))
                                .layout(.center)
                                .children({});
                        });
                        Text(status.label())
                            .font(9, if (is_selected) @as(u32, 800) else @as(u32, 500), if (is_selected) status.color() else TE.text_secondary)
                            .fontFamily(TE.font)
                            .end();
                    }
                });
            });
        });

        // Actions — chunky TE buttons
        Box()
            .layout(.right_center)
            .spacing(8)
            .margin(.t(4))
            .children({
            Button(closeAddModal, .{})
                .padding(.xy(14, 8))
                .background(.palette(.text_color))
                .border(.solid(.all(TE.border_w), .palette(.text_color), .all(TE.radius_sm)))
                .children({
                Text("CANCEL")
                    .font(10, 800, .palette(.background))
                    .fontFamily(TE.font)
                    .end();
            });
            Button(addTask, .{})
                .padding(.xy(14, 8))
                .background(.{ .color = TE.orange })
                .border(.solid(.all(TE.border_w), TE.orange, .all(TE.radius_sm)))
                .children({
                Icon(.plus)
                    .font(12, 800, .hex("#000000"))
                    .end();
                Text("CREATE")
                    .font(10, 800, .hex("#000000"))
                    .fontFamily(TE.font)
                    .end();
            });
        });
    });
}

fn renderDetailSheetContent(_: *Sheet) void {
    if (selected_task) |task| {
        Stack()
            .width(.percent(100))
            .height(.percent(100))
            .padding(.all(20))
            .spacing(20)
            .children({
            // Header
            Box()
                .layout(.x_between_center)
                .padding(.b(12))
                .border(.bottom(TE.border_w, TE.border))
                .children({
                Box()
                    .layout(.left_center)
                    .spacing(8)
                    .children({
                    Box()
                        .width(.px(10))
                        .height(.px(10))
                        .background(.{ .color = task.status.color() })
                        .border(.round(task.status.color(), .all(1)))
                        .children({});
                    Text("TASK DETAILS")
                        .font(14, 800, TE.text)
                        .fontFamily(TE.font)
                        .end();
                });
                Button(closeDetailSheet, .{})
                    .width(.px(32))
                    .height(.px(32))
                    .layout(.center)
                    .pointer()
                    .border(.solid(.all(TE.border_w), TE.border_light, .all(TE.radius_sm)))
                    .children({
                    Icon(.x_lg)
                        .font(14, 400, TE.text_secondary)
                        .end();
                });
            });

            // Title and Status badges
            Box()
                .width(.percent(100))
                .padding(.all(16))
                .border(.solid(.all(TE.border_w), TE.border, .all(TE.radius_md)))
                .direction(.column)
                .spacing(10)
                .layout(.center)
                .children({
                Text(task.title)
                    .font(18, 800, TE.text)
                    .fontFamily(TE.font)
                    .end();
                Box()
                    .layout(.center)
                    .spacing(6)
                    .children({
                    Box()
                        .padding(.xy(8, 4))
                        .background(.transparentizeHex(task.status.color(), 0.2))
                        .border(.solid(.all(1), task.status.color(), .all(TE.radius_sm)))
                        .children({
                        Text(task.status.label())
                            .font(9, 800, task.status.color())
                            .fontFamily(TE.font)
                            .end();
                    });
                    Box()
                        .padding(.xy(8, 4))
                        .background(.transparentizeHex(task.priority.color(), 0.2))
                        .border(.solid(.all(1), task.priority.color(), .all(TE.radius_sm)))
                        .children({
                        Text(task.priority.label())
                            .font(9, 800, task.priority.color())
                            .fontFamily(TE.font)
                            .end();
                    });
                });
            });

            // Description
            if (task.description.len > 0) {
                Stack()
                    .width(.percent(100))
                    .spacing(6)
                    .children({
                    Text("DESCRIPTION")
                        .font(9, 800, TE.text_muted)
                        .fontFamily(TE.font)
                        .end();
                    Text(task.description)
                        .font(12, 400, TE.text_secondary)
                        .fontFamily(TE.font)
                        .end();
                });
            }

            // Details grid
            Stack()
                .width(.percent(100))
                .spacing(0)
                .children({
                if (task.assignee) |assignee| {
                    renderDetailRow("ASSIGNEE", assignee);
                }
                if (task.due_date) |due| {
                    renderDetailRow("DUE DATE", due.formatDate(Vapor.arena(.frame)) catch "");
                }
                renderDetailRow("CREATED", task.created_at);
                renderDetailRowFmt("TASK ID", "TASK-{d}", .{task.id});
            });

            // Tags
            if (task.tags.len > 0) {
                Stack()
                    .width(.percent(100))
                    .spacing(6)
                    .children({
                    Text("TAGS")
                        .font(9, 800, TE.text_muted)
                        .fontFamily(TE.font)
                        .end();
                    Box()
                        .layout(.left_center)
                        .spacing(6)
                        .wrap(.wrap)
                        .children({
                        for (task.tags) |tag| {
                            Box()
                                .padding(.xy(8, 4))
                                .background(.palette(.highlight_color))
                                .border(.solid(.all(1), TE.border_light, .all(TE.radius_sm)))
                                .children({
                                Text(tag)
                                    .font(9, 700, TE.text_secondary)
                                    .fontFamily(TE.font)
                                    .end();
                            });
                        }
                    });
                });
            }

            // Actions — chunky TE buttons
            Box()
                .width(.percent(100))
                .layout(.left_center)
                .spacing(8)
                .children({
                Button(closeDetailSheet, .{})
                    .padding(.xy(12, 7))
                    .background(.{ .color = TE.orange })
                    .border(.solid(.all(TE.border_w), TE.orange, .all(TE.radius_sm)))
                    .pointer()
                    .layout(.center)
                    .spacing(6)
                    .children({
                    Icon(.pencil)
                        .font(14, 400, .hex("#000000"))
                        .end();
                    Text("EDIT")
                        .font(10, 800, .hex("#000000"))
                        .fontFamily(TE.font)
                        .end();
                });
                Button(closeDetailSheet, .{})
                    .padding(.xy(12, 7))
                    .background(TE.bg_elevated)
                    .border(.solid(.all(TE.border_w), TE.border_light, .all(TE.radius_sm)))
                    .pointer()
                    .layout(.center)
                    .spacing(6)
                    .children({
                    Icon(.link)
                        .font(14, 400, TE.text_secondary)
                        .end();
                    Text("COPY LINK")
                        .font(10, 800, TE.text_secondary)
                        .fontFamily(TE.font)
                        .end();
                });
            });
        });
    }
}

fn renderDetailRow(label_text: []const u8, value: []const u8) void {
    Box()
        .width(.percent(100))
        .layout(.x_between_center)
        .padding(.xy(0, 10))
        .border(.bottom(1, TE.border_light))
        .children({
        Text(label_text)
            .font(9, 800, TE.text_muted)
            .fontFamily(TE.font)
            .end();
        Text(value)
            .font(11, 600, TE.text)
            .fontFamily(TE.font)
            .end();
    });
}

fn renderDetailRowFmt(label_text: []const u8, comptime fmt: []const u8, args: anytype) void {
    Box()
        .width(.percent(100))
        .layout(.x_between_center)
        .padding(.xy(0, 10))
        .border(.bottom(1, TE.border_light))
        .children({
        Text(label_text)
            .font(9, 800, TE.text_muted)
            .fontFamily(TE.font)
            .end();
        TextFmt(fmt, args)
            .font(11, 600, TE.text)
            .fontFamily(TE.font)
            .end();
    });
}

// ============================================================================
// MAIN RENDER
// ============================================================================

pub fn render() void {
    Box()
        .width(.percent(100))
        .height(.percent(100))
        .background(TE.bg_base)
        .layout(.top_left)
        .children({

        // Main content area
        Stack()
            .width(.percent(100))
            .height(.percent(100))
            .children({
            renderHeader();
            renderBoard();
        });

        // Custom drag overlay
        drag_ctx.dragLayerTyped(Task, renderDragOverlay);

        // Overlays
        detail_sheet.render();
        alert.render();
    });
}
