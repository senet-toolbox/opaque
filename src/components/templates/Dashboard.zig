// Dashboard
const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Box;
const Stack = Vapor.Stack;
const Center = Vapor.Center;
const Icon = Vapor.Icon;
const Label = Vapor.Label;
const TextFmt = Vapor.TextFmt;
const TextField = Vapor.TextField;
const TextArea = Vapor.TextArea;
const Animation = Vapor.Animation;
const ButtonCtx = Vapor.Button;
const toggleTheme = @import("../../routes/vapor-ui/VaporUINav.zig").toggleTheme;

// Import UI Components
const SelectStruct = @import("../../components/Select.zig");
const TableStruct = @import("../../components/tables/Table.zig");
const ChartStruct = @import("../../components/charts/Chart.zig").Chart;
const ChartEnhancedStruct = @import("../../components/charts/ChartEnhanced.zig").Chart;
const DatePickerStruct = @import("../../components/DatePicker.zig");
const ComboBoxStruct = @import("../../components/ComboBox.zig");
const ToastStruct = @import("../../components/Toast.zig");
const SheetStruct = @import("../../components/Sheet.zig");
const FieldStruct = @import("../../components/Field.zig");
const TooltipStruct = @import("../../components/ToolTip.zig");
const SwitchStruct = @import("../../components/Switch.zig");
const TabsStruct = @import("../../components/Tabs.zig");
const AccordionStruct = @import("../../components/Accordion.zig");
const SliderStruct = @import("../../components/Slider.zig");
const GroupStruct = @import("../../components/Group.zig");
const Button = @import("../../components/Button.zig").Button;
const SideBar = @import("../../components/Sidebar.zig");

const Dashboard = @This();

// ============================================================================
// TYPE ALIASES
// ============================================================================

pub const Select = SelectStruct.Select;
pub const Table = TableStruct.Table;
pub const Column = TableStruct.Column;
pub const Action = TableStruct.Action;
// pub const Chart = ChartStruct;
pub const ChartEnhanced = ChartEnhancedStruct;
pub const DatePicker = DatePickerStruct;
pub const ComboBox = ComboBoxStruct.ComboBox;
pub const Toast = ToastStruct;
pub const Sheet = SheetStruct;
pub const Field = FieldStruct;
pub const Tooltip = TooltipStruct;
pub const Switch = SwitchStruct;
pub const Tabs = TabsStruct;
pub const Accordion = AccordionStruct;
pub const Slider = SliderStruct;
pub const Group = GroupStruct;

// ============================================================================
// DATA TYPES
// ============================================================================

pub const TransactionStatus = enum {
    completed,
    pending,
    failed,
    refunded,

    pub fn color(self: TransactionStatus) Vapor.Types.Color {
        return switch (self) {
            .completed => .palette(.tint),
            .pending => .hex("#f59e0b"),
            .failed => .palette(.danger),
            .refunded => .hex("#8b5cf6"),
        };
    }

    pub fn label(self: TransactionStatus) []const u8 {
        return switch (self) {
            .completed => "Completed",
            .pending => "Pending",
            .failed => "Failed",
            .refunded => "Refunded",
        };
    }
};

pub const Transaction = struct {
    id: usize,
    customer: []const u8,
    email: []const u8,
    amount: i32,
    status: TransactionStatus,
    date: []const u8,
    method: []const u8,
};

pub const EventType = enum {
    pageview,
    click,
    conversion,
    err,
};

pub fn color(self: EventType) Vapor.Types.Color {
    return switch (self) {
        .pageview => .hex("#3b82f6"),
        .click => .hex("#10b981"),
        .conversion => .hex("#f59e0b"),
        .err => .hex("#ef4444"),
    };
}

pub fn icon(self: EventType) *const Vapor.IconTokens {
    return switch (self) {
        .pageview => .eye,
        .click => .cursor,
        .conversion => .graph_up_arrow,
        .err => .exclamation_triangle,
    };
}

pub const AnalyticsEvent = struct {
    id: usize,
    event_type: EventType,
    page: []const u8,
    user_id: []const u8,
    timestamp: []const u8,
    duration_ms: u32,
};

// ============================================================================
// STATE
// ============================================================================

var selected_nav: NavItem = .dashboard;
var selected_time_range: TimeRange = .last_7d;
var show_detail_sheet: bool = false;
var selected_transaction: ?*const Transaction = null;
var is_live_mode: bool = true;
var show_date_picker: bool = false;
var search_query: []const u8 = "";
var email_query: []const u8 = "";
var chart_type: ChartType = .revenue;

const NavItem = enum {
    dashboard,
    transactions,
    analytics,
    customers,
    settings,

    pub fn label(self: NavItem) []const u8 {
        return switch (self) {
            .dashboard => "Dashboard",
            .transactions => "Transactions",
            .analytics => "Analytics",
            .customers => "Customers",
            .settings => "Settings",
        };
    }

    pub fn icon(self: NavItem) *const Vapor.IconTokens {
        return switch (self) {
            .dashboard => .grid_3x3,
            .transactions => .credit_card,
            .analytics => .bar_chart_line,
            .customers => .people,
            .settings => .gear,
        };
    }
};

const TimeRange = enum {
    today,
    last_7d,
    last_30d,
    last_90d,
    custom,

    pub fn label(self: TimeRange) []const u8 {
        return switch (self) {
            .today => "Today",
            .last_7d => "Last 7 days",
            .last_30d => "Last 30 days",
            .last_90d => "Last 90 days",
            .custom => "Custom",
        };
    }
};

const ChartType = enum {
    revenue,
    transactions,
    customers,
};

// ============================================================================
// COMPONENT INSTANCES
// ============================================================================

var transactions_data: Vapor.Array(Transaction) = undefined;
var events_data: Vapor.Array(AnalyticsEvent) = undefined;
var transactions_table: TransactionsTable = undefined;
var revenue_chart: ChartEnhanced = undefined;
var requests_chart: ChartEnhanced = undefined;
var detail_sheet: Sheet = undefined;
var date_picker: DatePicker = undefined;
var status_filter: Select(TransactionStatus) = undefined;
var time_range_select: Select(TimeRange) = undefined;

