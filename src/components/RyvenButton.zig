const Vapor = @import("vapor");
const ButtonCtx = Vapor.Button;
const Edges = Vapor.Edges;

var background: Vapor.Types.Color = .transparentize(.hex("#F5F5F5"), 0.2);
var border: Vapor.Types.Border = .round(.palette(.border_color_light), .all(12));

const blue = Vapor.Types.Color.hex("#1e3a8a");
const cyan = Vapor.Types.Color.hex("#00ffff");

// const btn_edges = Vapor.Edges.init("btn-wrap", "button")
//     // Normal state: all edges at 1px, dark color
//     .all()
//     .thickness(1)
//     .color(.palette(.border_color_light))
//     .transition(100)
//
//     // Hover: edges move outward and shrink
//     .onHover()
//     .top().offset(-2).inset(4)
//     .bottom().offset(-2).inset(4)
//     .left().offset(-2).inset(4)
//     .right().offset(-2).inset(4);

// ============================================
// SINGLE ELEMENT - Just left/right edges
// ============================================
const box_vertical = Edges.box("my-box")
    .vertical() // left + right edges only
    .thickness(2)
    .color(.hex("#3b82f6"))
    .transition(300)
    .onHover()
    .vertical().offset(-8).inset(10).color(.red);

// HTML: <div class="my-box">Content</div>

// ============================================
// SINGLE ELEMENT - Just top/bottom edges
// ============================================
const box_horizontal = Edges.box("divider")
    .horizontal() // top + bottom edges only
    .thickness(1)
    .transition(100)
    .color(.transparent)
    .onHover()
    .horizontal().offset(-4).color(.palette(.tint));

// HTML: <div class="divider">Content</div>

// ============================================
// WRAPPED - All 4 edges (original API)
// ============================================
const btn_edges = Edges.wrapped("btn-wrap", "button")
    .all()
    .thickness(1)
    .color(.hex("#0f172a"))
    .transition(300)
    .onHover()
    .all().offset(-6).inset(10).color(.hex("#3b82f6"));

// HTML: <div class="btn-wrap"><button class="button">Click</button></div>

// ============================================
// MIXED - Different settings per edge
// ============================================
const fancy = Edges.box("fancy")
    .left().thickness(3).color(.red)
    .right().thickness(3).color(.blue)
    .onHover()
    .left().offset(-10).color(.magenta)
    .right().offset(-10).color(.cyan);

pub fn new() void {
    btn_edges.build();
    box_vertical.build();
    box_horizontal.build();
    fancy.build();
}

pub fn Wrap() Vapor.Builder(.pure) {
    return Vapor.Box()
        .layout(.center)
        .background(.transparent)
        .edges("btn-wrap");
}

pub fn Button(func: anytype, args: anytype) Vapor.ButtonBuilder(.pure) {
    return ButtonCtx(func, args)
        .layout(.x_between_center)
        .spacing(8)
        .width(.fit)
        .height(.fit)
        .background(.transparent)
        .edges("button")
        .duration(100);
}
