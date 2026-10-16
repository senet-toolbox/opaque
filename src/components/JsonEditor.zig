const std = @import("std");
const Vapor = @import("vapor");
const Row = Vapor.Row;
const Text = Vapor.Text;
const TextArea = Vapor.TextArea;
const Icon = Vapor.Icon;
const ArrayList = Vapor.Array;

const JsonEditor = @This();

// ============================================================================
// Types
// ============================================================================

const TokenType = enum {
    string_key,
    string_value,
    number,
    boolean,
    null_literal,
    punctuation,
    whitespace,
    newline,
    comment,
    invalid,
};

const Token = struct {
    type: TokenType,
    text: []const u8,
    line: usize,
    column: usize,
};

const AutoClosePair = struct { open: u8, close: u8 };

const auto_close_pairs = [_]AutoClosePair{
    .{ .open = '{', .close = '}' },
    .{ .open = '[', .close = ']' },
    .{ .open = '"', .close = '"' },
};

const LineBounds = struct { start: usize, end: usize };

// ============================================================================
// State
// ============================================================================

/// Dynamic backing buffer — replaces the old fixed [8192]u8.
text_buffer: ArrayList(u8) = undefined,
text: []const u8 = "",
on_change: ?*const fn (evt: *Vapor.Event) void = null,

indent_buffer: [8192]u8 = undefined,
new_cursor_pos: usize = 0,

// Tokenized lines for rendering
token_lines: ?[][]Token = null,

// Bindings
editor_container: Vapor.Element = .{},
text_area: Vapor.Element = .{},
highlighter_layer: Vapor.Element = .{},

// Key state
holding_meta: bool = false,
holding_shift: bool = false,

// Layout constants
line_height: f32 = 22.5,

// ============================================================================
// Init
// ============================================================================

pub fn init() JsonEditor {
    var editor = JsonEditor{};
    editor.text_buffer = ArrayList(u8).init(Vapor.lib.allocator_global);
    editor.text = editor.text_buffer.items; // empty slice
    return editor;
}

// ============================================================================
// Buffer Management (follows SQL editor pattern)
// ============================================================================

/// Central function that every text mutation goes through.
/// Copies `new_text` into the dynamic ArrayList and points `self.text` at it.
pub fn setText(self: *JsonEditor, new_text: []const u8) void {
    self.text_buffer.clearRetainingCapacity();
    self.text_buffer.appendSlice(new_text) catch {
        std.log.err("JsonEditor: failed to allocate text buffer for {d} bytes", .{new_text.len});
        return;
    };
    self.text = self.text_buffer.items;
}

// ============================================================================
// Public Text Setters
// ============================================================================

pub fn setTextDirect(self: *JsonEditor, raw: []const u8) void {
    self.setText(raw);
    self.tokenize();
}

pub fn setTextFormatted(self: *JsonEditor, raw: []const u8) void {
    const formatted = formatJson(raw);
    self.setText(formatted);
    self.tokenize();
}

// ============================================================================
// Tokenizer (minimal JSON lexer)
// ============================================================================

