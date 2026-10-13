const Vapor = @import("vapor");
const Box = Vapor.Box;
const Text = Vapor.Text;
const DateTime = Vapor.DateTime;
const TextFmt = Vapor.TextFmt;
const Details = @import("Login.zig").Details;
const user_count: u32 = 10;

pub fn render(details: *const Details) void {
    Box()
        .width(.percent(22))
        .height(.percent(60))
        .pos(.relative)
        .scroll(.none())
        .direction(.column)
        .layout(.top_center)
        .border(.round(.transparent, .all(16)))
        .fontFamily("IBM Plex Mono,monospace")
        // .newShadow(Vapor.Types.NewShadow.init()
        //     .dropSpread(0, 4, 12, 6, .transparentizeHex(.black, 0.1)))
        .children({
        Box()
            .pos(.tl(.px(-6), .percent(5), .absolute))
            .inlineStyle("border: none; border-top: 12px dotted white;", .{})
            .zIndex(100)
            .width(.percent(90))
            .children({});
        Box()
            .pos(.bl(.px(-6), .percent(5), .absolute))
            .inlineStyle("border: none; border-top: 12px dotted white;", .{})
            .zIndex(100)
            .width(.percent(90))
            .children({});
        Box()
            .width(.percent(100))
            .height(.percent(80))
            .border(.round(.yellow, .all(16)))
            .scroll(.none())
            .background(.yellow)
            .direction(.column)
            .children({
            Box()
                .background(.yellow)
                .layout(.right_center)
                .width(.percent(100))
                .children({
                Box()
                    .width(.percent(100))
                    .height(.px(72))
                    .layer(.line(18, 32, Vapor.Types.LinesDirection.diagonal_up, .black))
                    .children({});
                Box()
                    .pos(.tr(.px(1), .percent(60), .absolute))
                    .inlineStyle("clip-path: polygon(0 0, 100% 0, calc(100% - 72px) 100%, 0 100%);", .{})
                    .width(.percent(60))
                    .background(.yellow)
                    .height(.px(72))
                    .children({});
            });
            Box()
                .pos(.tl(.percent(32), .percent(0), .absolute))
                .width(.percent(100))
                .height(.px(120))
                .layer(.line(26, 42, Vapor.Types.LinesDirection.diagonal_up, .hex("#F5F533")))
                .children({});

            Box()
                .width(.percent(100))
                .height(.percent(100))
                .direction(.column)
                .padding(.tb(8, 8))
                .zIndex(100)
                .children({
                Box()
                    .width(.percent(60))
                    .background(.black)
                    .layout(.right_center)
                    .padding(.lr(16, 16))
                    .children({
                    Text("ACORN TICKET").font(18, 900, .white).end();
                });
                Box()
                    .padding(.all(16))
                    .width(.percent(100))
                    .layout(.x_between)
                    .children({
                    Box()
                        .padding(.tblr(8, 8, 16, 16))
                        .width(.percent(100))
                        .direction(.column)
                        .spacing(8)
                        .children({
                        TextFmt("VERSION:  {s}", .{"1.0.0"})
                            .font(16, 900, .black)
                            .whiteSpace(.pre)
                            .end();
                        TextFmt("USERNAME: {s}", .{details.username})
                            .font(16, 300, .black)
                            .whiteSpace(.pre)
                            .end();
                        TextFmt("EMAIL:    {s}", .{details.email})
                            .font(16, 300, .black)
                            .whiteSpace(.pre)
                            .end();
                        TextFmt("DATE:     {s}", .{DateTime.now().formatDate(Vapor.arena(.frame)) catch ""})
                            .font(16, 300, .black)
                            .whiteSpace(.pre)
                            .end();
                    });
                    Vapor.Svg(.{ .svg = @embedFile("qrcode.svg"), .override = true })
                        .width(.px(172))
                        .height(.px(172))
                        .end();
                });

                Box()
                    .width(.percent(100))
                    .direction(.column)
                    // .layout(.center)
                    .children({
                    Box()
                        .width(.percent(60))
                        .background(.red)
                        .layout(.right_center)
                        .padding(.lr(16, 16))
                        .children({
                        TextFmt("TICKET COUNT {d}", .{user_count}).font(18, 900, .white).end();
                    });
                    Box()
                        .padding(.horizontal(16))
                        .width(.percent(100))
                        .direction(.column)
                        .children({
                        TextFmt("CLASS:    {s}", .{"PREMIUM"})
                            .font(16, 900, .black)
                            .whiteSpace(.pre)
                            .end();
                    });
                    Box()
                        .width(.percent(100))
                        .direction(.column)
                        .layout(.center)
                        .children({
                        TextFmt("{s}", .{DateTime.now().formatTime(Vapor.arena(.frame)) catch ""})
                            .font(72, 900, .black)
                            .end();
                    });
                });
            });
        });
        Box()
            .pos(.bl(.percent(19.5), .percent(5), .absolute))
            .inlineStyle("border: none; border-top: 8px dotted white;", .{})
            .zIndex(100)
            .width(.percent(90))
            .children({});
        Box()
            .border(.round(.transparent, .all(16)))
            .background(.yellow)
            .width(.percent(100))
            .height(.percent(20))
            .padding(.t(16))
            .pos(.relative)
            .children({
            Box()
                .padding(.horizontal(16))
                .width(.percent(100))
                .direction(.column)
                .spacing(4)
                .children({
                Text("Password").font(16, 300, .black).end();
                Box()
                    .width(.percent(100))
                    .direction(.column)
                    .height(.px(38))
                    .background(.white)
                    .layout(.center)
                .padding(.all(4))
                    .children({
                    Vapor.Svg(.{ .svg = @embedFile("barcode.svg"), .override = true })
                        .width(.percent(100))
                        .height(.percent(100))
                        .end();
                    // var password = Vapor.arena(.frame).alloc(u8, details.password.len * 3) catch unreachable;
                    // for (0..details.password.len) |i| {
                    //     @memcpy(password[i * 3 ..][0..3], "●");
                    // }
                    // TextFmt("{s}", .{password})
                    //     .ellipsis(.dot)
                    //     .fontFamily("Azeret Mono, monospace")
                    //     .layout(.center)
                    //     .size(.w(.grow))
                    //     .font(24, 800, .black)
                    //     .end();
                });
            });

            Box()
                .pos(.bl(.px(0), .px(0), .absolute))
                .width(.percent(100))
                .background(.yellow)
                .height(.px(18))
                .layer(.line(18, 32, Vapor.Types.LinesDirection.diagonal_up, .black))
                .children({});
            Box()
                .pos(.bl(.px(-1), .percent(50), .absolute))
                .inlineStyle("clip-path: polygon(20px 0, 100% 0, 100% 100%, 0 100%);", .{})
                .width(.percent(50))
                .background(.yellow)
                .height(.px(20))
                .children({});
        });
    });
}

