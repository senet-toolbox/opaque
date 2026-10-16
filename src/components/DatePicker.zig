const Vapor = @import("vapor");
const Box = Vapor.Box;
const Text = Vapor.Text;
const TextFmt = Vapor.TextFmt;
const Button = Vapor.Button;
const Stack = Vapor.Stack;
const Icon = Vapor.Icon;
const DateTime = Vapor.DateTime;
const std = @import("std");
const Select = @import("Select.zig").Select;
const new = @import("Select.zig").new;

const week_days: []const []const u8 = &.{
    "Mo",
    "Tu",
    "We",
    "Th",
    "Fr",
    "Sa",
    "Su",
};

var border: Vapor.Types.Border = .round(.transparent, .all(6));
var selected_border: Vapor.Types.Border = .round(.palette(.tint), .all(6));
var selected_background: Vapor.Types.Color = .palette(.tint);
var shadow: Vapor.Types.Shadow = .glow(2, .transparent);
// .color = .transparent,
// .spread = 2,
// };
var selected_shadow: Vapor.Types.Shadow = .glow(2, .transparentize(.palette(.tint), 0.1));
// .color = .transparentizeHex(.palette(.tint), 0.1),
// .spread = 2,
// };

var months: []const []const u8 = &.{
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
};

const DatePicker = @This();
_allocator: *std.mem.Allocator = undefined,

// State/Data
current_date: DateTime,
start_date: ?DateTime = null,
_viewed_date: DateTime = undefined,
_selected_date: DateTime = undefined,
_all_dates: []DateTime = undefined,

// Dimensions
_container_width: f32 = 256,
_container_height: f32 = 260,
_cell_dim: f32 = 32,

// Select options
months_select: Select(DateTime) = undefined,
years_select: Select(i32) = undefined,

// Event handlers
on_date_select: ?*const fn (date_picker: *DatePicker, date: DateTime) void = null,
on_year_select: ?*const fn (year: i32) void = null,
on_month_select: ?*const fn (month: i32) void = null,
on_next_month: ?*const fn () void = null,
on_prev_month: ?*const fn () void = null,

// Colors
tint: Vapor.Types.Color = .palette(.tint),
background: Vapor.Types.Color = .palette(.background),
selected_text_color: Vapor.Types.Color = .white,
text_color: Vapor.Types.Color = .palette(.text),
border_color: Vapor.Types.Color = .palette(.text),

pub fn init(date_picker: *DatePicker) void {
    var allocator = Vapor.arena(.persist);
    const selected_date = date_picker.start_date orelse DateTime.now();
    const start_dates = DateTime.getCalendarView(
        &allocator,
        selected_date.month,
        selected_date.year,
    ) catch |err| {
        Vapor.print(.err, "Error getting calendar view {any}", .{err});
        unreachable;
    };

    new();
    const current_months = DateTime.getMonths(&allocator, selected_date.year) catch {
        Vapor.print(.err, "Error getting months", .{});
        unreachable;
    };

    var months_select: Select(DateTime) = .fromItems(&.{
        .{ .value = current_months[0], .label = "January" },
        .{ .value = current_months[1], .label = "February" },
        .{ .value = current_months[2], .label = "March" },
        .{ .value = current_months[3], .label = "April" },
        .{ .value = current_months[4], .label = "May" },
        .{ .value = current_months[5], .label = "June" },
        .{ .value = current_months[6], .label = "July" },
        .{ .value = current_months[7], .label = "August" },
        .{ .value = current_months[8], .label = "September" },
        .{ .value = current_months[9], .label = "October" },
        .{ .value = current_months[10], .label = "November" },
        .{ .value = current_months[11], .label = "December" },
    });

    months_select.on_select = selectMonth;
    months_select.trigger = "Month";
    months_select.default(Select(DateTime).Item{ .value = selected_date, .label = DateTime.monthString(selected_date.month) });

    var temp = Vapor.array(Select(i32).Item, .persist);
    for (1925..2036) |year| {
        temp.append(.{ .value = @intCast(year), .label = std.fmt.allocPrint(allocator, "{d}", .{year}) catch unreachable }) catch unreachable;
    }

    var years_select: Select(i32) = .fromItems(temp.toOwnedSlice() catch unreachable);
    years_select.on_select = selectYear;
    years_select.trigger = "Year";
    years_select.default(Select(i32).Item{ .value = selected_date.year, .label = std.fmt.allocPrint(allocator, "{d}", .{selected_date.year}) catch unreachable });

    const view_date = selected_date;
    date_picker.* = DatePicker{
        ._selected_date = selected_date,
        ._allocator = &allocator,
        .current_date = DateTime.now(),
        ._viewed_date = view_date,
        ._all_dates = start_dates,
        .months_select = months_select,
        .years_select = years_select,
    };
}

