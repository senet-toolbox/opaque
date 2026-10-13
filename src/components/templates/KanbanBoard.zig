// Kanban board - styled to match Dashboard theme
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

// Import UI Components (matching Dashboard imports)
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
            .low => .hex("#1E00FF"),
            .medium => .hex("#FFD900"),
            .high => .hex("#C300FF"),
            .urgent => .palette(.danger),
        };
    }

    pub fn label(self: TaskPriority) []const u8 {
        return switch (self) {
            .low => "Low",
            .medium => "Medium",
            .high => "High",
            .urgent => "Urgent",
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
            .backlog => "Backlog",
            .todo => "To Do",
            .in_progress => "In Progress",
            .review => "Review",
            .done => "Done",
        };
    }

    pub fn color(self: TaskStatus) Vapor.Types.Color {
        return switch (self) {
            .backlog => .hex("#6b7280"),
            .todo => .hex("#3b82f6"),
            .in_progress => .hex("#8b5cf6"),
            .review => .hex("#f59e0b"),
            .done => .hex("#10b981"),
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
};

// ============================================================================
// STATE
// ============================================================================

var tasks: Vapor.Array(Task) = undefined;
var next_task_id: usize = 100;
var show_add_modal: bool = false;
var editing_task: ?*Task = null;
var dragging_task: ?*Task = null;
var hover_column: ?TaskStatus = null;
var search_query: []const u8 = "";
var filter_priority: ?TaskPriority = null;
var show_completed: bool = true;
var selected_task: ?*const Task = null;

// New task form state
var new_task_title: []const u8 = "";
var new_task_description: []const u8 = "";
var new_task_priority: TaskPriority = .medium;
var new_task_status: TaskStatus = .todo;

// Component instances
var detail_sheet: Sheet = undefined;
var priority_filter: Select(TaskPriority) = undefined;
var status_select: Select(TaskStatus) = undefined;
var alert: Alert = undefined;

// Select options
var priority_options = [_]Select(TaskPriority).Item{
    .{ .value = .low, .label = "Low" },
    .{ .value = .medium, .label = "Medium" },
    .{ .value = .high, .label = "High" },
    .{ .value = .urgent, .label = "Urgent" },
};

var status_options = [_]Select(TaskStatus).Item{
    .{ .value = .backlog, .label = "Backlog" },
    .{ .value = .todo, .label = "To Do" },
    .{ .value = .in_progress, .label = "In Progress" },
    .{ .value = .review, .label = "Review" },
    .{ .value = .done, .label = "Done" },
};

// ============================================================================
// THEME (Matching Dashboard Theme)
// ============================================================================

const Theme = struct {
    const bg_base = Vapor.Types.Color.palette(.background);
    const bg_card = Vapor.Types.Color.palette(.background);
    const bg_elevated = Vapor.Types.Color.palette(.background);
    const bg_hover = Vapor.Types.Color.hex("#3f3f46");
    const border = Vapor.Types.Color.hex("#27272a");
    const border_light = Vapor.Types.Color.hex("#3f3f46");
    const text = Vapor.Types.Color.palette(.text_color);
    const text_secondary = Vapor.Types.Color.hex("#a1a1aa");
    const text_muted = Vapor.Types.Color.hex("#71717a");
    const accent = Vapor.Types.Color.hex("#6366f1");
    const accent_hover = Vapor.Types.Color.hex("#818cf8");
    const success = Vapor.Types.Color.hex("#10b981");
    const warning = Vapor.Types.Color.hex("#F5590B");
    const err = Vapor.Types.Color.palette(.danger);
    const gradient_start = Vapor.Types.Color.hex("#6366f1");
    const gradient_end = Vapor.Types.Color.hex("#8b5cf6");
};

// ============================================================================
// ANIMATIONS (Matching Dashboard Animation Style)
// ============================================================================

const pulse_glow = Animation.init("kanban-pulse-glow")
    .prop(.opacity, 1, 0.5)
    .duration(2000)
    .dir(.alternate)
    .infinite();

const slide_up = Animation.init("kanban-slide-up")
    .prop(.translateY, 20, 0)
    .prop(.opacity, 0, 1)
    .duration(300)
    .easing(.easeOut)
    .fill(.forwards);

const fade_scale = Animation.init("kanban-fade-scale")
    .prop(.scale, 0.95, 1)
    .prop(.opacity, 0, 1)
    .duration(200)
    .easing(.easeOut)
    .fill(.forwards);

const card_enter = Animation.init("kanban-card-enter")
    .prop(.translateY, 10, 0)
    .prop(.opacity, 0, 1)
    .duration(200)
    .easing(.easeOut)
    .fill(.forwards);

const modal_enter = Animation.init("kanban-modal-enter")
    .prop(.scale, 0.95, 1)
    .prop(.opacity, 0, 1)
    .duration(200)
    .easing(.easeOutBack)
    .fill(.forwards);

// ============================================================================
// SAMPLE DATA
// ============================================================================

fn createProgressCircle() ProgressCircle {
    return ProgressCircle.init(Vapor.arena(.persist), .{
        .size = 16,
        .stroke_width = 2,
        .track_color = .palette(.highlight_color),
        .color = .palette(.text_color),
        .clockwise = false,
        .show_label = false,
    });
}

var rand = std.Random.DefaultPrng.init(0);
fn initSampleData() void {
    tasks.appendSlice(&.{
        Task{ .id = 1, .title = "Design system setup", .description = "Create color tokens, typography scale, and spacing system", .status = .done, .priority = .high, .assignee = "Sarah", .tags = &.{ "design", "foundation" }, .due_date = DateTime.fromDayMonthYear(1, 1, 2026), .created_at = "Jan 5" },
        .{ .id = 2, .title = "User authentication flow", .description = "Implement login, signup, and password reset", .status = .in_progress, .priority = .urgent, .assignee = "Mike", .tags = &.{ "backend", "security" }, .due_date = DateTime.fromDayMonthYear(13, 1, 2026), .created_at = "Jan 8" },
        .{ .id = 3, .title = "Dashboard wireframes", .description = "Create low-fidelity wireframes for main dashboard", .status = .review, .priority = .medium, .assignee = "Sarah", .tags = &.{"design"}, .due_date = DateTime.fromDayMonthYear(8, 1, 2026), .created_at = "Jan 6" },
        .{ .id = 4, .title = "API documentation", .description = "Document all REST endpoints with examples", .status = .todo, .priority = .low, .assignee = "Alex", .tags = &.{ "docs", "api" }, .due_date = DateTime.fromDayMonthYear(21, 1, 2026), .created_at = "Jan 20" },
        .{ .id = 5, .title = "Database schema review", .description = "Review and optimize current database schema", .status = .backlog, .priority = .medium, .assignee = null, .tags = &.{ "backend", "database" }, .due_date = null, .created_at = "Jan 10" },
        .{ .id = 6, .title = "Mobile responsive layout", .description = "Ensure all pages work on mobile devices", .status = .todo, .priority = .high, .assignee = "Sarah", .tags = &.{ "frontend", "mobile" }, .due_date = DateTime.fromDayMonthYear(12, 8, 2026), .created_at = "Jan 7" },
        .{ .id = 7, .title = "Unit test coverage", .description = "Increase test coverage to 80%", .status = .in_progress, .priority = .medium, .assignee = "Mike", .tags = &.{ "testing", "quality" }, .due_date = DateTime.fromDayMonthYear(17, 4, 2026), .created_at = "Jan 11" },
        .{ .id = 8, .title = "Performance audit", .description = "Run Lighthouse and optimize critical metrics", .status = .backlog, .priority = .low, .assignee = null, .tags = &.{"performance"}, .due_date = null, .created_at = "Jan 12" },
        .{ .id = 9, .title = "Notification system", .description = "Build real-time notification infrastructure", .status = .todo, .priority = .high, .assignee = "Alex", .tags = &.{ "backend", "realtime" }, .due_date = DateTime.fromDayMonthYear(3, 6, 2026), .created_at = "Jan 10" },
        .{ .id = 10, .title = "Settings page", .description = "User preferences and account settings UI", .status = .review, .priority = .medium, .assignee = "Sarah", .tags = &.{ "frontend", "ui" }, .due_date = DateTime.fromDayMonthYear(28, 4, 2026), .created_at = "Jan 8" },
    }) catch |err| Vapor.printErr("Failed to init tasks: {any}", .{err});

    for (tasks.items) |*task| {
        var progress_circle = createProgressCircle();
        const rand_value: f64 = @floatFromInt(rand.random().intRangeAtMost(u32, 0, 100));
        progress_circle.setProgress(rand_value / 100); // 75%
        task.progress = progress_circle;
        task.percent = rand_value;
    }
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
    editing_task = null;
}

fn addTask() void {
    if (new_task_title.len == 0) return;

    var progress_circle = createProgressCircle();
    const rand_value: f64 = @floatFromInt(rand.random().intRangeAtMost(u32, 0, 100));
    progress_circle.setProgress(rand_value / 100); // 75%

    const task = Task{
        .id = next_task_id,
        .title = Vapor.arena(.persist).dupe(u8, new_task_title) catch return,
        .description = Vapor.arena(.persist).dupe(u8, new_task_description) catch return,
        .status = new_task_status,
        .priority = new_task_priority,
        .assignee = null,
        .tags = &.{},
        .due_date = null,
        .created_at = "Today",
        .progress = progress_circle,
        .percent = rand_value,
    };

    tasks.append(task) catch return;
    next_task_id += 1;
    closeAddModal();
    Toast.success(.{ .title = "Task Created", .description = "New task has been added to the board" });
}

fn moveTask(task: *Task, new_status: TaskStatus) void {
    task.status = new_status;
}

fn deleteTask(task: *Task) void {
    for (tasks.items, 0..) |*t, i| {
        if (t.id == task.id) {
            _ = tasks.orderedRemove(i);
            break;
        }
    }
    Toast.warning(.{ .title = "Task Deleted", .description = "This action cannot be undone" });
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
        Toast.info(.{ .title = "Showing Completed", .description = "Done tasks are now visible" });
    } else {
        Toast.info(.{ .title = "Hiding Completed", .description = "Done tasks are now hidden" });
    }
}

