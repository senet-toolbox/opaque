// ============================================================================
// SortableCollection.zig — Generic sortable collection with drag-and-drop
// ============================================================================
//
// CRITICAL DESIGN NOTES
// =====================
//
// 1. POSITIONAL SLOTS: Vapor UUIDs are position-based. Slots (Binded refs)
//    are pinned to DOM positions and NEVER reorder with items.
//
// 2. PERSIST-ARENA RECTS: Cached bounding rects must survive across render
//    cycles (frame arena gets freed). We allocate from persist arena and
//    free/reallocate on each cacheRects() call.
//
// 3. SAFE FRACTIONAL INDEXING: After reorders, position keys on items may
//    not be in sorted order. FractionalIndex.between() handles this by
//    falling back to generateAfter() when before >= after.
//
// 4. TRANSFER API: transferTo() moves an item between collections
//    programmatically (e.g. from button clicks). It removes from source,
//    appends to destination, and fires the on_transfer callback on
//    the destination collection.
//
// 5. TYPED HANDLES: Collection identity is a comptime-supplied IdType
//    (typically an enum). The DragContext, hover state, and TransferEvent
//    all use IdType directly, so callers never have to compare strings
//    or maintain id ↔ string conversions.

const std = @import("std");
const is_wasm = @import("builtin").target.cpu.arch == .wasm32;
const Vapor = @import("vapor");
const drag_context = @import("DragContext.zig");

pub const DragContext = drag_context.DragContext;
pub const Direction = drag_context.Direction;

const FractionalIndex = @import("FractionalIndex.zig");
const VirtualList = @import("tables/Virtualize.zig").VirtualList;

// ============================================================================
// Event Types (parameterized on IdType)
// ============================================================================

pub fn ReorderEvent(comptime T: type) type {
    return struct {
        item: *T,
        from_index: usize,
        to_index: usize,
        position: []const u8,
        rollback_fn: ?*const fn () void = null,

        pub fn rollback(self: @This()) void {
            if (self.rollback_fn) |f| f();
        }
    };
}

pub fn TransferEvent(comptime T: type, comptime IdType: type) type {
    return struct {
        item: *T,
        from_collection: IdType,
        to_collection: IdType,
        from_index: usize,
        to_index: usize,
        position: []const u8,
        rollback_fn: ?*const fn () void = null,

        pub fn rollback(self: @This()) void {
            if (self.rollback_fn) |f| f();
        }
    };
}

// ============================================================================
// Configuration
// ============================================================================

pub fn CollectionConfig(comptime T: type, comptime IdType: type) type {
    return struct {
        id_field: []const u8 = "id",
        direction: Direction = .vertical,
        on_reorder: ?*const fn (ReorderEvent(T)) void = null,
        on_transfer: ?*const fn (TransferEvent(T, IdType)) void = null,
        animate_gap: bool = true,
        allow_drag_out: bool = true,
        allow_drop_in: bool = true,
        accepts: ?*const fn (item: *const T) bool = null,
        handle_class: ?[]const u8 = null,
        show_drag_overlay: bool = true,
        drag_overlay_render: ?*const fn (item: *T, delta_x: f32, delta_y: f32) void = null,
        gap_render: ?*const fn (dir: Direction) void = null,
        no_items_render: ?*const fn (count: usize, dir: Direction) void = null,
        height: f32 = 172,
        gap_height: f32 = 60,
        item_spacing: f32 = 8, // ← new: pixels between items

        // Pixels the pointer must move before drag activates.
        // Clicks on buttons/links inside items will flow through normally
        // because they don't move the pointer.
        drag_activation_distance: f32 = 5,

        // Optional predicate. Return false to prevent drag from
        // starting on this pointerdown (e.g. when target is a button).
        // Receives the event so you can inspect target/tag/role.
        should_start_drag: ?*const fn (evt: *Vapor.Event) bool = null,

        // Optional human-readable name function for logs/debugging only.
        // When IdType is an enum, you can pass `@tagName` directly.
        // This is NEVER used for identity comparisons — those use IdType.
        name_of: ?*const fn (id: IdType) []const u8 = null,

        // Auto-scroll during drag
        auto_scroll: bool = true,
        auto_scroll_zone: f32 = 80,
        auto_scroll_max_speed: f32 = 14,
        auto_scroll_min_speed: f32 = 2,
    };
}

// ============================================================================
// Per-position tracking (pinned to DOM positions, never reorders)
// ============================================================================

fn ItemSlot(comptime T: type) type {
    _ = T;
    return struct {
        binded: Vapor.Element = .{},
    };
}

// ============================================================================
// Collection
// ============================================================================