fn tokenize(self: *JsonEditor) void {
    const alloc = Vapor.arena(.persist);
    var lines = ArrayList([]Token).init(alloc);
    var current_line = ArrayList(Token).init(alloc);

    var pos: usize = 0;
    var line: usize = 1;
    var col: usize = 1;
    var expect_key = false;
    var depth_is_object = ArrayList(bool).init(alloc);

    while (pos < self.text.len) {
        const c = self.text[pos];
        const start = pos;
        const start_line = line;
        const start_col = col;

        // Newline
        if (c == '\n') {
            lines.append(current_line.toOwnedSlice() catch unreachable) catch unreachable;
            current_line = ArrayList(Token).init(alloc);
            pos += 1;
            line += 1;
            col = 1;
            continue;
        }

        // Whitespace
        if (c == ' ' or c == '\t' or c == '\r') {
            while (pos < self.text.len and (self.text[pos] == ' ' or self.text[pos] == '\t' or self.text[pos] == '\r')) {
                pos += 1;
                col += 1;
            }
            current_line.append(.{ .type = .whitespace, .text = self.text[start..pos], .line = start_line, .column = start_col }) catch unreachable;
            continue;
        }

        // Single-line comment
        if (c == '/' and pos + 1 < self.text.len and self.text[pos + 1] == '/') {
            while (pos < self.text.len and self.text[pos] != '\n') {
                pos += 1;
                col += 1;
            }
            current_line.append(.{ .type = .comment, .text = self.text[start..pos], .line = start_line, .column = start_col }) catch unreachable;
            continue;
        }

        // String
        if (c == '"') {
            pos += 1;
            col += 1;
            while (pos < self.text.len and self.text[pos] != '\n') {
                if (self.text[pos] == '\\' and pos + 1 < self.text.len) {
                    pos += 2;
                    col += 2;
                    continue;
                }
                if (self.text[pos] == '"') {
                    pos += 1;
                    col += 1;
                    break;
                }
                pos += 1;
                col += 1;
            }
            const tt: TokenType = if (expect_key) .string_key else .string_value;
            if (expect_key) expect_key = false;
            current_line.append(.{ .type = tt, .text = self.text[start..pos], .line = start_line, .column = start_col }) catch unreachable;
            continue;
        }

        // Number
        if (std.ascii.isDigit(c) or (c == '-' and pos + 1 < self.text.len and std.ascii.isDigit(self.text[pos + 1]))) {
            if (c == '-') {
                pos += 1;
                col += 1;
            }
            while (pos < self.text.len and (std.ascii.isDigit(self.text[pos]) or self.text[pos] == '.' or self.text[pos] == 'e' or self.text[pos] == 'E' or self.text[pos] == '+' or self.text[pos] == '-')) {
                if ((self.text[pos] == '+' or self.text[pos] == '-') and pos > start + 1 and self.text[pos - 1] != 'e' and self.text[pos - 1] != 'E') break;
                pos += 1;
                col += 1;
            }
            current_line.append(.{ .type = .number, .text = self.text[start..pos], .line = start_line, .column = start_col }) catch unreachable;
            continue;
        }

        // Boolean / null
        if (c == 't' or c == 'f' or c == 'n') {
            const rest = self.text[pos..];
            if (std.mem.startsWith(u8, rest, "true") and (rest.len == 4 or !std.ascii.isAlphanumeric(rest[4]))) {
                pos += 4;
                col += 4;
                current_line.append(.{ .type = .boolean, .text = self.text[start..pos], .line = start_line, .column = start_col }) catch unreachable;
                continue;
            }
            if (std.mem.startsWith(u8, rest, "false") and (rest.len == 5 or !std.ascii.isAlphanumeric(rest[5]))) {
                pos += 5;
                col += 5;
                current_line.append(.{ .type = .boolean, .text = self.text[start..pos], .line = start_line, .column = start_col }) catch unreachable;
                continue;
            }
            if (std.mem.startsWith(u8, rest, "null") and (rest.len == 4 or !std.ascii.isAlphanumeric(rest[4]))) {
                pos += 4;
                col += 4;
                current_line.append(.{ .type = .null_literal, .text = self.text[start..pos], .line = start_line, .column = start_col }) catch unreachable;
                continue;
            }
            // Invalid word
            while (pos < self.text.len and (std.ascii.isAlphanumeric(self.text[pos]) or self.text[pos] == '_')) {
                pos += 1;
                col += 1;
            }
            current_line.append(.{ .type = .invalid, .text = self.text[start..pos], .line = start_line, .column = start_col }) catch unreachable;
            continue;
        }

        // Punctuation
        if (c == '{' or c == '}' or c == '[' or c == ']' or c == ',' or c == ':') {
            pos += 1;
            col += 1;
            switch (c) {
                '{' => {
                    depth_is_object.append(true) catch unreachable;
                    expect_key = true;
                },
                '[' => {
                    depth_is_object.append(false) catch unreachable;
                    expect_key = false;
                },
                '}', ']' => {
                    if (depth_is_object.items.len > 0) _ = depth_is_object.pop();
                    expect_key = false;
                },
                ',' => {
                    expect_key = depth_is_object.items.len > 0 and depth_is_object.items[depth_is_object.items.len - 1];
                },
                ':' => {
                    expect_key = false;
                },
                else => {},
            }
            current_line.append(.{ .type = .punctuation, .text = self.text[start..pos], .line = start_line, .column = start_col }) catch unreachable;
            continue;
        }

        // Invalid character
        pos += 1;
        col += 1;
        current_line.append(.{ .type = .invalid, .text = self.text[start..pos], .line = start_line, .column = start_col }) catch unreachable;
    }

    // Push last line
    lines.append(current_line.toOwnedSlice() catch unreachable) catch unreachable;
    self.token_lines = lines.toOwnedSlice() catch unreachable;
}

// ============================================================================
// JSON Formatter
// ============================================================================

