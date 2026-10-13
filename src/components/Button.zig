const Vapor = @import("vapor");

var background: Vapor.Types.Color = .transparentize(.hex("#F5F5F5"), 0.2);
var border: Vapor.Types.BorderGrouped = .round(.palette(.border_color_light), .all(12));

pub fn Button(func: anytype, args: anytype) Vapor.Builder(.pure) {
    return Vapor.Button(func, args).layout(.x_between_center)
        .spacing(8).padding(.tblr(8, 8, 10, 10))
        .width(.fit).height(.fit)
        .border(border).background(background)
        .duration(100)
        .shadow(Vapor.Types.NewShadow.init()
            .inset(0, -2, .transparentizeHex(.black, 0.2))
            .drop(0, 1, 3, .transparentizeHex(.black, 0.1)))
        .hover(.{
        .color_mix = .darken(.background_color, null, 0.05),
        .transform = .scaleDecimal(1.01),
        .new_shadow = Vapor.Types.NewShadow.init()
            .inset(0, -2, .transparentizeHex(.black, 0))
            .drop(0, 1, 3, .transparentizeHex(.black, 0)),
    });
}