fn clearFilter() void {
    filter_priority = null;
}

fn setFilterPriority(_: *Select(TaskPriority), item: *Select(TaskPriority).Item) void {
    if (filter_priority == item.value) {
        filter_priority = null;
    } else {
        filter_priority = item.value;
    }
}

fn handleExport() void {
    Toast.info(.{ .title = "Exporting Data", .description = "Your board data will be ready shortly" });
}

fn handleRefresh() void {
    Toast.success(.{ .title = "Board Refreshed", .description = "All tasks are up to date" });
}

// ============================================================================
// INITIALIZATION
// ============================================================================

var bar: ProgressBar = undefined;
var progress_bar_tooltip: ProgressBar = undefined;

const total_completed: f64 = 0.34;
pub fn init() void {
    // Build animations
    pulse_glow.build();
    slide_up.build();
    fade_scale.build();
    card_enter.build();
    modal_enter.build();

    // Initialize component libraries
    SelectStruct.new();
    ToastStruct.new();
    SheetStruct.new();
    FieldStruct.new();
    TooltipStruct.new();
    SwitchStruct.new();
    GroupStruct.new();

    // Initialize data
    tasks = Vapor.array(Task, .persist);
    initSampleData();

    // Initialize selects
    priority_filter = .fromItems(&priority_options);
    priority_filter.trigger = "Priority";
    priority_filter.on_select = setFilterPriority;

    status_select = .fromItems(&status_options);
    status_select.trigger = "Status";

    // Initialize sheet
    detail_sheet = Sheet.init(.right);
    detail_sheet.content = renderDetailSheetContent;
    alert = .init(renderAddModal);

    bar = ProgressBar.init(Vapor.arena(.persist), .{
        .width = 128,
        .height = 6,
        .color = .palette(.tint),
        .background = .transparentize(.palette(.text_color), 0.1),
    });
    bar.setProgress(total_completed);

    progress_bar_tooltip = ProgressBar.init(Vapor.arena(.persist), .{
        .width = 128,
        .height = 6,
        .color = .palette(.tint),
        .background = .transparentize(.palette(.text_color), 0.1),
    });
    progress_bar_tooltip.setProgress(0);
}