var sidebar: SideBar = .{
    .items = &menu_items,
    .title = "Vapor UI",
    .show_menu = true,
    .on_item_click = onItemClick,
};

fn onItemClick(item: *const MenuItem) void {
    selected_nav = std.meta.stringToEnum(NavItem, Vapor.utils.toLowerCase(item.title, .frame)) orelse unreachable;
    Vapor.lib.store("selected_nav", @tagName(selected_nav));
}

fn getNavItem() ?*const MenuItem {
    for (&menu_items) |*item| {
        if (std.ascii.eqlIgnoreCase(selected_nav.label(), item.title)) {
            return item;
        }
    }
    return null;
}

const GroupItem = SideBar.GroupItem;
const MenuItem = SideBar.MenuItem;

var menu_items = [_]MenuItem{
    MenuItem{
        .title = "Dashboard",
        .link = "/dashboard",
        .icon = .house,
    },
    MenuItem{
        .title = "Transactions",
        .link = "/projects",
        .icon = .folder,
    },
    MenuItem{
        .title = "Analytics",
        .link = "/routes",
        .icon = .diagram_3,
    },
    MenuItem{
        .title = "Customers",
        .link = "/treehouse",
        .icon = .tree,
    },
    MenuItem{
        .title = "Settings",
        .link = "/database",
        .icon = .database,
    },
};

// Table configuration
const transaction_columns = [_]Column(Transaction){
    Column(Transaction){ .title = "Customer", .width = 180, .key = "customer", .search = true },
    Column(Transaction){ .title = "Amount", .width = 100, .key = "amount", .sort = .desc },
    Column(Transaction){ .title = "Status", .width = 100, .key = "status", .filter = true },
    Column(Transaction){ .title = "Date", .width = 120, .key = "date" },
    Column(Transaction){ .title = "Method", .width = 100, .key = "method" },
};

const TransactionsTable = Table(Transaction, &transaction_columns, .{
    .actions = &[_]Action(Transaction){
        .{ .label = "View", .on_action = handleViewTransaction, .icon = .eye },
        .{ .label = "Refund", .on_action = handleRefundTransaction, .icon = .arrow_counterclockwise },
        .{ .label = "Delete", .on_action = handleDeleteTransaction, .icon = .trash },
    },
});

// Select options
var status_options = [_]Select(TransactionStatus).Item{
    .{ .value = .completed, .label = "Completed" },
    .{ .value = .pending, .label = "Pending" },
    .{ .value = .failed, .label = "Failed" },
    .{ .value = .refunded, .label = "Refunded" },
};

var time_range_options = [_]Select(TimeRange).Item{
    .{ .value = .today, .label = "Today" },
    .{ .value = .last_7d, .label = "Last 7 days" },
    .{ .value = .last_30d, .label = "Last 30 days" },
    .{ .value = .last_90d, .label = "Last 90 days" },
    .{ .value = .custom, .label = "Custom Range" },
};

// ============================================================================
// ANIMATIONS
// ============================================================================

const pulse_glow = Animation.init("dashboard-pulse-glow")
    .prop(.opacity, 1, 0.5)
    .duration(2000)
    .dir(.alternate)
    .infinite();

const slide_up = Animation.init("dashboard-slide-up")
    .prop(.translateY, 20, 0)
    .prop(.opacity, 0, 1)
    .duration(300)
    .easing(.easeOut)
    .fill(.forwards);

const fade_scale = Animation.init("dashboard-fade-scale")
    .prop(.scale, 0.95, 1)
    .prop(.opacity, 0, 1)
    .duration(200)
    .easing(.easeOut)
    .fill(.forwards);

const shimmer = Animation.init("dashboard-shimmer")
    .at(0)
    .set(.opacity, 0.5)
    .at(50)
    .set(.opacity, 1)
    .at(100)
    .set(.opacity, 0.5)
    .duration(1500)
    .infinite();

// ============================================================================
// SAMPLE DATA
// ============================================================================

fn initSampleData() void {
    transactions_data.appendSlice(&.{
        .{ .id = 1, .customer = "Emma Thompson", .email = "emma@company.co", .amount = 2499, .status = .completed, .date = "Jan 12, 2026", .method = "Visa •••• 4242" },
        .{ .id = 2, .customer = "James Wilson", .email = "james.w@startup.io", .amount = 8750, .status = .completed, .date = "Jan 12, 2026", .method = "Mastercard •••• 5555" },
        .{ .id = 3, .customer = "Sofia Garcia", .email = "sofia@design.studio", .amount = 1299, .status = .pending, .date = "Jan 11, 2026", .method = "Amex •••• 1234" },
        .{ .id = 4, .customer = "Michael Chen", .email = "m.chen@tech.dev", .amount = 4500, .status = .completed, .date = "Jan 11, 2026", .method = "Visa •••• 9876" },
        .{ .id = 5, .customer = "Olivia Brown", .email = "olivia.b@agency.net", .amount = 3200, .status = .failed, .date = "Jan 10, 2026", .method = "Visa •••• 1111" },
        .{ .id = 6, .customer = "Lucas Martinez", .email = "lucas@freelance.me", .amount = 950, .status = .refunded, .date = "Jan 10, 2026", .method = "PayPal" },
        .{ .id = 7, .customer = "Ava Johnson", .email = "ava.j@enterprise.com", .amount = 15000, .status = .completed, .date = "Jan 9, 2026", .method = "Wire Transfer" },
        .{ .id = 8, .customer = "Noah Williams", .email = "noah@startup.vc", .amount = 2100, .status = .pending, .date = "Jan 9, 2026", .method = "Mastercard •••• 8888" },
        .{ .id = 9, .customer = "Isabella Davis", .email = "bella@creative.co", .amount = 675, .status = .completed, .date = "Jan 8, 2026", .method = "Visa •••• 3333" },
        .{ .id = 10, .customer = "Ethan Moore", .email = "ethan.m@dev.io", .amount = 5400, .status = .completed, .date = "Jan 8, 2026", .method = "Amex •••• 7777" },
        .{ .id = 11, .customer = "Mia Anderson", .email = "mia@consulting.biz", .amount = 12500, .status = .completed, .date = "Jan 7, 2026", .method = "Wire Transfer" },
        .{ .id = 12, .customer = "Alexander Taylor", .email = "alex.t@agency.co", .amount = 890, .status = .failed, .date = "Jan 7, 2026", .method = "Visa •••• 2222" },
        .{ .id = 13, .customer = "Charlotte Thomas", .email = "charlotte@brand.io", .amount = 3750, .status = .completed, .date = "Jan 6, 2026", .method = "Mastercard •••• 6666" },
        .{ .id = 14, .customer = "William Jackson", .email = "will.j@tech.startup", .amount = 1800, .status = .pending, .date = "Jan 6, 2026", .method = "PayPal" },
        .{ .id = 15, .customer = "Amelia White", .email = "amelia@design.pro", .amount = 4200, .status = .completed, .date = "Jan 5, 2026", .method = "Visa •••• 4444" },
        .{ .id = 16, .customer = "Benjamin Harris", .email = "ben.h@software.dev", .amount = 9800, .status = .completed, .date = "Jan 5, 2026", .method = "Amex •••• 9999" },
        .{ .id = 17, .customer = "Harper Martin", .email = "harper@media.group", .amount = 2300, .status = .refunded, .date = "Jan 4, 2026", .method = "Mastercard •••• 1212" },
        .{ .id = 18, .customer = "Daniel Garcia", .email = "daniel.g@corp.net", .amount = 6700, .status = .completed, .date = "Jan 4, 2026", .method = "Wire Transfer" },
        .{ .id = 19, .customer = "Evelyn Robinson", .email = "evelyn@retail.shop", .amount = 420, .status = .completed, .date = "Jan 3, 2026", .method = "Visa •••• 5678" },
        .{ .id = 20, .customer = "Henry Clark", .email = "henry.c@finance.ltd", .amount = 18500, .status = .completed, .date = "Jan 3, 2026", .method = "Wire Transfer" },
    }) catch |err| Vapor.print(.err, "Failed to append transactions: {any}", .{err});
}

