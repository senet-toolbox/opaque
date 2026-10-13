// ============================================================================
// DragContext.zig — Global drag coordinator
// ============================================================================
//
// IMPORTANT: Vapor does not re-render on pointermove by default.
// This module calls Vapor.cycle() after updating drag state.
//
// IMPORTANT: Cached rects are allocated from persist arena so they
// survive across render cycles. They are re-cached at the start of
// every new drag operation.
//
// TRANSFER EVENTS: On cross-collection drops, the DragContext calls
// fire_transfer_fn on the destination collection handle so that
// the typed collection can emit a properly-typed TransferEvent
// with human-readable collection names.

const std = @import("std");
const Vapor = @import("vapor");
const FractionalIndex = @import("FractionalIndex.zig");

const DragContext = @This();

// ============================================================================
// Types
// ============================================================================

pub const CollectionHandle = struct {
    id: []const u8 = "",
    ptr: ?*anyopaque = null,
    direction: Direction = .vertical,
    item_rects: []CachedRect = &.{},
    container_rect: ?Rect = null,
    item_count: usize = 0,

    // vtable
    cache_rects_fn: ?*const fn (ptr: *anyopaque) void = null,
    set_gap_fn: ?*const fn (ptr: *anyopaque, index: ?usize) void = null,
    get_position_key_fn: ?*const fn (ptr: *anyopaque, index: usize, buf: []u8) []const u8 = null,
    remove_item_fn: ?*const fn (ptr: *anyopaque, index: usize) void = null,
    insert_item_fn: ?*const fn (ptr: *anyopaque, index: usize, item_ptr: *anyopaque) void = null,
    finalize_reorder_fn: ?*const fn (ptr: *anyopaque, from: usize, to: usize) void = null,
    get_item_ptr_fn: ?*const fn (ptr: *anyopaque, index: usize) ?*anyopaque = null,
    cache_container_rect_fn: ?*const fn (ptr: *anyopaque) ?Rect = null,

    /// Fire a typed transfer event on the destination collection.
    /// Parameters: (self_ptr, inserted_item_ptr, from_collection_name, from_index, to_index)
    fire_transfer_fn: ?*const fn (
        ptr: *anyopaque,
        item_ptr: *anyopaque,
        from_collection_name: []const u8,
        from_index: usize,
        to_index: usize,
    ) void = null,

    /// Get the human-readable display name for this collection.
    get_display_name_fn: ?*const fn (ptr: *anyopaque) []const u8 = null,

    pub fn cacheRects(self: *CollectionHandle) void {
        if (self.cache_rects_fn) |f| f(self.ptr.?);
        if (self.cache_container_rect_fn) |f| self.container_rect = f(self.ptr.?);
    }

    pub fn setGap(self: *CollectionHandle, index: ?usize) void {
        if (self.set_gap_fn) |f| f(self.ptr.?, index);
    }

    pub fn getDisplayName(self: *const CollectionHandle) []const u8 {
        if (self.get_display_name_fn) |f| return f(self.ptr.?);
        return self.id;
    }
};

pub const Direction = enum { vertical, horizontal };

pub const Rect = struct {
    top: f32 = 0,
    left: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,

    pub fn centerX(self: Rect) f32 {
        return self.left + self.width / 2.0;
    }
    pub fn centerY(self: Rect) f32 {
        return self.top + self.height / 2.0;
    }
    pub fn containsPoint(self: Rect, x: f32, y: f32) bool {
        return x >= self.left and x <= self.right and y >= self.top and y <= self.bottom;
    }
};

pub const CachedRect = struct {
    rect: Rect = .{},
    item_index: usize = 0,
};

pub const ActiveDrag = struct {
    source_collection_id: []const u8 = "",
    source_index: usize = 0,
    hover_collection_id: ?[]const u8 = null,
    hover_index: ?usize = null,
    pointer_x: f32 = 0,
    pointer_y: f32 = 0,
    start_x: f32 = 0,
    start_y: f32 = 0,
    item_ptr: ?*anyopaque = null,
    is_active: bool = false,
    threshold: f32 = 5,
    threshold_met: bool = false,
    initial_rect: ?Rect = null,
};

pub const DragOverlayState = struct {
    is_active: bool = false,
    x: f32 = 0,
    y: f32 = 0,
    delta_x: f32 = 0,
    delta_y: f32 = 0,
    item_ptr: ?*anyopaque = null,
    source_collection_id: []const u8 = "",
    initial_rect: ?Rect = null,
};

pub const ItemState = struct {
    is_dragging: bool = false,
    is_placeholder: bool = false,
    is_over: bool = false,
    index: usize = 0,
};

// ============================================================================
// Fields
// ============================================================================

collections: ?std.StringHashMap(*CollectionHandle) = null,
active_drag: ?ActiveDrag = null,
move_listener_id: ?u32 = null,
up_listener_id: ?u32 = null,
animations_enabled: bool = true,
overlay_state: DragOverlayState = .{},

