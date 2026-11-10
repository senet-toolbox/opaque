//! A menu button: a button that opens a list of actions.
//!
//!   const items = [_]Menu.Item{
//!       .{ .label = "Edit", .icon = .pencil, .shortcut = "E" },
//!       .{ .label = "Delete", .icon = .trash, .destructive = true, .separator_before = true },
//!   };
//!   var menu: Menu = undefined;
//!   menu = Menu.init("Actions", &items, onPick); // once, in init
//!   menu.render(); // every render
//!
//!   fn onPick(item: *const Menu.Item, index: usize) void { ... }
//!
//! It follows the ARIA menu button pattern. The button opens the menu and
//! the focus moves to its first item; Up and Down move between items,
//! wrapping round, Home and End go to the ends, and a letter goes to the
//! next item starting with it. Enter or Space picks the focused item.
//! Escape, Tab or a click outside closes it. Closing puts the focus back on
//! the button.

const std = @import("std");
const Vapor = @import("vapor");
const Focus = @import("Focus.zig");
const Box = Vapor.Box;
const Stack = Vapor.Stack;
const Text = Vapor.Text;
const Icon = Vapor.Icon;
const Button = Vapor.Button;
const Anchor = Vapor.Anchor;

const Menu = @This();

pub const Item = struct {
    label: []const u8,
    icon: ?Vapor.IconTokens = null,
    /// Shown at the right, such as a key it is also on; the menu doesn't
    /// bind the key itself.
    shortcut: ?[]const u8 = null,
    /// Coloured as a warning: delete, remove, sign out.
    destructive: bool = false,
    /// Shown, but can't be picked, and the keys pass over it.
    disabled: bool = false,
    /// A line above it, to group the items.
    separator_before: bool = false,
};

pub var background: Vapor.Types.Color = .palette(.background);
pub var border_color: Vapor.Types.Color = .palette(.border_color_light);
pub var text_color: Vapor.Types.Color = .palette(.text_color);
pub var highlight: Vapor.Types.Color = .transparentize(.palette(.tint), 0.15);
pub var destructive_color: Vapor.Types.Color = .hex("#ef4444");

const animate_enter = Vapor.Animation.init("opaque-menu-enter")
    .prop(.opacity, 0, 1)
    .prop(.translateY, -4, 0)
    .duration(120)
    .easing(.easeOut);

pub fn new() void {
    animate_enter.build();
}

/// Names the button and the menu: its text on the standard button, and
/// for screen readers.
label: []const u8,
items: []const Item,
/// Called with the item picked, and its place in `items`.
on_select: ?*const fn (item: *const Item, index: usize) void = null,
/// Where the menu opens, against the button.
placement: Vapor.Types.AnchorPlacement = .bottom,
/// The button; the focus goes back to it when the menu closes.
trigger: Vapor.Element = .{},
_open: bool = false,
_focus: usize = 0,
_id: u32 = 0,

var next_id: u32 = 0;

pub fn init(label: []const u8, items: []const Item, on_select: ?*const fn (item: *const Item, index: usize) void) Menu {
    next_id += 1;
    return .{ .label = label, .items = items, .on_select = on_select, ._id = next_id };
}

pub fn isOpen(menu: *const Menu) bool {
    return menu._open;
}

/// Opens the menu with the focus on its first item that can be picked.
pub fn open(menu: *Menu) void {
    menu.openAt(.first);
}

pub fn close(menu: *Menu) void {
    if (!menu._open) return;
    menu._open = false;
    Vapor.onLayout(focusTrigger, .{menu});
}

pub fn toggle(menu: *Menu) void {
    if (menu._open) menu.close() else menu.open();
}

const Start = enum { first, last };

fn openAt(menu: *Menu, start: Start) void {
    menu._open = true;
    menu._focus = switch (start) {
        .first => menu.step(menu.items.len - 1, 1),
        .last => menu.step(0, -1),
    };
    Vapor.onLayout(focusCurrent, .{menu});
}