/// A sortable collection of items of type `T`, identified by `IdType`,
/// configured by `config`.
///
/// Typical usage:
///
///   const ColumnId = enum { backlog, todo, in_progress, done };
///   const Ctx = SortableCollection.DragContext(ColumnId);
///   const TaskCol = SortableCollection.Collection(Task, ColumnId, .{
///       .on_transfer = handleTransfer,
///   });
///
///   var ctx: Ctx = undefined;
///   ctx.init();
///
///   var backlog: TaskCol = undefined;
///   backlog.init(&ctx, .backlog, initial_tasks);
///
/// `IdType` must be comparable with `==` (any enum, integer, or other
/// equatable type works). It must match the IdType of the DragContext
/// the collection is registered with.
pub fn Collection(
    comptime T: type,
    comptime IdType: type,
    comptime config: CollectionConfig(T, IdType),
) type {
    comptime {
        if (!@hasField(T, "id")) {
            @compileError("Table requires a field named 'id'");
        }
    }

    const TaskIdType = comptime blk: {
        const fields = @typeInfo(T).@"struct".fields;
        for (fields) |field| {
            if (std.mem.eql(u8, field.name, "id")) {
                break :blk field.type;
            }
        }
        unreachable;
    };

    return struct {
        const Self = @This();
        pub const Ctx = DragContext(IdType);
        pub const Handle = Ctx.CollectionHandle;
        total_window_items: usize = 0,

        total_height: f32 = 0,

        items: Vapor.ArrayArena(T) = undefined,
        slots: Vapor.ArrayArena(ItemSlot(T)) = undefined,
        drag_ctx: ?*Ctx = null,
        handle: Handle = .{},
        container_binded: Vapor.Element = .{},

        /// The typed identifier for this collection. Set at init time and
        /// used as the key in DragContext, hover state, and TransferEvent.
        id: IdType = undefined,
        registered: bool = false,
        initialized: bool = false,

        gap_index: ?usize = null,

        /// Optional runtime filter. When set, only items for which this
        /// function returns `true` are rendered. Filtered-out items remain
        /// in the collection's data but are hidden from the UI and excluded
        /// from drag hit-testing rects. Set via `setFilter()`, clear with
        /// `clearFilter()`.
        filter_fn: ?ErasedFilterCallback = null,
        tranfer_fn: ?ErasedTransferCallback = null,

        /// Persist-allocated rect cache. Freed and reallocated on each
        /// cacheRects() call so it survives across render cycles.
        cached_rects: ?[]drag_context.CachedRect = null,

        // Pending drag state — tracks pointerdown until we know
        // whether this is a click or a real drag.
        pending_drag: ?PendingDrag = null,

        captured_slot_index: ?usize = null,
        captured_pointer_id: u32 = 0,

        container_height: f32 = 0,

        visible_count: usize = 0,
        buffer_zone: usize = 0,
        current_window_start: usize = 0,

        // Tracking for render logic
        prev_scroll_top: f32 = 0,
        initial_index: usize = 0,

        // Auto-scroll state
        auto_scroll_active: bool = false,
        auto_scroll_speed: f32 = 0,
        auto_scroll_raf_id: u32 = 0,

        const PendingDrag = struct {
            real_index: usize,
            local_index: usize,
            start_x: f32,
            start_y: f32,
            initial_rect: ?drag_context.Rect,
        };

        // ====================================================================
        // Initialization
        // ====================================================================

        /// Initialize with a shared drag context, a typed id, and seed items.
        /// `id` must be unique across all collections registered with the
        /// same DragContext.
        pub fn init(self: *Self, ctx: *Ctx, id: IdType, initial_items: []const T) void {
            self.items = Vapor.persist.array(T);
            self.slots = Vapor.persist.array(ItemSlot(T));
            self.drag_ctx = ctx;
            self.id = id;
            self.initialized = true;

            for (initial_items) |item| {
                self.items.append(item);
            }

            self.container_height = config.height * 3;
            self.visible_count = @as(usize, @intFromFloat(@ceil(self.container_height / config.height)));
            self.buffer_zone = self.visible_count;
            self.current_window_start = 0;
            self.initial_index = 0;
            self.syncCapacity(); // ← does the rest

            self.handle = .{
                .id = id,
                .ptr = @ptrCast(self),
                .direction = config.direction,
                .item_count = self.items.items.len,
                .cache_rects_fn = cacheRectsErased,
                .set_gap_fn = setGapErased,
                .get_position_key_fn = getPositionKeyErased,
                .remove_item_fn = removeItemErased,
                .insert_item_fn = insertItemErased,
                .finalize_reorder_fn = finalizeReorderErased,
                .get_item_ptr_fn = getItemPtrErased,
                .cache_container_rect_fn = cacheContainerRectErased,
                .fire_transfer_fn = fireTransferErased,
                .auto_scroll_check_fn = checkAutoScrollErased,
            };
        }

        // ====================================================================
        // Display Name (debug/logging only — never used for identity)
        // ====================================================================

        /// Returns a human-readable name for this collection. Uses the
        /// configured `name_of` function if provided. Otherwise, when
        /// IdType is an enum, returns `@tagName(self.id)`. Otherwise
        /// returns "<unnamed>".
        ///
        /// This is for logs and debugging only. All identity comparisons
        /// use the typed `id` directly.
        pub fn getDisplayName(self: *const Self) []const u8 {
            if (config.name_of) |f| return f(self.id);
            if (@typeInfo(IdType) == .@"enum") return @tagName(self.id);
            return "<unnamed>";
        }

        // ====================================================================
        // Item Management
        // ====================================================================

        /// Recompute total_height, total_window_items, and slot count.
        /// Call after any mutation that changes items.len.
        pub fn syncCapacity(self: *Self) void {
            const n = self.items.items.len;
            const stride: f32 = config.height + config.item_spacing;
            self.total_height = @as(f32, @floatFromInt(n)) * stride;

            const number_of_items_fit = @as(usize, @intFromFloat(@ceil(self.container_height / stride)));
            const ideal_buffer = number_of_items_fit * 3;
            const max_buffer: usize = 100;
            const new_window = @min(n, @min(ideal_buffer, max_buffer));

            // Grow slots if needed (never shrink — slots are positional and cheap)
            while (self.slots.items.len < new_window) {
                self.slots.append(.{});
            }

            self.total_window_items = new_window;

            // Clamp window_start so window stays in bounds
            if (n == 0) {
                self.current_window_start = 0;
            } else if (self.current_window_start + new_window > n) {
                self.current_window_start = n -| new_window; // saturating sub
            }

            self.handle.item_count = n;
        }

        fn visibleHeight(self: *const Self) f32 {
            const stride = config.height + config.item_spacing;
            if (self.visibleCount() == 0) return 100;
            return @as(f32, @floatFromInt(self.visibleCount())) * stride;
        }

        fn visibleIndexBefore(self: *const Self, raw_index: usize) usize {
            var local_count: usize = 0;
            const ctx = self.drag_ctx;
            const drag_source = if (ctx) |c|
                if (c.isDraggingFrom(self.id)) c.getDragSourceIndex() else null
            else
                null;

            for (self.items.items[0..@min(raw_index, self.items.items.len)], 0..) |*item, i| {
                const is_dragging = (drag_source orelse std.math.maxInt(usize)) == i;
                if (is_dragging or self.passesFilter(item)) local_count += 1;
            }
            return local_count;
        }

        pub fn append(self: *Self, item: T) !void {
            self.items.append(item);
            self.syncCapacity();
        }

        pub fn remove(self: *Self, index: usize) T {
            const item = self.items.orderedRemove(index);
            self.syncCapacity();
            return item;
        }

        pub fn insertAt(self: *Self, index: usize, item: T) void {
            self.items.insert(index, item);
            self.syncCapacity();
        }
        /// Remove an item by pointer. Searches for the item whose address
        /// matches `item_ptr` within the items slice. Returns the removed
        /// item or null if not found.
        pub fn removeByPtr(self: *Self, item_ptr: *const T) ?T {
            const index = self.indexOfPtr(item_ptr) orelse return null;
            return self.remove(index);
        }

        pub fn count(self: *const Self) usize {
            return self.items.items.len;
        }

        pub fn getItems(self: *const Self) []T {
            return self.items.items;
        }

        /// Find the index of an item by pointer identity. Compares the
        /// address of `item_ptr` against each element in the items slice.
        pub fn indexOfPtr(self: *const Self, item_ptr: *const T) ?usize {
            const items = self.items.items;
            for (items, 0..) |*item, i| {
                if (item == item_ptr) return i;
            }
            return null;
        }

        /// Find the index of an item by its id field value.
        pub fn indexOfId(self: *const Self, id: anytype) ?usize {
            const items = self.items.items;
            for (items, 0..) |*item, i| {
                if (@field(item, config.id_field) == id) return i;
            }
            return null;
        }

        fn ensureSlots(self: *Self, n: usize) void {
            _ = self;
            _ = n;
            // self.slots.ensureCapacity(n);
            // while (self.slots.items.len < n) {
            //     self.slots.appendAssumeCapacity(.{});
            // }
        }

        // ====================================================================
        // Filtering
        // ====================================================================

        /// Set a runtime filter function. Only items for which `f` returns
        /// true will be rendered and participate in drag hit-testing.
        /// The filter does NOT remove items from the collection — it only
        /// controls visibility.
        pub const ErasedFilterCallback = struct {
            ctx: *anyopaque,
            callFn: *const fn (*anyopaque, *const T) bool,
            destroyFn: *const fn (*anyopaque) void,

            pub fn call(self: *const ErasedFilterCallback, evt: *const T) bool {
                return self.callFn(self.ctx, evt);
            }

            pub fn make(cb: anytype, args: anytype) !ErasedFilterCallback {
                const Args = @TypeOf(args);

                const Closure = struct {
                    arguments: Args,

                    fn run(ptr: *anyopaque, task: *const T) bool {
                        const self: *@This() = @ptrCast(@alignCast(ptr));
                        return @call(.auto, cb, self.arguments ++ .{task});
                    }

                    fn destroy(ptr: *anyopaque) void {
                        const self: *@This() = @ptrCast(@alignCast(ptr));
                        Vapor.persist.arena().destroy(self);
                    }
                };

                const closure = try Vapor.persist.arena().create(Closure);
                closure.* = .{ .arguments = args };

                return .{
                    .ctx = @ptrCast(closure),
                    .callFn = Closure.run,
                    .destroyFn = Closure.destroy,
                };
            }
        };

        pub fn setFilter(self: *Self, callback: anytype, args: anytype) void {
            if (self.filter_fn) |old| old.destroyFn(old.ctx);

            const erased = ErasedFilterCallback.make(callback, args) catch |err| {
                std.log.err("Failed to create erased callback: {}", .{err});
                return;
            };
            self.filter_fn = erased;
        }

        pub fn clearFilter(self: *Self) void {
            if (self.filter_fn) |old| old.destroyFn(old.ctx);
            self.filter_fn = null;
        }

        /// Returns true if the item at the given index passes the current
        /// filter (or if no filter is set).
        fn passesFilter(self: *const Self, item: *const T) bool {
            if (self.filter_fn) |f| return f.call(item);
            if (self.drag_ctx) |ctx| {
                if (ctx.shared_filter) |f| {
                    return f.call_fn(f.ctx, @ptrCast(item));
                }
            }
            return true;
        }

        pub const ErasedTransferCallback = struct {
            ctx: *anyopaque,
            callFn: *const fn (*anyopaque, TransferEvent(T, IdType)) void,

            pub fn call(self: *const ErasedTransferCallback, evt: TransferEvent(T, IdType)) void {
                return self.callFn(self.ctx, evt);
            }

            pub fn make(cb: anytype, args: anytype) !ErasedTransferCallback {
                const Args = @TypeOf(args);

                const Closure = struct {
                    arguments: Args,

                    fn run(ptr: *anyopaque, evt: TransferEvent(T, IdType)) void {
                        const self: *@This() = @ptrCast(@alignCast(ptr));
                        @call(.auto, cb, self.arguments ++ .{evt});
                    }
                };

                const closure = try Vapor.persist.arena().create(Closure);
                closure.* = .{ .arguments = args };

                return .{
                    .ctx = @ptrCast(closure),
                    .callFn = Closure.run,
                };
            }
        };

        pub fn onTransfer(self: *Self, callback: anytype, args: anytype) void {
            const erased = ErasedTransferCallback.make(callback, args) catch |err| {
                std.log.err("Failed to create erased callback: {}", .{err});
                return;
            };
            self.tranfer_fn = erased;
        }

        // pub fn onReorder(self: *Self, callback: anytype, args: anytype) void {}

        /// Count only items that pass the current filter.
        pub fn visibleCount(self: *const Self) usize {
            const has_filter = self.filter_fn != null or
                (if (self.drag_ctx) |ctx| ctx.shared_filter != null else false);
            if (!has_filter) return self.items.items.len;
            var n: usize = 0;
            for (self.items.items) |*item| {
                if (self.passesFilter(item)) n += 1;
            }
            return n;
        }

        // ====================================================================
        // Cross-collection Transfer (programmatic)
        // ====================================================================

        /// Transfer an item from this collection to another collection.
        /// The item is identified by pointer. It is removed from `self`
        /// and appended to `dest`. Fires the on_transfer callback on the
        /// destination collection.
        ///
        /// Both collections must share the same IdType (enforced by the
        /// type system: both are `Collection(T, IdType, ...)`).
        ///
        /// Usage (e.g. from a "move right" button handler):
        ///   from_col.transferTo(&to_col, task);
        pub fn transferTo(self: *Self, dest: *Self, item_ptr: *T) void {
            self.transferToAt(dest, item_ptr, dest.count());
        }

        /// Transfer an item to a specific index in the destination collection.
        pub fn transferToAt(self: *Self, dest: *Self, item_ptr: *T, dest_index: usize) void {
            const from_index = self.indexOfPtr(item_ptr) orelse return;
            const item_copy = item_ptr.*;

            // Remove from source first (we have a copy)
            _ = self.remove(from_index);

            // Clamp dest_index to destination length
            const clamped_index = @min(dest_index, dest.count());

            // Insert into destination
            dest.insertAt(clamped_index, item_copy);

            // Compute a position key for the new location
            var key_buf: [64]u8 = undefined;
            const position_key = dest.getPositionKey(clamped_index, &key_buf);
            const persisted_key = Vapor.arena(.persist).alloc(u8, position_key.len) catch unreachable;
            @memcpy(persisted_key, position_key);

            // Update position field if present
            if (@hasField(T, "position")) {
                @field(&dest.items.items[clamped_index], "position") = persisted_key;
            }

            // Fire transfer callback
            if (self.tranfer_fn) |f| {
                f.call(.{
                    .item = &dest.items.items[clamped_index],
                    .from_collection = self.id,
                    .to_collection = dest.id,
                    .from_index = from_index,
                    .to_index = clamped_index,
                    .position = persisted_key,
                    .rollback_fn = null,
                });
            }
            // if (config.on_transfer) |callback| {
            //     callback(.{
            //         .item = &dest.items.items[clamped_index],
            //         .from_collection = self.id,
            //         .to_collection = dest.id,
            //         .from_index = from_index,
            //         .to_index = clamped_index,
            //         .position = persisted_key,
            //         .rollback_fn = null,
            //     });
            // }
        }

        // ====================================================================
        // Fractional Index Key Generation
        // ====================================================================

        fn getPositionKey(self: *Self, index: usize, buf: []u8) []const u8 {
            const items = self.items.items;

            const before: ?[]const u8 = if (index > 0)
                getItemPosition(&items[index - 1])
            else
                null;

            const after: ?[]const u8 = if (index < items.len)
                getItemPosition(&items[index])
            else
                null;

            return FractionalIndex.between(before, after, buf);
        }

        fn getItemPosition(item: *const T) ?[]const u8 {
            if (@hasField(T, "position")) {
                return @field(item, "position");
            }
            return null;
        }

        // ====================================================================
        // Rect Caching (persist arena — survives across renders)
        // ====================================================================

        fn cacheRects(self: *Self) void {
            const slot_count = self.slots.items.len;
            const rects = Vapor.arena(.persist).alloc(
                drag_context.CachedRect,
                slot_count,
            ) catch unreachable;

            for (0..slot_count) |local_i| {
                const real_i = self.current_window_start + local_i;
                if (real_i >= self.items.items.len) {
                    rects[local_i] = .{ .item_index = real_i };
                    continue;
                }
                const slot = &self.slots.items[local_i];
                if (slot.binded.getBoundingClientRect()) |bounds| {
                    rects[local_i] = .{
                        .rect = .{
                            .top = bounds.top,
                            .left = bounds.left,
                            .right = bounds.right,
                            .bottom = bounds.bottom,
                            .width = bounds.width,
                            .height = bounds.height,
                        },

                        .item_index = real_i, // ← real index, not local
                    };
                } else {
                    rects[local_i] = .{ .item_index = real_i };
                }
            }

            self.cached_rects = rects;
            self.handle.item_rects = rects;
            self.handle.item_count = self.items.items.len; // total, not slot count
        }

        fn cacheContainerRect(self: *Self) ?drag_context.Rect {
            if (self.container_binded.getBoundingClientRect()) |bounds| {
                return .{
                    .top = bounds.top,
                    .left = bounds.left,
                    .right = bounds.right,
                    .bottom = bounds.bottom,
                    .width = bounds.width,
                    .height = bounds.height,
                };
            }
            return null;
        }

        // ====================================================================
        // Gap Management
        // ====================================================================

        fn setGap(self: *Self, index: ?usize) void {
            self.gap_index = index;
        }

        // ====================================================================
        // Reorder
        // ====================================================================

        fn finalizeReorder(self: *Self, from: usize, to: usize) void {
            if (from == to) {
                self.gap_index = null;
                return;
            }

            // Translate visual gap index → item-array destination
            const dest = if (to > from) to - 1 else to;

            if (dest == from) {
                self.gap_index = null;
                return;
            }

            // Compute position key BEFORE moving
            var key_buf: [64]u8 = undefined;
            const position_key = self.getPositionKey(dest, &key_buf);

            const persisted_key = Vapor.arena(.persist).alloc(u8, position_key.len) catch unreachable;
            @memcpy(persisted_key, position_key);

            // Reorder ONLY the items array. Slots stay pinned.
            const item = self.items.orderedRemove(from);
            self.items.insert(dest, item);

            if (@hasField(T, "position")) {
                @field(&self.items.items[dest], "position") = persisted_key;
            }

            if (config.on_reorder) |callback| {
                callback(.{
                    .item = &self.items.items[dest],
                    .from_index = from,
                    .to_index = dest,
                    .position = persisted_key,
                    .rollback_fn = null,
                });
            }

            self.gap_index = null;
        }

        // ====================================================================
        // Fire Transfer Event (called by DragContext on cross-collection drop)
        // ====================================================================

        fn fireTransfer(
            self: *Self,
            item_ptr: *T,
            from_collection_id: IdType,
            from_index: usize,
            to_index: usize,
        ) void {
            // Compute position key for the inserted item
            var key_buf: [64]u8 = undefined;
            const position_key = self.getPositionKey(to_index, &key_buf);
            const persisted_key = Vapor.arena(.persist).alloc(u8, position_key.len) catch unreachable;
            @memcpy(persisted_key, position_key);

            // Update position field
            if (@hasField(T, "position")) {
                @field(item_ptr, "position") = persisted_key;
            }

            // if (config.on_transfer) |callback| {
            //     callback(.{
            //         .item = item_ptr,
            //         .from_collection = from_collection_id,
            //         .to_collection = self.id,
            //         .from_index = from_index,
            //         .to_index = to_index,
            //         .position = persisted_key,
            //         .rollback_fn = null,
            //     });
            // }
            // Fire transfer callback
            if (self.tranfer_fn) |f| {
                f.call(.{
                    .item = item_ptr,
                    .from_collection = from_collection_id,
                    .to_collection = self.id,
                    .from_index = from_index,
                    .to_index = to_index,
                    .position = persisted_key,
                    .rollback_fn = null,
                });
            }
        }

        // ====================================================================
        // Type-erased vtable
        // ====================================================================

        fn cacheRectsErased(ptr: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.cacheRects();
        }

        fn checkAutoScrollErased(ptr: *anyopaque, px: f32, py: f32) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.checkAutoScroll(px, py);
        }

        fn cacheContainerRectErased(ptr: *anyopaque) ?drag_context.Rect {
            const self: *Self = @ptrCast(@alignCast(ptr));
            return self.cacheContainerRect();
        }

        fn setGapErased(ptr: *anyopaque, index: ?usize) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.setGap(index);
        }

        fn getPositionKeyErased(ptr: *anyopaque, index: usize, buf: []u8) []const u8 {
            const self: *Self = @ptrCast(@alignCast(ptr));
            return self.getPositionKey(index, buf);
        }

        fn removeItemErased(ptr: *anyopaque, index: usize) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            _ = self.remove(index);
        }

        fn insertItemErased(ptr: *anyopaque, index: usize, item_ptr: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const item: *T = @ptrCast(@alignCast(item_ptr));
            self.insertAt(index, item.*);
        }

        fn finalizeReorderErased(ptr: *anyopaque, from: usize, to: usize) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.finalizeReorder(from, to);
        }

        fn getItemPtrErased(ptr: *anyopaque, index: usize) ?*anyopaque {
            const self: *Self = @ptrCast(@alignCast(ptr));
            if (index >= self.items.items.len) return null;
            return @ptrCast(&self.items.items[index]);
        }

        fn fireTransferErased(
            ptr: *anyopaque,
            item_ptr: *anyopaque,
            from_collection_id: IdType,
            from_index: usize,
            to_index: usize,
        ) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const typed_item: *T = @ptrCast(@alignCast(item_ptr));
            self.fireTransfer(typed_item, from_collection_id, from_index, to_index);
        }

        // ====================================================================
        // Drag Handlers
        // ====================================================================

        fn handleItemPointerDown(self: *Self, local_index: usize, evt: *Vapor.Event) void {
            const real_index = self.current_window_start + local_index;
            _ = self.drag_ctx orelse return;

            // Filter: skip if user-supplied predicate rejects this target
            if (config.should_start_drag) |predicate| {
                if (!predicate(evt)) return;
            }

            // DO NOT capture pointer or preventDefault here.
            // Doing so would retarget the click event away from buttons
            // inside the item. We wait until movement threshold is crossed.

            const px = evt.clientX();
            const py = evt.clientY();

            var initial_rect: ?drag_context.Rect = null;
            self.ensureSlots(local_index + 1);
            if (self.slots.items[local_index].binded.getBoundingClientRect()) |bounds| {
                initial_rect = .{
                    .top = bounds.top,
                    .left = bounds.left,
                    .right = bounds.right,
                    .bottom = bounds.bottom,
                    .width = bounds.width,
                    .height = bounds.height,
                };
            }

            self.pending_drag = .{
                .real_index = real_index,
                .local_index = local_index,
                .start_x = px,
                .start_y = py,
                .initial_rect = initial_rect,
            };
        }

        fn checkAutoScroll(self: *Self, px: f32, py: f32) void {
            if (!config.auto_scroll) return;
            const ctx = self.drag_ctx orelse return;
            if (!ctx.isDragActive()) {
                self.stopAutoScroll();
                return;
            }

            const bounds = self.container_binded.getBoundingClientRect() orelse {
                self.stopAutoScroll();
                return;
            };

            // Pointer outside container's horizontal bounds → no auto-scroll from this collection
            if (px < bounds.left or px > bounds.right) {
                self.stopAutoScroll();
                return;
            }

            const dist_from_top = py - bounds.top;
            const dist_from_bottom = bounds.bottom - py;
            const zone = config.auto_scroll_zone;

            var speed: f32 = 0;

            if (dist_from_top >= 0 and dist_from_top < zone) {
                const depth = 1.0 - (dist_from_top / zone);
                speed = -lerpf(config.auto_scroll_min_speed, config.auto_scroll_max_speed, depth);
            } else if (dist_from_bottom >= 0 and dist_from_bottom < zone) {
                const depth = 1.0 - (dist_from_bottom / zone);
                speed = lerpf(config.auto_scroll_min_speed, config.auto_scroll_max_speed, depth);
            }

            if (speed == 0) {
                self.stopAutoScroll();
                return;
            }

            self.auto_scroll_speed = speed;

            if (!self.auto_scroll_active) {
                self.auto_scroll_active = true;
                self.scheduleAutoScrollTick();
            }
        }

        fn lerpf(a: f32, b: f32, t: f32) f32 {
            return a + (b - a) * t;
        }

        fn scheduleAutoScrollTick(self: *Self) void {
            self.auto_scroll_raf_id = Vapor.lib.runOnAnimationFrame(
                autoScrollTickErased,
                .{self},
            );
        }

        fn autoScrollTickErased(self: *Self) void {
            self.autoScrollTick();
        }

        fn autoScrollTick(self: *Self) void {
            if (!self.auto_scroll_active) return;

            const ctx = self.drag_ctx orelse {
                self.stopAutoScroll();
                return;
            };
            if (!ctx.isDragActive()) {
                self.stopAutoScroll();
                return;
            }

            const current = self.container_binded.scrollTop();
            const max_scroll = @max(0, self.total_height - self.container_height);
            const next = @max(0, @min(current + self.auto_scroll_speed, max_scroll));

            if (next != current) {
                self.container_binded.scrollToTop(next);

                // Shift the virtual window if needed (same logic as trackScroll)
                const current_item_index = @floor(next / config.height);
                const window_start_px = @as(f32, @floatFromInt(self.current_window_start)) * config.height;
                const window_len_px = @as(f32, @floatFromInt(self.total_window_items)) * config.height;
                const window_end_px = window_start_px + window_len_px;
                const buffer_px = @as(f32, @floatFromInt(self.buffer_zone)) * config.height;

                const approaching_top = next < (window_start_px + buffer_px);
                const approaching_bottom = (next + self.container_height) > (window_end_px - buffer_px);

                if (approaching_bottom or approaching_top) {
                    self.updateVisibleRange(current_item_index);
                }

                // Items moved on screen → refresh hover state with the unchanged pointer.
                // DragContext re-caches rects and re-runs hit-testing.
                ctx.refreshHover();
            }

            Vapor.cycle();

            // Schedule next frame — even if we hit the scroll limit, keep ticking
            // so the user moving away from the edge can stop it cleanly.
            self.scheduleAutoScrollTick();
        }

        fn stopAutoScroll(self: *Self) void {
            if (!self.auto_scroll_active) return;
            self.auto_scroll_active = false;
            self.auto_scroll_speed = 0;
            if (is_wasm and self.auto_scroll_raf_id != 0) {
                Vapor.Wasm.cancelAnimationFrameWasm(self.auto_scroll_raf_id);
                self.auto_scroll_raf_id = 0;
            }
        }
        fn handleItemPointerMove(self: *Self, evt: *Vapor.Event) void {
            const pending = self.pending_drag orelse return;
            const ctx = self.drag_ctx orelse return;

            const dx = evt.clientX() - pending.start_x;
            const dy = evt.clientY() - pending.start_y;
            const dist_sq = dx * dx + dy * dy;
            const threshold = config.drag_activation_distance;
            const threshold_sq = threshold * threshold;

            if (dist_sq < threshold_sq) return;

            // Threshold crossed — promote pending pointerdown into a real drag.
            self.pending_drag = null;
            evt.preventDefault();

            // NOW capture the pointer to the slot's wrapper element so subsequent
            // pointer events flow through this collection even if pointer leaves.
            self.ensureSlots(pending.local_index + 1);
            self.slots.items[pending.local_index].binded.setPointerCapture(evt);
            self.captured_slot_index = pending.local_index;
            self.captured_pointer_id = evt.id;

            ctx.startDrag(
                self.id,
                pending.real_index,
                @ptrCast(&self.items.items[pending.real_index]),
                evt.clientX(),
                evt.clientY(),
                pending.initial_rect,
            );
        }

        fn handleItemPointerUp(self: *Self, evt: *Vapor.Event) void {
            // Released without crossing threshold — it was a click. Clear pending
            // state and let the click event fire normally on the actual target.
            if (self.pending_drag != null) {
                self.pending_drag = null;
                return;
            }

            // Otherwise this is the end of a real drag — release pointer capture.
            self.releaseCaptureIfHeld(evt);
        }

        fn releaseCaptureIfHeld(self: *Self, _: *Vapor.Event) void {
            const slot_index = self.captured_slot_index orelse return;
            if (is_wasm and slot_index < self.slots.items.len) {
                // self.slots.items[slot_index].binded.releasePointerCapture(self.captured_pointer_id);
                const id = self.slots.items[slot_index].binded._get_id() orelse {
                    std.log.info("SortableCollection Slot Id is null", .{});
                    return;
                };
                Vapor.Wasm.releasePointerCaptureWasm(id.ptr, id.len, self.captured_pointer_id);
            }
            self.captured_slot_index = null;
            self.captured_pointer_id = 0;
        }

        // ====================================================================
        // Rendering
        // ====================================================================

        pub fn surface(self: *Self) Surface {
            const container = Vapor.Box();

            if (!self.registered) {
                if (self.drag_ctx) |ctx| {
                    ctx.registerCollection(self.id, &self.handle);
                    self.registered = true;
                }
            }

            return .{ .collection = self, .container = container };
        }

        pub fn trackScroll(self: *Self, _: *Vapor.Event) void {
            const stride: f32 = config.height + config.item_spacing;
            // Lower throttle for smoother updates (16ms is ~60fps)
            if (Vapor.Kit.throttle(8)) return;

            const scroll_top: f32 = self.container_binded.scrollTop();

            // Get actual container height from the DOM instead of using the fixed value
            const bounds = self.container_binded.getBoundingClientRect() orelse return;
            if (bounds.height > 0) {
                self.container_height = bounds.height;
            }

            const current_item_index = @floor(scroll_top / stride);

            // Boundaries in Pixels

            const window_start_px = @as(f32, @floatFromInt(self.current_window_start)) * stride;
            const window_len_px = @as(f32, @floatFromInt(self.total_window_items)) * stride;
            const window_end_px = window_start_px + window_len_px;
            const buffer_px = @as(f32, @floatFromInt(self.buffer_zone)) * stride;

            const approaching_top = scroll_top < (window_start_px + buffer_px);
            const approaching_bottom = (scroll_top + self.container_height) > (window_end_px - buffer_px);

            if (approaching_bottom or approaching_top) {
                self.updateVisibleRange(current_item_index);
            }

            self.prev_scroll_top = scroll_top;
            Vapor.cycle();
        }

        fn updateVisibleRange(self: *Self, current_view_index: f32) void {
            // Calculate ideal start index to keep the view centered in the buffer
            const half_window = @as(f32, @floatFromInt(self.total_window_items / 2));
            const view_center_offset = @as(f32, @floatFromInt(self.visible_count / 2));

            const ideal_start = current_view_index - half_window + view_center_offset;

            // Clamp
            const max_start = @as(f32, @floatFromInt(self.getItems().len - self.total_window_items));
            const start_f = @max(0, @min(ideal_start, max_start));
            const new_start_index = @as(usize, @intFromFloat(start_f));

            if (new_start_index == self.current_window_start) return;

            self.current_window_start = new_start_index;

            // Update Data Slice
            // In a reactive framework, this triggers the DOM update

            // Note: We DO NOT translate any window here.
            // The position is handled in the render loop below.
        }

        pub fn mount(self: *Self) void {
            if (self.initial_index > 0) {
                const scroll_to = @as(f32, @floatFromInt(self.initial_index)) * config.height;
                self.container_binded.scrollToTop(scroll_to);
            }

            // const bounds = self.container_binded.getBoundingClientRect() orelse return;
        }

        pub const Surface = struct {
            collection: *Self,
            container: Vapor.Builder(.pure),

            pub fn width(s: Surface, w: anytype) Surface {
                return .{ .collection = s.collection, .container = s.container.width(w) };
            }
            pub fn height(s: Surface, h: anytype) Surface {
                return .{ .collection = s.collection, .container = s.container.height(h) };
            }
            pub fn background(s: Surface, bg: anytype) Surface {
                return .{ .collection = s.collection, .container = s.container.background(bg) };
            }
            pub fn padding(s: Surface, p: anytype) Surface {
                return .{ .collection = s.collection, .container = s.container.padding(p) };
            }
            pub fn spacing(s: Surface, sp: anytype) Surface {
                return .{ .collection = s.collection, .container = s.container.spacing(sp) };
            }
            pub fn border(s: Surface, b: anytype) Surface {
                return .{ .collection = s.collection, .container = s.container.border(b) };
            }
            pub fn layout(s: Surface, l: anytype) Surface {
                return .{ .collection = s.collection, .container = s.container.layout(l) };
            }
            pub fn direction(s: Surface, d: anytype) Surface {
                return .{ .collection = s.collection, .container = s.container.direction(d) };
            }
            pub fn scroll(s: Surface, sc: anytype) Surface {
                return .{ .collection = s.collection, .container = s.container.scroll(sc) };
            }
            pub fn pos(s: Surface, p: anytype) Surface {
                return .{ .collection = s.collection, .container = s.container.pos(p) };
            }
            pub fn shadow(s: Surface, sh: anytype) Surface {
                return .{ .collection = s.collection, .container = s.container.shadow(sh) };
            }

            pub fn render(
                s: Surface,
                render_fn: anytype,
                args: anytype,
            ) void {
                const self = s.collection;
                const ctx = self.drag_ctx;
                const is_dragging_from_here = if (ctx) |c| c.isDraggingFrom(self.id) else false;
                const drag_source_index = if (ctx) |c| c.getDragSourceIndex() else null;
                const stride = config.height + config.item_spacing;

                const dir: Vapor.Types.Direction = if (config.direction == .vertical)
                    .column
                else
                    .row;

                s.container
                    .onEvent(.scroll, trackScroll, .{self})
                    .ref(&self.container_binded)
                    .height(.expand)
                    .maxHeight(.px(self.container_height))
                    .scroll(.{ .y = .scroll, .x = .hidden })
                    .direction(dir)
                    .children({
                    Vapor.Stack()
                        .width(.percent(100))
                        .height(.px(self.visibleHeight()))
                        .pos(.relative)
                        .onMount(mount, .{self})
                        .children({
                        Vapor.List()
                            .width(.percent(100))
                            .height(.px(self.visibleHeight() + if (self.gap_index != null) config.gap_height else 0))
                            .padding(.all(0))
                            .listStyle(.none)
                            .pos(.relative)
                            .children({
                            const items = self.items.items;
                            self.ensureSlots(items.len);
                            const end = @min(items.len, self.current_window_start + self.total_window_items);

                            var visible_count: usize = 0;
                            var visible_index: usize = self.visibleIndexBefore(self.current_window_start);

                            // Render the gap once, positioned absolutely at its computed Y.
                            if (self.gap_index) |gap| {
                                const gap_y = @as(f32, @floatFromInt(self.visibleIndexBefore(gap))) * stride;

                                Vapor.Box()
                                    .width(.percent(100))
                                    .height(.px(config.gap_height))
                                    .pos(.{ .type = .absolute, .top = .px(0), .left = .px(0) })
                                    .inlineStyle("transform: translate3d({d}px, {d}px, {d}px);", .{ 0, gap_y, 0 })
                                    .children({
                                    renderGap(config.direction);
                                });
                            }
                            for (items[self.current_window_start..end], 0..) |*item, local_i| {
                                const real_i = self.current_window_start + local_i;
                                const slot = &self.slots.items[local_i];

                                const is_this_item_dragging = is_dragging_from_here and
                                    (drag_source_index orelse std.math.maxInt(usize)) == real_i;

                                if (!is_this_item_dragging and !self.passesFilter(item)) {
                                    continue;
                                }

                                // Position by visible index, not real index
                                var y_pos = @as(f32, @floatFromInt(visible_index)) * stride;

                                if (self.gap_index) |gap| {
                                    if (real_i >= gap) y_pos += config.gap_height;
                                }

                                visible_index += 1;
                                visible_count += 1;

                                const state = drag_context.ItemState{
                                    .is_dragging = is_this_item_dragging,
                                    .is_placeholder = is_this_item_dragging,
                                    .is_over = false,
                                    .index = local_i,
                                };

                                const id = blk: switch (@typeInfo(TaskIdType)) {
                                    .pointer => break :blk item.id,
                                    .int => break :blk Vapor.frame.fmt("ST-Item-{d}", .{item.id}),
                                    else => {
                                        std.log.err("Must be int or pointer type for Task Id", .{});
                                        break :blk "";
                                    },
                                };

                                Vapor.Box()
                                    .id(id)
                                    .height(.px(config.height))
                                    .width(.percent(100))
                                    .ref(&slot.binded)
                                    .pos(.{ .type = .absolute, .top = .px(0), .left = .px(0) })
                                    .inlineStyle("transform: translate3d({d}px, {d}px, {d}px);", .{ 0, y_pos, 0 })
                                    .onEvent(.pointerdown, handlePointerDownDispatch, .{ self, local_i })
                                    .onEvent(.pointermove, handlePointerMoveDispatch, .{self})
                                    .onEvent(.pointerup, handlePointerUpDispatch, .{self})
                                    .onEvent(.pointercancel, handlePointerUpDispatch, .{self})
                                    .cursor(if (is_this_item_dragging) .grabbing else .grab)
                                    .opacity(if (is_this_item_dragging) 0.3 else 1.0)
                                    .children({
                                    @call(.auto, render_fn, args ++ .{ item, local_i, state });
                                });
                            }

                            // Gap at end (when gap is past the last item)
                            if (self.gap_index) |gap| {
                                if (gap >= items.len) {
                                    const gap_y = @as(f32, @floatFromInt(self.visibleIndexBefore(gap))) * stride;
                                    Vapor.Box()
                                        .width(.percent(100))
                                        .height(.px(config.gap_height))
                                        .pos(.{ .type = .absolute, .top = .px(0), .left = .px(0) })
                                        .inlineStyle("transform: translate3d({d}px, {d}px, {d}px);", .{ 0, gap_y, 0 })
                                        .children({
                                        renderGap(config.direction);
                                    });
                                }
                            }

                            if (visible_count == 0 and self.gap_index == null) {
                                renderNoItems(self.count(), config.direction);
                            }
                        });
                    });
                });

                // Default drag overlay
                if (config.show_drag_overlay) {
                    if (ctx) |c| {
                        const overlay = c.getOverlayState();
                        if (overlay.is_active and c.isDraggingFrom(self.id)) {
                            if (overlay.initial_rect) |rect| {
                                const overlay_x = rect.left + overlay.delta_x;
                                const overlay_y = rect.top + overlay.delta_y;

                                if (config.drag_overlay_render) |custom_render| {
                                    if (overlay.item_ptr) |ptr| {
                                        const typed_item: *T = @ptrCast(@alignCast(ptr));
                                        custom_render(typed_item, overlay.delta_x, overlay.delta_y);
                                    } else {
                                        Vapor.Null();
                                    }
                                } else {
                                    if (overlay.item_ptr) |ptr| {
                                        const typed_item: *T = @ptrCast(@alignCast(ptr));
                                        const drag_idx = drag_source_index orelse 0;

                                        Vapor.Box()
                                            .pos(.tl(.px(overlay_y), .px(overlay_x), .fixed))
                                            .width(.px(rect.width))
                                            .zIndex(9999)
                                            .cursor(.grabbing)
                                            .opacity(0.9)
                                            .shadow(Vapor.Types.Shadow.init().dropSpread(0, 4, 16, 2, .transparentize(.black, 0.15)))
                                            .border(.round(.palette(.tint), .all(8)))
                                            .background(.palette(.background))
                                            .children({
                                            @call(.auto, render_fn, args ++ .{ typed_item, drag_idx, drag_context.ItemState{
                                                .is_dragging = true,
                                                .is_placeholder = false,
                                                .is_over = false,
                                                .index = drag_idx,
                                            } });
                                        });
                                    } else {
                                        Vapor.Null();
                                    }
                                }
                            } else {
                                Vapor.Null();
                            }
                        } else {
                            Vapor.Null();
                        }
                    } else {
                        Vapor.Null();
                    }
                }
            }
        };

        fn handlePointerDownDispatch(self: *Self, local_index: usize, evt: *Vapor.Event) void {
            self.handleItemPointerDown(local_index, evt);
        }

        fn handlePointerMoveDispatch(self: *Self, evt: *Vapor.Event) void {
            self.handleItemPointerMove(evt);
        }

        fn handlePointerUpDispatch(self: *Self, evt: *Vapor.Event) void {
            self.handleItemPointerUp(evt);
        }

        fn renderNoItems(collection_count: usize, comptime dir: Direction) void {
            // _ = dir;
            if (config.no_items_render) |f| {
                f(collection_count, dir);
                return;
            }
            Vapor.Center()
                .height(.px(100))
                .children({
                Vapor.Stack()
                    .layout(.center)
                    .spacing(8)
                    .children({
                    Vapor.Text(if (collection_count > 0) "No Matching Tasks" else "No tasks")
                        .font(13, 400, Vapor.Types.Color.hex("#71717a"))
                        .fontFamily("Montserrat")
                        .end();
                });
            });
        }

        fn renderGap(comptime dir: Direction) void {
            // _ = dir;
            if (config.gap_render) |f| {
                f(dir);
                return;
            }
            Vapor.Box()
                .width(if (dir == .horizontal) .px(60) else .percent(100))
                .height(if (dir == .vertical) .px(60) else .percent(100))
                .background(.transparentize(.palette(.tint), 0.1))
                .border(.round(.transparentize(.palette(.tint), 0.3), .all(8)))
                .duration(150)
                .children({});
        }
    };
}