fn formatJson(input: []const u8) []const u8 {
    var result = ArrayList(u8).init(Vapor.arena(.persist));
    var indent: usize = 0;
    const tab = "  ";
    var in_str = false;
    var esc = false;
    var i: usize = 0;

    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (esc) {
            result.append(c) catch unreachable;
            esc = false;
            continue;
        }
        if (c == '\\' and in_str) {
            result.append(c) catch unreachable;
            esc = true;
            continue;
        }
        if (c == '"') {
            in_str = !in_str;
            result.append(c) catch unreachable;
            continue;
        }
        if (in_str) {
            result.append(c) catch unreachable;
            continue;
        }
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') continue;

        switch (c) {
            '{', '[' => {
                result.append(c) catch unreachable;
                const next = skipWs(input, i + 1);
                const close: u8 = if (c == '{') '}' else ']';
                if (next < input.len and input[next] == close) {
                    result.append(close) catch unreachable;
                    i = next;
                } else {
                    indent += 1;
                    result.append('\n') catch unreachable;
                    for (0..indent) |_| result.appendSlice(tab) catch unreachable;
                }
            },
            '}', ']' => {
                indent -|= 1;
                result.append('\n') catch unreachable;
                for (0..indent) |_| result.appendSlice(tab) catch unreachable;
                result.append(c) catch unreachable;
            },
            ':' => result.appendSlice(": ") catch unreachable,
            ',' => {
                result.append(',') catch unreachable;
                result.append('\n') catch unreachable;
                for (0..indent) |_| result.appendSlice(tab) catch unreachable;
            },
            else => result.append(c) catch unreachable,
        }
    }
    return result.items;
}

fn skipWs(input: []const u8, start: usize) usize {
    var p = start;
    while (p < input.len and (input[p] == ' ' or input[p] == '\t' or input[p] == '\n' or input[p] == '\r')) : (p += 1) {}
    return p;
}

// ============================================================================
// Event Handlers
// ============================================================================

fn onChange(self: *JsonEditor, evt: *Vapor.Event) void {
    const new_text = evt.text();
    // Sync the ArrayList buffer with whatever the DOM textarea contains
    self.text_buffer.clearRetainingCapacity();
    self.text_buffer.appendSlice(new_text) catch {};
    self.text = self.text_buffer.items;
    self.tokenize();
    if (self.on_change) |cb| cb(evt);
}

fn onKeyDown(self: *JsonEditor, evt: *Vapor.Event) void {
    const key = evt.key();

    if (std.mem.eql(u8, key, "Enter")) {
        evt.preventDefault();
        self.handleEnter();
    } else if (std.mem.eql(u8, key, "Tab")) {
        evt.preventDefault();
        self.handleTab(evt.shiftKey());
    } else if (std.mem.eql(u8, key, "Meta")) {
        self.holding_meta = true;
    } else if (std.mem.eql(u8, key, "Shift")) {
        self.holding_shift = true;
    } else if (key.len == 1 and getClosing(key[0]) != null) {
        evt.preventDefault();
        self.insertPair(key[0], getClosing(key[0]).?);
    } else if (key.len == 1 and isClosing(key[0]) and key[0] != '"') {
        if (self.skipClosing(key[0])) {
            evt.preventDefault();
            return;
        }
    } else if (std.mem.eql(u8, key, "Backspace")) {
        if (self.deletePair()) {
            evt.preventDefault();
            return;
        }
    }
}

fn onKeyUp(self: *JsonEditor, evt: *Vapor.Event) void {
    const key = evt.key();
    if (std.mem.eql(u8, key, "Meta")) self.holding_meta = false;
    if (std.mem.eql(u8, key, "Shift")) self.holding_shift = false;
}

fn onBlur(self: *JsonEditor, _: *Vapor.Event) void {
    self.holding_meta = false;
    self.holding_shift = false;
}

fn onScroll(self: *JsonEditor, _: *Vapor.Event) void {
    const scroll_top = self.text_area.scrollTop();
    self.highlighter_layer.scrollToTop(scroll_top);
}

// ============================================================================
// Auto-close Pairs
// ============================================================================

fn getClosing(c: u8) ?u8 {
    for (auto_close_pairs) |p| {
        if (p.open == c) return p.close;
    }
    return null;
}

fn isClosing(c: u8) bool {
    for (auto_close_pairs) |p| {
        if (p.close == c) return true;
    }
    return false;
}

