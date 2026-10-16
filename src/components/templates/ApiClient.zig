// =============================================================================
// API CLIENT - MINIMAL TEMPLATE
// =============================================================================
// A single-file REST API client component with:
//   - Method selector (GET/POST/PUT/DELETE/PATCH)
//   - URL input field
//   - Request body editor (JSON) with syntax highlighting
//   - Headers editor (key/value pairs)
//   - Response viewer with dummy data (no real backend calls)
//
// USAGE:
//   1. Import your existing JsonEditor + json_syntax_highlighter
//   2. Call ApiClient.init() at startup
//   3. Call ApiClient.render() in your render loop
//   4. Replace `submitRequest()` with real fetch logic when ready
// =============================================================================

const std = @import("std");
const Vapor = @import("vapor");

const Box = Vapor.Box;
const Stack = Vapor.Stack;
const Text = Vapor.Text;
const Icon = Vapor.Icon;
const TextFmt = Vapor.TextFmt;
const ButtonCtx = Vapor.Button;

// ── Component Imports (adjust paths to your project) ─────────────────
const Opaque = @import("../../components/Opaque.zig");
const Select = Opaque.Select;
const Tabs = Opaque.Tabs;
const Field = Opaque.Field;
const JsonEditor = @import("JsonEditor.zig");

const ApiClient = @This();

// =============================================================================
// TYPES
// =============================================================================

pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,

    pub fn label(self: Method) []const u8 {
        return @tagName(self);
    }

    pub fn color(self: Method) Vapor.Types.Color {
        return switch (self) {
            .GET => .hex("#10b981"),
            .POST => .hex("#3b82f6"),
            .PUT => .hex("#f59e0b"),
            .DELETE => .hex("#ef4444"),
            .PATCH => .hex("#8b5cf6"),
        };
    }
};

pub const Header = struct {
    key: []const u8 = "",
    value: []const u8 = "",
    enabled: bool = true,
};

pub const ResponseHeader = struct {
    key: []const u8,
    value: []const u8,
};

pub const ResponseData = struct {
    status_code: u32 = 0,
    body: []const u8 = "",
    headers: []const ResponseHeader = &.{},
    elapsed_ms: i64 = 0,
    size_bytes: usize = 0,
};

// =============================================================================
// STATE
// =============================================================================

// ── Request ──
var url: []const u8 = "";
var method: Method = .GET;
var body_editor: JsonEditor = undefined;
var headers: std.ArrayListUnmanaged(Header) = .{};
var allocator: std.mem.Allocator = undefined;

// ── Response ──
var response: ?ResponseData = null;
var requesting: bool = false;

// ── UI ──
var method_select: Select(Method) = undefined;
var req_tab_index: usize = 0;
var res_tab_index: usize = 0;

// =============================================================================
// INIT
// =============================================================================

pub fn init() void {
    allocator = Vapor.arena(.persist);

    // Body editor
    body_editor = JsonEditor.init();
    body_editor.setTextAutoFmt(
        \\{
        \\  "name": "hello",
        \\  "value": 42
        \\}
    );

    // Method dropdown
    method_select = Select(Method).fromItems(&.{
        .{ .value = .GET, .label = "GET" },
        .{ .value = .POST, .label = "POST" },
        .{ .value = .PUT, .label = "PUT" },
        .{ .value = .DELETE, .label = "DELETE" },
        .{ .value = .PATCH, .label = "PATCH" },
    });
    method_select.trigger = "GET";
    method_select.border = .sharp(.all(1), .palette(.border_color_light));
    method_select.selected_border = .sharp(.all(1), .palette(.tint));
    method_select.shadow = .{ .color = .transparent };
    method_select.on_select = onMethodSelect;
}

// =============================================================================
// ACTIONS
// =============================================================================

fn onMethodSelect(_: *Select(Method), item: *Select(Method).Item) void {
    method = item.value;
}

fn onUrlChange(evt: *Vapor.Event) void {
    url = Vapor.arena(.persist).dupe(u8, evt.text()) catch return;
}

fn onBodyChange(_: *Vapor.Event) void {
    // body_editor.text holds the current body content
}