// ============================================================================
// Lifecycle
// ============================================================================

pub fn init(self: *DragContext) void {
    self.collections = std.StringHashMap(*CollectionHandle).init(Vapor.arena(.persist));
    self.active_drag = null;
    self.overlay_state = .{};
}

// ============================================================================
// Collection Registration
// ============================================================================

pub fn registerCollection(self: *DragContext, id: []const u8, handle: *CollectionHandle) void {
    var collections = self.collections orelse return;
    const id_alloc = Vapor.arena(.persist).alloc(u8, id.len) catch unreachable;
    @memcpy(id_alloc, id);
    handle.id = id_alloc;
    collections.put(id_alloc, handle) catch unreachable;
    self.collections = collections;
}

pub fn unregisterCollection(self: *DragContext, id: []const u8) void {
    var collections = self.collections orelse return;
    _ = collections.remove(id);
    self.collections = collections;
}

pub fn getCollection(self: *DragContext, id: []const u8) ?*CollectionHandle {
    const collections = self.collections orelse return null;
    return collections.get(id);
}

// ============================================================================
// Drag Lifecycle
// ============================================================================

pub fn startDrag(
    self: *DragContext,
    source_collection_id: []const u8,
    source_index: usize,
    item_ptr: *anyopaque,
    pointer_x: f32,
    pointer_y: f32,
    initial_rect: ?Rect,
) void {
    if (self.active_drag != null) return;

    self.active_drag = .{
        .source_collection_id = source_collection_id,
        .source_index = source_index,
        .item_ptr = item_ptr,
        .start_x = pointer_x,
        .start_y = pointer_y,
        .pointer_x = pointer_x,
        .pointer_y = pointer_y,
        .is_active = false,
        .threshold_met = false,
        .initial_rect = initial_rect,
    };

    self.move_listener_id = Vapor.addGlobalListenerCtx(.pointermove, handlePointerMove, .{self}) orelse null;
    self.up_listener_id = Vapor.addGlobalListenerCtx(.pointerup, handlePointerUp, .{self}) orelse null;
}

fn handlePointerMove(self: *DragContext, evt: *Vapor.Event) void {
    var drag = self.active_drag orelse return;
    evt.preventDefault();

    const px = evt.clientX();
    const py = evt.clientY();

    if (!drag.threshold_met) {
        const dx = px - drag.start_x;
        const dy = py - drag.start_y;
        const dist = @sqrt(dx * dx + dy * dy);
        if (dist < drag.threshold) return;

        drag.threshold_met = true;
        drag.is_active = true;

        // Cache rects now that drag is confirmed
        self.cacheAllRects();
    }

    drag.pointer_x = px;
    drag.pointer_y = py;

    self.overlay_state = .{
        .is_active = true,
        .x = px,
        .y = py,
        .delta_x = px - drag.start_x,
        .delta_y = py - drag.start_y,
        .item_ptr = drag.item_ptr,
        .source_collection_id = drag.source_collection_id,
        .initial_rect = drag.initial_rect,
    };

    self.hitTest(px, py, &drag);
    self.active_drag = drag;

    // pointermove does not trigger Vapor re-render
    Vapor.cycle();
}