// Chart data
const revenue_points = [_]ChartEnhanced.Point{
    .{ .x = 1, .y = 12400 },
    .{ .x = 2, .y = 15800 },
    .{ .x = 3, .y = 13200 },
    .{ .x = 4, .y = 18900 },
    .{ .x = 5, .y = 22100 },
    .{ .x = 6, .y = 19500 },
    .{ .x = 7, .y = 24800 },
    .{ .x = 8, .y = 28300 },
    .{ .x = 9, .y = 25600 },
    .{ .x = 10, .y = 31200 },
    .{ .x = 11, .y = 29800 },
    .{ .x = 12, .y = 35400 },
};

const transactions_points = [_]ChartEnhanced.Point{
    .{ .x = 1, .y = 1450 },
    .{ .x = 2, .y = 18900 },
    .{ .x = 3, .y = 1670 },
    .{ .x = 4, .y = 2129 },
    .{ .x = 5, .y = 8560 },
    .{ .x = 6, .y = 5340 },
    .{ .x = 7, .y = 12780 },
    .{ .x = 8, .y = 6120 },
    .{ .x = 9, .y = 2890 },
    .{ .x = 10, .y = 15450 },
    .{ .x = 11, .y = 3230 },
    .{ .x = 12, .y = 9890 },
};

// Define colors for each status code category
const gray = Vapor.Types.Color.hex("#212121"); // 1/2/3XX
const yellow = Vapor.Types.Color.hex("#FFBF00"); // 4XX
const red = Vapor.Types.Color.hex("#2108FF"); // 5XX