// ============================================================================
// COMPONENTS
// ============================================================================

fn renderNavigation() void {
    Stack()
        .width(.px(240))
        .height(.percent(100))
        .padding(.all(20))
        .spacing(24)
        .children({
        // Logo
        Box()
            .layout(.left_center)
            .spacing(12)
            .children({
            Box()
                .width(.px(40))
                .height(.px(40))
                .background(.black)
                .border(.round(.black, .all(8)))
                .layout(.center)
                .children({
                Icon(.kanban)
                    .font(20, 700, .white)
                    .end();
            });
            Stack()
                .spacing(0)
                .children({
                Text("Kanban")
                    .font(20, 700, Theme.text)
                    .fontFamily("Montserrat")
                    .end();
                Text("Board")
                    .font(11, 500, Theme.text_muted)
                    .fontFamily("Montserrat")
                    .end();
            });
        });

        // Navigation Items
        Stack()
            .width(.percent(100))
            .spacing(4)
            .children({
            Text("VIEWS")
                .font(10, 600, Theme.text_muted)
                .fontFamily("Montserrat")
                .margin(.b(8))
                .end();

            renderNavButton("Board", .kanban, true);
            renderNavButton("List", .list_ul, false);
            renderNavButton("Calendar", .calendar, false);
            renderNavButton("Timeline", .bar_chart_line, false);
        });

        // Stats Section
        Stack()
            .width(.percent(100))
            .spacing(4)
            .children({
            Text("STATISTICS")
                .font(10, 600, Theme.text_muted)
                .fontFamily("Montserrat")
                .margin(.b(8))
                .end();

            renderStatRow("Total Tasks", tasks.items.len);
            renderStatRow("In Progress", countByStatus(.in_progress));
            renderStatRow("Completed", countByStatus(.done));
        });

        // Spacer
        Box().height(.grow).children({});

        // User profile
        Box()
            .width(.percent(100))
            .padding(.all(8))
            .layout(.left_center)
            .spacing(12)
            .children({
            Stack()
                .spacing(0)
                .width(.grow)
                .children({
                Text("Vic Rokx")
                    .font(14, 500, Theme.text)
                    .fontFamily("Montserrat")
                    .end();
                Text("Project Manager")
                    .font(12, 400, Theme.text_muted)
                    .fontFamily("Montserrat")
                    .end();
            });
            Icon(.chevron_expand)
                .font(14, 400, Theme.text_muted)
                .end();
        });
    });
}

fn renderNavButton(label: []const u8, nav_icon: *const Vapor.IconTokens, is_active: bool) void {
    Box()
        .width(.percent(100))
        .padding(.xy(14, 4))
        .background(if (is_active) .transparentizeHex(.palette(.tint), 0.1) else .transparent)
        .border(.r(1, if (is_active) .palette(.tint) else .transparent))
        .layer(if (is_active) .dot(0.5, 6, .transparentizeHex(.palette(.tint), 0.3)) else null)
        .layout(.left_center)
        .spacing(12)
        .pointer()
        .duration(150)
        .hover(.{
            .background = if (is_active) .transparentizeHex(.palette(.tint), 0.1) else .palette(.highlight_color),
        })
        .children({
        Box()
            .width(.px(32))
            .height(.px(32))
            .layout(.center)
            .children({
            Icon(nav_icon)
                .font(16, 400, if (is_active) .palette(.tint) else Theme.text_secondary)
                .end();
        });
        Text(label)
            .font(14, if (is_active) @as(u32, 500) else @as(u32, 400), if (is_active) .palette(.tint) else Theme.text_secondary)
            .fontFamily("Montserrat")
            .end();
    });
}

