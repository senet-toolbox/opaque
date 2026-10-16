//! Collapsible sections: each item's trigger opens and closes its panel.
//!
//!   var items = [_]Accordion.AccordionItem{
//!       .{ .title = "Shipping", .description = "...", .trigger = myTrigger, .content = myContent },
//!   };
//!   var accordion = Accordion.init(&items);
//!   accordion.render();
//!
//! Panels take their content's height, whatever it is: the open/close
//! animation runs on a grid row, not on a measured pixel height. A closed
//! panel is hidden from the tab order and from screen readers.

const std = @import("std");
const Vapor = @import("vapor");
const Box = Vapor.Box;
const Button = Vapor.Button;

const Accordion = @This();
items: []AccordionItem,

const duration_ms = 150;

pub const AccordionItem = struct {
    title: []const u8,
    description: []const u8,
    is_open: bool = false,
    trigger: ?*const fn (*AccordionItem) void = null,
    content: ?*const fn (*AccordionItem) void = null,

    fn toggle(item: *AccordionItem) void {
        item.is_open = !item.is_open;
    }

    pub fn render(item: *AccordionItem) void {
        // Two grid rows: the trigger at its own height, and the panel,
        // which animates between 0fr and 1fr, i.e. 0 and its content height.
        Box()
            .width(.percent(100))
            .inlineStyle("display: grid; grid-template-rows: auto {s}; transition: grid-template-rows {d}ms ease-in-out;", .{
                if (item.is_open) "1fr" else "0fr",
                duration_ms,
            })
            .children({
            Button(toggle, .{item})
                .a11y(Vapor.Accessibility.init().setExpanded(item.is_open))
                .width(.percent(100))
                .padding(.vertical(8))
                .background(.transparent)
                .cursor(.pointer)
                .layout(.x_between_center)
                .spacing(12)
                .children({
                if (item.trigger) |trigger| trigger(item);
                Vapor.Icon(if (item.is_open) .chevron_up else .chevron_down)
                    .font(12, 700, .palette(.text_color))
                    .end();
            });
            // The panel. Once closed it turns invisible, after the animation,
            // which takes its buttons out of the tab order.
            Box()
                .width(.percent(100))
                .direction(.column)
                .inlineStyle("min-height: 0; overflow: hidden; visibility: {s}; transition: visibility 0s linear {d}ms;", .{
                    if (item.is_open) "visible" else "hidden",
                    if (item.is_open) @as(u32, 0) else duration_ms,
                })
                .children({
                Box()
                    .width(.percent(100))
                    .direction(.column)
                    .padding(.{ .left = 12, .right = 12, .bottom = 12 })
                    .children({
                    if (item.content) |content| content(item);
                });
            });
        });
    }
};

pub fn init(items: []AccordionItem) Accordion {
    return Accordion{
        .items = items,
    };
}

pub fn render(accordion: *Accordion) void {
    Box()
        .width(.percent(100))
        .direction(.column)
        .spacing(8)
        .children({
        for (accordion.items) |*item| {
            item.render();
        }
    });
}
