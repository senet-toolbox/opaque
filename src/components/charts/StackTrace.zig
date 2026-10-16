const std = @import("std");
const Vapor = @import("vapor");
const Box = Vapor.Box;
const Text = Vapor.Text;
const Svg = @import("Svg.zig").Svg;
const path_util = @import("util/path.zig");
const color_util = @import("util/color.zig");
const ArrayList = std.array_list.Managed;

// ============================================================
// Stack Trace Visualizer
//
// Two modes:
//   1. Tree view   – top-down DAG with curved edges + arrowheads
//                    heat-mapped nodes, weighted edges,
//                    collapse/expand, path highlighting
//   2. Flame graph – stacked rects, width ∝ samples, no arrows
//
// Public API for consumers:
//   - currentHovered()   → currently hovered node (or null)
//   - selectedNode()     → currently clicked/selected node (or null)
//   - toggleCollapse()   → expand/collapse a node's children
//   - expandAll()        → show all nodes
//   - collapseAll()      → collapse everything except root
//   - collapseToDepth()  → collapse below a given depth
//   - ancestorsOf()      → path from root to a given node
//   - filteredNodes()    → all currently visible layout nodes
//   - isCollapsed()      → check if a node is collapsed
//   - isOnSelectedPath() → check if a node is on the highlighted path
// ============================================================

/// A single frame in the call stack.
/// Children are const — layout data is stored separately in node_layout.
pub const StackNode = struct {
    name: []const u8,
    file: ?[]const u8 = null,
    line: ?u32 = null,
    module: ?[]const u8 = null,
    samples: u64 = 1,
    self_samples: u64 = 0,
    color: ?Vapor.Types.Color = null,
    children: []const StackNode = &.{},
};