fn renderStatRow(label: []const u8, count: usize) void {
    Box()
        .width(.percent(100))
        .padding(.xy(14, 8))
        .layout(.x_between_center)
        .children({
        Text(label)
            .font(13, 400, Theme.text_secondary)
            .fontFamily("Montserrat")
            .end();
        TextFmt("{d}", .{count})
            .font(13, 600, Theme.text)
            .fontFamily("Montserrat")
            .end();
    });
}

fn renderHeader() void {
    Box()
        .width(.percent(100))
        .height(.px(72))
        .padding(.horizontal(28))
        .background(Theme.bg_base)
        .layout(.x_between_center)
        .children({
        // Left: Title
        Stack()
            .spacing(4)
            .layout(.left_center)
            .children({
            Text("Kanban Board")
                .font(24, 700, Theme.text)
                .fontFamily("Montserrat")
                .end();
        });

        // Right: Controls
        Box()
            .layout(.right_center)
            .spacing(12)
            .children({

            // Search
            Box()
                .width(.px(200))
                .layout(.left_center)
                .spacing(8)
                .children({
                Field.render(.{ .label = "Search...", .value = .{ .string = &search_query } });
            });

            // Priority filter
            Box()
                .width(.px(140))
                .children({
                priority_filter.renderPos(.bottom);
            });

            // Toggle completed
            Button(toggleCompleted, .{})
                .padding(.xy(14, 9))
                .children({
                if (show_completed) {
                    Box()
                        .width(.px(8))
                        .height(.px(8))
                        .background(.palette(.tint))
                        .border(.round(.palette(.tint), .all(99)))
                        .animation("kanban-pulse-glow")
                        .children({});
                }
                Text(if (show_completed) "Hide Done" else "Show Done")
                    .font(13, 500, if (show_completed) .palette(.tint) else Theme.text_secondary)
                    .fontFamily("Montserrat")
                    .end();
            });

            Button(handleExport, .{})
                .padding(.xy(14, 9))
                .children({
                Text("Export")
                    .font(13, 500, .palette(.text_color))
                    .fontFamily("Montserrat")
                    .end();
                Icon(.download)
                    .font(14, 400, .palette(.text_color))
                    .end();
            });

            // Refresh button
            Button(handleRefresh, .{})
                .width(.px(40))
                .height(.px(40))
                .layout(.center)
                .pointer()
                .children({
                Icon(.arrow_clockwise)
                    .inheritHover(&.{.text_color})
                    .font(18, 700, .palette(.text_color))
                    .end();
            });

            // Add task button
            Button(openAddModal, .{})
                .padding(.xy(14, 9))
                .background(.palette(.tint))
                .children({
                Icon(.plus)
                    .font(14, 600, .palette(.background))
                    .end();
                Text("Add Task")
                    .font(13, 500, .palette(.background))
                    .fontFamily("Montserrat")
                    .end();
            });
        });
    });

    Box()
        .width(.percent(100))
        .padding(.horizontal(28))
        .layout(.left_center)
        .spacing(16)
        .children({
        Box()
            .spacing(8)
            .padding(.xy(16, 6))
            .border(.round(.palette(.border_color_light), .all(6)))
            .layout(.left_center)
            .children({
            Text("Board Progress").font(14, 300, Theme.text).end();
            bar.render();
            TextFmt("{d}%", .{total_completed * 100})
                .font(14, 300, Theme.text)
                .fontFamily("Montserrat")
                .end();
        });
    });
}

fn countByStatus(status: TaskStatus) usize {
    var count: usize = 0;
    for (tasks.items) |task| {
        if (task.status == status) count += 1;
    }
    return count;
}

fn renderBoard() void {
    Box()
        // .width(.percent(100))
        .height(.fit)
        .padding(.all(28))
        .layout(.top_left)
        .spacing(20)
        .scroll(.scroll_x())
        .children({
        // Render columns for each status
        for (std.enums.values(TaskStatus)) |status| {
            if (status == .done and !show_completed) continue;
            renderColumn(status);
        }
    });
}

fn renderColumn(status: TaskStatus) void {
    const is_drop_target = hover_column == status and dragging_task != null;
    const task_count = countByStatus(status);

    Box()
        .width(.percent(19))
        // .height(.percent(100))
        .direction(.column)
        .border(.round(if (is_drop_target) status.color() else .palette(.border_color_light), .all(20)))
        .padding(.all(8))
        .spacing(12)
        .children({
        // Column header
        Box()
            .layout(.x_between_center)
            .children({
            Box()
                .layout(.left_center)
                .spacing(10)
                .children({
                Box()
                    .padding(.xy(8, 4))
                    .children({
                    TextFmt("{d}", .{task_count})
                        .font(14, 300, null)
                        .end();
                });
                Text(status.label())
                    .font(16, 300, Theme.text)
                    .fontFamily("Montserrat")
                    .end();
            });

            ButtonCtx(addTaskToColumn, .{status})
                .layout(.center)
                .duration(100)
                .textColor(Theme.text_muted)
                .pointer()
                .hover(.{
                    .text_color = .palette(.highlight_color),
                })
                .children({
                Icon(.plus)
                    .fontSize(22)
                    .end();
            });
        });

        // Tasks list
        Stack()
            .width(.percent(100))
            .height(.grow)
            .spacing(10)
            .scroll(.scroll_y())
            .children({
            for (tasks.items) |*task| {
                if (task.status != status) continue;
                if (!matchesFilter(task)) continue;
                renderTaskCard(task);
            }

            // Empty state
            if (task_count == 0) {
                Center()
                    .height(.px(100))
                    .children({
                    Stack()
                        .layout(.center)
                        .spacing(8)
                        .children({
                        Icon(.inbox)
                            .font(24, 400, Theme.text_muted)
                            .end();
                        Text("No tasks")
                            .font(13, 400, Theme.text_muted)
                            .fontFamily("Montserrat")
                            .end();
                    });
                });
            }
        });
    });
}

