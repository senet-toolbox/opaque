const Vapor = @import("vapor");
const std = @import("std");
const Opaque = @import("Opaque.zig");
const Button = Opaque.Button;
const Box = Vapor.Box;
const Text = Vapor.Text;
const Field = Opaque.Field;
const Stack = Vapor.Stack;
const Toast = Opaque.Toast;
const Tooltip = Opaque.Tooltip;

var peristant_tabs: std.StringHashMap(*Tabs) = undefined;

const Tabs = @This();
active_tab: ?[]const u8 = null,
names: []const []const u8,
on_click: ?*const fn (*Tabs) void = null,
selected_index: usize = 0,
// tabs: std.array_list.Managed(Tab),

pub fn new() void {
    peristant_tabs = std.StringHashMap(*Tabs).init(Vapor.arena(.persist));
}

const Tab = struct {
    title: []const u8,
    content: []const u8,
    tag: []const u8,
};

fn getTab(tabs: *Tabs, name: []const u8) ?Tab {
    for (tabs.tabs.items) |tab| {
        if (std.mem.eql(u8, tab.tag, name)) {
            return tab;
        }
    }
    return null;
}

fn component() void {
    Vapor.print("component", .{});
}

fn closeTabs(_: void) void {
    Vapor.print("closeTabs", .{});
}

pub fn Content(tag: []const u8) *const fn (void) void {
    Vapor.print("Content", .{});
    const tabs = peristant_tabs.get(tag) orelse blk: {
        const tabs = Vapor.arena(.persist).create(Tabs) catch unreachable;
        peristant_tabs.put(tag, tabs) catch unreachable;
        break :blk tabs;
    };
    const current_tab = if (tabs.active_tab == null) tag else tabs.active_tab.?;
    // 2. Default to index 0 if nothing is selected
    // (You might want to store 'active_index: usize' instead of strings for O(1) lookups)

    if (std.mem.eql(u8, current_tab, tag)) {
        return closeTabs;
    }
    return closeTabs;
}

pub fn switchToTab(tag: []const u8, index: usize) void {
    const tabs = peristant_tabs.get(tag) orelse blk: {
        const t = Vapor.arena(.persist).create(Tabs) catch unreachable;
        t.* = .{}; // Initialize list
        peristant_tabs.put(tag, t) catch unreachable;
        break :blk t;
    };
    tabs.active_tab = tabs.names[index];
}

pub fn NavBar(tag: []const u8, names: []const []const u8) usize {
    // 1. Retrieve or Create State
    const tabs = peristant_tabs.get(tag) orelse blk: {
        const t = Vapor.arena(.persist).create(Tabs) catch unreachable;
        t.* = .{
            .names = names,
        }; // Initialize list
        peristant_tabs.put(tag, t) catch unreachable;
        break :blk t;
    };

    // 2. Default to index 0 if nothing is selected
    // (You might want to store 'active_index: usize' instead of strings for O(1) lookups)
    var active_idx: usize = 0;

    // logic to find current active index based on stored string
    if (tabs.active_tab) |active_name| {
        for (names, 0..) |name, i| {
            if (std.mem.eql(u8, active_name, name)) {
                active_idx = i;
                break;
            }
        }
    }

    Nav(tabs, active_idx);
    tabs.selected_index = active_idx;

    return active_idx;
}

pub fn create(tag: []const u8, names: []const []const u8) *Tabs {
    // 1. Retrieve or Create State
    const tabs = peristant_tabs.get(tag) orelse blk: {
        const t = Vapor.arena(.persist).create(Tabs) catch unreachable;
        t.* = .{
            .names = names,
        }; // Initialize list
        peristant_tabs.put(tag, t) catch unreachable;
        break :blk t;
    };
    tabs.names = names;

    return tabs;
}

pub fn default(tabs: *Tabs, name: ?[]const u8) *Tabs {
    if (name == null) return tabs;
    tabs.active_tab = name;
    return tabs;
}

pub fn onClick(tabs: *Tabs, callback: *const fn (*Tabs) void) *Tabs {
    tabs.on_click = callback;
    return tabs;
}