fn handlePointerUp(self: *DragContext, evt: *Vapor.Event) void {
    _ = evt;

    const drag = self.active_drag orelse {
        self.cleanup();
        return;
    };

    if (!drag.is_active) {
        self.cleanup();
        Vapor.cycle();
        return;
    }

    if (drag.hover_collection_id) |hover_id| {
        if (drag.hover_index) |hover_index| {
            if (std.mem.eql(u8, hover_id, drag.source_collection_id)) {
                // Reorder within same collection
                if (self.getCollection(hover_id)) |collection| {
                    if (collection.finalize_reorder_fn) |f| {
                        f(collection.ptr.?, drag.source_index, hover_index);
                    }
                }
            } else {
                // Transfer between collections.
                //
                // IMPORTANT: drag.item_ptr points into the source's items
                // array. We must insert into the destination FIRST (which
                // copies the data), then remove from source. If we remove
                // first, item_ptr becomes a dangling pointer because
                // orderedRemove shifts the array.
                const source = self.getCollection(drag.source_collection_id);
                const dest = self.getCollection(hover_id);
                if (source != null and dest != null) {
                    const src = source.?;
                    const dst = dest.?;

                    if (src.remove_item_fn) |remove_fn| {
                        if (dst.insert_item_fn) |insert_fn| {
                            if (drag.item_ptr) |item_ptr| {
                                // Get source display name before removal
                                const from_name = src.getDisplayName();

                                // Insert first (copies item data while pointer is still valid)
                                insert_fn(dst.ptr.?, hover_index, item_ptr);

                                // Now safe to remove from source
                                remove_fn(src.ptr.?, drag.source_index);

                                // Fire the transfer event on the destination collection
                                // so it can emit a typed TransferEvent. The inserted
                                // item is now at hover_index in the destination.
                                if (dst.fire_transfer_fn) |fire_fn| {
                                    // Get the newly inserted item pointer from destination
                                    if (dst.get_item_ptr_fn) |get_fn| {
                                        if (get_fn(dst.ptr.?, hover_index)) |new_item_ptr| {
                                            fire_fn(
                                                dst.ptr.?,
                                                new_item_ptr,
                                                from_name,
                                                drag.source_index,
                                                hover_index,
                                            );
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    self.cleanup();
    Vapor.cycle();
}

fn cleanup(self: *DragContext) void {
    if (self.move_listener_id) |id| {
        _ = Vapor.removeGlobalListener(.pointermove, id);
        self.move_listener_id = null;
    }
    if (self.up_listener_id) |id| {
        _ = Vapor.removeGlobalListener(.pointerup, id);
        self.up_listener_id = null;
    }

    if (self.collections) |collections| {
        var iter = collections.valueIterator();
        while (iter.next()) |handle| {
            handle.*.setGap(null);
        }
    }

    self.active_drag = null;
    self.overlay_state = .{};
}

// ============================================================================
// Hit Testing
// ============================================================================

fn cacheAllRects(self: *DragContext) void {
    const collections = self.collections orelse return;
    var iter = collections.valueIterator();
    while (iter.next()) |handle| {
        handle.*.cacheRects();
    }
}

fn hitTest(self: *DragContext, px: f32, py: f32, drag: *ActiveDrag) void {
    const collections = self.collections orelse return;

    var hit_collection: ?*CollectionHandle = null;
    var iter = collections.valueIterator();
    while (iter.next()) |handle_ptr| {
        const handle = handle_ptr.*;
        if (handle.container_rect) |cr| {
            if (cr.containsPoint(px, py)) {
                hit_collection = handle;
                break;
            }
        }
    }

    if (hit_collection) |collection| {
        drag.hover_collection_id = collection.id;
        const index = findInsertionIndex(collection, px, py);
        drag.hover_index = index;
        collection.setGap(index);

        var other_iter = collections.valueIterator();
        while (other_iter.next()) |other_ptr| {
            const other = other_ptr.*;
            if (!std.mem.eql(u8, other.id, collection.id)) {
                other.setGap(null);
            }
        }
    } else {
        drag.hover_collection_id = null;
        drag.hover_index = null;

        var clear_iter = collections.valueIterator();
        while (clear_iter.next()) |handle_ptr| {
            handle_ptr.*.setGap(null);
        }
    }
}

fn findInsertionIndex(collection: *CollectionHandle, px: f32, py: f32) usize {
    const rects = collection.item_rects;
    if (rects.len == 0) return 0;

    const is_vertical = collection.direction == .vertical;

    for (rects, 0..) |cached, i| {
        const center = if (is_vertical) cached.rect.centerY() else cached.rect.centerX();
        const pointer_pos = if (is_vertical) py else px;
        if (pointer_pos < center) return i;
    }

    return rects.len;
}

// ============================================================================
// Drag State Queries
// ============================================================================

pub fn isActive(self: *const DragContext) bool {
    if (self.active_drag) |drag| return drag.is_active;
    return false;
}

pub fn isDraggingFrom(self: *const DragContext, collection_id: []const u8) bool {
    if (self.active_drag) |drag| {
        return drag.is_active and std.mem.eql(u8, drag.source_collection_id, collection_id);
    }
    return false;
}

pub fn getDragSourceIndex(self: *const DragContext) ?usize {
    if (self.active_drag) |drag| {
        if (drag.is_active) return drag.source_index;
    }
    return null;
}

pub fn getOverlayState(self: *const DragContext) DragOverlayState {
    return self.overlay_state;
}

// ============================================================================
// DragLayer rendering
// ============================================================================

pub fn dragLayer(self: *DragContext, comptime render_fn: fn (DragOverlayState) void) void {
    render_fn(self.overlay_state);
}

pub fn dragLayerTyped(
    self: *DragContext,
    comptime T: type,
    comptime render_fn: fn (?*T, f32, f32) void,
) void {
    const state = self.overlay_state;
    if (!state.is_active) {
        Vapor.Null();
        return;
    }
    const item: ?*T = if (state.item_ptr) |ptr|
        @ptrCast(@alignCast(ptr))
    else
        null;

    var overlay_x: f32 = state.delta_x;
    var overlay_y: f32 = state.delta_y;
    if (self.overlay_state.initial_rect) |rect| {
        overlay_x = rect.left + state.delta_x;
        overlay_y = rect.top + state.delta_y;
    }
    render_fn(item, overlay_x, overlay_y);
}

