const Vapor = @import("vapor");
const std = @import("std");
const Binded = Vapor.Binded;
const Box = Vapor.Box;
const List = Vapor.List;
const ListItem = Vapor.ListItem;
const Stack = Vapor.Stack;

pub fn VirtualList(comptime T: type) type {
    return struct {
        var total_height: f32 = 0;
        var total_items: f32 = 0;
        var total_window_items: usize = 0;

        const VirtualListOptions = struct {
            data: []const T,
            render: ?*const fn (*T, usize) void = null,
            render_ctx: ?*const fn (*T, usize, ?*anyopaque) void = null,
            buffer_size: usize = 10,
            item_height: Vapor.Types.Sizing,
            item_width: Vapor.Types.Sizing,
            container_height: ?f32 = null,
            initial_index: usize = 0,
        };

        const Self = @This();
        data: []const T = undefined,
        render: ?*const fn (*T, usize) void = null,
        render_ctx: ?*const fn (*T, usize, ?*anyopaque) void = null,
        item_height: f32 = 0,
        item_width: f32 = 0,
        _internal_slice: []T = undefined,

        // We only need the outer scrollable container and the list spacer
        inner_container: Binded = undefined,
        list_element: Binded = undefined, // This acts as the anchor

        container_height: f32 = 0,
        needs_virtualization: bool = false,

        visible_count: usize = 0,
        buffer_zone: usize = 0,
        current_window_start: usize = 0,

        // Tracking for render logic
        prev_scroll_top: f32 = 0,
        initial_index: usize = 0,

        ctx: ?*anyopaque = null,

        pub fn init(options: VirtualListOptions) Self {
            const calculated_item_height = options.item_height.size.min;
            const calculated_item_width = options.item_width.size.min;
            const container_height = if (options.container_height) |height| height else Vapor.lib.browser_height;

            // return Self{};

            var item_height: f32 = 0;
            var item_width: f32 = 0;
            switch (options.item_height.type) {
                .fit => item_height = calculated_item_height,
                .min_max_vp => item_height = calculated_item_height,
                .grow => item_height = calculated_item_height,
                .percent => item_height = calculated_item_height * container_height / 100,
                .fixed => item_height = options.item_height.size.min,
                .elastic => item_height = calculated_item_height,
                .elastic_percent => item_height = calculated_item_height,
                .clamp_px => item_height = calculated_item_height,
                .clamp_percent => item_height = calculated_item_height,
                .auto => item_height = calculated_item_height,
                .none => {},
                else => {},
            }
            switch (options.item_width.type) {
                .fit => item_width = calculated_item_width,
                .min_max_vp => item_width = calculated_item_width,
                .grow => item_width = calculated_item_width,
                .percent => item_width = calculated_item_width * Vapor.lib.browser_width / 100,
                .fixed => item_width = options.item_width.size.min,
                .elastic => item_width = calculated_item_width,
                .elastic_percent => item_width = calculated_item_width,
                .clamp_px => item_width = calculated_item_width,
                .clamp_percent => item_width = calculated_item_width,
                .auto => item_width = calculated_item_width,
                .none => {},
                else => {},
            }

            total_height = @as(f32, @floatFromInt(options.data.len)) * item_height;
            total_items = @as(f32, @floatFromInt(options.data.len));

            const number_of_items_fit = @as(usize, @intFromFloat(@ceil(container_height / item_height)));

            // Calculate buffer
            const ideal_buffer = number_of_items_fit * 3;
            const max_buffer: usize = 100;
            total_window_items = @min(options.data.len, @min(ideal_buffer, max_buffer));
            const needs_virtualization = total_window_items < options.data.len;

            // Calculate Initial Window
            const half_window = total_window_items / 2;
            const initial_window_start = if (options.initial_index <= half_window)
                0
            else if (options.initial_index + half_window >= options.data.len)
                options.data.len - total_window_items
            else
                options.initial_index - half_window;

            // Allocate Slice
            var internal_slice: []T = Vapor.arena(.persist).alloc(T, total_window_items) catch unreachable;
            for (0..total_window_items) |i| {
                internal_slice[i] = options.data[initial_window_start + i];
            }

            const buffer_zone = number_of_items_fit; // 1 screen buffer

            return Self{
                .data = options.data,
                .render = options.render,
                .render_ctx = options.render_ctx,
                .item_height = item_height,
                .item_width = 0, // Set this correctly based on your switch logic
                ._internal_slice = internal_slice,
                .inner_container = Binded{},
                .list_element = Binded{},
                .container_height = container_height,
                .needs_virtualization = needs_virtualization,
                .visible_count = number_of_items_fit,
                .buffer_zone = buffer_zone,
                .initial_index = options.initial_index,
                .current_window_start = initial_window_start,
            };
        }

        pub fn trackScroll(self: *Self, _: *Vapor.Event) void {
            // Lower throttle for smoother updates (16ms is ~60fps)
            if (Vapor.Kit.throttle(8)) return;
            if (!self.needs_virtualization) return;

            const scroll_top: f32 = self.inner_container.scrollTop();

            // Get actual container height from the DOM instead of using the fixed value
            const bounds = self.inner_container.getBoundingClientRect() orelse return;
            if (bounds.height > 0) {
                self.container_height = bounds.height;
            }
            std.log.info("container_height: {d}", .{self.container_height});

            const current_item_index = @floor(scroll_top / self.item_height);

            // Boundaries in Pixels
            const window_start_px = @as(f32, @floatFromInt(self.current_window_start)) * self.item_height;
            const window_len_px = @as(f32, @floatFromInt(self._internal_slice.len)) * self.item_height;
            const window_end_px = window_start_px + window_len_px;
            const buffer_px = @as(f32, @floatFromInt(self.buffer_zone)) * self.item_height;

            const approaching_top = scroll_top < (window_start_px + buffer_px);
            const approaching_bottom = (scroll_top + self.container_height) > (window_end_px - buffer_px);

            if (approaching_bottom or approaching_top) {
                self.updateVisibleRange(current_item_index);
            }

            self.prev_scroll_top = scroll_top;
        }

        fn updateVisibleRange(self: *Self, current_view_index: f32) void {
            // Calculate ideal start index to keep the view centered in the buffer
            const half_window = @as(f32, @floatFromInt(self._internal_slice.len / 2));
            const view_center_offset = @as(f32, @floatFromInt(self.visible_count / 2));

            const ideal_start = current_view_index - half_window + view_center_offset;

            // Clamp
            const max_start = @as(f32, @floatFromInt(self.data.len - self._internal_slice.len));
            const start_f = @max(0, @min(ideal_start, max_start));
            const new_start_index = @as(usize, @intFromFloat(start_f));

            if (new_start_index == self.current_window_start) return;

            self.current_window_start = new_start_index;

            // Update Data Slice
            // In a reactive framework, this triggers the DOM update
            for (0..self._internal_slice.len) |i| {
                self._internal_slice[i] = self.data[new_start_index + i];
            }

            // Note: We DO NOT translate any window here.
            // The position is handled in the render loop below.
        }

        pub fn mount(self: *Self) void {
            if (self.initial_index > 0) {
                const scroll_to = @as(f32, @floatFromInt(self.initial_index)) * self.item_height;
                self.inner_container.scrollToTop(scroll_to);
            }

            // const bounds = self.inner_container.getBoundingClientRect() orelse return;
            // std.log.info("scroll_to: {d} {d}", .{ bounds.height, total_height });
        }

        pub fn renderWithCtx(self: *Self, ctx: ?*anyopaque) void {
            List()
                .onEventCtx(.scroll, trackScroll, .{self})
                .ref(&self.inner_container)
                // .width(.percent(100))
                .height(.grow)
                .direction(.column)
                .scroll(.{ .y = .scroll, .x = .hidden })
                .children({
                // The Scroll Phantom: Forces the scrollbar to be the correct size
                // But we don't put children inside it effectively (or we overlay them).
                Stack().ref(&self.list_element)
                    .width(.percent(100))
                    .height(.px(total_height))
                    .pos(.relative)
                    .onMount(mount, .{self})
                    .children({
                    List().ref(&self.list_element)
                        .width(.percent(100))
                        .height(.px(total_height))
                        .padding(.all(0))
                        .listStyle(.none)
                        .pos(.relative)
                        .children({
                        // RENDER LOOP
                        for (self._internal_slice, 0..) |*item, i| {

                            // 1. Calculate the real absolute Y position
                            const real_index = self.current_window_start + i;
                            const y_pos = @as(f32, @floatFromInt(real_index)) * self.item_height;

                            ListItem()
                                .inlineStyle("transform: translate3d({d}px, {d}px, {d}px);", .{ 0, y_pos, 0 })
                                .height(.px(self.item_height))
                                // .width(.percent(100))
                                .pos(.{ .type = .absolute, .top = .px(0), .left = .px(0) })
                                .children({
                                if (self.render_ctx) |render_ctx| {
                                    @call(.auto, render_ctx, .{ item, real_index, ctx });
                                }
                            });
                        }
                    });
                });
            });
        }

        pub fn generate(self: *Self) void {
            List()
                .onEventCtx(.scroll, trackScroll, .{self})
                .ref(&self.inner_container)
                .width(.percent(100))
                .height(.px(self.container_height))
                .direction(.column)
                .scroll(.{ .x = .hidden, .y = .scroll_y() })
                .children({
                // The Scroll Phantom: Forces the scrollbar to be the correct size
                // But we don't put children inside it effectively (or we overlay them).
                Stack().ref(&self.list_element)
                    .width(.percent(100))
                    .height(.px(total_height))
                    .pos(.relative)
                    .onMount(mount, .{self})
                    .children({
                    // RENDER LOOP
                    for (self._internal_slice, 0..) |*item, i| {

                        // 1. Calculate the real absolute Y position
                        const real_index = self.current_window_start + i;
                        const y_pos = @as(f32, @floatFromInt(real_index)) * self.item_height;

                        ListItem()
                            .inlineStyle("transform: translate3d({d}px, {d}px, {d}px); contain: content;", .{ 0, y_pos, 0 })
                            .height(.px(self.item_height))
                            .width(.percent(100))
                            .pos(.{ .type = .absolute, .top = .px(0), .left = .px(0) })
                            .children({
                            if (self.render) |render| {
                                @call(.auto, render, .{ item, real_index });
                            }
                        });
                    }
                });
            });
        }
    };
}
