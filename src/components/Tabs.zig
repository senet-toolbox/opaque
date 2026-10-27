const Vapor = @import("vapor");
const std = @import("std");
const Opaque = @import("Opaque.zig");
const Button = Vapor.Button;
const Box = Vapor.Box;
const Text = Vapor.Text;
const Field = Opaque.Field;
const Stack = Vapor.Stack;
const Toast = Opaque.Toast;
const Tooltip = Opaque.Tooltip;

var peristant_tabs: std.StringHashMap(*Tabs) = undefined;

const Tabs = @This();
/// The name these tabs are kept under; their element ids start with it.
tag: []const u8 = "",
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

pub fn switchToTab(tag: []const u8, index: usize) void {
    // Tabs that have not rendered yet have no names to switch between.
    const tabs = peristant_tabs.get(tag) orelse return;
    if (index >= tabs.names.len) return;
    tabs.active_tab = tabs.names[index];
}

pub fn NavBar(tag: []const u8, names: []const []const u8) usize {
    // 1. Retrieve or Create State
    const tabs = peristant_tabs.get(tag) orelse blk: {
        const t = Vapor.arena(.persist).create(Tabs) catch unreachable;
        t.* = .{
            .tag = tag,
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
            .tag = tag,
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
        .a11y(.tabList("Main navigation tabs"))
        .onEvent(.keydown, navKey, .{tabs})
        .layout(.left_center)
        .padding(.all(2))
        .scroll(.scrollX())
        .spacing(12)
        .children({
        for (tabs.names, 0..) |name, i| {
            const is_selected = (active_idx == i);
            Button(switchTabs, .{ tabs, name, active_idx })
                .id(tabId(tabs, name))
                .a11y(Vapor.Accessibility.init().setRole(.tab).setSelected(is_selected))
                .tabIndex(if (is_selected) 0 else -1)
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
    Button(switchTabs, .{ tabs, name, active_idx })
        .id(tabId(tabs, name))
        .a11y(Vapor.Accessibility.init().setRole(.tab).setSelected(is_selected))
        .tabIndex(if (is_selected) 0 else -1)
        .background(if (active_idx == i) .transparentize(.palette(.tint), 0.7) else .transparent)
        .border(.round(.palette(.tint), .all(4)))
        .padding(.xy(8, 4))
        .children({
        Text(name)
            .fontFamily("IBM Plex Sans,monospace")
            .font(14, 300, if (active_idx == i) .white else .palette(.text))
            .end();
    });
}

fn Nav(tabs: *Tabs, active_idx: usize) void {
    // Tabs that do not fit scroll sideways instead of widening the page.
    Box()
        .a11y(.tabList("Main navigation tabs"))
        .onEvent(.keydown, navKey, .{tabs})
        .inlineStyle("max-width: 100%;", .{})
        .scroll(.scrollX())
        .layout(.left_center)
        .background(.transparentize(.palette(.tint), 0.1))
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

/// A tab's element id, "tab-<tag>-<name>": unique per Tabs, the same in a
/// prerendered page and in the app, and safe in HTML (names may hold spaces).
fn tabId(tabs: *const Tabs, name: []const u8) []const u8 {
    const id = Vapor.fmtln("tab-{s}-{s}", .{ tabs.tag, name });
    const safe = Vapor.frame.arena().dupe(u8, id) catch return id;
    for (safe[4..]) |*c| {
        if (!std.ascii.isAlphanumeric(c.*)) c.* = '-' else c.* = std.ascii.toLower(c.*);
    }
    return safe;
}

/// Left/Right move to the previous/next tab and Home/End to the first/last,
/// selecting it and taking focus with it (the WAI-ARIA tabs pattern).
fn navKey(tabs: *Tabs, evt: *Vapor.Event) void {
    const count = tabs.names.len;
    if (count == 0) return;
    const key = evt.key();
    const current = tabs.selected_index;
    const next: usize = if (std.mem.eql(u8, key, "ArrowRight"))
        (current + 1) % count
    else if (std.mem.eql(u8, key, "ArrowLeft"))
        (current + count - 1) % count
    else if (std.mem.eql(u8, key, "Home"))
        0
    else if (std.mem.eql(u8, key, "End"))
        count - 1
    else
        return;
    evt.preventDefault();
    switchTabs(tabs, tabs.names[next], current);
    Vapor.onLayout(focusSelected, .{tabs});
}

/// Focuses whichever tab is selected when it runs: with keys pressed in
/// quick succession, an earlier call can run after a later one.
fn focusSelected(tabs: *Tabs) void {
    if (tabs.selected_index >= tabs.names.len) return;
    Vapor.lib.focus(tabId(tabs, tabs.names[tabs.selected_index]));
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