/// The next item that can be picked from `from`, `dir` places on (1 or
/// -1), wrapping round; `from` itself when none can.
fn step(menu: *const Menu, from: usize, dir: i2) usize {
    const n = menu.items.len;
    if (n == 0) return 0;
    var i = from;
    for (0..n) |_| {
        i = if (dir > 0) (i + 1) % n else (i + n - 1) % n;
        if (!menu.items[i].disabled) return i;
    }
    return from;
}

fn anchorName(menu: *const Menu) []const u8 {
    return Vapor.fmtln("opaque-menu-{d}", .{menu._id});
}

fn itemId(menu: *const Menu, index: usize) []const u8 {
    return Vapor.fmtln("opaque-menu-{d}-item-{d}", .{ menu._id, index });
}

fn focusCurrent(menu: *Menu) void {
    if (!menu._open or menu._focus >= menu.items.len) return;
    Vapor.lib.focus(itemId(menu, menu._focus));
}

/// Moves the highlight and the focus to `index`; the render draws the
/// highlight.
fn moveTo(menu: *Menu, index: usize) void {
    menu._focus = index;
    focusCurrent(menu);
    Vapor.cycle();
}

fn focusTrigger(menu: *Menu) void {
    if (menu.trigger._get_id() != null) menu.trigger.focus();
}

fn pick(menu: *Menu, index: usize) void {
    if (index >= menu.items.len or menu.items[index].disabled) return;
    menu.close();
    if (menu.on_select) |on_select| on_select(&menu.items[index], index);
}

/// The pointer moves the focus with it, so hover and keys share one
/// highlight.
fn hoverItem(menu: *Menu, index: usize, _: *Vapor.Event) void {
    if (menu.items[index].disabled or menu._focus == index) return;
    menu.moveTo(index);
}

/// Down or Up on the button opens the menu at its first or last item.
fn onTriggerKey(menu: *Menu, evt: *Vapor.Event) void {
    const key = evt.key();
    if (std.mem.eql(u8, key, "ArrowDown")) {
        evt.preventDefault();
        menu.openAt(.first);
    } else if (std.mem.eql(u8, key, "ArrowUp")) {
        evt.preventDefault();
        menu.openAt(.last);
    }
}

fn onMenuKey(menu: *Menu, evt: *Vapor.Event) void {
    const key = evt.key();
    const n = menu.items.len;
    if (n == 0) return;
    var next = menu._focus;
    if (std.mem.eql(u8, key, "ArrowDown")) {
        next = menu.step(menu._focus, 1);
    } else if (std.mem.eql(u8, key, "ArrowUp")) {
        next = menu.step(menu._focus, -1);
    } else if (std.mem.eql(u8, key, "Home")) {
        next = menu.step(n - 1, 1);
    } else if (std.mem.eql(u8, key, "End")) {
        next = menu.step(0, -1);
    } else if (std.mem.eql(u8, key, "Escape") or std.mem.eql(u8, key, "Tab")) {
        evt.preventDefault();
        menu.close();
        return;
    } else if (key.len == 1 and std.ascii.isAlphanumeric(key[0])) {
        // The next item starting with the letter.
        var i = menu._focus;
        for (0..n) |_| {
            i = (i + 1) % n;
            const item = menu.items[i];
            if (!item.disabled and item.label.len > 0 and std.ascii.toLower(item.label[0]) == std.ascii.toLower(key[0])) {
                next = i;
                break;
            }
        }
    } else {
        // Enter and Space reach the focused item's button as a click.
        return;
    }
    evt.preventDefault();
    menu.moveTo(next);
}

/// The standard button: the label and a chevron.
pub fn render(menu: *Menu) void {
    menu.button().children({
        Text(menu.label)
            .font(14, 400, text_color)
            .end();
        Icon(.chevron_down)
            .font(12, 400, text_color)
            .end();
    });
    menu.renderMenu();
}