// Create data points with stacked segments
// Each point represents a time bucket
const data_1xx_2xx_3xx = [_]ChartEnhanced.Point{
    .{ .x = 1, .stack = &.{ .{ .value = 50, .color = gray }, .{ .value = 30, .color = gray }, .{ .value = 15, .color = yellow }, .{ .value = 20, .color = red } } },
    .{ .x = 2, .stack = &.{ .{ .value = 40, .color = gray }, .{ .value = 25, .color = gray }, .{ .value = 25, .color = yellow }, .{ .value = 30, .color = red } } },
    .{ .x = 3, .stack = &.{ .{ .value = 60, .color = gray }, .{ .value = 35, .color = gray }, .{ .value = 10, .color = yellow }, .{ .value = 20, .color = red } } },
    .{ .x = 4, .stack = &.{ .{ .value = 45, .color = gray }, .{ .value = 20, .color = gray }, .{ .value = 30, .color = yellow }, .{ .value = 40, .color = red } } },
    .{ .x = 5, .stack = &.{ .{ .value = 55, .color = gray }, .{ .value = 28, .color = gray }, .{ .value = 18, .color = yellow }, .{ .value = 25, .color = red } } },
    .{ .x = 6, .stack = &.{ .{ .value = 70, .color = gray }, .{ .value = 40, .color = gray }, .{ .value = 12, .color = yellow }, .{ .value = 15, .color = red } } },
    .{ .x = 7, .stack = &.{ .{ .value = 35, .color = gray }, .{ .value = 22, .color = gray }, .{ .value = 28, .color = yellow }, .{ .value = 35, .color = red } } },
    .{ .x = 8, .stack = &.{ .{ .value = 48, .color = gray }, .{ .value = 32, .color = gray }, .{ .value = 20, .color = yellow }, .{ .value = 22, .color = red } } },
    .{ .x = 9, .stack = &.{ .{ .value = 62, .color = gray }, .{ .value = 38, .color = gray }, .{ .value = 8, .color = yellow }, .{ .value = 12, .color = red } } },
    .{ .x = 10, .stack = &.{ .{ .value = 42, .color = gray }, .{ .value = 18, .color = gray }, .{ .value = 35, .color = yellow }, .{ .value = 45, .color = red } } },
    .{ .x = 11, .stack = &.{ .{ .value = 58, .color = gray }, .{ .value = 33, .color = gray }, .{ .value = 14, .color = yellow }, .{ .value = 18, .color = red } } },
    .{ .x = 12, .stack = &.{ .{ .value = 75, .color = gray }, .{ .value = 45, .color = gray }, .{ .value = 10, .color = yellow }, .{ .value = 10, .color = red } } },
    .{ .x = 13, .stack = &.{ .{ .value = 30, .color = gray }, .{ .value = 15, .color = gray }, .{ .value = 40, .color = yellow }, .{ .value = 50, .color = red } } },
    .{ .x = 14, .stack = &.{ .{ .value = 52, .color = gray }, .{ .value = 30, .color = gray }, .{ .value = 22, .color = yellow }, .{ .value = 28, .color = red } } },
    .{ .x = 15, .stack = &.{ .{ .value = 65, .color = gray }, .{ .value = 42, .color = gray }, .{ .value = 15, .color = yellow }, .{ .value = 16, .color = red } } },
    .{ .x = 16, .stack = &.{ .{ .value = 38, .color = gray }, .{ .value = 24, .color = gray }, .{ .value = 32, .color = yellow }, .{ .value = 38, .color = red } } },
    .{ .x = 17, .stack = &.{.{ .value = 120, .color = red }} },
    .{ .x = 18, .stack = &.{.{ .value = 140, .color = red }} },
    .{ .x = 19, .stack = &.{.{ .value = 90, .color = red }} },
    .{ .x = 20, .stack = &.{ .{ .value = 68, .color = gray }, .{ .value = 44, .color = gray }, .{ .value = 12, .color = yellow }, .{ .value = 14, .color = red } } },
    .{ .x = 21, .stack = &.{ .{ .value = 34, .color = gray }, .{ .value = 20, .color = gray }, .{ .value = 36, .color = yellow }, .{ .value = 42, .color = red } } },
    .{ .x = 22, .stack = &.{ .{ .value = 80, .color = gray }, .{ .value = 50, .color = gray }, .{ .value = 6, .color = yellow }, .{ .value = 6, .color = red } } },
    .{ .x = 23, .stack = &.{.{ .value = 60, .color = red }} },
    .{ .x = 24, .stack = &.{.{ .value = 74, .color = red }} },
    .{ .x = 25, .stack = &.{ .{ .value = 63, .color = gray }, .{ .value = 40, .color = gray } } },
    .{ .x = 26, .stack = &.{ .{ .value = 41, .color = gray }, .{ .value = 23, .color = gray }, .{ .value = 30, .color = yellow }, .{ .value = 36, .color = red } } },
    .{ .x = 27, .stack = &.{ .{ .value = 77, .color = gray }, .{ .value = 46, .color = gray }, .{ .value = 9, .color = yellow }, .{ .value = 11, .color = red } } },
    .{ .x = 28, .stack = &.{ .{ .value = 36, .color = gray }, .{ .value = 19, .color = gray }, .{ .value = 34, .color = yellow }, .{ .value = 44, .color = red } } },
    .{ .x = 29, .stack = &.{ .{ .value = 59, .color = gray }, .{ .value = 37, .color = gray }, .{ .value = 16, .color = yellow }, .{ .value = 19, .color = red } } },
    .{ .x = 30, .stack = &.{ .{ .value = 71, .color = gray }, .{ .value = 43, .color = gray }, .{ .value = 11, .color = yellow }, .{ .value = 13, .color = red } } },
    .{ .x = 31, .stack = &.{ .{ .value = 49, .color = gray }, .{ .value = 29, .color = gray } } },
    .{ .x = 32, .stack = &.{ .{ .value = 66, .color = gray }, .{ .value = 41, .color = gray } } },
    .{ .x = 33, .stack = &.{ .{ .value = 39, .color = gray }, .{ .value = 21, .color = gray } } },
    .{ .x = 34, .stack = &.{ .{ .value = 85, .color = gray }, .{ .value = 52, .color = gray } } },
    .{ .x = 35, .stack = &.{ .{ .value = 47, .color = gray }, .{ .value = 27, .color = gray } } },
    .{ .x = 36, .stack = &.{ .{ .value = 61, .color = gray }, .{ .value = 39, .color = gray } } },
    .{ .x = 37, .stack = &.{ .{ .value = 53, .color = gray }, .{ .value = 31, .color = gray } } },
    .{ .x = 38, .stack = &.{ .{ .value = 74, .color = gray }, .{ .value = 47, .color = gray } } },
    .{ .x = 39, .stack = &.{ .{ .value = 43, .color = gray }, .{ .value = 25, .color = gray } } },
    .{ .x = 40, .stack = &.{ .{ .value = 67, .color = gray }, .{ .value = 42, .color = gray } } },
    .{ .x = 41, .stack = &.{ .{ .value = 50, .color = gray }, .{ .value = 30, .color = gray } } },
    .{ .x = 42, .stack = &.{ .{ .value = 40, .color = gray }, .{ .value = 25, .color = gray } } },
    .{ .x = 43, .stack = &.{ .{ .value = 60, .color = gray }, .{ .value = 35, .color = gray }, .{ .value = 10, .color = yellow }, .{ .value = 20, .color = red } } },
    .{ .x = 44, .stack = &.{ .{ .value = 45, .color = gray }, .{ .value = 20, .color = gray }, .{ .value = 30, .color = yellow }, .{ .value = 40, .color = red } } },
    .{ .x = 45, .stack = &.{ .{ .value = 55, .color = gray }, .{ .value = 28, .color = gray }, .{ .value = 18, .color = yellow }, .{ .value = 25, .color = red } } },
    .{ .x = 46, .stack = &.{ .{ .value = 70, .color = gray }, .{ .value = 40, .color = gray }, .{ .value = 12, .color = yellow }, .{ .value = 15, .color = red } } },
    .{ .x = 47, .stack = &.{ .{ .value = 35, .color = gray }, .{ .value = 22, .color = gray }, .{ .value = 28, .color = yellow }, .{ .value = 35, .color = red } } },
    .{ .x = 48, .stack = &.{ .{ .value = 48, .color = gray }, .{ .value = 32, .color = gray }, .{ .value = 20, .color = yellow }, .{ .value = 22, .color = red } } },
    .{ .x = 49, .stack = &.{ .{ .value = 62, .color = gray }, .{ .value = 38, .color = gray }, .{ .value = 8, .color = yellow }, .{ .value = 12, .color = red } } },
    .{ .x = 50, .stack = &.{ .{ .value = 42, .color = gray }, .{ .value = 18, .color = gray }, .{ .value = 35, .color = yellow }, .{ .value = 45, .color = red } } },
    .{ .x = 51, .stack = &.{ .{ .value = 58, .color = gray }, .{ .value = 33, .color = gray }, .{ .value = 14, .color = yellow }, .{ .value = 18, .color = red } } },
    .{ .x = 52, .stack = &.{ .{ .value = 75, .color = gray }, .{ .value = 45, .color = gray }, .{ .value = 10, .color = yellow }, .{ .value = 10, .color = red } } },
    .{ .x = 53, .stack = &.{ .{ .value = 41, .color = gray }, .{ .value = 23, .color = gray }, .{ .value = 30, .color = yellow }, .{ .value = 36, .color = red } } },
    .{ .x = 54, .stack = &.{ .{ .value = 77, .color = gray }, .{ .value = 46, .color = gray }, .{ .value = 9, .color = yellow }, .{ .value = 11, .color = red } } },
    .{ .x = 55, .stack = &.{ .{ .value = 36, .color = gray }, .{ .value = 19, .color = gray }, .{ .value = 34, .color = yellow }, .{ .value = 44, .color = red } } },
    .{ .x = 56, .stack = &.{ .{ .value = 59, .color = gray }, .{ .value = 37, .color = gray }, .{ .value = 16, .color = yellow }, .{ .value = 19, .color = red } } },
    .{ .x = 57, .stack = &.{ .{ .value = 71, .color = gray }, .{ .value = 43, .color = gray }, .{ .value = 11, .color = yellow }, .{ .value = 13, .color = red } } },
    .{ .x = 58, .stack = &.{ .{ .value = 49, .color = gray }, .{ .value = 29, .color = gray }, .{ .value = 23, .color = yellow }, .{ .value = 27, .color = red } } },
    .{ .x = 59, .stack = &.{ .{ .value = 66, .color = gray }, .{ .value = 41, .color = gray }, .{ .value = 13, .color = yellow }, .{ .value = 15, .color = red } } },
    .{ .x = 60, .stack = &.{ .{ .value = 39, .color = gray }, .{ .value = 21, .color = gray }, .{ .value = 31, .color = yellow }, .{ .value = 40, .color = red } } },
};