pub const StackTrace = struct {
    allocator: std.mem.Allocator,
    config: Config,
    root: ?*const StackNode = null,
    current_svg: ?[]const u8 = null,
    container: Vapor.Element = .{},
    tooltip: ?Tooltip = null,
    bounds: Bounds = .{},

    rendered_elements: ArrayList(RenderedElement),
    old_rendered_elements: ArrayList(RenderedElement),

    platform: Platform,
    has_data: bool = false,

    // Layout cache (filled during build)
    layout_nodes: ArrayList(LayoutNode),
    layout_edges: ArrayList(LayoutEdge),

    // Layout data keyed by node pointer address (avoids mutating const nodes)
    node_layout: std.AutoHashMap(usize, NodeLayout),

    // ---------- Interactive state ----------

    /// Set of collapsed node addresses — children of these nodes are hidden
    collapsed_set: std.AutoHashMap(usize, void),

    /// Currently hovered node (updated on pointer move)
    hovered_node: ?*const StackNode = null,

    /// Currently selected/clicked node (persists until another click or deselect)
    selected: ?*const StackNode = null,

    /// Cached ancestor path for the selected node (root → … → selected)
    /// Stored as a set of node addresses for O(1) lookup during rendering
    selected_path: std.AutoHashMap(usize, void),

    /// Parent lookup: child address → parent address (built during layout)
    parent_map: std.AutoHashMap(usize, usize),

    // ============ Types ============

    pub const Config = struct {
        width: u32 = 900,
        height: u32 = 600,
        margin: Margin = .{},
        mode: Mode = .tree,
        background: ?Vapor.Types.Color = null,
        palette: color_util.Palette = color_util.palettes.category10,

        // Tree mode
        node_height: f64 = 28,
        node_padding_x: f64 = 8,
        node_padding_y: f64 = 4,
        node_radius: f64 = 8,
        node_min_width: f64 = 40,
        level_gap: f64 = 80,
        sibling_gap: f64 = 16,
        edge_style: EdgeStyle = .curved,

        // Heat map colors (tree mode, ordered cold → hot)
        heat_colors: []const []const u8 = &.{
            "#3b4252", // cold  — dark slate (near zero %)
            "#434c5e", // cool
            "#385D89", // blue
            "#8CDFF6", // teal
            "#a3be8c", // green
            "#FDCD6B", // yellow
            "#d08770", // orange
            "#bf616a", // red-orange
            "#5016FF", // purple
        },

        // Edge weight range (tree mode)
        edge_min_width: f32 = 1,
        edge_max_width: f32 = 3.0,
        edge_color: []const u8 = "#A8A8A8",
        edge_hot_color: []const u8 = "#d33f49",

        // Dimming for non-highlighted nodes when a path is selected
        dim_opacity: f64 = 0.25,

        // Collapse indicator
        collapse_indicator_size: f64 = 8,

        // Flame mode
        flame_row_height: f64 = 22,
        flame_min_width: f64 = 2,

        // Text
        font_size: u32 = 10,
        font_color: Vapor.Types.Color = .hex("#333333"),
        show_tooltips: bool = true,

        // Percentage label on nodes
        show_percentage: bool = true,
        percentage_font_size: u32 = 9,
    };

    pub const Mode = enum { tree, flame };
    pub const EdgeStyle = enum { straight, curved, elbow };

    pub const Margin = struct {
        top: u32 = 20,
        right: u32 = 20,
        bottom: u32 = 20,
        left: u32 = 20,
    };

    /// Layout data computed per node, stored in hash map keyed by node address
    const NodeLayout = struct {
        x: f64 = 0,
        y: f64 = 0,
        width: f64 = 0,
        depth: u32 = 0,
        subtree_width: f64 = 0,
        index: u32 = 0,
        percentage: f64 = 0, // % of total samples
        has_children: bool = false, // true even if currently collapsed
    };

    const LayoutNode = struct {
        node: *const StackNode,
        x: f64,
        y: f64,
        width: f64,
        height: f64,
        depth: u32,
        color: Vapor.Types.Color,
        percentage: f64,
    };

    const LayoutEdge = struct {
        from_x: f64,
        from_y: f64,
        to_x: f64,
        to_y: f64,
        weight: f64, // 0..1 proportion of total samples
    };

    pub const Platform = union(enum) {
        browser: BrowserPlatform,
    };

    pub const BrowserPlatform = struct {
        pub fn setAttribute(_: BrowserPlatform, id: []const u8, key: []const u8, value: []const u8) void {
            if (!Vapor.lib.isWasi) return;
            Vapor.Wasm.setAttributeWasm(id.ptr, id.len, key.ptr, key.len, value.ptr, value.len);
        }
    };

    pub const ElementType = enum(u8) {
        node_rect,
        node_text,
        node_pct_text,
        edge_path,
        flame_rect,
        flame_text,
        arrowhead,
        collapse_indicator,
    };

    pub const ElementId = struct {
        node_index: u32,
        element_type: ElementType,

        pub fn toString(self: ElementId, buf: []u8) ![]u8 {
            return std.fmt.bufPrint(buf, "st-{d}-{s}", .{
                self.node_index,
                @tagName(self.element_type),
            });
        }
    };

    pub const RenderedElement = struct {
        id: ElementId,
        attrs: union(enum) {
            rect: struct { x: f64, y: f64, width: f64, height: f64, fill: ?Vapor.Types.Color = null, opacity: ?f64 = null },
            path: struct { d: []const u8, stroke: ?Vapor.Types.Color = null, stroke_width: ?f32 = null, fill: ?Vapor.Types.Color = null, opacity: ?f64 = null },
        },
    };

    const Tooltip = struct {
        top: f32 = 0,
        left: f32 = 0,
        binded: Vapor.Element = .{},
        hide: bool = true,
        name: []const u8 = "",
        file: []const u8 = "",
        line: ?u32 = null,
        module: []const u8 = "",
        samples: u64 = 0,
        self_samples: u64 = 0,
        percentage: f64 = 0,
        depth: u32 = 0,
    };

    const Bounds = struct {
        offset_x: f32 = 0,
        offset_y: f32 = 0,
        x: f32 = 0,
        y: f32 = 0,
        width: f32 = 0,
        height: f32 = 0,
    };

    // ============ Lifecycle ============

    pub fn init(allocator: std.mem.Allocator, config: Config) StackTrace {
        return .{
            .allocator = allocator,
            .config = config,
            .rendered_elements = ArrayList(RenderedElement).init(allocator),
            .old_rendered_elements = ArrayList(RenderedElement).init(allocator),
            .layout_nodes = ArrayList(LayoutNode).init(allocator),
            .layout_edges = ArrayList(LayoutEdge).init(allocator),
            .node_layout = std.AutoHashMap(usize, NodeLayout).init(allocator),
            .collapsed_set = std.AutoHashMap(usize, void).init(allocator),
            .selected_path = std.AutoHashMap(usize, void).init(allocator),
            .parent_map = std.AutoHashMap(usize, usize).init(allocator),
            .platform = .{ .browser = .{} },
            .tooltip = if (config.show_tooltips) Tooltip{} else null,
            .bounds = calculateBounds(config),
        };
    }

    fn calculateBounds(config: Config) Bounds {
        var bounds = Bounds{};
        if (!Vapor.lib.isWasi) return bounds;
        bounds.x = @floatFromInt(config.margin.left);
        bounds.y = @floatFromInt(config.margin.top);
        bounds.width = @floatFromInt(config.width - config.margin.left - config.margin.right);
        bounds.height = @floatFromInt(config.height - config.margin.top - config.margin.bottom);
        return bounds;
    }

    pub fn deinit(self: *StackTrace) void {
        self.rendered_elements.deinit();
        self.old_rendered_elements.deinit();
        self.layout_nodes.deinit();
        self.layout_edges.deinit();
        self.node_layout.deinit();
        self.collapsed_set.deinit();
        self.selected_path.deinit();
        self.parent_map.deinit();
    }

    // ============ Data ============

    pub fn setRoot(self: *StackTrace, root: *const StackNode) void {
        self.root = root;
    }

    // ============ Public Interactive API ============

    /// Returns the node currently under the pointer (or null).
    pub fn currentHovered(self: *const StackTrace) ?*const StackNode {
        return self.hovered_node;
    }

    /// Returns the node that was last clicked/selected (or null).
    pub fn selectedNode(self: *const StackTrace) ?*const StackNode {
        return self.selected;
    }

    /// Select a node programmatically (builds the ancestor highlight path).
    pub fn selectNode(self: *StackTrace, node: ?*const StackNode) !void {
        self.selected = node;
        try self.rebuildSelectedPath();
    }

    /// Toggle collapse state of a node. Collapsed nodes hide their children.
    pub fn toggleCollapse(self: *StackTrace, node: *const StackNode) void {
        const key = nodeKey(node);
        if (self.collapsed_set.contains(key)) {
            _ = self.collapsed_set.remove(key);
        } else {
            self.collapsed_set.put(key, {}) catch {};
        }
    }

    /// Returns true if the given node's children are currently hidden.
    pub fn isCollapsed(self: *const StackTrace, node: *const StackNode) bool {
        return self.collapsed_set.contains(nodeKey(node));
    }

    /// Expand all nodes (clear the collapsed set).
    pub fn expandAll(self: *StackTrace) void {
        self.collapsed_set.clearRetainingCapacity();
    }

    /// Collapse all nodes that have children (except root).
    pub fn collapseAll(self: *StackTrace) void {
        self.collapsed_set.clearRetainingCapacity();
        if (self.root) |root| {
            self.collapseAllRecursive(root, 0) catch {};
        }
    }

    fn collapseAllRecursive(self: *StackTrace, node: *const StackNode, depth: u32) !void {
        // Collapse everything except root (depth 0)
        if (depth > 0 and node.children.len > 0) {
            try self.collapsed_set.put(nodeKey(node), {});
        }
        for (node.children) |*child| {
            try self.collapseAllRecursive(child, depth + 1);
        }
    }

    /// Collapse all nodes below the given depth.
    pub fn collapseToDepth(self: *StackTrace, max_depth: u32) void {
        self.collapsed_set.clearRetainingCapacity();
        if (self.root) |root| {
            self.collapseToDepthRecursive(root, 0, max_depth) catch {};
        }
    }

    fn collapseToDepthRecursive(self: *StackTrace, node: *const StackNode, depth: u32, max_depth: u32) !void {
        if (depth >= max_depth and node.children.len > 0) {
            try self.collapsed_set.put(nodeKey(node), {});
        }
        for (node.children) |*child| {
            try self.collapseToDepthRecursive(child, depth + 1, max_depth);
        }
    }

    /// Check if a node is on the currently highlighted ancestor path.
    pub fn isOnSelectedPath(self: *const StackTrace, node: *const StackNode) bool {
        return self.selected_path.contains(nodeKey(node));
    }

    /// Returns the ancestor chain from root to the given node (caller must free).
    pub fn ancestorsOf(self: *const StackTrace, node: *const StackNode) ![]const *const StackNode {
        // Walk parent_map backwards to build path
        var path_list = ArrayList(*const StackNode).init(self.allocator);
        defer path_list.deinit();

        var current_key = nodeKey(node);
        // Add the node itself
        try path_list.append(node);

        // Walk up via parent_map
        while (self.parent_map.get(current_key)) |parent_key| {
            // Convert address back to pointer — find the LayoutNode for this key
            var found_node: ?*const StackNode = null;
            for (self.layout_nodes.items) |*ln| {
                if (nodeKey(ln.node) == parent_key) {
                    found_node = ln.node;
                    break;
                }
            }
            if (found_node) |pn| {
                try path_list.append(pn);
                current_key = parent_key;
            } else break;
        }

        // Reverse so it's root → … → node
        const result = try self.allocator.alloc(*const StackNode, path_list.items.len);
        for (path_list.items, 0..) |item, i| {
            result[path_list.items.len - 1 - i] = item;
        }
        return result;
    }

    /// Returns all currently visible layout nodes (useful for external filtering/search).
    pub fn filteredNodes(self: *const StackTrace) []const LayoutNode {
        return self.layout_nodes.items;
    }

    // ============ Internal: Selected Path ============

    fn rebuildSelectedPath(self: *StackTrace) !void {
        self.selected_path.clearRetainingCapacity();
        const sel = self.selected orelse return;

        // Walk from selected node up to root via parent_map
        var current_key = nodeKey(sel);
        try self.selected_path.put(current_key, {});

        while (self.parent_map.get(current_key)) |parent_key| {
            try self.selected_path.put(parent_key, {});
            current_key = parent_key;
        }
    }

    // ============ Helpers ============

    fn nodeKey(node: *const StackNode) usize {
        return @intFromPtr(node);
    }

    fn getLayout(self: *StackTrace, node: *const StackNode) NodeLayout {
        return self.node_layout.get(nodeKey(node)) orelse NodeLayout{};
    }

    fn putLayout(self: *StackTrace, node: *const StackNode, layout: NodeLayout) !void {
        try self.node_layout.put(nodeKey(node), layout);
    }

    /// Compute heat color based on percentage (0–100).
    /// Linearly interpolates through config.heat_colors.
    fn heatColor(self: *const StackTrace, percentage: f64) Vapor.Types.Color {
        const colors = self.config.heat_colors;
        if (colors.len == 0) return .hex("#888888");
        if (colors.len == 1) return .hex(colors[0]);

        // Clamp to 0–100, map to 0–1
        const t = std.math.clamp(percentage, 0, 100) / 100.0;
        // Map t to index range
        const max_idx: f64 = @floatFromInt(colors.len - 1);
        const pos = t * max_idx;
        const lo: usize = @intFromFloat(@floor(pos));
        const hi: usize = @min(lo + 1, colors.len - 1);

        if (lo == hi) return .hex(colors[lo]);

        // For simplicity, just pick the nearest color bucket
        // (full RGB lerp would require parsing hex — can be added later)
        const frac = pos - @as(f64, @floatFromInt(lo));
        return if (frac < 0.5) .hex(colors[lo]) else .hex(colors[hi]);
    }

    /// Compute edge stroke width based on child's sample proportion.
    fn edgeWidth(self: *const StackTrace, child_samples: u64) f32 {
        const root = self.root orelse return self.config.edge_min_width;
        const total: f64 = @floatFromInt(root.samples);
        if (total == 0) return self.config.edge_min_width;

        const proportion = @as(f64, @floatFromInt(child_samples)) / total;
        const min_w: f64 = @floatCast(self.config.edge_min_width);
        const max_w: f64 = @floatCast(self.config.edge_max_width);

        return @floatCast(min_w + proportion * (max_w - min_w));
    }

    /// Compute edge color — blend from neutral to hot based on proportion.
    fn edgeColor(self: *const StackTrace, _: u64) []const u8 {
        const root = self.root orelse return self.config.edge_color;
        const total: f64 = @floatFromInt(root.samples);
        if (total == 0) return self.config.edge_color;

        // const proportion = @as(f64, @floatFromInt(child_samples)) / total;
        // Use hot color if >40% of total
        // return if (proportion > 0.4) self.config.edge_hot_color else self.config.edge_color;
        return self.config.edge_color;
    }

    // ============ Build ============

    pub fn build(self: *StackTrace) !void {
        if (!Vapor.lib.isWasi) return;
        const root = self.root orelse return;

        self.layout_nodes.clearRetainingCapacity();
        self.layout_edges.clearRetainingCapacity();
        self.rendered_elements.clearRetainingCapacity();
        self.node_layout.clearRetainingCapacity();
        self.parent_map.clearRetainingCapacity();

        var svg = try Svg.initCapacity(self.allocator, 8192);
        errdefer svg.deinit();

        try svg.openSvg(self.config.width, self.config.height);

        switch (self.config.mode) {
            .tree => try svg.style(
                \\.st-node { cursor: pointer; }
                \\.st-node-text { font-family: 'JetBrains Mono', 'Fira Code', 'SF Mono', monospace; pointer-events: none; user-select: none; }
                \\.st-pct-text { font-family: 'JetBrains Mono', 'Fira Code', 'SF Mono', monospace; pointer-events: none; user-select: none; }
                \\.st-edge { fill: none; }
                \\.st-arrowhead { fill: #A8A8A8; }
                \\.st-collapse-icon { pointer-events: none; }
                \\.st-node:hover { filter: brightness(0.9); }
                \\.st-node.st-dimmed { transition: opacity 200ms ease; }
                \\.st-node.st-highlighted { filter: brightness(1.1) drop-shadow(0 0 3px rgba(255,255,255,0.3)); }
            ),
            .flame => try svg.style(
                \\.st-flame { transition: opacity 100ms ease; cursor: pointer; }
                \\.st-flame:hover { opacity: 0.8; }
                \\.st-flame-text { font-family: 'JetBrains Mono', 'Fira Code', 'SF Mono', monospace; pointer-events: none; user-select: none; }
            ),
        }

        if (self.config.background) |bg| {
            try svg.rect(0, 0, @floatFromInt(self.config.width), @floatFromInt(self.config.height), .{
                .id = "st-background",
                .fill = bg,
            });
        }

        if (self.config.mode == .tree) {
            try self.writeArrowMarker(&svg);
        }

        const m = self.config.margin;
        var transform_buf: [64]u8 = undefined;
        const transform = try std.fmt.bufPrint(&transform_buf, "translate({d},{d})", .{ m.left, m.top });
        try svg.openGroup("st-area", transform);

        switch (self.config.mode) {
            .tree => try self.buildTree(&svg, root),
            .flame => try self.buildFlame(&svg, root),
        }

        try svg.closeGroup();
        try svg.closeSvg();

        self.current_svg = try svg.toOwnedSlice();
        self.has_data = true;
    }

    fn writeArrowMarker(_: *StackTrace, svg: *Svg) !void {
        const w = svg;
        try w.appendSlice("<defs>");
        try w.appendSlice("<marker id=\"st-arrow\" viewBox=\"0 0 10 10\" refX=\"3\" refY=\"5\" ");
        try w.appendSlice("markerWidth=\"4\" markerHeight=\"4\" orient=\"auto-start-reverse\">");
        try w.appendSlice("<path d=\"M 0 0 L 10 5 L 0 10 z\" class=\"st-arrowhead\"/>");
        try w.appendSlice("</marker>");
        try w.appendSlice("</defs>\n");
    }

    // ============ Tree Layout ============

    fn buildTree(self: *StackTrace, svg: *Svg, root: *const StackNode) !void {
        const chart_w: f64 = @floatFromInt(self.config.width - self.config.margin.left - self.config.margin.right);
        const total_samples: f64 = @floatFromInt(root.samples);

        var node_counter: u32 = 0;
        try self.measureSubtreeWidth(root, 0, &node_counter, total_samples, null);

        const root_layout = self.getLayout(root);
        const total_width = root_layout.subtree_width;
        const scale = if (total_width > chart_w) chart_w / total_width else 1.0;
        const offset_x = if (total_width < chart_w) (chart_w - total_width) / 2.0 else 0.0;
        try self.assignPositions(root, offset_x, 0, scale);

        // Render edges first (below nodes)
        try self.renderTreeEdges(svg, root);
        // Then nodes on top
        try self.renderTreeNodes(svg, root);
    }

    fn measureSubtreeWidth(
        self: *StackTrace,
        node: *const StackNode,
        depth: u32,
        counter: *u32,
        total_samples: f64,
        parent: ?*const StackNode,
    ) !void {
        const idx = counter.*;
        counter.* += 1;

        // Record parent relationship
        if (parent) |p| {
            try self.parent_map.put(nodeKey(node), nodeKey(p));
        }

        const percentage = if (total_samples > 0)
            @as(f64, @floatFromInt(node.samples)) / total_samples * 100.0
        else
            0;

        const char_width: f64 = 7.0;
        const text_width = @as(f64, @floatFromInt(node.name.len)) * char_width;

        // Account for percentage label width if enabled
        const pct_extra: f64 = if (self.config.show_percentage) 40.0 else 0;
        const content_width = text_width + pct_extra;

        const node_width = @max(self.config.node_min_width, content_width + self.config.node_padding_x * 2);

        const is_collapsed = self.collapsed_set.contains(nodeKey(node));
        const effective_children = if (is_collapsed) &[_]StackNode{} else node.children;

        if (effective_children.len == 0) {
            try self.putLayout(node, .{
                .depth = depth,
                .index = idx,
                .width = node_width,
                .subtree_width = node_width,
                .percentage = percentage,
                .has_children = node.children.len > 0,
            });
            return;
        }

        var children_width: f64 = 0;
        for (effective_children) |*child| {
            try self.measureSubtreeWidth(child, depth + 1, counter, total_samples, node);
            const child_layout = self.getLayout(child);
            children_width += child_layout.subtree_width;
        }
        children_width += @as(f64, @floatFromInt(effective_children.len -| 1)) * self.config.sibling_gap;

        try self.putLayout(node, .{
            .depth = depth,
            .index = idx,
            .width = node_width,
            .subtree_width = @max(node_width, children_width),
            .percentage = percentage,
            .has_children = node.children.len > 0,
        });
    }

    fn assignPositions(self: *StackTrace, node: *const StackNode, x_start: f64, depth: u32, scale: f64) !void {
        const y = @as(f64, @floatFromInt(depth)) * (self.config.node_height + self.config.level_gap);
        var layout = self.getLayout(node);

        layout.x = x_start + (layout.subtree_width * scale - layout.width) / 2.0;
        layout.y = y;
        try self.putLayout(node, layout);

        const is_collapsed = self.collapsed_set.contains(nodeKey(node));
        if (is_collapsed or node.children.len == 0) return;

        var child_x = x_start;
        for (node.children) |*child| {
            try self.assignPositions(child, child_x, depth + 1, scale);
            const child_layout = self.getLayout(child);
            child_x += child_layout.subtree_width * scale + self.config.sibling_gap;
        }
    }

    fn renderTreeEdges(self: *StackTrace, svg: *Svg, node: *const StackNode) !void {
        // Don't render edges to children if collapsed
        if (self.collapsed_set.contains(nodeKey(node))) return;
        if (node.children.len == 0) return;

        const nl = self.getLayout(node);
        const parent_cx = nl.x + nl.width / 2.0;
        const parent_bottom = nl.y + self.config.node_height;

        const has_selection = self.selected != null;

        for (node.children) |*child| {
            const cl = self.getLayout(child);
            const child_cx = cl.x + cl.width / 2.0;
            const child_top = cl.y;

            var pb = path_util.PathBuilder.init(self.allocator);
            defer pb.deinit();

            switch (self.config.edge_style) {
                .straight => {
                    try pb.moveTo(parent_cx, parent_bottom);
                    try pb.lineTo(child_cx, child_top);
                },
                .curved => {
                    const mid_y = (parent_bottom + child_top) / 2.0;
                    try pb.moveTo(parent_cx, parent_bottom);
                    try pb.curveTo(parent_cx, mid_y, child_cx, mid_y, child_cx, child_top - 4);
                },
                .elbow => {
                    const mid_y = (parent_bottom + child_top) / 2.0;
                    try pb.moveTo(parent_cx, parent_bottom);
                    try pb.verticalTo(mid_y);
                    try pb.horizontalTo(child_cx);
                    try pb.verticalTo(child_top);
                },
            }

            const path_d = pb.slice();

            // Weighted stroke width based on child's sample proportion
            const sw = self.edgeWidth(child.samples);
            const stroke_color = self.edgeColor(child.samples);

            // Dim edges not on selected path
            const on_path = self.selected_path.contains(nodeKey(node)) and
                self.selected_path.contains(nodeKey(child));
            const opacity: ?f64 = if (has_selection and !on_path) self.config.dim_opacity else null;

            var id_buf: [64]u8 = undefined;
            const id = try std.fmt.bufPrint(&id_buf, "st-edge-{d}-{d}", .{ nl.index, cl.index });

            // Use raw writer for edges since we need marker-end + custom stroke-width + opacity
            const w = svg;
            try w.print("<path id=\"{s}\" d=\"{s}\" class=\"st-edge\" stroke=\"{s}\" stroke-width=\"{d:.1}\" marker-end=\"url(#st-arrow)\"", .{
                id,
                path_d,
                stroke_color,
                sw,
            });
            if (opacity) |o| {
                try w.print(" opacity=\"{d:.2}\"", .{o});
            }
            try w.appendSlice("/>\n");

            const weight: f64 = blk: {
                const root = self.root orelse break :blk 0;
                const total: f64 = @floatFromInt(root.samples);
                if (total == 0) break :blk 0;
                break :blk @as(f64, @floatFromInt(child.samples)) / total;
            };

            try self.layout_edges.append(.{
                .from_x = parent_cx,
                .from_y = parent_bottom,
                .to_x = child_cx,
                .to_y = child_top,
                .weight = weight,
            });

            try self.renderTreeEdges(svg, child);
        }
    }

    fn renderTreeNodes(self: *StackTrace, svg: *Svg, node: *const StackNode) !void {
        const nl = self.getLayout(node);
        const total_samples: f64 = if (self.root) |r| @floatFromInt(r.samples) else 1;
        const percentage = if (total_samples > 0)
            @as(f64, @floatFromInt(node.samples)) / total_samples * 100.0
        else
            0;

        // Heat-mapped color based on percentage of total samples
        const color = node.color orelse self.heatColor(percentage);

        // Path highlighting: dim nodes not on the selected path
        const has_selection = self.selected != null;
        const on_path = self.selected_path.contains(nodeKey(node));
        const opacity: ?f64 = if (has_selection and !on_path) self.config.dim_opacity else null;

        // Determine CSS class
        const css_class: []const u8 = if (has_selection and on_path)
            "st-node st-highlighted"
        else if (has_selection and !on_path)
            "st-node st-dimmed"
        else
            "st-node";

        var rect_id_buf: [64]u8 = undefined;
        const rect_id = try std.fmt.bufPrint(&rect_id_buf, "st-{d}-node_rect", .{nl.index});

        try svg.rect(nl.x + 2, nl.y + 2, nl.width, self.config.node_height, .{
            .id = rect_id,
            .class = css_class,
            .fill = .palette(.text_color),
            .rx = self.config.node_radius + 2,
            .opacity = opacity,
        });

        try svg.rect(nl.x, nl.y, nl.width, self.config.node_height, .{
            .id = rect_id,
            .class = css_class,
            .fill = color,
            .rx = self.config.node_radius,
            .opacity = opacity,
        });

        try self.rendered_elements.append(.{
            .id = .{ .node_index = nl.index, .element_type = .node_rect },
            .attrs = .{ .rect = .{
                .x = nl.x,
                .y = nl.y,
                .width = nl.width,
                .height = self.config.node_height,
                .fill = color,
                .opacity = opacity,
            } },
        });

        // Function name label — truncate to fit (leave room for percentage)
        const pct_reserved: f64 = if (self.config.show_percentage) 40.0 else 0;
        const available_text_width = nl.width - self.config.node_padding_x * 2 - pct_reserved;
        const max_chars: usize = @intFromFloat(@max(1.0, available_text_width / 7.0));
        const display_name = if (node.name.len > max_chars and max_chars > 3)
            node.name[0 .. max_chars - 2]
        else
            node.name;

        var text_id_buf: [64]u8 = undefined;
        const text_id = try std.fmt.bufPrint(&text_id_buf, "st-{d}-node_text", .{nl.index});

        // Text position: left-aligned if showing percentage, centered otherwise
        const text_x = if (self.config.show_percentage)
            nl.x + self.config.node_padding_x
        else
            nl.x + nl.width / 2.0;

        const text_anchor: Svg.TextAnchor = if (self.config.show_percentage) .start else .middle;

        try svg.text(
            text_x,
            nl.y + self.config.node_height / 2.0,
            display_name,
            .{
                .id = text_id,
                .class = "st-node-text",
                .anchor = text_anchor,
                .dominant_baseline = .middle,
                .font_size = self.config.font_size,
                .fill = .hex("#ffffff"),
            },
        );

        // Percentage label (right-aligned inside node)
        if (self.config.show_percentage) {
            var pct_buf: [16]u8 = undefined;
            const pct_str = try std.fmt.bufPrint(&pct_buf, "{d:.1}%", .{percentage});

            var pct_id_buf: [64]u8 = undefined;
            const pct_id = try std.fmt.bufPrint(&pct_id_buf, "st-{d}-node_pct_text", .{nl.index});

            try svg.text(
                nl.x + nl.width - self.config.node_padding_x,
                nl.y + self.config.node_height / 2.0,
                pct_str,
                .{
                    .id = pct_id,
                    .class = "st-pct-text",
                    .anchor = .end,
                    .dominant_baseline = .middle,
                    .font_size = self.config.percentage_font_size,
                    .fill = .hex("#ffffffaa"),
                },
            );
        }

        // Collapse indicator: small chevron/plus for nodes with children
        if (nl.has_children) {
            const is_collapsed = self.collapsed_set.contains(nodeKey(node));
            const indicator_y = nl.y + self.config.node_height + 2;
            const indicator_x = nl.x + nl.width / 2.0;
            const s = self.config.collapse_indicator_size;

            var indicator_path = path_util.PathBuilder.init(self.allocator);
            defer indicator_path.deinit();

            if (is_collapsed) {
                // "+" icon — small plus sign indicating expandable
                // Horizontal line
                try indicator_path.moveTo(indicator_x - s / 2, indicator_y + s / 2);
                try indicator_path.horizontalTo(indicator_x + s / 2);
                // Vertical line
                try indicator_path.moveTo(indicator_x, indicator_y);
                try indicator_path.verticalTo(indicator_y + s);
            } else {
                // "−" icon — horizontal line indicating collapsible
                try indicator_path.moveTo(indicator_x - s / 2, indicator_y + s / 2);
                try indicator_path.horizontalTo(indicator_x + s / 2);
            }

            var indicator_id_buf: [64]u8 = undefined;
            const indicator_id = try std.fmt.bufPrint(&indicator_id_buf, "st-{d}-collapse", .{nl.index});

            try svg.path(indicator_path.slice(), .{
                .id = indicator_id,
                .class = "st-collapse-icon",
                .stroke = .hex("#888888"),
                .stroke_width = 1.5,
            });
        }

        try self.layout_nodes.append(.{
            .node = node,
            .x = nl.x,
            .y = nl.y,
            .width = nl.width,
            .height = self.config.node_height,
            .depth = nl.depth,
            .color = color,
            .percentage = percentage,
        });

        // Recurse into children (skip if collapsed)
        if (!self.collapsed_set.contains(nodeKey(node))) {
            for (node.children) |*child| {
                try self.renderTreeNodes(svg, child);
            }
        }
    }

    // ============ Flame Graph Layout ============

    fn buildFlame(self: *StackTrace, svg: *Svg, root: *const StackNode) !void {
        const chart_w: f64 = @floatFromInt(self.config.width - self.config.margin.left - self.config.margin.right);
        const total_samples: f64 = @floatFromInt(root.samples);
        if (total_samples == 0) return;

        var counter: u32 = 0;
        try self.renderFlameNode(svg, root, 0, 0, chart_w, total_samples, &counter);
    }

    fn renderFlameNode(
        self: *StackTrace,
        svg: *Svg,
        node: *const StackNode,
        depth: u32,
        x_start: f64,
        available_width: f64,
        total_samples: f64,
        counter: *u32,
    ) !void {
        const idx = counter.*;
        counter.* += 1;

        const node_width = (@as(f64, @floatFromInt(node.samples)) / total_samples) * available_width;
        if (node_width < self.config.flame_min_width) return;

        const y = @as(f64, @floatFromInt(depth)) * self.config.flame_row_height;
        const color = node.color orelse self.flameColor(node, depth);

        var id_buf: [64]u8 = undefined;
        const rect_id = try std.fmt.bufPrint(&id_buf, "st-{d}-flame_rect", .{idx});

        try svg.rect(x_start, y, node_width, self.config.flame_row_height - 1, .{
            .id = rect_id,
            .class = "st-flame",
            .fill = color,
            .rx = 2,
        });

        try self.rendered_elements.append(.{
            .id = .{ .node_index = idx, .element_type = .flame_rect },
            .attrs = .{ .rect = .{
                .x = x_start,
                .y = y,
                .width = node_width,
                .height = self.config.flame_row_height - 1,
                .fill = color,
            } },
        });

        // Label (only if wide enough)
        const char_width: f64 = 7.0;
        const min_label_width = char_width * 3;
        if (node_width > min_label_width + 8) {
            const max_chars: usize = @intFromFloat((node_width - 8) / char_width);
            const display_name = if (node.name.len > max_chars and max_chars > 3)
                node.name[0 .. max_chars - 2]
            else
                node.name;

            var text_id_buf: [64]u8 = undefined;
            const text_id = try std.fmt.bufPrint(&text_id_buf, "st-{d}-flame_text", .{idx});

            try svg.text(
                x_start + 4,
                y + self.config.flame_row_height / 2.0,
                display_name,
                .{
                    .id = text_id,
                    .class = "st-flame-text",
                    .anchor = .start,
                    .dominant_baseline = .middle,
                    .font_size = self.config.font_size,
                    .fill = .hex("#000000"),
                },
            );
        }

        try self.layout_nodes.append(.{
            .node = node,
            .x = x_start,
            .y = y,
            .width = node_width,
            .height = self.config.flame_row_height - 1,
            .depth = depth,
            .color = color,
            .percentage = 0,
        });

        // Children occupy proportional sub-widths
        var child_x = x_start;
        for (node.children) |*child| {
            const child_width = (@as(f64, @floatFromInt(child.samples)) / @as(f64, @floatFromInt(node.samples))) * node_width;
            try self.renderFlameNode(svg, child, depth + 1, child_x, child_width, total_samples, counter);
            child_x += child_width;
        }
    }

    fn flameColor(_: *StackTrace, node: *const StackNode, depth: u32) Vapor.Types.Color {
        var hash: u32 = 0;
        for (node.name) |c| {
            hash = hash *% 31 +% @as(u32, c);
        }
        const warm_colors = [_][]const u8{
            "#e25822", "#e8702a", "#f09030", "#f4a836",
            "#f8c03c", "#ff6b35", "#ff4500", "#ff8c00",
            "#ffa500", "#ffd700", "#e06030", "#d45020",
        };
        const idx = (hash +% depth) % warm_colors.len;
        return Vapor.Types.Color.hex(warm_colors[idx]);
    }

    // ============ Tooltip / Hover ============

    pub fn findNodeAt(self: *StackTrace, mouse_x: f64, mouse_y: f64) ?*const LayoutNode {
        const m = self.config.margin;
        const local_x = mouse_x - @as(f64, @floatFromInt(m.left));
        const local_y = mouse_y - @as(f64, @floatFromInt(m.top));

        var i = self.layout_nodes.items.len;
        while (i > 0) {
            i -= 1;
            const ln = &self.layout_nodes.items[i];
            if (local_x >= ln.x and local_x <= ln.x + ln.width and
                local_y >= ln.y and local_y <= ln.y + ln.height)
            {
                return ln;
            }
        }
        return null;
    }

    pub fn showTooltip(self: *StackTrace, _: *Vapor.Event) void {
        const offsets = self.container.getBoundingClientRect() orelse return;
        self.bounds.offset_x = offsets.left;
        self.bounds.offset_y = offsets.top;

        if (self.tooltip) |*tooltip| {
            tooltip.binded.mutateStyleString("display", "block");
            tooltip.hide = false;
        }
    }

    pub fn updateTooltip(self: *StackTrace, event: *Vapor.Event) void {
        if (Vapor.Kit.throttle(16)) return;
        if (self.tooltip) |*tooltip| {
            const x = event.pageX() - self.bounds.offset_x;
            const y = event.pageY() - self.bounds.offset_y;

            tooltip.left = x;
            tooltip.top = y;

            if (self.findNodeAt(@floatCast(x), @floatCast(y))) |ln| {
                tooltip.binded.mutateStyleString("display", "block");
                const node = ln.node;

                // Update hovered state
                self.hovered_node = node;

                tooltip.name = node.name;
                tooltip.file = node.file orelse "";
                tooltip.line = node.line;
                tooltip.module = node.module orelse "";
                tooltip.samples = node.samples;
                tooltip.self_samples = node.self_samples;
                tooltip.depth = ln.depth;

                if (self.root) |root| {
                    const total: f64 = @floatFromInt(root.samples);
                    if (total > 0) {
                        tooltip.percentage = @as(f64, @floatFromInt(node.samples)) / total * 100.0;
                    }
                }

                _ = tooltip.binded.translate3d(.{ .x = x + 12, .y = y + 12 });
                Vapor.cycle();
            } else {
                tooltip.binded.mutateStyleString("display", "none");
                self.hovered_node = null;
            }
        }
    }

    /// Handle click: select node (highlight path) or toggle collapse
    pub fn handleClick(self: *StackTrace, event: *Vapor.Event) void {
        const x = event.pageX() - self.bounds.offset_x;
        const y = event.pageY() - self.bounds.offset_y;

        if (self.findNodeAt(@floatCast(x), @floatCast(y))) |ln| {
            const node = ln.node;

            // If clicking the already-selected node, deselect
            if (self.selected) |sel| {
                if (nodeKey(sel) == nodeKey(node)) {
                    self.selected = null;
                    self.selected_path.clearRetainingCapacity();
                    self.build() catch {};
                    return;
                }
            }

            // Select this node and rebuild path highlight
            self.selected = node;
            self.rebuildSelectedPath() catch {};
            self.build() catch {};
        } else {
            // Clicked empty space — deselect
            self.selected = null;
            self.selected_path.clearRetainingCapacity();
            self.build() catch {};
        }
    }

    /// Handle double-click: toggle collapse
    pub fn handleDblClick(self: *StackTrace, event: *Vapor.Event) void {
        const x = event.pageX() - self.bounds.offset_x;
        const y = event.pageY() - self.bounds.offset_y;

        if (self.findNodeAt(@floatCast(x), @floatCast(y))) |ln| {
            if (ln.node.children.len > 0) {
                self.toggleCollapse(ln.node);
                self.build() catch {};
            }
        }
    }

    fn hideTooltip(self: *StackTrace, _: *Vapor.Event) void {
        if (self.tooltip) |*tooltip| {
            tooltip.binded.mutateStyleString("display", "none");
            tooltip.hide = true;
        }
        self.hovered_node = null;
    }

    // ============ Diffing / Update ============

    pub fn update(self: *StackTrace) !void {
        for (self.rendered_elements.items, 0..) |new_el, i| {
            if (i < self.old_rendered_elements.items.len) {
                const old_el = self.old_rendered_elements.items[i];
                try self.emitAttributeUpdates(old_el, new_el);
            }
        }
        self.old_rendered_elements.clearRetainingCapacity();
    }

    fn emitAttributeUpdates(self: *StackTrace, old: RenderedElement, new: RenderedElement) !void {
        var id_buf: [64]u8 = undefined;
        const id = try new.id.toString(&id_buf);

        switch (new.attrs) {
            .rect => |r| {
                const old_r = old.attrs.rect;
                if (r.x != old_r.x) {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{r.x});
                    self.platform.browser.setAttribute(id, "x", val);
                }
                if (r.y != old_r.y) {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{r.y});
                    self.platform.browser.setAttribute(id, "y", val);
                }
                if (r.width != old_r.width) {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{r.width});
                    self.platform.browser.setAttribute(id, "width", val);
                }
                if (r.height != old_r.height) {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{r.height});
                    self.platform.browser.setAttribute(id, "height", val);
                }
                if (r.fill) |f| {
                    self.platform.browser.setAttribute(id, "fill", Svg.convertColor(f));
                }
                if (r.opacity) |o| {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{o});
                    self.platform.browser.setAttribute(id, "opacity", val);
                }
            },
            .path => |p| {
                self.platform.browser.setAttribute(id, "d", p.d);
                if (p.stroke) |s| {
                    self.platform.browser.setAttribute(id, "stroke", Svg.convertColor(s));
                }
                if (p.stroke_width) |sw| {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.1}", .{sw});
                    self.platform.browser.setAttribute(id, "stroke-width", val);
                }
                if (p.opacity) |o| {
                    var buf: [32]u8 = undefined;
                    const val = try std.fmt.bufPrint(&buf, "{d:.2}", .{o});
                    self.platform.browser.setAttribute(id, "opacity", val);
                }
            },
        }
    }

    // ============ Rendering (Vapor) ============

    fn mount(self: *StackTrace) void {
        const offsets = self.container.getOffsets() orelse return;
        self.bounds.offset_x = offsets.offset_left;
        self.bounds.offset_y = offsets.offset_top;
        if (self.tooltip) |*tooltip| {
            tooltip.binded.mutateStyleString("display", "none");
        }
    }

    pub fn render(self: *StackTrace) void {
        if (!self.has_data) return;
        Box()
            .width(.px(@floatFromInt(self.config.width)))
            .height(.px(@floatFromInt(self.config.height)))
            .onMount(mount, .{self})
            .children({
            Box()
                .ref(&self.container)
                .pos(.relative)
                .width(.percent(100))
                .height(.percent(100))
                .onEvent(.pointerenter, showTooltip, .{self})
                .onEvent(.pointerleave, hideTooltip, .{self})
                .onEvent(.pointermove, updateTooltip, .{self})
                .onEvent(.click, handleClick, .{self})
                .onEvent(.dblclick, handleDblClick, .{self})
                .children({
                if (self.tooltip) |*tooltip| {
                    Box()
                        .ref(&tooltip.binded)
                        .pos(.absolute)
                        .width(.px(240))
                        .padding(.xy(10, 8))
                        .layout(.top_left)
                        .direction(.column)
                        .background(.hex("#1e1e2e"))
                        .border(.round(.hex("#333346"), .all(1)))
                        // .shadow(.glow(8, .transparentizeHex(.hex("#000000"), 0.3)))
                        .zIndex(1000)
                        .children({
                        // Name
                        Text(tooltip.name)
                            .inlineStyle("user-select: none; font-weight: 600; font-family: 'JetBrains Mono', monospace;", .{})
                            .font(12, 600, .hex("#cdd6f4")).end();

                        // File:line
                        if (tooltip.file.len > 0) {
                            Box().layout(.left_center).spacing(0).children({
                                Text(tooltip.file)
                                    .inlineStyle("user-select: none;", .{})
                                    .font(10, 400, .hex("#6c7086")).end();
                                if (tooltip.line) |line| {
                                    Text(":")
                                        .inlineStyle("user-select: none;", .{})
                                        .font(10, 400, .hex("#6c7086")).end();
                                    Vapor.Number(line)
                                        .inlineStyle("user-select: none;", .{})
                                        .font(10, 400, .hex("#6c7086")).end();
                                }
                            });
                        }

                        // Module
                        if (tooltip.module.len > 0) {
                            Box().layout(.x_between_center).children({
                                Text("Module")
                                    .inlineStyle("user-select: none;", .{})
                                    .font(10, 400, .hex("#585b70")).end();
                                Text(tooltip.module)
                                    .inlineStyle("user-select: none;", .{})
                                    .font(10, 400, .hex("#a6adc8")).end();
                            });
                        }

                        // Divider
                        Vapor.Spacer(1)
                            .width(.percent(100))
                            .background(.hex("#333346"))
                            .end();

                        // Samples
                        Box().layout(.x_between_center).children({
                            Text("Samples")
                                .inlineStyle("user-select: none;", .{})
                                .font(11, 400, .hex("#a6adc8")).end();
                            Vapor.Number(tooltip.samples)
                                .inlineStyle("user-select: none; font-variant-numeric: tabular-nums;", .{})
                                .font(11, 500, .hex("#cdd6f4")).end();
                        });

                        // Self samples
                        if (tooltip.self_samples > 0) {
                            Box().layout(.x_between_center).children({
                                Text("Self")
                                    .inlineStyle("user-select: none;", .{})
                                    .font(11, 400, .hex("#a6adc8")).end();
                                Vapor.Number(tooltip.self_samples)
                                    .inlineStyle("user-select: none; font-variant-numeric: tabular-nums;", .{})
                                    .font(11, 500, .hex("#cdd6f4")).end();
                            });
                        }

                        // Percentage
                        Box().layout(.x_between_center).children({
                            Text("% Total")
                                .inlineStyle("user-select: none;", .{})
                                .font(11, 400, .hex("#a6adc8")).end();
                            Vapor.Number(tooltip.percentage)
                                .inlineStyle("user-select: none; font-variant-numeric: tabular-nums;", .{})
                                .font(11, 600, .hex("#f38ba8")).end();
                        });

                        // Depth
                        Box().layout(.x_between_center).children({
                            Text("Depth")
                                .inlineStyle("user-select: none;", .{})
                                .font(10, 400, .hex("#585b70")).end();
                            Vapor.Number(tooltip.depth)
                                .inlineStyle("user-select: none; font-variant-numeric: tabular-nums;", .{})
                                .font(10, 400, .hex("#585b70")).end();
                        });
                    });
                } else {
                    Vapor.Null();
                }

                if (self.current_svg) |svg_content| {
                    Vapor.Svg(.{ .svg = svg_content, .override = true })
                        .end();
                } else {
                    Vapor.Null();
                }
            });
        });
    }
};
