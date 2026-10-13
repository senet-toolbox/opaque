const Vapor = @import("vapor");
const Box = Vapor.Box;
const Text = Vapor.Text;

pub fn render() void {
    Box()
        .width(.percent(100))
        .height(.percent(100))
        .direction(.column)
        .layout(.top_center)
        .children({
        Text("Profile").font(72, 700, .palette(.text_color)).end();
    });
}
