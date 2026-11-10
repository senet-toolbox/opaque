//! Where a page sits: links to the pages above it, then the page itself.
//!
//!   Breadcrumb.render(&.{
//!       .{ .label = "Home", .url = "/" },
//!       .{ .label = "Components", .url = "/ui/components" },
//!       .{ .label = "Breadcrumb" },
//!   }, .{});
//!
//! The last crumb is the page you are on: not a link, and screen readers
//! hear it as the current page. A trail too long for its row wraps.

const Vapor = @import("vapor");
const Focus = @import("Focus.zig");
const Box = Vapor.Box;
const List = Vapor.List;
const ListItem = Vapor.ListItem;
const Link = Vapor.Link;
const Text = Vapor.Text;
const Icon = Vapor.Icon;

pub const Crumb = struct {
    label: []const u8,
    /// Where it goes. The last crumb, the page you are on, needs none.
    url: ?[]const u8 = null,
    /// Drawn before the label.
    icon: ?Vapor.IconTokens = null,
};

pub const Separator = enum {
    /// ›
    chevron,
    /// /
    slash,

    fn glyph(separator: Separator) []const u8 {
        return switch (separator) {
            .chevron => "›",
            .slash => "/",
        };
    }
};

pub const Options = struct {
    /// Names the trail for screen readers.
    label: []const u8 = "Breadcrumb",
    separator: Separator = .chevron,
};

/// The links and separators.
pub var muted_color: Vapor.Types.Color = .transparentize(.palette(.text_color), 0.6);
/// The page you are on, and a link under the pointer.
pub var current_color: Vapor.Types.Color = .palette(.text_color);
pub var font_size: u8 = 14;

pub fn render(crumbs: []const Crumb, options: Options) void {
    Box()
        .a11y(Vapor.Accessibility.init().setRole(.navigation).setLabel(options.label))
        .children({
        List()
            .layout(.left_center)
            .wrap(.wrap)
            .spacing(6)
            .padding(.all(0))
            .listStyle(.none)
            .children({
            for (crumbs, 0..) |crumb, i| {
                const last = i + 1 == crumbs.len;
                ListItem()
                    .layout(.left_center)
                    .spacing(6)
                    .children({
                    if (last or crumb.url == null) {
                        current(crumb, last);
                    } else {
                        link(crumb);
                    }
                    if (!last) {
                        Text(options.separator.glyph())
                            .ariaHidden(true)
                            .font(font_size, 400, muted_color)
                            .inlineStyle("user-select: none;", .{})
                            .end();
                    }
                });
            }
        });
    });
}

fn link(crumb: Crumb) void {
    Link(.{ .url = crumb.url.? })
        .layout(.left_center)
        .spacing(4)
        .textColor(muted_color)
        .radius(.all(4))
        .duration(120)
        .hover(.{ .text_color = current_color })
        .focusVisible(Focus.ring())
        .children({
        label(crumb, null, 400);
    });
}

/// The page you are on, or a crumb with nowhere to go.
fn current(crumb: Crumb, last: bool) void {
    const box = Box()
        .layout(.left_center)
        .spacing(4);
    (if (last) box.attribute("aria-current", "page") else box).children({
        if (last) label(crumb, current_color, 500) else label(crumb, muted_color, 400);
    });
}

/// `color` null takes the link's, so its hover colour reaches the text.
fn label(crumb: Crumb, color: ?Vapor.Types.Color, weight: u16) void {
    if (crumb.icon) |icon| {
        Icon(icon)
            .ariaHidden(true)
            .font(font_size, 400, color)
            .end();
    }
    Text(crumb.label)
        .font(font_size, weight, color)
        .end();
}
