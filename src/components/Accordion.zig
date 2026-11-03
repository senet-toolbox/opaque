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
        Box()
            .width(.percent(100))
            .direction(.column)
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
            // Opens to its content's height, whatever it is, and shuts; shut,
            // its content is out of the tab order and away from screen
            // readers. The trigger stays outside it, so it never moves.
            Vapor.Collapse(item.is_open)
                .width(.percent(100))
                .direction(.column)
                .padding(.{ .left = 12, .right = 12, .bottom = 12 })
                .children({
                if (item.content) |content| content(item);
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