fn addHeader() void {
    headers.append(allocator, .{}) catch return;
}

fn removeHeader(idx: usize) void {
    _ = headers.orderedRemove(idx);
}

fn toggleHeader(idx: usize) void {
    headers.items[idx].enabled = !headers.items[idx].enabled;
}

// =============================================================================
// SUBMIT (DUMMY DATA)
// =============================================================================
// Replace this function with real fetch logic when connecting to a backend.

fn submitRequest() void {
    if (url.len == 0) return;

    requesting = true;

    // ── Simulate a response ──────────────────────────────────────────
    // In production, replace this block with:
    //   const fetch = Vapor.Kit.Fetch.fetch;
    //   fetch(url, .{ .method = ... }).handle(handleResponse);

    response = .{
        .status_code = 200,
        .elapsed_ms = 42,
        .body =
        \\{
        \\  "id": 1,
        \\  "message": "Success",
        \\  "data": {
        \\    "items": [
        \\      { "name": "Alpha", "value": 100 },
        \\      { "name": "Beta",  "value": 200 }
        \\    ],
        \\    "total": 2
        \\  }
        \\}
        ,
        .headers = &.{
            .{ .key = "content-type", .value = "application/json; charset=utf-8" },
            .{ .key = "x-request-id", .value = "abc-123-def-456" },
            .{ .key = "cache-control", .value = "no-cache" },
        },
        .size_bytes = 186,
    };

    requesting = false;
}

// =============================================================================
// HELPERS
// =============================================================================

fn statusColor() Vapor.Types.Color {
    if (response) |r| {
        if (r.status_code >= 200 and r.status_code < 300) return .hex("#10b981");
        if (r.status_code >= 300 and r.status_code < 400) return .hex("#f59e0b");
        if (r.status_code >= 400) return .hex("#ef4444");
    }
    return .palette(.text_color);
}

fn formatSize() []const u8 {
    if (response) |r| {
        if (r.size_bytes < 1024) return Vapor.fmtArena("{d} B", .{r.size_bytes}, .frame);
        const kb = @as(f32, @floatFromInt(r.size_bytes)) / 1024.0;
        return Vapor.fmtArena("{d:.1} KB", .{kb}, .frame);
    }
    return "0 B";
}

fn formatTiming() []const u8 {
    if (response) |r| {
        if (r.elapsed_ms < 1000) return Vapor.fmtArena("{d} ms", .{r.elapsed_ms}, .frame);
        const secs = @as(f32, @floatFromInt(r.elapsed_ms)) / 1000.0;
        return Vapor.fmtArena("{d:.2} s", .{secs}, .frame);
    }
    return "0 ms";
}

// =============================================================================
// FIELD COMPONENT (URL input styling)
// =============================================================================

fn UrlFieldComp(field: *Field) Vapor.Builder(.pure) {
    return Stack()
        .width(.percent(100))
        .spacing(8)
        .pos(.relative)
        .height(.px(36))
        .border(.sharp(.all(1), if (field.is_focused) .palette(.tint) else .palette(.border_color_light)))
        .background(field.background);
}

fn HeaderFieldComp(field: *Field) Vapor.Builder(.pure) {
    return Stack()
        .width(.percent(100))
        .spacing(8)
        .pos(.relative)
        .height(.px(32))
        .border(.sharp(.all(1), if (field.is_focused) .palette(.tint) else .palette(.border_color_light)))
        .background(field.background);
}

// =============================================================================
// TAB BUTTONS
// =============================================================================

fn TabButton(_: *Tabs, name: []const u8, is_active: bool) void {
    Box()
        .inlineStyle("min-width: 60px;", .{})
        .layout(.center)
        .children({
        TextFmt("{{{s}}}", .{Vapor.utils.toLowerCase(name, .frame)})
            .pointer()
            .fontFamily("IBM Plex Sans,monospace")
            .font(14, 300, if (is_active) .palette(.text_color) else .hex("#71717a"))
            .end();
    });
}

// =============================================================================
// RENDER - HEADERS EDITOR
// =============================================================================