fn insertPair(self: *JsonEditor, open: u8, close: u8) void {
    const cur = self.text_area.cursorPosition();
    const sel = self.text_area.selection() orelse return;

    if (sel.start != sel.end) {
        const wrapped = std.fmt.allocPrint(Vapor.arena(.frame), "{c}{s}{c}", .{ open, self.text[sel.start..sel.end], close }) catch unreachable;
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..sel.start], wrapped, self.text[sel.end..] }) catch unreachable;
        self.setText(total);
        self.new_cursor_pos = sel.start + wrapped.len;
    } else {
        // For quotes: if next char is same quote, just skip over it
        if (open == close and cur < self.text.len and self.text[cur] == close) {
            self.new_cursor_pos = cur + 1;
            Vapor.onLayout(setCursor, .{self});
            return;
        }
        const pair = std.fmt.allocPrint(Vapor.arena(.frame), "{c}{c}", .{ open, close }) catch unreachable;
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..cur], pair, self.text[cur..] }) catch unreachable;
        self.setText(total);
        self.new_cursor_pos = cur + 1;
    }
    self.tokenize();
    Vapor.onLayout(setCursor, .{self});
}

fn skipClosing(self: *JsonEditor, close: u8) bool {
    const cur = self.text_area.cursorPosition();
    if (cur < self.text.len and self.text[cur] == close) {
        self.new_cursor_pos = cur + 1;
        Vapor.onLayout(setCursor, .{self});
        return true;
    }
    return false;
}

fn deletePair(self: *JsonEditor) bool {
    const cur = self.text_area.cursorPosition();
    if (cur == 0 or cur >= self.text.len) return false;
    const before = self.text[cur - 1];
    const after = self.text[cur];
    for (auto_close_pairs) |p| {
        if (before == p.open and after == p.close) {
            const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}", .{ self.text[0 .. cur - 1], self.text[cur + 1 ..] }) catch unreachable;
            self.setText(total);
            self.new_cursor_pos = cur - 1;
            self.tokenize();
            Vapor.onLayout(setCursor, .{self});
            return true;
        }
    }
    return false;
}

// ============================================================================
// Enter / Tab
// ============================================================================

fn handleEnter(self: *JsonEditor) void {
    const cur = self.text_area.cursorPosition();
    const ls = if (std.mem.lastIndexOf(u8, self.text[0..cur], "\n")) |p| p + 1 else 0;
    const line = self.text[ls..cur];

    var indent: usize = 0;
    for (line) |ch| {
        if (ch == ' ' or ch == '\t') indent += 1 else break;
    }

    var extra: usize = 0;
    const trimmed = std.mem.trim(u8, line, " \t");
    if (std.mem.endsWith(u8, trimmed, "{") or std.mem.endsWith(u8, trimmed, "[")) extra = 2;

    const total_indent = @min(indent + extra, self.indent_buffer.len);
    @memset(self.indent_buffer[0..total_indent], ' ');

    const char_before = if (cur > 0) self.text[cur - 1] else @as(u8, 0);
    const char_after = if (cur < self.text.len) self.text[cur] else @as(u8, 0);
    const between = (char_before == '{' and char_after == '}') or (char_before == '[' and char_after == ']');

    if (between) {
        const closing_indent = @min(indent, self.indent_buffer.len - total_indent);
        @memset(self.indent_buffer[total_indent .. total_indent + closing_indent], ' ');
        const ins = std.fmt.allocPrint(Vapor.arena(.frame), "\n{s}\n{s}", .{
            self.indent_buffer[0..total_indent],
            self.indent_buffer[0..indent],
        }) catch unreachable;
        self.new_cursor_pos = cur + 1 + total_indent;
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..cur], ins, self.text[cur..] }) catch unreachable;
        self.setText(total);
    } else {
        const ins = std.fmt.allocPrint(Vapor.arena(.frame), "\n{s}", .{self.indent_buffer[0..total_indent]}) catch unreachable;
        self.new_cursor_pos = cur + ins.len;
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}{s}", .{ self.text[0..ls], line, ins, self.text[cur..] }) catch unreachable;
        self.setText(total);
    }

    self.tokenize();
    Vapor.onLayout(setCursor, .{self});
}