fn selectMonth(select: *Select(DateTime), item: *Select(DateTime).Item) void {
    const date_picker: *DatePicker = @alignCast(@fieldParentPtr("months_select", select));
    date_picker._viewed_date = item.value;
    date_picker.updateViewedDate();
    if (date_picker.on_month_select) |cb| {
        @call(.auto, cb, .{item.value.month});
    }
}

fn selectYear(select: *Select(i32), item: *Select(i32).Item) void {
    const date_picker: *DatePicker = @alignCast(@fieldParentPtr("years_select", select));
    date_picker._viewed_date.year = item.value;
    date_picker.updateViewedDate();
    if (date_picker.on_year_select) |cb| {
        @call(.auto, cb, .{item.value});
    }
}

fn selectDate(date_picker: *DatePicker, date_time: DateTime) void {
    date_picker._selected_date = date_time;
    if (date_picker.on_date_select) |cb| {
        @call(.auto, cb, .{ date_picker, date_time });
    }
}

fn isSelectedColor(date_picker: *DatePicker, date_time: DateTime) Vapor.Types.Color {
    if (isSameDay(date_picker._selected_date, date_time)) {
        return date_picker.tint;
    } else if (date_time.day == date_picker.current_date.day and date_time.month == date_picker.current_date.month) {
        return .transparentize(date_picker.tint, 0.1);
    }
    return date_picker.background;
}

fn isSelectedBorder(date_picker: *DatePicker, date_time: DateTime) Vapor.Types.Border {
    if (isSameDay(date_picker._selected_date, date_time)) {
        return selected_border;
    } else if (date_time.day == date_picker.current_date.day and date_time.month == date_picker.current_date.month) {
        return .round(.transparentize(date_picker.tint, 0.1), .all(6));
    }
    return border;
}

fn isSelectedShadow(date_picker: *DatePicker, date_time: DateTime) Vapor.Types.Shadow {
    if (isSameDay(date_picker._selected_date, date_time)) {
        return selected_shadow;
    } else if (date_time.day == date_picker.current_date.day and date_time.month == date_picker.current_date.month) {
        return selected_shadow;
        // return .{
        //     .color = .transparentizeHex(date_picker.tint, 0.1),
        //     .spread = 2,
        // };
    }
    return shadow;
}

fn isSelectedText(date_picker: *DatePicker, date_time: DateTime) Vapor.Types.Color {
    if (DateTime.isWithinMonth(date_time, date_picker._viewed_date.month, date_picker._viewed_date.year)) {
        return date_picker.text_color;
    } else {
        return .transparentize(.grey, 0.7);
    }
}

/// The same calendar day: day, month and year.
fn isSameDay(a: DateTime, b: DateTime) bool {
    return a.day == b.day and a.month == b.month and a.year == b.year;
}

fn isSelected(date_picker: *DatePicker, date_time: DateTime) bool {
    if (isSameDay(date_picker._selected_date, date_time)) {
        return true;
    } else {
        return false;
    }
}

fn isSelectedBackground(date_picker: *DatePicker, date_time: DateTime) Vapor.Types.Color {
    if (DateTime.isWithinMonth(date_time, date_picker._viewed_date.month, date_picker._viewed_date.year)) {
        return date_picker.background;
    } else {
        return .transparentize(.grey, 0.1);
    }
}

fn prev(date_picker: *DatePicker) void {
    var allocator = Vapor.arena(.persist);
    const new_date = date_picker._viewed_date.addMonths(-1);
    date_picker._viewed_date = new_date;

    // Old Dates
    const old_dates = date_picker._all_dates;
    allocator.free(old_dates);

    const dates = date_picker.getMonthDays();
    date_picker._all_dates = dates;
    if (date_picker.on_prev_month) |cb| {
        @call(.auto, cb, .{});
    }
}