const data_4xx = [_]ChartEnhanced.Point{
    .{ .x = 1, .stack = &.{.{ .value = 15, .color = yellow }} },
    .{ .x = 2, .stack = &.{.{ .value = 25, .color = yellow }} },
    .{ .x = 3, .stack = &.{.{ .value = 10, .color = yellow }} },
    .{ .x = 4, .stack = &.{.{ .value = 30, .color = yellow }} },
};

const data_5xx = [_]ChartEnhanced.Point{
    .{ .x = 1, .stack = &.{.{ .value = 20, .color = red }} },
    .{ .x = 2, .stack = &.{.{ .value = 35, .color = red }} },
    .{ .x = 3, .stack = &.{.{ .value = 15, .color = red }} },
    .{ .x = 4, .stack = &.{.{ .value = 25, .color = red }} },
};

// ============================================================================
// COLORS
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
    const err = Vapor.Types.Color.hex("#ef4444");
    const gradient_start = Vapor.Types.Color.hex("#6366f1");
    const gradient_end = Vapor.Types.Color.hex("#8b5cf6");
};

// ============================================================================
// EVENT HANDLERS
// ============================================================================

fn selectNav(item: NavItem) void {
    Vapor.lib.store("selected_nav", @tagName(item));
    selected_nav = item;
}

fn selectTimeRange(_: *Select(TimeRange), item: *Select(TimeRange).Item) void {
    selected_time_range = item.value;
}

fn toggleLiveMode() void {
    is_live_mode = !is_live_mode;
    if (is_live_mode) {
        Toast.success(.{ .title = "Live Mode Enabled", .description = "Data will refresh automatically" });
    } else {
        Toast.info(.{ .title = "Live Mode Disabled", .description = "Data is now static" });
    }
}

fn toggleDatePicker() void {
    show_date_picker = !show_date_picker;
}

fn handleViewTransaction(txn: *Transaction) void {
    Vapor.print("handleViewTransaction {s}", .{txn.email});
    selected_transaction = txn;
    detail_sheet.open();
}

fn handleRefundTransaction(txn: *Transaction) void {
    txn.status = .refunded;
    Toast.success(.{ .title = "Refund Initiated", .description = "Transaction will be refunded within 3-5 business days" });
    // detail_sheet.close();
}

fn handleDeleteTransaction(txn: *Transaction) void {
    _ = txn;
    Toast.warning(.{ .title = "Transaction Deleted", .description = "This action cannot be undone" });
}

fn handleTableSelect(txn: *Transaction) void {
    selected_transaction = txn;
}

fn closeDetailSheet() void {
    detail_sheet.close();
    selected_transaction = null;
}

fn handleExport() void {
    Toast.info(.{ .title = "Exporting Data", .description = "Your report will be ready shortly" });
}

fn handleRefresh() void {
    Toast.success(.{ .title = "Data Refreshed", .description = "All metrics are up to date" });
}

// ============================================================================
// INITIALIZATION
// ============================================================================

