// ============================================================================
// Sortable.zig — Drag-and-drop sortable collections for Vapor
// ============================================================================
//
// Top-level module that re-exports the sortable collection system.
//
// Usage:
//   const Sortable = @import("Sortable.zig");
//
//   var drag_ctx: Sortable.DragContext(u32) = .{};
//   var backlog = Sortable.Collection(Card, .{ .id_field = "id" });
//
// Or if added to Opaque:
//   const Sortable = Opaque.Sortable;

const std = @import("std");
const Vapor = @import("vapor");

pub const DragContext = @import("DragContext.zig").DragContext;
pub const FractionalIndex = @import("FractionalIndex.zig");

const SortableCollection = @import("SortableCollection.zig");
pub const Collection = SortableCollection.Collection;
pub const CollectionConfig = SortableCollection.CollectionConfig;
pub const ReorderEvent = SortableCollection.ReorderEvent;
pub const TransferEvent = SortableCollection.TransferEvent;

pub const ItemState = @import("DragContext.zig").ItemState;
pub const Direction = @import("DragContext.zig").Direction;
pub fn DragOverlayState(comptime IdType: type) type {
    return DragContext(IdType).DragOverlayState;
}
pub const Rect = @import("DragContext.zig").Rect;

// ============================================================================
// Global Initialization
// ============================================================================

/// Call once at app startup (like Field.new(), Tooltip.new(), etc.)
pub fn new() void {
    // Currently no global state needed beyond what DragContext manages.
    // This exists for consistency with the Opaque component pattern
    // and as a hook for future global state (e.g., shared animations).
}
