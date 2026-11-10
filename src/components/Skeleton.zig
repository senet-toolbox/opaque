//! Shapes where content will be while it loads, so the page keeps its
//! layout and shows that something is on its way.
//!
//!   Skeleton.render(.{ .width = .px(120), .height = 16 });
//!   Skeleton.text(3);    // three lines of text, the last one shorter
//!   Skeleton.circle(40); // an avatar
//!
//! They pulse, unless the system asks for less motion. Screen readers skip
//! them; mark the region that is loading with `aria-busy` instead.

const Vapor = @import("vapor");
const Box = Vapor.Box;
const Stack = Vapor.Stack;

pub const Options = struct {
    width: Vapor.Types.Sizing = .percent(100),
    /// In pixels.
    height: f32 = 16,
    radius: u16 = 6,
};

/// A faint wash of the text colour: it shows in light and dark themes.
pub var color: Vapor.Types.Color = .transparentize(.palette(.text_color), 0.12);

const pulse = Vapor.Animation.init("opaque-skeleton-pulse")
    .prop(.opacity, 1, 0.45)
    .duration(900)
    .easing(.easeInOut)
    .dir(.alternate)
    .infinite();

/// Registers the pulse; once, at startup (Opaque.new does it).
pub fn new() void {
    pulse.build();
    Vapor.injectCSS(
        \\@media (prefers-reduced-motion: reduce) { [data-skeleton] { animation: none !important; } }
    );
}

pub fn render(options: Options) void {
    Box()
        // An attribute, not a class: a class names one style for every
        // skeleton, and theirs differ.
        .attribute("data-skeleton", "true")
        .ariaHidden(true)
        .width(options.width)
        .height(.px(options.height))
        .background(color)
        .radius(.all(options.radius))
        .animation("opaque-skeleton-pulse")
        .inlineStyle("flex-shrink: 0;", .{})
        .children({});
}

/// `lines` lines of text, the last one shorter, as a paragraph ends.
pub fn text(lines: usize) void {
    Stack()
        .ariaHidden(true)
        .width(.percent(100))
        .spacing(8)
        .children({
        for (0..lines) |i| {
            render(.{
                .width = .percent(if (i + 1 == lines and lines > 1) 60 else 100),
                .height = 12,
                .radius = 4,
            });
        }
    });
}

/// A circle `diameter` pixels across: where an avatar will be.
pub fn circle(diameter: f32) void {
    render(.{
        .width = .px(diameter),
        .height = diameter,
        .radius = @intFromFloat(diameter / 2),
    });
}