pub fn init() void {
    // Build animations
    pulse_glow.build();
    slide_up.build();
    fade_scale.build();
    shimmer.build();

    // Initialize component libraries
    SelectStruct.new();
    ToastStruct.new();
    SheetStruct.new();
    FieldStruct.new();
    TooltipStruct.new();
    SwitchStruct.new();
    GroupStruct.new();
    Tabs.new();
    Slider.new();

    // Initialize data
    transactions_data = Vapor.array(Transaction, .persist);
    events_data = Vapor.array(AnalyticsEvent, .persist);
    initSampleData();

    // Initialize table
    transactions_table.init(transactions_data.items);
    transactions_table.on_select = handleTableSelect;

    // Initialize chart
    revenue_chart = ChartEnhanced.init(Vapor.arena(.persist), .{
        .height = 280,
        .width = 600,
        .palette = .{ .colors = &.{ "#6366f1", "#10b981", "#f59e0b" } },
    });

    revenue_chart.addSeries(.line_smooth, "Revenue", &revenue_points, .{ .color = .palette(.text_color) }) catch unreachable;
    revenue_chart.addSeries(.line_smooth, "Transactions", &transactions_points, .{ .color = .palette(.danger) }) catch unreachable;
    revenue_chart.xAxis(.{ .label = "Month", .tick_count = 12 });
    revenue_chart.yAxis(.{ .label = "USD ($)", .tick_count = 6 });
    revenue_chart.legend(.{ .position = .top_right, .text_color = .palette(.text_color) });
    revenue_chart.build() catch unreachable;

    // Initialize chart
    requests_chart = ChartEnhanced.init(Vapor.arena(.persist), .{
        .height = 280,
        .width = 600,
        .palette = .{ .colors = &.{ "#6366f1", "#10b981", "#f59e0b" } },
    });

    requests_chart.addSeries(.stacked_bar, "1/2XX", &data_1xx_2xx_3xx, .{
        .color = gray,
        .bar_radius = 0,
        .border = .top(1, .hex("#000000")),
        .stroke = .hex("#000000"),
        .stroke_width = 0.5,
    }) catch unreachable;

    requests_chart.xAxis(.{ .label = "Time", .tick_count = 4 });
    requests_chart.yAxis(.{ .label = "Requests", .tick_count = 5 });
    requests_chart.legend(.{
        .position = .top_right,
        .direction = .row,
        .text_color = .palette(.text_color),
        .fields = &.{
            // .{ .title = "1/2/3XX", .color = gray, .background = gray },
            .{ .title = "3XX", .color = gray, .background = gray },
            .{ .title = "4XX", .color = yellow, .background = yellow },
            .{ .title = "5XX", .color = red, .background = red },
        },
    });

    requests_chart.build() catch unreachable;

    status_filter = .fromItems(&status_options);
    time_range_select = .fromItems(&time_range_options);
    time_range_select.on_select = selectTimeRange;
    time_range_select.trigger = "Time Range";

    // Initialize sheet
    detail_sheet = Sheet.init(.right);
    detail_sheet.content = renderDetailSheetContent;

    // Initialize date picker
    date_picker.init();
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
                Icon(.flower)
                    .font(20, 700, .white)
                    .end();
            });
            Stack()
                .spacing(0)
                .children({
                Text("Watcher")
                    .font(20, 700, Theme.text)
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
                Text("Analytics")
                    .font(11, 500, Theme.text_muted)
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
            });
        });

        // Navigation Items
        Stack()
            .width(.percent(100))
            .spacing(4)
            .children({
            Text("MENU")
                .font(10, 600, Theme.text_muted)
                .fontFamily("IBM Plex Mono,monospace")
                .margin(.{ .bottom = 8 })
                .end();

            for (std.enums.values(NavItem)) |nav_item| {
                if (nav_item != .settings) {
                    renderNavButton(nav_item);
                }
            }
        });

        // Spacer
        // Box().height(.grow).children({});
        Vapor.Spacer(16).end();

        // Settings at bottom
        renderNavButton(.settings);

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
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
                Text("Admin")
                    .font(12, 400, Theme.text_muted)
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
            });
            Icon(.chevron_expand)
                .font(14, 400, Theme.text_muted)
                .end();
        });
    });
}

fn renderNavButton(item: NavItem) void {
    const is_active = selected_nav == item;

    ButtonCtx(selectNav, .{item})
        .width(.percent(100))
        .padding(.xy(14, 4))
        .background(if (is_active) .transparentize(.palette(.tint), 0.1) else .transparent)
        .border(.right(1, if (is_active) .palette(.tint) else .transparent))
        .layer(if (is_active) .dot(0.5, 6, .transparentize(.palette(.tint), 0.3)) else null)
        .layout(.left_center)
        .spacing(12)
        .pointer()
        .duration(150)
        .hover(.{
            .background = if (is_active) .transparentize(.palette(.tint), 0.1) else .palette(.highlight_color),
        })
        .children({
        Box()
            .width(.px(32))
            .height(.px(32))
            .layout(.center)
            .children({
            Icon(item.icon())
                .font(16, 400, if (is_active) .palette(.tint) else Theme.text_secondary)
                .end();
        });
        Text(item.label())
            .font(14, 400, if (is_active) .palette(.tint) else Theme.text_secondary)
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
            Text(selected_nav.label())
                .font(24, 700, Theme.text)
                .fontFamily("IBM Plex Mono,monospace")
                .end();
        });

        // Right: Controls
        Box()
            .layout(.right_center)
            .spacing(12)
            .children({

            // Time range select
            Box()
                .width(.px(160))
                .children({
                time_range_select.renderPos(.bottom);
            });

            // Live mode toggle
            Button(toggleLiveMode, .{})
                .padding(.xy(14, 9))
                .children({
                if (is_live_mode) {
                    Box()
                        .width(.px(8))
                        .height(.px(8))
                        .background(.palette(.tint))
                        .border(.round(.palette(.tint), .all(99)))
                        .animation("dashboard-pulse-glow")
                        .children({});
                }
                Text(if (is_live_mode) "Live" else "Paused")
                    .font(13, 500, if (is_live_mode) .palette(.tint) else Theme.text_secondary)
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
            });

            Button(toggleLiveMode, .{})
                .padding(.xy(14, 9))
                .children({
                Text("Export")
                    .font(13, 500, .palette(.text_color))
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
                Icon(.download)
                    .font(14, 400, .palette(.text_color))
                    .end();
            });

            Box()
                .width(.px(40))
                .height(.px(40))
                .pos(.relative)
                .children({
                Button(toggleDatePicker, .{})
                    .width(.px(40))
                    .height(.px(40))
                    .layout(.center)
                    .pointer()
                    .children({
                    Icon(.calendar)
                        .inheritHover(&.{.text_color})
                        .font(18, 700, .palette(.text_color))
                        .end();
                });

                if (show_date_picker) {
                    Box()
                        .pos(.tr(.px(44), .px(0), .absolute))
                        .zIndex(1000)
                        .children({
                        date_picker.render();
                    });
                }
            });

            // Refresh button
            Button(toggleLiveMode, .{})
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
        });
    });
}