fn handleTab(self: *JsonEditor, shift: bool) void {
    const cur = self.text_area.cursorPosition();
    if (shift) {
        // Outdent current line
        const bounds = self.getLineBounds(cur);
        const line = self.text[bounds.start..bounds.end];
        var skip: usize = 0;
        if (line.len > 0 and line[0] == ' ') {
            skip = 1;
            if (line.len > 1 and line[1] == ' ') skip = 2;
        }
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..bounds.start], line[skip..], self.text[bounds.end..] }) catch unreachable;
        self.setText(total);
        self.new_cursor_pos = if (cur >= skip) cur - skip else cur;
    } else {
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}  {s}", .{ self.text[0..cur], self.text[cur..] }) catch unreachable;
        self.setText(total);
        self.new_cursor_pos = cur + 2;
    }
    self.tokenize();
    Vapor.onLayout(setCursor, .{self});
}

// ============================================================================
// Helpers
// ============================================================================

fn getLineBounds(self: *JsonEditor, cur: usize) LineBounds {
    const start = if (std.mem.lastIndexOf(u8, self.text[0..cur], "\n")) |p| p + 1 else 0;
    const end = std.mem.indexOfPos(u8, self.text, cur, "\n") orelse self.text.len;
    return .{ .start = start, .end = end };
}

fn setCursor(self: *JsonEditor) void {
    self.text_area.setCursorPosition(self.new_cursor_pos);
}

fn tokenColor(tt: TokenType) Vapor.Types.Color {
    return switch (tt) {
        .string_key => .hex("#82AAFF"),
        .string_value => .hex("#C3E88D"),
        .number => .hex("#F78C6C"),
        .boolean, .null_literal => .hex("#C792EA"),
        .punctuation => .hex("#89DDFF"),
        .comment => .hex("#546E7A"),
        .invalid => .hex("#FF5370"),
        .whitespace, .newline => .hex("#EEFFFF"),
    };
}

// ============================================================================
// Render
// ============================================================================

pub fn render(self: *JsonEditor) void {
    Vapor.Stack()
        .height(.expand)
        .width(.percent(100))
        .children({

        // Editor area
        Row()
            .ref(&self.editor_container)
            .height(.grow)
            .width(.percent(100))
            .pos(.relative)
            .background(.hex("#282828"))
            .children({

            // Syntax highlight layer
            Row()
                .ref(&self.highlighter_layer)
                .height(.percent(100))
                .width(.percent(100))
                .padding(.horizontal(12))
                .scroll(.scrollY())
                .pos(.tl(.percent(0), .percent(0), .absolute))
                .children({
                self.renderHighlighted();
            });

            // Transparent textarea layer
            Row()
                .background(.transparent)
                .width(.percent(100))
                .height(.percent(100))
                .padding(.horizontal(12))
                .pos(.tl(.percent(0), .percent(0), .absolute))
                .children({
                TextArea()
                    .ref(&self.text_area)
                    .background(.transparent)
                    .val(&self.text)
                    .placeholder(self.text)
                    .width(.percent(100))
                    .outline(.none, null)
                    .border(.none)
                    .resize(.none)
                    .border(.thin(.transparent))
                    .height(.percent(100))
                    .whiteSpace(.pre)
                    .padding(.{ .top = 11, .left = 47 })
                    .fontFamily("DM Mono, monospace")
                    .caret(.{ .type = .block, .color = .white })
                    .textDecoration(.none)
                    .font(15, 400, .transparent)
                    .onEvent(.scroll, onScroll, .{self})
                    .onEvent(.input, onChange, .{self})
                    .onEvent(.keydown, onKeyDown, .{self})
                    .onEvent(.keyup, onKeyUp, .{self})
                    .onEvent(.blur, onBlur, .{self})
                    .end();
            });
        });
    });
}

fn renderHighlighted(self: *JsonEditor) void {
    const lines = self.token_lines orelse return;

    Row().style(&.{
        .direction = .column,
        .layout = .{ .x = .start, .y = .start },
        .padding = .all(12),
    }).children({
        for (lines, 0..) |tokens, line_idx| {
            Row().style(&.{
                .size = .hw(.px(22.5), .percent(100)),
                .layout = .left_center,
            }).children({
                // Line number
                Text(line_idx + 1)
                    .font(14, 600, .hex("#555555"))
                    .fontFamily("DM Mono, monospace")
                    .width(.px(24))
                    .end();

                // Tokens
                Row().style(&.{
                    .size = .h(.px(22.5)),
                    .visual = .{ .white_space = .pre },
                    .layout = .left_center,
                    .padding = .{ .left = 12 },
                    .font_family = "DM Mono, monospace",
                }).children({
                    for (tokens) |tok| {
                        Text(tok.text)
                            .unmanaged()
                            .font(15, 400, tokenColor(tok.type))
                            .fontFamily("DM Mono, monospace")
                            .end();
                    }
                });
            });
        }
    });
}
