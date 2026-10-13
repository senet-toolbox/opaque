const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Box;
const ButtonCtx = Vapor.CtxButton;
const Button = Vapor.Button;

const Accordion = @This();
items: []AccordionItem,

var border_color: Vapor.Types.Color = .hex("#e4e4e4");

pub const AccordionItem = struct {
    title: []const u8,
    description: []const u8,
    is_open: bool = false,
    min_height: f32 = 42,
    max_height: f32 = 252,
    height: f32 = 42,
    total_height: Vapor.Types.Sizing = .px(42),
    binded: Vapor.Binded = .{},
    calculated_height: f32 = 0,

    trigger: ?*const fn (*AccordionItem) void = null,
    content: ?*const fn (*AccordionItem) void = null,

    fn toggle(accordon_item: *AccordionItem) void {
        if (accordon_item.is_open) {
            accordon_item.is_open = false;
            accordon_item.height = accordon_item.min_height;
            accordon_item.total_height = .px(42);
        } else {
            accordon_item.is_open = true;
            accordon_item.height = accordon_item.max_height;
            accordon_item.total_height = .px(accordon_item.calculated_height);
        }
    }

    fn mount(accordon_item: *AccordionItem) void {
        const full_height = accordon_item.binded.getAttributeNumber("scrollHeight") + 52;
        accordon_item.calculated_height = @floatFromInt(full_height);
    }

    pub fn render(accordon_item: *AccordionItem) void {
        Box()
            .onMount(mount, .{accordon_item})
            .width(.percent(100))
            .height(accordon_item.total_height)
            .transition(.{
                .properties = &.{.height},
                .duration = 150,
                .timing = .easeInOut,
            })
            // Position: Top Right, fixed/absolute
            .background(.transparent)

            // Layout: Row (Icon -> Content -> Close)
            .layout(.top_left) // Vertically center items
            .direction(.column)
            .children({
            Box()
                .height(.px(accordon_item.min_height))
                .layout(.x_between_center)
                .width(.percent(100))
                .children({
                ButtonCtx(toggle, .{accordon_item})
                    .height(.percent(100))
                    .width(.percent(100))
                    .background(.transparent)
                    .cursor(.pointer)
                    .layout(.x_between_center)
                    .children({
                    if (accordon_item.trigger) |trigger| {
                        trigger(accordon_item);
                    }
                    Vapor.Icon(if (accordon_item.is_open) .chevron_down else .chevron_up)
                        .font(12, 700, .palette(.text_color))
                        .end();
                });
            });
            Box()
                .height(.grow)
                .width(.percent(100))
                .padding(.horizontal(12))
                .ref(&accordon_item.binded)
                .scroll(.{ .x = .hidden, .y = .hidden })
                .children({
                if (accordon_item.content) |content| {
                    content(accordon_item);
                }
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
        .direction(.column)
        .spacing(8)
        .children({
        for (accordion.items) |*item| {
            item.render();
        }
    });
}