fn renderMetricCard(
    comptime title: []const u8,
    comptime value: []const u8,
    comptime change: []const u8,
    comptime is_positive: bool,
    _: *const Vapor.IconTokens,
) void {
    Box()
        .width(.percent(25))
        .padding(.all(24))
        .direction(.column)
        .spacing(16)
        .children({
        Box()
            .layout(.x_between_center)
            .children({
            Text(title)
                .font(18, 500, Theme.text_muted)
                .fontFamily("IBM Plex Mono,monospace")
                .end();
        });

        Stack()
            .spacing(8)
            .children({
            Text(value)
                .font(32, 700, Theme.text)
                .fontFamily("IBM Plex Mono,monospace")
                .end();

            Box()
                .layout(.left_center)
                .spacing(6)
                .children({
                Box()
                    .padding(.xy(6, 3))
                    .background(.transparentize(if (is_positive) Theme.success else Theme.err, 0.5))
                    .border(.round(if (is_positive) Theme.success else Theme.err, .all(4)))
                    .layout(.center)
                    .spacing(4)
                    .children({
                    Icon(if (is_positive) .arrow_up else .arrow_down)
                        .font(10, 600, if (is_positive) Theme.success else Theme.err)
                        .end();
                    Text(change)
                        .font(11, 600, if (is_positive) Theme.success else Theme.err)
                        .fontFamily("IBM Plex Mono,monospace")
                        .end();
                });
                Text("vs last period")
                    .font(12, 400, Theme.text_muted)
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
            });
        });
    });
}

fn renderDashboardView() void {
    Stack()
        .width(.percent(100))
        .height(.percent(100))
        .padding(.all(28))
        .spacing(28)
        .scroll(.scrollY())
        .children({
        Box()
            .width(.percent(100))
            .layout(.top_left)
            .direction(.column)
            .spacing(20)
            .children({
            // Main chart
            Box()
                .width(.percent(100))
                .padding(.all(24))
                .direction(.row)
                .layout(.x_between_center)
                .spacing(20)
                .children({
                Box()
                    .direction(.column)
                    .children({
                    Stack()
                        .spacing(4)
                        .children({
                        Text("Revenue Overview")
                            .font(18, 600, Theme.text)
                            .fontFamily("IBM Plex Mono,monospace")
                            .end();
                        Text("Monthly revenue and transaction volume")
                            .font(13, 400, Theme.text_muted)
                            .fontFamily("IBM Plex Mono,monospace")
                            .end();
                    });
                    revenue_chart.render();
                });
                Box()
                    .direction(.column)
                    .children({
                    Stack()
                        .spacing(4)
                        .children({
                        Text("Requests Overview")
                            .font(18, 600, Theme.text)
                            .fontFamily("IBM Plex Mono,monospace")
                            .end();
                        Text("Monthly requests")
                            .font(13, 400, Theme.text_muted)
                            .fontFamily("IBM Plex Mono,monospace")
                            .end();
                    });
                    requests_chart.render();
                });
            });
        });

        // Transactions section
        Box()
            .width(.percent(100))
            .padding(.all(24))
            .direction(.column)
            .spacing(20)
            .children({
            Box()
                .layout(.x_between_center)
                .children({
                Stack()
                    .spacing(4)
                    .children({
                    Text("Recent Transactions")
                        .font(18, 600, Theme.text)
                        .fontFamily("IBM Plex Mono,monospace")
                        .end();
                    Text("Latest payment activity across all channels")
                        .font(13, 400, Theme.text_muted)
                        .fontFamily("IBM Plex Mono,monospace")
                        .end();
                });

                Box()
                    .layout(.right_center)
                    .spacing(12)
                    .children({
                    Box()
                        .width(.px(140))
                        .children({
                        status_filter.renderPos(.bottom);
                    });
                    Button(selectNav, .{NavItem.transactions})
                        .padding(.xy(14, 9))
                        .background(.palette(.tint))
                        .children({
                        Text("View All")
                            .font(13, 500, .palette(.background))
                            .fontFamily("IBM Plex Mono,monospace")
                            .end();
                        Icon(.arrow_right)
                            .font(14, 400, .palette(.background))
                            .end();
                    });
                });
            });

            Box()
                .width(.percent(100))
                .height(.px(720))
                .layout(.top_center)
                .children({
                transactions_table.render();
            });
        });
    });
}

fn renderChartTypeButton(chart_btn_type: ChartType, label: []const u8) void {
    const is_active = chart_type == chart_btn_type;
    Box()
        .padding(.xy(12, 8))
        .background(.{ .color = if (is_active) Theme.accent else .transparent })
        .border(.round(if (is_active) Theme.accent else Theme.border, .all(6)))
        .pointer()
        .children({
        Text(label)
            .font(12, 500, if (is_active) .white else Theme.text_secondary)
            .fontFamily("IBM Plex Mono,monospace")
            .end();
    });
}

fn renderProductRow(comptime name: []const u8, comptime revenue: []const u8, comptime percentage: u32) void {
    Box()
        .width(.percent(100))
        .layout(.x_between_center)
        .children({
        Stack()
            .spacing(4)
            .children({
            Text(name)
                .font(14, 500, Theme.text)
                .fontFamily("IBM Plex Mono,monospace")
                .end();
            Text(revenue)
                .font(12, 400, Theme.text_muted)
                .fontFamily("IBM Plex Mono,monospace")
                .end();
        });
        Box()
            .layout(.right_center)
            .spacing(8)
            .children({
            Box()
                .width(.px(80))
                .height(.px(6))
                .background(Theme.bg_elevated)
                .border(.round(Theme.bg_elevated.color.?, .all(99)))
                .children({
                Box()
                    .width(.percent(percentage))
                    .height(.percent(100))
                    .background(.{ .color = Theme.accent })
                    .border(.round(Theme.accent, .all(99)))
                    .children({});
            });
            TextFmt("{d}%", .{percentage})
                .font(12, 500, Theme.text_secondary)
                .fontFamily("IBM Plex Mono,monospace")
                .width(.px(32))
                .end();
        });
    });
}