fn next(date_picker: *DatePicker) void {
    var allocator = Vapor.arena(.persist);
    const new_date = date_picker._viewed_date.addMonths(1);
    date_picker._viewed_date = new_date;

    // Old Dates
    const old_dates = date_picker._all_dates;
    allocator.free(old_dates);

    const dates = date_picker.getMonthDays();
    date_picker._all_dates = dates;
    if (date_picker.on_next_month) |cb| {
        @call(.auto, cb, .{});
    }
}

fn updateViewedDate(date_picker: *DatePicker) void {
    var allocator = Vapor.arena(.persist);
    // Old Dates
    const old_dates = date_picker._all_dates;
    allocator.free(old_dates);

    const dates = date_picker.getMonthDays();
    date_picker._all_dates = dates;
}

fn getMonthDays(date_picker: *DatePicker) []DateTime {
    var allocator = Vapor.arena(.persist);
    const _all_dates = DateTime.getCalendarView(
        &allocator,
        date_picker._viewed_date.month,
        date_picker._viewed_date.year,
    ) catch |err| {
        Vapor.print(.err, "Calendar Error {any}\n", .{err});
        unreachable;
    };
    return _all_dates;
}

pub fn render(date_picker: *DatePicker) void {
    Stack()
        .width(.px(date_picker._container_width))
        .border(.round(.transparentize(date_picker.border_color, 0.1), .all(8)))
        .shadow(.glow(4, .transparentize(date_picker.border_color, 0.05)))
        .background(date_picker.background)
        .layout(.center)
        .spacing(8)
        .padding(.vertical(12))
        .children({
        Box()
            .width(.percent(90))
            .layout(.x_between_center)
            .children({
            Button(prev, .{date_picker})
                .ariaLabel("Previous Month")
                .background(date_picker.background)
                .cursor(.pointer)
                .children({
                Icon(.chevron_left)
                    .fontSize(14)
                    .end();
            });
            TextFmt("{s} {d}", .{
                DateTime.monthString(@intCast(date_picker._viewed_date.month)),
                date_picker._viewed_date.year,
            }).end();
            Button(next, .{date_picker})
                .ariaLabel("Next Month")
                .background(date_picker.background)
                .cursor(.pointer)
                .children({
                Icon(.chevron_right)
                    .fontSize(16)
                    .end();
            });
        });
        Box()
            .width(.percent(100))
            .layout(.center)
            .direction(.column)
            .padding(.horizontal(9))
            .spacing(8)
            .children({
            Box()
                .width(.percent(100))
                .layout(.x_between_center)
                .children({
                Box()
                    .width(.percent(58))
                    .children({
                    date_picker.months_select.renderPos(.bottom);
                });
                Box()
                    .width(.percent(38))
                    .children({
                    date_picker.years_select.renderPos(.bottom);
                });
            });

            Box()
                .width(.percent(100))
                .spacing(2)
                .children({
                for (week_days) |day| {
                    Box()
                        .width(.px(date_picker._cell_dim))
                        .height(.px(date_picker._cell_dim))
                        .layout(.center)
                        .children({
                        Text(day).font(14, null, date_picker.text_color).end();
                    });
                }
            });
            Box()
                .width(.percent(100))
                .wrap(.wrap)
                .spacing(2)
                .children({
                for (date_picker._all_dates) |date| {
                    const color: Vapor.Types.Color = if (date_picker.isSelected(date)) date_picker.background else .transparentize(.black, 0.05);
                    Button(selectDate, .{ date_picker, date })
                        // Named by its full date, and pressed when chosen.
                        .a11y(Vapor.Accessibility.init().setPressed(if (date_picker.isSelected(date)) .true_val else .false_val))
                        .ariaLabel(Vapor.fmtln("{s} {d}, {d}", .{ DateTime.monthString(date.month), date.day, date.year }))
                        .cursor(.pointer)
                        .background(date_picker.background)
                        .width(.px(date_picker._cell_dim))
                        .height(.px(date_picker._cell_dim))
                        .mt(2)
                        .mb(2)
                        .border(isSelectedBorder(date_picker, date))
                        .shadow(isSelectedShadow(date_picker, date))
                        .layout(.center)
                        .hover(.{
                            .background = color,
                        })
                        .children({
                        TextFmt("{d:2}", .{date.day})
                            .layout(.center)
                            .font(14, 300, isSelectedText(date_picker, date))
                            .end();
                    });
                }
            });
        });
    });
}
