const Vapor = @import("vapor");
const std = @import("std");
const Binded = Vapor.Binded;
const Box = Vapor.Box;
const HooksCtx = Vapor.Static.HooksCtx;
const List = Vapor.List;
const ListItem = Vapor.ListItem;

pub fn VirtualList(comptime T: type) type {
    return struct {
        var total_height: f32 = 0;
        var list_height: f32 = 0;
        var total_items: f32 = 0;
        var scroll_top_max: f32 = 0;
        var total_window_items: usize = 0;
        const VirtualListOptions = struct {
            data: []const T,
            render: *const fn (T, usize) void,
            buffer_size: usize = 10,
            item_height: Vapor.Types.Sizing,
            item_width: Vapor.Types.Sizing,
            container_height: ?f32 = null, // null = use browser height
        };
        const ScrollDirection = enum {
            up,
            down,
            none,
        };
        const Self = @This();
        data: []const T,
        render: *const fn (T, usize) void,
        buffer_size: f32 = 10,
        item_height: f32,
        item_width: f32,
        _internal_slice: []T,
        list_element: Binded = undefined,
        inner_container: Binded = undefined,
        window_element: Binded = undefined,
        current_scroll: f32 = 0, // the current scroll of the list
        current_item_index: usize = 0, // the current item index
        current_window_start: usize = 0,

        // Add these fields to your struct
        prev_scroll_top: f32 = 0,
        prev_item_index: f32 = 0,
        up_threshold: f32 = 0,
        down_threshold: f32 = 0,
        container_height: f32 = 0,
        needs_virtualization: bool = false,

        visible_count: usize, // items that fit in viewport
        buffer_zone: usize, // items to keep as buffer above/below visible area

        pub fn init(options: VirtualListOptions) Self {
            const calculated_item_height = options.item_height.size.min;
            const calculated_item_width = options.item_width.size.min;
            const container_height = if (options.container_height) |height| height else Vapor.lib.browser_height;

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
            }

            total_height = @as(f32, @floatFromInt(options.data.len)) * item_height;
            total_items = @as(f32, @floatFromInt(options.data.len));
            scroll_top_max = total_height - container_height;

            const number_of_items_fit = @as(usize, @intFromFloat(@ceil(container_height / item_height)));
            Vapor.print("Number of items fit: {d}", .{number_of_items_fit});

            // Simple heuristic: render 3x what's visible (1x above, 1x visible, 1x below)
            // but cap it and also handle small lists
            const ideal_buffer = number_of_items_fit * 3;
            const max_buffer: usize = 100;

            total_window_items = @min(options.data.len, @min(ideal_buffer, max_buffer));

            // Track whether we even need virtualization
            const needs_virtualization = total_window_items < options.data.len;

            Vapor.println("total_window_items {d}", .{total_window_items});

            list_height = @as(f32, @floatFromInt(total_window_items)) * item_height;

            var internal_slice: []T = Vapor.arena(.persist).alloc(T, total_window_items) catch unreachable;
            for (0..total_window_items) |i| {
                internal_slice[i] = options.data[i];
            }

            // In init, calculate these:
            const visible_count = @as(usize, @intFromFloat(@ceil(container_height / item_height)));
            const buffer_zone = visible_count; // 1 screen worth of buffer on each side

            // Initialize thresholds based on initial state (at top)
            const initial_down_threshold = @as(f32, @floatFromInt(buffer_zone)) * item_height;

            return Self{
                .data = options.data,
                .render = options.render,
                .buffer_size = @as(f32, @floatFromInt(options.buffer_size)),
                .item_height = item_height,
                .item_width = item_width,
                ._internal_slice = internal_slice,
                .list_element = Binded{},
                .inner_container = Binded{},
                .window_element = Binded{},
                .current_scroll = 0,
                .current_item_index = 0,
                .container_height = container_height,
                .needs_virtualization = needs_virtualization,
                .down_threshold = initial_down_threshold,
                .visible_count = visible_count,
                .buffer_zone = buffer_zone,
            };
        }

        pub fn trackScroll(self: *Self, _: *Vapor.Event) void {
            if (!self.needs_virtualization) return;

            const scroll_top: f32 = @floatFromInt(self.inner_container.scrollTop());
            const current_item_index = @floor(scroll_top / self.item_height);

            // Calculate where the current window starts in the data
            const window_start = @as(f32, @floatFromInt(self.current_window_start));
            const buffer_zone_px = @as(f32, @floatFromInt(self.buffer_zone)) * self.item_height;

            // We want to re-center the window when we've scrolled through most of the buffer
            const window_start_px = window_start * self.item_height;
            const window_end_px = window_start_px + @as(f32, @floatFromInt(self._internal_slice.len)) * self.item_height;

            // Trigger rerender when approaching edges of rendered window
            const approaching_top = scroll_top < (window_start_px + buffer_zone_px);
            const approaching_bottom = (scroll_top + self.container_height) > (window_end_px - buffer_zone_px);

            if (approaching_bottom and !self.isAtEnd(current_item_index)) {
                self.recenterWindow(current_item_index);
            } else if (approaching_top and !self.isAtStart(current_item_index)) {
                self.recenterWindow(current_item_index);
            }

            self.prev_scroll_top = scroll_top;
        }

        fn recenterWindow(self: *Self, current_item_index: f32) void {
            // Center the window around current view position
            const half_window = @as(f32, @floatFromInt(self._internal_slice.len / 2));
            const ideal_start = current_item_index - half_window + @as(f32, @floatFromInt(self.visible_count / 2));

            // Clamp to valid range
            const max_start = @as(f32, @floatFromInt(self.data.len - self._internal_slice.len));
            const start_f = @max(0, @min(ideal_start, max_start));
            const start_index = @as(usize, @intFromFloat(start_f));

            // Only update if we've actually moved
            if (start_index == self.current_window_start) return;

            self.current_window_start = start_index;

            // Copy data
            for (0..self._internal_slice.len) |i| {
                self._internal_slice[i] = self.data[start_index + i];
            }

            Vapor.print("Recentering Window", .{});
            // Translate window
            const y = @as(f32, @floatFromInt(start_index)) * self.item_height;
            _ = self.window_element.translate3d(.{ .y = y });
        }

        fn isAtEnd(self: *Self, current_item_index: f32) bool {
            return current_item_index + self.buffer_size - 1 >= @as(f32, @floatFromInt(self.data.len));
        }

        fn isAtStart(_: *Self, current_item_index: f32) bool {
            return current_item_index <= 0;
        }

        pub fn generate(self: *Self) void {
            List()
                .onEventCtx(.scroll, trackScroll, self)
                .ref(&self.inner_container)
                .style(&.{
                .size = .{
                    .height = .px(self.container_height),
                    .width = .px(Vapor.lib.browser_width),
                },
                .direction = .column,
                .scroll = .scroll_y(),
                .padding = .all(0),
                .list_style = .none,
                .show_scrollbar = false,
                .position = .{
                    .type = .relative,
                    .top = .px(0),
                },
            })({
                Box().ref(&self.list_element).style(&.{
                    .size = .{
                        .height = .px(total_height),
                        .width = .percent(100),
                    },
                    .direction = .column,
                })({
                    List().ref(&self.window_element).style(&.{
                        .position = .{
                            .type = .absolute,
                            .top = .px(0),
                        },
                        .list_style = .none,
                        .size = .{
                            .height = .px(list_height),
                            .width = .percent(100),
                        },
                        .direction = .column,
                        .scroll = .none(),
                        .padding = .all(0),
                    })({
                        for (self._internal_slice, 0..) |item, i| {
                            ListItem().style(&.{
                                .size = .{
                                    .height = .px(self.item_height),
                                    // .width = .percent(self.item_width),
                                },
                            })({
                                @call(.auto, self.render, .{ item, i });
                            });
                        }
                    });
                });
            });
        }
    };
}