fn renderFunnelStep(comptime name: []const u8, comptime value: []const u8, comptime percentage: u32) void {
    Box()
        .width(.percent(100))
        .layout(.x_between_center)
        .children({
        Box()
            .layout(.left_center)
            .spacing(12)
            .children({
            Box()
                .width(.px(percentage))
                .height(.px(8))
                .background(.{ .color = Theme.accent })
                .border(.round(Theme.accent, .all(4)))
                .children({});
            Text(name)
                .font(14, 400, Theme.text_secondary)
                .fontFamily("IBM Plex Mono,monospace")
                .end();
        });
        Text(value)
            .font(14, 600, Theme.text)
            .fontFamily("IBM Plex Mono,monospace")
            .end();
    });
}

fn renderTransactionsView() void {
    Stack()
        .width(.percent(100))
        .height(.percent(100))
        .padding(.all(28))
        .spacing(24)
        .layout(.top_center)
        .children({
        // Table
        Box()
            .width(.percent(100))
            .layer(.grid(14, 1, .transparentize(.black, 0.05)))
            .children({
            transactions_table.render();
        });
    });
}

fn renderAnalyticsView() void {
    Stack()
        .width(.percent(100))
        .height(.percent(100))
        .padding(.all(28))
        .spacing(24)
        .children({
        Text("Analytics view - Coming soon")
            .font(18, 400, Theme.text_muted)
            .fontFamily("IBM Plex Mono,monospace")
            .end();
    });
}

fn renderCustomersView() void {
    Stack()
        .width(.percent(100))
        .height(.percent(100))
        .padding(.all(28))
        .spacing(24)
        .children({
        Text("Customers view - Coming soon")
            .font(18, 400, Theme.text_muted)
            .fontFamily("IBM Plex Mono,monospace")
            .end();
    });
}

fn renderSettingsView() void {
    Stack()
        .width(.percent(100))
        .height(.percent(100))
        .padding(.all(28))
        .spacing(24)
        .children({
        // Profile settings
        Box()
            .width(.px(600))
            .padding(.all(24))
            .direction(.column)
            .spacing(20)
            .children({
            Text("Profile Settings")
                .font(18, 600, Theme.text)
                .fontFamily("IBM Plex Mono,monospace")
                .end();

            Field.render(.{ .label = "Display Name", .value = .{ .string = &search_query } });
            Field.render(.{ .label = "Email Address", .value = .{ .email = &email_query }, .type = .email });

            Box()
                .layout(.x_between_center)
                .children({
                Text("Enable Notifications")
                    .font(14, 400, Theme.text)
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
                Switch.render("notifications-switch", Vapor.alert, .{ "{s}", .{"Im a switch"} });
            });

            Box()
                .layout(.x_between_center)
                .children({
                Text("Dark Mode")
                    .font(14, 400, Theme.text)
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
                Switch.render("dark-mode-switch", toggleTheme, .{});
            });
        });
    });
}

fn renderDetailSheetContent(_: *Sheet) void {
    if (selected_transaction) |txn| {
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
                Text("Transaction Details")
                    .font(20, 700, Theme.text)
                    .fontFamily("IBM Plex Mono,monospace")
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

            // Amount
            Box()
                .width(.percent(100))
                .padding(.all(20))
                .direction(.column)
                .spacing(8)
                .layout(.center)
                .children({
                Text("Amount")
                    .font(12, 500, Theme.text_muted)
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
                TextFmt("${d}.00", .{txn.amount})
                    .font(36, 700, Theme.text)
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
                Box()
                    .padding(.xy(10, 6))
                    .children({
                    Text(txn.status.label())
                        .font(12, 600, txn.status.color())
                        .fontFamily("IBM Plex Mono,monospace")
                        .end();
                });
            });

            // Details
            Stack()
                .width(.percent(100))
                .spacing(16)
                .children({
                renderDetailRow("Customer", txn.customer);
                renderDetailRow("Email", txn.email);
                renderDetailRow("Date", txn.date);
                renderDetailRow("Payment Method", txn.method);
                renderDetailRowFmt("Transaction ID", "TXN-{d}", .{txn.id});
            });

            // Actions
            Box()
                .width(.percent(100))
                .layout(.left_center)
                .spacing(12)
                .children({
                Button(handleRefundTransaction, .{@constCast(txn)})
                    .padding(.xy(12, 8))
                    .background(.{ .color = Theme.warning })
                    .border(.round(Theme.warning, .all(12)))
                    .pointer()
                    .layout(.center)
                    .spacing(8)
                    .children({
                    Icon(.arrow_counterclockwise)
                        .font(16, 400, Theme.bg_base.color)
                        .end();
                    Text("Refund")
                        .font(14, 500, Theme.bg_base.color)
                        .fontFamily("Montserrat")
                        .end();
                });
                Button(closeDetailSheet, .{})
                    .padding(.xy(12, 8))
                    .background(Theme.bg_elevated)
                    .border(.round(Theme.border, .all(12)))
                    .pointer()
                    .layout(.center)
                    .spacing(8)
                    .children({
                    Icon(.printer)
                        .font(16, 400, Theme.text_secondary)
                        .end();
                    Text("Print Receipt")
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

fn renderDetailRowFmt(comptime label: []const u8, comptime fmt: []const u8, args: anytype) void {
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
    const nav = Vapor.lib.getStore([]const u8, "selected_nav") orelse "dashboard";
    selected_nav = std.meta.stringToEnum(NavItem, nav) orelse .dashboard;
    Box()
        .width(.percent(100))
        .height(.fit)
        .background(Theme.bg_base)
        .layout(.top_left)
        .children({
        // Navigation
        renderNavigation();

        // Main content area
        Stack()
            .width(.grow)
            .height(.fit)
            .children({
            // Header
            renderHeader();

            // Content
            Box()
                .width(.percent(100))
                .height(.grow)
                .children({
                switch (selected_nav) {
                    .dashboard => renderDashboardView(),
                    .transactions => renderTransactionsView(),
                    .analytics => renderAnalyticsView(),
                    .customers => renderCustomersView(),
                    .settings => renderSettingsView(),
                }
            });
        });

        // Overlays
        detail_sheet.render();
    });
}
