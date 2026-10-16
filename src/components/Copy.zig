const Vapor = @import("vapor");
const std = @import("std");

var copies: std.AutoHashMap(u32, bool) = undefined;

pub fn new() void {
    copies = .init(Vapor.persist.arena());
}

pub fn snippet(text: []const u8) void {
    const hash = Vapor.utils.hashKey(text);
    const copied: *bool = copies.getPtr(hash) orelse blk: {
        copies.put(hash, false) catch |err| {
            std.log.err("{any}", .{err});
            return;
        };
        break :blk copies.getPtr(hash) orelse unreachable;
    };
    Vapor.Button(copy, .{ text, copied })
        .layout(.x_between_center)
        .padding(.all(16))
        .background(.palette(.background))
        .radius(.all(4))
        .shadow(Vapor.Types.Shadow.init().dropSpread(0, 0, 2, 4, .transparentize(.black, 0.05)))
        .hover(.{ .text_color = .palette(.tint) })
        .children({
        Vapor.Text(text)
            .fontSize(16)
            .fontWeight(400)
            .fontFamily("IBM Plex Mono,monospace")
            .end();
        if (copied.*) {
            Vapor.Icon(.check)
                .fontSize(14)
                .end();
        } else {
            Vapor.Icon(.clipboard)
                .fontSize(14)
                .end();
        }
    });
}

fn copy(text: []const u8, copied_ptr: *bool) void {
    Vapor.Clipboard.copy(text);
    copied_ptr.* = true;
    Vapor.timeout("copy_btn_editor", 500, toggleIcon, .{copied_ptr});
}

fn toggleIcon(copied_ptr: *bool) void {
    copied_ptr.* = false;
    Vapor.cycle();
}
