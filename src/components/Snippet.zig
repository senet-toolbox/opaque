const Vapor = @import("vapor");
const std = @import("std");
const Row = Vapor.Row;
const Text = Vapor.Text;
const Button = Vapor.Button;
const Icon = Vapor.Icon;
const Color = Vapor.Types.Color;

const Snippet = @This();
copied: bool = false,
copied_text: []const u8 = "",

pub fn init(snippet: *Snippet) void {
    snippet.* = .{};
}

fn copy(snippet: *Snippet, text: []const u8) void {
    Vapor.Clipboard.copy(text);
    snippet.copied = true;
    snippet.copied_text = text;
    Vapor.timeout("copy_snippet", 500, toggleIcon, .{snippet});
}

fn toggleIcon(snippet: *Snippet) void {
    snippet.copied = false;
    snippet.copied_text = "";
    Vapor.cycle();
}

pub fn code(snippet: *Snippet, text: []const u8) void {
    Button(copy, .{ snippet, text })
        .style(&.{
            .visual = .{
                .border = .simple(.transparentize(.black, 0.1)),
                .text_color = .black,
                .cursor = .pointer,
                .background = .palette(.background),
                .shadow = .card(.transparentizeHex(.palette(.tint), 0.2)),
            },
            .padding = .all(8),
            .size = .square_percent(100),
            .child_gap = 16,
            .layout = .flex,
            .interactive = .{
                .hover = .{ .text_color = .palette(.tint), .border = .simple(.palette(.tint)) },
            },
            .position = .relative,
        }).children({
        Text(text)
            .font(14, null, null)
            .ellipsis(.dot)
            .fontFamily("Azeret Mono, monospace")
            .layout(.center)
            .size(.w(.grow))
            .end();
        Row().style(&.{
            // .position = .{ .type = .absolute, .right = .px(8), .top = .px(8) },
            .size = .square_px(22),
            .transition = .{ .duration = 100 },
            .visual = .{
                .border_radius = .all(4),
                .background = .transparent,
                .cursor = .pointer,
            },
            .layout = .center,
        }).children({
            if (snippet.copied and std.mem.eql(u8, text, snippet.copied_text)) {
                Icon(.check).style(&.{
                    .visual = .{ .font_size = 16 },
                }).end();
            } else {
                Icon(.clipboard).style(&.{
                    .visual = .{ .font_size = 16 }, // we need to fix this to make sure it does not repalce the class of the text below
                    // setting it to 16 results in the Text below being overwritten
                }).end();
            }
        });
    });
}
