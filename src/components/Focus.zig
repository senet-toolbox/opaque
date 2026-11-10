//! The ring a control shows while it has keyboard focus. Every component
//! uses this one, so a page reads the same way as you tab through it.
//!
//!   Focus.color = .palette(.tint);   // before the first render
//!
//! It shows on Tab, not on a mouse click (CSS `:focus-visible`).

const Vapor = @import("vapor");

/// The ring's colour. The text colour by default: it stands out on the
/// page's background in light and dark themes alike.
pub var color: Vapor.Types.Color = .palette(.text_color);

/// 2px, 2px out from the control.
pub fn ring() Vapor.Types.Visual {
    return .ring(color);
}

/// 2px, just inside the control's edge: for one that fills a list, a menu
/// or a table cell, where a ring outside would be cut off or cover its
/// neighbours.
pub fn inset() Vapor.Types.Visual {
    var visual = Vapor.Types.Visual.ring(color);
    visual.outline_offset = -2;
    return visual;
}