fn renderHeaders() void {
    Stack()
        .width(.percent(100))
        .height(.expand)
        .padding(.all(12))
        .spacing(8)
        .scroll(.scrollY())
        .children({

        // Column labels
        if (headers.items.len > 0) {
            Box()
                .width(.percent(100))
                .spacing(8)
                .children({
                Box().width(.percent(35)).children({
                    Text("Key").font(12, 300, .palette(.text_color)).end();
                });
                Box().width(.percent(35)).children({
                    Text("Value").font(12, 300, .palette(.text_color)).end();
                });
            });
        }

        // Header rows
        for (headers.items, 0..) |*header, hi| {
            Box()
                .width(.percent(100))
                .spacing(8)
                .layout(.left_center)
                .children({
                Box().width(.percent(35)).children({
                    Field.create(.{
                        .label = "Key",
                        .value = .{ .string = &header.key },
                    }).Component(HeaderFieldComp);
                });
                Box().width(.percent(35)).children({
                    Field.create(.{
                        .label = "Value",
                        .value = .{ .string = &header.value },
                    }).Component(HeaderFieldComp);
                });

                // Toggle
                ButtonCtx(toggleHeader, .{hi})
                    .size(.squarePx(28))
                    .pointer()
                    .layout(.center)
                    .textColor(if (header.enabled) .hex("#10b981") else .palette(.border_color_light))
                    .hover(.{ .text_color = .palette(.tint) })
                    .children({
                    Icon(if (header.enabled) .check_circle else .circle)
                        .fontSize(14)
                        .end();
                });

                // Remove
                ButtonCtx(removeHeader, .{hi})
                    .size(.squarePx(28))
                    .pointer()
                    .layout(.center)
                    .textColor(.palette(.text_color))
                    .hover(.{ .text_color = .hex("#ef4444") })
                    .children({
                    Icon(.x_lg).fontSize(12).end();
                });
            });
        }

        // Add header button
        ButtonCtx(addHeader, .{})
            .padding(.xy(8, 4))
            .border(.thin(.palette(.border_color_light)))
            .pointer()
            .textColor(.palette(.text_color))
            .hover(.{ .background = .palette(.tint), .text_color = .palette(.background) })
            .children({
            Box().layout(.left_center).spacing(4).children({
                Icon(.plus).fontSize(12).end();
                Text("Add Header")
                    .fontSize(12)
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
            });
        });
    });
}

// =============================================================================
// RENDER - RESPONSE PANEL
// =============================================================================

fn renderResponse() void {
    Stack()
        .width(.percent(100))
        .height(.expand)
        .children({

        // Response header bar
        Box()
            .width(.percent(100))
            .height(.px(40))
            .layout(.x_between_center)
            .border(.bottom(1, .palette(.border_color_light)))
            .padding(.horizontal(16))
            .children({

            // Left: tabs
            Box().layout(.left_center).spacing(16).children({
                Text("Response").font(16, 100, .palette(.text_color)).end();
                res_tab_index = Tabs.create("res-tabs", &.{ "Body", "Headers" })
                    .Trigger(TabButton);
            });

            // Right: status badges
            if (response) |r| {
                Box().layout(.right_center).spacing(12).children({
                    Box()
                        .padding(.xy(6, 2))
                        .background(.{ .color = statusColor() })
                        .radius(.all(2))
                        .children({
                        TextFmt("{d}", .{r.status_code})
                            .font(12, 600, .hex("#ffffff"))
                            .fontFamily("IBM Plex Mono,monospace")
                            .end();
                    });
                    Text(formatTiming())
                        .font(12, 300, .palette(.text_color))
                        .fontFamily("IBM Plex Mono,monospace")
                        .end();
                    Text(formatSize())
                        .font(12, 300, .palette(.text_color))
                        .fontFamily("IBM Plex Mono,monospace")
                        .end();
                });
            }
        });

        // Response content
        Box()
            .width(.percent(100))
            .height(.expand)
            .children({
            if (requesting) {
                Box().width(.percent(100)).height(.expand).layout(.center).children({
                    Text("Sending...").font(14, 300, .palette(.text_color)).end();
                });
            } else if (response != null) {
                switch (res_tab_index) {
                    0 => renderResponseBody(),
                    1 => renderResponseHeaders(),
                    else => {},
                }
            } else {
                // Empty state
                Box().width(.percent(100)).height(.expand).layout(.center).children({
                    Stack().spacing(8).layout(.center).children({
                        Icon(.send).font(32, 300, .palette(.border_color_light)).end();
                        Text("Send a request to see the response")
                            .font(14, 300, .palette(.text_color))
                            .end();
                    });
                });
            }
        });
    });
}