fn addTaskToColumn(status: TaskStatus) void {
    new_task_status = status;
    openAddModal();
}

fn matchesFilter(task: *const Task) bool {
    // Priority filter
    if (filter_priority) |priority| {
        if (task.priority != priority) return false;
    }

    // Search filter
    if (search_query.len > 0) {
        const title_lower = std.ascii.allocLowerString(Vapor.arena(.frame), task.title) catch return true;
        const query_lower = std.ascii.allocLowerString(Vapor.arena(.frame), search_query) catch return true;
        if (std.mem.indexOf(u8, title_lower, query_lower) == null) return false;
    }

    return true;
}

fn TooltipContent(task: *Task) void {
    progress_bar_tooltip.setProgress(task.percent / 100.0);
    Box()
        .width(.px(280))
        .padding(.all(16))
        .background(Theme.bg_card)
        .border(.round(.palette(.border_color_light), .all(12)))
        .direction(.column)
        .spacing(12)
        .animationEnter("kanban-fade-scale")
        .children({
        // Header with title and priority badge
        Box()
            .layout(.x_between_center)
            .children({
            Text(task.title)
                .font(14, 600, Theme.text)
                .fontFamily("Montserrat")
                .width(.px(180))
                .ellipsis(.dot)
                .end();
            Box()
                .padding(.xy(8, 4))
                .background(.transparentizeHex(task.priority.color(), 0.2))
                .border(.round(task.priority.color(), .all(6)))
                .children({
                Text(task.priority.label())
                    .font(10, 500, task.priority.color())
                    .fontFamily("Montserrat")
                    .end();
            });
        });

        // Divider
        Box()
            .width(.percent(100))
            .height(.px(1))
            .background(.{ .color = .palette(.border_color_light) })
            .children({});

        // Details section
        Stack()
            .width(.percent(100))
            .spacing(8)
            .children({
            // Due date
            if (task.due_date) |due| {
                Box()
                    .width(.percent(100))
                    .layout(.x_between_center)
                    .children({
                    Box()
                        .layout(.left_center)
                        .spacing(6)
                        .children({
                        Icon(.calendar)
                            .font(12, 400, Theme.text_muted)
                            .end();
                        Text("Due date")
                            .font(12, 400, Theme.text_muted)
                            .fontFamily("Montserrat")
                            .end();
                    });
                    Text(due.formatDate(Vapor.arena(.frame)) catch "")
                        .font(12, 500, Theme.text)
                        .fontFamily("Montserrat")
                        .end();
                });
            }

            // Created
            Box()
                .width(.percent(100))
                .layout(.x_between_center)
                .children({
                Box()
                    .layout(.left_center)
                    .spacing(6)
                    .children({
                    Icon(.clock)
                        .font(12, 400, Theme.text_muted)
                        .end();
                    Text("Created")
                        .font(12, 400, Theme.text_muted)
                        .fontFamily("Montserrat")
                        .end();
                });
                Text(task.created_at)
                    .font(12, 500, Theme.text)
                    .fontFamily("Montserrat")
                    .end();
            });

            // Assignee
            if (task.assignee) |assignee| {
                Box()
                    .width(.percent(100))
                    .layout(.x_between_center)
                    .children({
                    Box()
                        .layout(.left_center)
                        .spacing(6)
                        .children({
                        Text("Assignee")
                            .font(12, 400, Theme.text_muted)
                            .fontFamily("Montserrat")
                            .end();
                    });
                    Box()
                        .layout(.right_center)
                        .spacing(6)
                        .children({
                        Text(assignee)
                            .font(12, 500, Theme.text)
                            .fontFamily("Montserrat")
                            .end();
                    });
                });
            }
        });

        // Progress section
        Box()
            .width(.percent(100))
            .padding(.all(10))
            .border(.round(.palette(.border_color_light), .all(8)))
            .layout(.x_between_center)
            .children({
            Text("Progress")
                .font(12, 400, Theme.text_muted)
                .fontFamily("Montserrat")
                .end();
            Box()
                .layout(.right_center)
                .spacing(10)
                .children({
                progress_bar_tooltip.render();
                TextFmt("{d}%", .{task.percent})
                    .font(12, 600, Theme.text)
                    .fontFamily("Montserrat")
                    .end();
            });
        });
    });
}
fn TooltipTrigger(_: []const u8) void {
    Vapor.Image(.{ .src = "/assets/me.webp" })
        .width(.px(28))
        .height(.px(28))
        .radius(.all(999))
        .end();
}