/// A button you draw yourself, such as an icon alone: `label` still names
/// it for screen readers.
pub fn renderWith(menu: *Menu, comptime trigger_fn: anytype, args: anytype) void {
    menu.button()
        .ariaLabel(menu.label)
        .children({
        @call(.auto, trigger_fn, args);
    });
    menu.renderMenu();
}

fn button(menu: *Menu) Vapor.Builder(.pure) {
    return Button(toggle, .{menu})
        .focusVisible(Focus.ring())
        .ref(&menu.trigger)
        .a11y(Vapor.Accessibility.init()
        .setHasPopup(.menu)
        .setExpanded(menu._open))
        .anchorSource(anchorName(menu))
        .onEvent(.keydown, onTriggerKey, .{menu})
        .layout(.center)
        .spacing(8)
        .padding(.xy(12, 8))
        .background(background)
        .border(.round(border_color, .all(8)))
        .cursor(.pointer);
}

fn renderMenu(menu: *Menu) void {
    if (!menu._open) {
        Vapor.Null();
        Vapor.Null();
        return;
    }
    // Catches a click outside; the keyboard has Escape.
    Button(close, .{menu})
        .ariaHidden(true)
        .tabIndex(-1)
        .pos(.tl(.px(0), .px(0), .fixed))
        .size(.full)
        .background(.transparent)
        .zIndex(998)
        .children({});
    Anchor(anchorName(menu))
        .placement(menu.placement)
        .zIndex(999)
        .children({
        Stack()
            .a11y(Vapor.Accessibility.init().setRole(.menu).setLabel(menu.label))
            .onEvent(.keydown, onMenuKey, .{menu})
            .animationEnter("opaque-menu-enter")
            .minWidth(.px(200))
            .margin(.all(6))
            .padding(.all(4))
            .spacing(2)
            .background(background)
            .border(.round(border_color, .all(10)))
            .shadow(Vapor.Types.Shadow.init().dropSpread(0, 8, 24, 0, .transparentize(.black, 0.15)))
            .children({
            for (menu.items, 0..) |*item, i| {
                if (item.separator_before and i > 0) {
                    Box()
                        .a11y(Vapor.Accessibility.init().setRole(.separator))
                        .width(.percent(100))
                        .height(.px(1))
                        .margin(.{ .top = 4, .bottom = 4 })
                        .background(border_color)
                        .children({});
                }
                const color = if (item.destructive) destructive_color else text_color;
                Button(pick, .{ menu, i })
                    .id(itemId(menu, i))
                    .a11y(Vapor.Accessibility.init().setRole(.menu_item).setDisabled(item.disabled))
                    .attribute("aria-keyshortcuts", item.shortcut orelse "")
                    .tabIndex(-1)
                    .onEvent(.pointerenter, hoverItem, .{ menu, i })
                    .width(.percent(100))
                    .layout(.left_center)
                    .spacing(10)
                    .padding(.xy(10, 7))
                    .background(if (menu._focus == i) highlight else .transparent)
                    .border(.round(.transparent, .all(6)))
                    .cursor(if (item.disabled) .default else .pointer)
                    .opacity(if (item.disabled) 0.45 else 1)
                    .inlineStyle("outline: none;", .{})
                    .children({
                    if (item.icon) |icon| {
                        Icon(icon)
                            .font(14, 400, color)
                            .end();
                    }
                    Text(item.label)
                        .font(14, 400, color)
                        .inlineStyle("flex: 1; text-align: left; white-space: nowrap;", .{})
                        .end();
                    if (item.shortcut) |shortcut| {
                        // Read out as aria-keyshortcuts, not as part of the name.
                        Text(shortcut)
                            .ariaHidden(true)
                            .font(12, 400, .transparentize(text_color, 0.5))
                            .end();
                    }
                });
            }
        });
    });
}
