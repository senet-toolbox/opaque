const std = @import("std");
const Vapor = @import("vapor");

const FileUpload = @This();
reader: Vapor.FileReader = undefined,
image_src: []const u8 = "",

fn upload(file_upload: *FileUpload, evt: *Vapor.Event) void {
    std.log.info("Upload", .{});
    file_upload.reader = .init(evt);

    const info = file_upload.reader.fileInfo(0) catch |err| {
        std.log.err("Failed to get file info: {any}", .{err});
        return;
    };

    std.log.info("File: {s}", .{info.type});

    file_upload.image_src = file_upload.reader.createURLfromFile(0) catch |err| {
        std.log.err("Failed to create object URL: {any}", .{err});
        return;
    };
    std.log.info("Image URL: {s}", .{file_upload.image_src});
}

pub fn render(file_upload: *FileUpload) void {
    const is_uploaded = file_upload.image_src.len > 0;
    Vapor.Box()
        .pos(.relative)
        .width(.percent(100))
        .height(.percent(100))
        .layout(.center)
        .padding(.all(8))
        .spacing(8)
        .duration(100)
        .hover(.{
            .border = .thin(.palette(.tint)),
            .shadow = .glow(3, .transparentize(.palette(.tint), 0.2)),
            // .{
            //         .color = .transparentizeHex(.palette(.tint), 0.2),
            //         .spread = 3,
            //     },
        })
        .border(.round(if (is_uploaded) .palette(.tint) else .palette(.border_color_light), .all(12)))
        .shadow(
            .glow(if (is_uploaded) 3 else 0, if (is_uploaded) .transparentize(.palette(.tint), 0.2) else .transparent),
        )
        // .{
        //         .color = if (is_uploaded) .transparentizeHex(.palette(.tint), 0.2) else .transparent,
        //         .spread = 3,
        //     })
        .children({
        if (file_upload.image_src.len == 0) {
            Vapor.Icon(.upload).end();
            Vapor.Text("Upload").end();
        }
        Vapor.TextField(.file)
            .ariaLabel("Upload a file")
            .pos(.tl(.px(0), .px(0), .absolute))
            .width(.percent(100))
            .height(.percent(100))
            .border(.round(.transparent, .all(12)))
            .onEvent(.change, upload, .{file_upload})
            .font(16, null, .transparent)
            .end();
    });
}