fn renderTaskCard(task: *Task) void {
    Box()
        .width(.percent(100))
        .padding(.t(14))
        .animationEnter("kanban-card-enter")
        .border(.round(.palette(.border_color_light), .all(20)))
        .direction(.column)
        .spacing(10)
        .pointer()
        .hover(.{})
        .children({
        // Title and priority
        Box()
            .padding(.horizontal(14))
            .layout(.x_between_center)
            .children({
            Text(task.title)
                .ellipsis(.dot)
                .font(14, 500, Theme.text)
                .fontFamily("Montserrat")
                .width(.percent(70))
                .end();
            Box()
                .padding(.xy(6, 3))
                .children({
                Text(task.priority.label())
                    .font(10, 300, task.priority.color())
                    .fontFamily("Montserrat")
                    .end();
            });
        });

        // Description
        if (task.description.len > 0) {
            Text(task.description)
                .padding(.horizontal(14))
                .font(12, 400, Theme.text_secondary)
                .fontFamily("Montserrat")
                .end();
        }

        // Due date
        if (task.due_date) |due| {
            Box()
                .padding(.horizontal(14))
                .layout(.left_center)
                .spacing(4)
                .children({
                Icon(.calendar)
                    .font(11, 400, Theme.text_muted)
                    .end();
                Text(due.formatDate(Vapor.arena(.frame)) catch "")
                    .font(11, 400, Theme.text_muted)
                    .fontFamily("Montserrat")
                    .end();
            });
        }

        // Footer: Assignee, due date, actions
        Box()
            .width(.percent(100))
            .layout(.x_between_center)
            .padding(.xy(10, 4))
            .border(.top(1, .palette(.border_color_light)))
            .children({
            Box()
                .layout(.left_center)
                .spacing(12)
                .width(.px(36))
                .height(.px(36))
                .children({
                // Assignee
                if (task.assignee) |assignee| {
                    Tooltip.create(.{
                        .background = .palette(.background),
                        .stroke_color = .palette(.border_color_light),
                    })
                        .Trigger(TooltipTrigger, .{assignee})
                        .Component(TooltipContent, .{task})
                        .end();
                }
            });

            // Actions
            Box()
                .layout(.right_center)
                .spacing(4)
                .children({
                Box()
                    .height(.px(24))
                    .layout(.center)
                    .background(.transparent)
                    .pointer()
                    .textColor(Theme.text_muted)
                    .spacing(8)
                    .children({
                    TextFmt("{d}%", .{task.percent})
                        .fontFamily("Montserrat")
                        .font(12, 400, null)
                        .end();
                    if (task.progress) |*progress| {
                        progress.render();
                    }
                });

                // View
                ButtonCtx(handleViewTask, .{task})
                    .width(.px(24))
                    .height(.px(24))
                    .layout(.center)
                    .background(.transparent)
                    .pointer()
                    .textColor(Theme.text_muted)
                    .hover(.{ .text_color = .palette(.highlight_color) })
                    .children({
                    Icon(.eye)
                        .font(12, 400, null)
                        .end();
                });

                // Move left
                if (canMoveLeft(task.status)) {
                    ButtonCtx(moveTaskLeft, .{task})
                        .width(.px(24))
                        .height(.px(24))
                        .layout(.center)
                        .background(.transparent)
                        .pointer()
                        .textColor(Theme.text_muted)
                        .hover(.{ .text_color = .palette(.highlight_color) })
                        .children({
                        Icon(.chevron_left)
                            .font(12, 400, null)
                            .end();
                    });
                }
                //
                // Move right
                if (canMoveRight(task.status)) {
                    ButtonCtx(moveTaskRight, .{task})
                        .width(.px(24))
                        .height(.px(24))
                        .layout(.center)
                        .background(.transparent)
                        .pointer()
                        .textColor(Theme.text_muted)
                        .hover(.{ .text_color = .palette(.tint) })
                        .children({
                        Icon(.chevron_right)
                            .font(12, 400, null)
                            .end();
                    });
                }

                // Delete
                ButtonCtx(deleteTask, .{task})
                    .width(.px(24))
                    .height(.px(24))
                    .layout(.center)
                    .background(.transparent)
                    .pointer()
                    .textColor(Theme.text_muted)
                    .hover(.{ .text_color = .palette(.danger) })
                    .children({
                    Icon(.trash)
                        .font(14, 400, null)
                        .end();
                });
            });
        });
    });
}

fn canMoveLeft(status: TaskStatus) bool {
    return status != .backlog;
}

fn canMoveRight(status: TaskStatus) bool {
    return status != .done;
}

fn moveTaskLeft(task: *Task) void {
    task.status = switch (task.status) {
        .backlog => .backlog,
        .todo => .backlog,
        .in_progress => .todo,
        .review => .in_progress,
        .done => .review,
    };
}

