const std = @import("std");
const Vapor = @import("vapor");
const Box = Vapor.Static.Box;
const Hooks = Vapor.Static.Hooks;
const Text = Vapor.Static.Text;
const Button = Vapor.Static.Button;
const TextFmt = Vapor.Static.TextFmt;
const Icon = Vapor.Static.Icon;
const Custom = @import("../components/Custom.zig");
const DocNavbar = @import("../components/DocNavbar.zig");
const ListItem = Vapor.ListItem;
const List = Vapor.List;
const CtxButton = Vapor.Button;

pub var boxes: []BoxNumber = undefined;
// var bounds: Vapor.lib.Bounds = undefined;
const BoxNumber = struct {
    id: []const u8,
    number: usize,
    bounds: Vapor.lib.Bounds = .{},
    active: bool = true,
    link: []const u8 = "",
};

pub fn initBoxes() void {
    boxes = Vapor.arena(.view).alloc(BoxNumber, 0) catch unreachable;
}

pub fn reinitBoxes() void {
    const ids = Vapor.queryComponentIds(.Intersection) catch unreachable;
    var count: usize = 0;
    for (ids) |id| {
        if (std.mem.startsWith(u8, id, "Inte_")) continue;
        count += 1;
    }
    boxes = Vapor.arena(.view).alloc(BoxNumber, count) catch unreachable;
    for (ids, 0..) |id, i| {
        if (std.mem.startsWith(u8, id, "Inte_")) continue;
        const bounds = Vapor.getComponentBounds(id) orelse unreachable;
        const box_id = std.fmt.allocPrint(Vapor.arena(.view), "box-{d}", .{i}) catch unreachable;
        boxes[i] = .{ .id = box_id, .number = i, .bounds = bounds };
    }
}

pub fn deinitBoxes() void {
    Vapor.arena(.view).free(boxes);
}

pub fn new(default_text: []const u8) type {
    return struct {
        const Self = @This();
        var copied: bool = false;
        content_text: []const u8 = default_text,

        pub fn init(_: *Self) void {}

        fn toggleIcon(_: void) void {
            copied = false;
            // Vapor.cycle();
        }

        fn copy(self: *Self) void {
            Vapor.Clipboard.copy(self.content_text);
            copied = true;
            // Vapor.cycle();
            Vapor.registerCtxTimeout("markdown_copy", 1000, toggleIcon, .{{}});
        }

        pub fn content(self: *Self, render: *const fn () void) void {

            // Hooks(.{ .mounted = mount })({
            Box().style(&.{
                .size = .hw(.percent(100), .percent(100)),
                .layout = .top_center,
                .padding = .horizontal(12),
                .visual = .{
                    .layer = .grid(32, 1, .transparentize(.palette(.grid_color), 0.9)),
                    .border = .{
                        .thickness = .horizontal(1),
                        .color = .palette(.border_color_light),
                    },
                },
                .position = .relative,
            }).children({
                List().layout(.{}).pos(.tr(.px(0), .px(0), .absolute)).children({
                    for (boxes) |box| {
                        const color: Vapor.Types.Color = if (box.active) .palette(.tint) else .palette(.border_color_light);
                        ListItem().id(box.id)
                            // .pos(.tl(.px(box.bounds.top + (box.bounds.height - 56) / 2), .px(box.bounds.left - 56 - 12), .absolute)).zIndex(999)
                            // .pos(.tr(.px(box.bounds.top + (box.bounds.height - 56) / 2 - 90), .px(-56), .absolute)).zIndex(999)
                            .pos(.tr(.px(box.bounds.top - 80), .px(-56), .absolute)).zIndex(999)
                            .width(.px(56))
                            .height(.px(56))
                            .border(.thin(color))
                            .layout(.center)
                            .children({
                            TextFmt("{d}", .{box.number}).font(18, 300, color).end();
                        });
                    }
                });

                Box().style(&.{
                    .size = .w(.percent(100)),
                    .child_gap = 16,
                    .direction = .column,
                    .layout = .{ .x = .start, .y = .start },
                }).children({
                    Box().style(&.{
                        .size = .w(.percent(100)),
                        .layout = .x_between_center,
                    }).children({
                        Text("Getting Started").style(&.{
                            .visual = .font(16, 600, null),
                            .font_family = "IBM Plex Sans",
                            .size = .w(.grow),
                        }).end();
                        CtxButton(copy, .{self})
                            .ariaLabel("copy-markdown")
                            .style(&.{
                                .visual = .{ .background = .transparent, .cursor = .pointer },
                                .size = .w(.fit),
                                .child_gap = 12,
                                .padding = .vertical(8),
                                .layout = .right_center,
                                .interactive = .{ .hover = .{ .text_color = .palette(.tint) } },
                            }).children({
                            if (copied) {
                                Icon(.check).style(&.{
                                    .visual = .{ .font_size = 16 },
                                }).end();
                            } else {
                                Icon(.clipboard).style(&.{
                                    .visual = .{ .font_size = 16 },
                                }).end();
                            }
                        });
                    });
                    Box().style(&.{
                        .child_gap = 4,
                        .direction = .column,
                        .size = .hw(.percent(100), .percent(100)),
                        .layout = .{},
                    }).children({
                        render();
                    });
                });
            });
            // });
        }
    };
}