fn renderResponseBody() void {
    const resp = response orelse return;
    Box()
        .width(.percent(100))
        .height(.expand)
        .scroll(.scrollY())
        .padding(.all(12))
        .children({
        Text(resp.body)
            .width(.percent(100))
            .height(.expand)
            .fontFamily("IBM Plex Mono,monospace")
            .font(13, 300, .palette(.text_color))
            .background(.transparent)
            .end();
    });
}

fn renderResponseHeaders() void {
    const resp = response orelse return;
    Stack()
        .width(.percent(100))
        .height(.expand)
        .padding(.all(12))
        .spacing(4)
        .scroll(.scrollY())
        .children({
        if (resp.headers.len == 0) {
            Text("No headers").font(14, 300, .palette(.text_color)).end();
        }
        for (resp.headers) |header| {
            Box()
                .width(.percent(100))
                .spacing(8)
                .layout(.left_center)
                .padding(.xy(0, 4))
                .border(.bottom(1, .palette(.border_color_light)))
                .children({
                Text(header.key)
                    .font(13, 500, .palette(.tint))
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
                Text(header.value)
                    .font(13, 300, .palette(.text_color))
                    .fontFamily("IBM Plex Mono,monospace")
                    .end();
            });
        }
    });
}

// =============================================================================
// MAIN RENDER
// =============================================================================

pub fn render() void {
    Stack()
        .width(.percent(100))
        .height(.percent(100))
        .scroll(.none())
        .children({

        // ── URL Bar: [Method] [URL] [Send] ──────────────────────────
        Box()
            .width(.percent(100))
            .padding(.xy(16, 8))
            .spacing(8)
            .layout(.left_center)
            .border(.bottom(1, .palette(.border_color_light)))
            .children({

            // Method dropdown
            Box().width(.px(100)).children({
                method_select.render();
            });

            // URL input
            Box().width(.expand).children({
                Field.create(.{
                    .label = "URL",
                    .value = .{ .string = &url },
                    .on_change = onUrlChange,
                    .placeholder = .{ .string = "https://api.example.com/v1/..." },
                }).Component(UrlFieldComp);
            });

            // Send button
            ButtonCtx(submitRequest, .{})
                .height(.px(36))
                .padding(.xy(16, 0))
                .background(.palette(.tint))
                .duration(100)
                .pointer()
                .layout(.center)
                .hover(.{ .background = .hex("#222160"), .text_color = .white })
                .children({
                Box().layout(.left_center).spacing(6).children({
                    Icon(.send).font(14, 300, .palette(.background)).end();
                    Text("Send")
                        .font(14, 300, .palette(.background))
                        .fontFamily("IBM Plex Sans,monospace")
                        .end();
                });
            });
        });

        // ── Request Tabs: Body | Headers ────────────────────────────
        Box()
            .width(.percent(100))
            .padding(.xy(16, 8))
            .layout(.x_between_center)
            .border(.bottom(1, .palette(.border_color_light)))
            .children({
            req_tab_index = Tabs.create("req-body-tabs", &.{ "Body", "Headers" })
                .Trigger(TabButton);
        });

        // ── Request Body / Headers Content ──────────────────────────
        switch (req_tab_index) {
            0 => {
                Box()
                    .width(.percent(100))
                    .height(.percent(40))
                    .children({
                    body_editor.on_change = onBodyChange;
                    body_editor.render();
                });
            },
            1 => {
                Box()
                    .width(.percent(100))
                    .height(.percent(40))
                    .children({
                    renderHeaders();
                });
            },
            else => {},
        }

        // ── Response Panel ──────────────────────────────────────────
        renderResponse();
    });
}