fn moveTaskRight(task: *Task) void {
    task.status = switch (task.status) {
        .backlog => .todo,
        .todo => .in_progress,
        .in_progress => .review,
        .review => .done,
        .done => .done,
    };
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

fn renderAddModal(_: *Alert) void {

    // Modal
    Box()
        .width(.px(480))
        .padding(.all(24))
        .direction(.column)
        .spacing(20)
        .animationEnter("kanban-modal-enter")
        .children({
        // Header
        Box()
            .layout(.x_between_center)
            .children({
            Text("Add New Task")
                .font(20, 700, Theme.text)
                .fontFamily("Montserrat")
                .end();
            ButtonCtx(closeAddModal, .{})
                .width(.px(36))
                .height(.px(36))
                .layout(.center)
                .pointer()
                .children({
                Icon(.x_lg)
                    .font(16, 400, Theme.text_secondary)
                    .end();
            });
        });

        // Form
        Stack()
            .spacing(16)
            .children({
            // Title
            Stack()
                .spacing(6)
                .children({
                Text("Title")
                    .font(13, 500, Theme.text_secondary)
                    .fontFamily("Montserrat")
                    .end();
                Box()
                    .width(.percent(100))
                    .layout(.left_center)
                    .children({
                    Field.render(.{ .label = "Title", .value = .{ .string = &new_task_title } });
                });
            });

            // Description
            Stack()
                .spacing(6)
                .children({
                Text("Description")
                    .font(13, 500, Theme.text_secondary)
                    .fontFamily("Montserrat")
                    .end();
                Box()
                    .width(.percent(100))
                    .height(.px(100))
                    .children({
                    Vapor.TextArea()
                        .background(.palette(.background))
                        .bind(&new_task_description)
                        .ariaLabel("Text Area")
                        .width(.percent(100))
                        .height(.percent(100))
                        .outline(.none)
                        .border(.solid(.tblr(1, 3, 1, 1), .palette(.border_color_light), .all(6)))
                        .padding(.all(8))
                        .font(16, 300, .palette(.text_color))
                        .fontFamily("IBM Plex Sans,monospace")
                        .resize(.none)
                        .end();
                });
            });

            // Priority selector
            Stack()
                .spacing(6)
                .children({
                Text("Priority")
                    .font(13, 500, Theme.text_secondary)
                    .fontFamily("Montserrat")
                    .end();
                Box()
                    .layout(.left_center)
                    .spacing(8)
                    .children({
                    for (std.enums.values(TaskPriority)) |priority| {
                        const is_selected = new_task_priority == priority;
                        CheckBox(selectPriority, .{priority})
                            .border(.round(if (is_selected) priority.color() else .palette(.border_color_light), .all(6)))
                            .layout(.center)
                            .pointer()
                            .children({
                            Box()
                                .width(.px(14))
                                .height(.px(14))
                                .background(.{ .color = if (is_selected) priority.color() else .transparent })
                                .border(.round(.transparent, .all(4)))
                                .hoverScale()
                                .layout(.center)
                                .children({});
                        });
                        Text(priority.label())
                            .font(12, 500, if (is_selected) priority.color() else Theme.text_secondary)
                            .fontFamily("Montserrat")
                            .end();
                    }
                });
            });

            // Status selector
            Stack()
                .spacing(6)
                .children({
                Text("Status")
                    .font(13, 500, Theme.text_secondary)
                    .fontFamily("Montserrat")
                    .end();
                Box()
                    .layout(.left_center)
                    .spacing(8)
                    .wrap(.wrap)
                    .children({
                    for (std.enums.values(TaskStatus)) |status| {
                        const is_selected = new_task_status == status;
                        CheckBox(selectStatus, .{status})
                            .border(.round(if (is_selected) status.color() else .palette(.border_color_light), .all(6)))
                            .layout(.center)
                            .pointer()
                            .children({
                            Box()
                                .width(.px(14))
                                .height(.px(14))
                                .background(.{ .color = if (is_selected) status.color() else .transparent })
                                .border(.round(.transparent, .all(4)))
                                .hoverScale()
                                .layout(.center)
                                .children({});
                        });
                        Text(status.label())
                            .font(12, 500, if (is_selected) status.color() else Theme.text_secondary)
                            .fontFamily("Montserrat")
                            .end();
                    }
                });
            });
        });

        // Actions
        Box()
            .layout(.right_center)
            .spacing(12)
            .margin(.t(8))
            .children({
            Button(closeAddModal, .{})
                .background(.palette(.text_color))
                .children({
                Text("Cancel")
                    .font(14, 300, .palette(.background))
                    .fontFamily("Montserrat")
                    .end();
            });
            Button(addTask, .{})
                .background(.palette(.tint))
                .children({
                Icon(.plus)
                    .font(14, 600, .palette(.background))
                    .end();
                Text("Add Task")
                    .font(14, 300, .palette(.background))
                    .fontFamily("Montserrat")
                    .end();
            });
        });
    });
}

fn selectPriority(priority: TaskPriority) void {
    new_task_priority = priority;
}

fn selectStatus(status: TaskStatus) void {
    new_task_status = status;
}

fn renderDetailSheetContent(_: *Sheet) void {
    if (selected_task) |task| {
        Stack()
            .width(.percent(100))
            .height(.percent(100))
            .padding(.all(24))
            .spacing(24)
            .children({
            // Header
            Box()
                .layout(.x_between_center)
                .children({
                Text("Task Details")
                    .font(20, 700, Theme.text)
                    .fontFamily("Montserrat")
                    .end();
                Button(closeDetailSheet, .{})
                    .width(.px(36))
                    .height(.px(36))
                    .layout(.center)
                    .pointer()
                    .children({
                    Icon(.x_lg)
                        .font(16, 400, Theme.text_secondary)
                        .end();
                });
            });

            // Title and Status
            Box()
                .width(.percent(100))
                .padding(.all(20))
                .direction(.column)
                .spacing(12)
                .layout(.center)
                .children({
                Text(task.title)
                    .font(24, 700, Theme.text)
                    .fontFamily("Montserrat")
                    .end();
                Box()
                    .layout(.center)
                    .spacing(8)
                    .children({
                    Box()
                        .padding(.xy(10, 6))
                        .background(.transparentizeHex(task.status.color(), 0.2))
                        .border(.round(task.status.color(), .all(6)))
                        .children({
                        Text(task.status.label())
                            .font(12, 600, task.status.color())
                            .fontFamily("Montserrat")
                            .end();
                    });
                    Box()
                        .padding(.xy(10, 6))
                        .background(.transparentizeHex(task.priority.color(), 0.2))
                        .border(.round(task.priority.color(), .all(6)))
                        .children({
                        Text(task.priority.label())
                            .font(12, 600, task.priority.color())
                            .fontFamily("Montserrat")
                            .end();
                    });
                });
            });

            // Description
            if (task.description.len > 0) {
                Stack()
                    .width(.percent(100))
                    .spacing(8)
                    .children({
                    Text("Description")
                        .font(12, 500, Theme.text_muted)
                        .fontFamily("Montserrat")
                        .end();
                    Text(task.description)
                        .font(14, 400, Theme.text_secondary)
                        .fontFamily("Montserrat")
                        .end();
                });
            }

            // Details
            Stack()
                .width(.percent(100))
                .spacing(16)
                .children({
                if (task.assignee) |assignee| {
                    renderDetailRow("Assignee", assignee);
                }
                if (task.due_date) |due| {
                    renderDetailRow("Due Date", due.formatDate(Vapor.arena(.frame)) catch "");
                }
                renderDetailRow("Created", task.created_at);
                renderDetailRowFmt("Task ID", "TASK-{d}", .{task.id});
            });

            // Tags
            if (task.tags.len > 0) {
                Stack()
                    .width(.percent(100))
                    .spacing(8)
                    .children({
                    Text("Tags")
                        .font(12, 500, Theme.text_muted)
                        .fontFamily("Montserrat")
                        .end();
                    Box()
                        .layout(.left_center)
                        .spacing(8)
                        .wrap(.wrap)
                        .children({
                        for (task.tags) |tag| {
                            Box()
                                .padding(.xy(10, 6))
                                .background(.palette(.highlight_color))
                                .border(.round(.palette(.border_color_light), .all(6)))
                                .children({
                                Text(tag)
                                    .font(12, 500, Theme.text_secondary)
                                    .fontFamily("Montserrat")
                                    .end();
                            });
                        }
                    });
                });
            }

            // Actions
            Box()
                .width(.percent(100))
                .layout(.left_center)
                .spacing(12)
                .children({
                Button(closeDetailSheet, .{})
                    .padding(.xy(12, 8))
                    .background(.{ .color = Theme.warning })
                    .border(.round(Theme.warning, .all(12)))
                    .pointer()
                    .layout(.center)
                    .spacing(8)
                    .children({
                    Icon(.pencil)
                        .font(16, 400, Theme.bg_base.color)
                        .end();
                    Text("Edit Task")
                        .font(14, 500, Theme.bg_base.color)
                        .fontFamily("Montserrat")
                        .end();
                });
                Button(closeDetailSheet, .{})
                    .padding(.xy(12, 8))
                    .background(Theme.bg_elevated)
                    .border(.round(.palette(.border_color_light), .all(12)))
                    .pointer()
                    .layout(.center)
                    .spacing(8)
                    .children({
                    Icon(.link)
                        .font(16, 400, Theme.text_secondary)
                        .end();
                    Text("Copy Link")
                        .font(14, 500, Theme.text_secondary)
                        .fontFamily("Montserrat")
                        .end();
                });
            });
        });
    }
}

fn renderDetailRow(label: []const u8, value: []const u8) void {
    Box()
        .width(.percent(100))
        .layout(.x_between_center)
        .padding(.vertical(12))
        .border(.bottom(1, .palette(.border_color_light)))
        .children({
        Text(label)
            .font(14, 400, Theme.text_muted)
            .fontFamily("Montserrat")
            .end();
        Text(value)
            .font(14, 500, Theme.text)
            .fontFamily("Montserrat")
            .end();
    });
}

fn renderDetailRowFmt(label: []const u8, comptime fmt: []const u8, args: anytype) void {
    Box()
        .width(.percent(100))
        .layout(.x_between_center)
        .padding(.vertical(12))
        .border(.bottom(1, .palette(.border_color_light)))
        .children({
        Text(label)
            .font(14, 400, Theme.text_muted)
            .fontFamily("Montserrat")
            .end();
        TextFmt(fmt, args)
            .font(14, 500, Theme.text)
            .fontFamily("Montserrat")
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
        .background(Theme.bg_base)
        .layout(.top_left)
        .children({

        // Main content area
        Stack()
            .width(.percent(100))
            .height(.percent(100))
            .children({
            // Header
            renderHeader();

            // Board
            renderBoard();
        });

        // Overlays
        detail_sheet.render();
        alert.render();
    });
}