pub fn render(tabs: *Tabs) usize {
    // 2. Default to index 0 if nothing is selected
    // (You might want to store 'active_index: usize' instead of strings for O(1) lookups)
    var active_idx: usize = 0;

    // logic to find current active index based on stored string
    if (tabs.active_tab) |active_name| {
        for (tabs.names, 0..) |name, i| {
            if (std.mem.eql(u8, active_name, name)) {
                active_idx = i;
                break;
            }
        }
    }

    Nav(tabs, active_idx);
    tabs.selected_index = active_idx;

    return active_idx;
}

pub fn Trigger(tabs: *Tabs, trigger_fn: *const fn (*Tabs, []const u8, bool) void) usize {
    // 2. Default to index 0 if nothing is selected
    // (You might want to store 'active_index: usize' instead of strings for O(1) lookups)
    var active_idx: usize = 0;

    // logic to find current active index based on stored string
    if (tabs.active_tab) |active_name| {
        for (tabs.names, 0..) |name, i| {
            if (std.mem.eql(u8, active_name, name)) {
                active_idx = i;
                break;
            }
        }
    }

    Box()
        .a11y(.tabList("Main navigation tabs")) // Add this
        .layout(.left_center)
        .padding(.all(2))
        .scroll(.scroll_x())
        .spacing(12)
        .children({
        for (tabs.names, 0..) |name, i| {
            const is_selected = (active_idx == i);
            const panel_id = Vapor.fmtln("tabpanel-{s}", .{name});

            Button(switchTabs, .{ tabs, name, active_idx })
                .a11y(.tab(is_selected, panel_id)) // Add this
                .children({
                trigger_fn(tabs, name, if (active_idx == i) true else false);
            });
        }
    });

    return active_idx;
}

const NavBtnCtx = struct {
    tabs: *Tabs,
    name: []const u8,
    active_idx: usize,
    i: usize,
};

fn NavBtn(ctx: ?*anyopaque) void {
    if (ctx == null) return;
    const nav_btn_ctx: *NavBtnCtx = @ptrCast(@alignCast(ctx));
    const tabs = nav_btn_ctx.tabs;
    const name = nav_btn_ctx.name;
    const active_idx = nav_btn_ctx.active_idx;
    const i = nav_btn_ctx.i;

    const is_selected = (active_idx == i);
    const panel_id = Vapor.fmtln("tabpanel-{s}", .{name});

    Button(switchTabs, .{ tabs, name, active_idx })
        .a11y(.tab(is_selected, panel_id)) // Add this
        .background(if (active_idx == i) .transparentizeHex(.palette(.tint), 0.7) else .transparent)
        .border(.round(.palette(.tint), .all(4)))
        .padding(.tblr(4, 4, 8, 8))
        .children({
        Text(name)
            .fontFamily("IBM Plex Sans,monospace")
            .font(14, 300, if (active_idx == i) .white else .palette(.text))
            .end();
    });
}

fn Nav(tabs: *Tabs, active_idx: usize) void {
    Box()
        .a11y(.tabList("Main navigation tabs")) // Add this
        .layout(.left_center)
        .background(.transparentizeHex(.palette(.tint), 0.1))
        .padding(.all(2))
        .border(.round(.transparent, .all(4)))
        .spacing(12)
        .children({
        for (tabs.names, 0..) |name, i| {
            const ctx = Vapor.arena(.frame).create(NavBtnCtx) catch unreachable;
            ctx.* = NavBtnCtx{ .tabs = tabs, .name = name, .active_idx = active_idx, .i = i };
            NavBtn(@ptrCast(@alignCast(ctx)));
        }
    });
}

fn switchTabs(tabs: *Tabs, selected_name: []const u8, _: usize) void {
    tabs.active_tab = selected_name;

    // logic to find current active index based on stored string
    if (tabs.active_tab) |active_name| {
        for (tabs.names, 0..) |name, i| {
            if (std.mem.eql(u8, active_name, name)) {
                tabs.selected_index = i;
                break;
            }
        }
    }

    if (tabs.on_click) |callback| {
        callback(tabs);
    }
}
