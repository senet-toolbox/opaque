const std = @import("std");
const Vapor = @import("vapor");
const Page = Vapor.Page;
const Box = Vapor.Box;
const Text = Vapor.Text;
const Hooks = Vapor.Hooks;
const TextArea = Vapor.TextArea;
const Vaporize = @import("vaporize");
const JSONHighlighter = @import("json_syntax_highlighter.zig").JSONHighlighter;
const CoalescedSpan = @import("json_syntax_highlighter.zig").CoalescedSpan;
const TokenType = @import("json_syntax_highlighter.zig").TokenType;
const Icon = Vapor.Icon;

const auto_close_pairs = [_]AutoClosePair{
    .{ .open = '{', .close = '}' },
    .{ .open = '[', .close = ']' },
    .{ .open = '"', .close = '"' },
};

const JsonEditor = @This();
highlighter: JSONHighlighter = undefined,
line_height: f32 = 22.5,
container_height: f32 = 22.5 * 12,
drag: Vapor.Draggable = .{ .on_drag = onDrag },
buffer: [8192]u8 = undefined,
text: []const u8 = "",
on_change: ?*const fn (evt: *Vapor.Event) void = null,

indent_buffer: [8192]u8 = undefined,
holding_meta: bool = false,
holding_ctrl: bool = false,
holding_shift: bool = false,

char_width: f32 = 8.7,
line_number_width: f32 = 36,
editor_padding_top: f32 = 12,
editor_padding_left: f32 = 12,

hover_tooltip: HoverTooltip = .{},
editor_container: Vapor.Binded = .{},
text_area: Vapor.Binded = .{},
new_cursor_pos: usize = 0,
var last_time: i64 = 0;

const AutoClosePair = struct { open: u8, close: u8 };

fn getClosingChar(c: u8) ?u8 {
    for (auto_close_pairs) |pair| {
        if (pair.open == c) return pair.close;
    }
    return null;
}

fn isClosingChar(c: u8) bool {
    for (auto_close_pairs) |pair| {
        if (pair.close == c) return true;
    }
    return false;
}

pub fn init() JsonEditor {
    var editor = JsonEditor{
        .highlighter = JSONHighlighter.init(Vapor.arena(.persist)),
    };
    editor.text = std.fmt.bufPrint(&editor.buffer, "{s}", .{editor.text}) catch unreachable;
    return editor;
}

pub fn throttle(delay: i64) bool {
    const current_time = std.time.milliTimestamp();
    if (current_time - last_time < delay) return true;
    last_time = current_time;
    return false;
}

fn onChange(self: *JsonEditor, evt: *Vapor.Event) void {
    if (throttle(60)) return;
    self.text = evt.text();
    self.recompile();
    if (self.on_change) |callback| callback(evt);
}

pub fn parse(self: *JsonEditor) void {
    self.highlighter.parse(self.text) catch unreachable;
    self.highlighter.validateJSON() catch unreachable;
}

pub fn recompile(self: *JsonEditor) void {
    self.highlighter.recompile(self.text) catch unreachable;
    self.highlighter.validateJSON() catch unreachable;
}

// ============================================================================
// Auto-Format
// ============================================================================

/// Sets the editor text to a pretty-printed version of the given JSON string,
/// then re-parses for syntax highlighting / validation.
pub fn setTextAutoFmt(self: *JsonEditor, raw: []const u8) void {
    const formatted = formatJson(raw);
    self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{formatted}) catch unreachable;
    self.parse();
}

fn formatJson(input: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(Vapor.arena(.persist));
    var indent_level: usize = 0;
    const indent_str = "  ";
    var in_string = false;
    var escape = false;
    var i: usize = 0;

    while (i < input.len) : (i += 1) {
        const c = input[i];

        if (escape) {
            result.append(c) catch unreachable;
            escape = false;
            continue;
        }

        if (c == '\\' and in_string) {
            result.append(c) catch unreachable;
            escape = true;
            continue;
        }

        if (c == '"') {
            in_string = !in_string;
            result.append(c) catch unreachable;
            continue;
        }

        if (in_string) {
            result.append(c) catch unreachable;
            continue;
        }

        // Skip existing whitespace outside strings
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') continue;

        switch (c) {
            '{', '[' => {
                result.append(c) catch unreachable;
                // Peek ahead: if the matching close is next (empty object/array), keep compact
                const next = skipWhitespace(input, i + 1);
                const close: u8 = if (c == '{') '}' else ']';
                if (next < input.len and input[next] == close) {
                    result.append(close) catch unreachable;
                    i = next;
                } else {
                    indent_level += 1;
                    result.append('\n') catch unreachable;
                    appendIndent(&result, indent_level, indent_str);
                }
            },
            '}', ']' => {
                indent_level -|= 1;
                result.append('\n') catch unreachable;
                appendIndent(&result, indent_level, indent_str);
                result.append(c) catch unreachable;
            },
            ':' => {
                result.appendSlice(": ") catch unreachable;
            },
            ',' => {
                result.append(',') catch unreachable;
                result.append('\n') catch unreachable;
                appendIndent(&result, indent_level, indent_str);
            },
            else => {
                result.append(c) catch unreachable;
            },
        }
    }

    return result.items;
}

fn skipWhitespace(input: []const u8, start: usize) usize {
    var pos = start;
    while (pos < input.len and (input[pos] == ' ' or input[pos] == '\t' or input[pos] == '\n' or input[pos] == '\r')) : (pos += 1) {}
    return pos;
}

fn appendIndent(result: *std.array_list.Managed(u8), level: usize, indent_str: []const u8) void {
    for (0..level) |_| {
        result.appendSlice(indent_str) catch unreachable;
    }
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
    } else if (std.mem.eql(u8, key, "Control")) {
        self.holding_ctrl = true;
    } else if (std.mem.eql(u8, key, "Shift")) {
        self.holding_shift = true;
    } else if ((std.mem.eql(u8, key, "/") or std.mem.eql(u8, key, "?")) and self.holding_meta) {
        self.toggleLineComment(evt);
    } else if (std.mem.eql(u8, key, "d") and self.holding_meta) {
        evt.preventDefault();
        self.duplicateLine();
    } else if (std.mem.eql(u8, key, "k") and self.holding_meta) {
        evt.preventDefault();
        self.deleteLine();
    } else if (std.mem.eql(u8, key, "ArrowUp") and self.holding_meta and evt.altKey()) {
        evt.preventDefault();
        self.moveLineUp();
    } else if (std.mem.eql(u8, key, "ArrowDown") and self.holding_meta and evt.altKey()) {
        evt.preventDefault();
        self.moveLineDown();
    } else if (key.len == 1 and getClosingChar(key[0]) != null) {
        evt.preventDefault();
        const open = key[0];
        const close = getClosingChar(open).?;
        self.insertAutoClosePair(open, close);
    } else if (key.len == 1 and isClosingChar(key[0]) and key[0] != '"') {
        if (self.trySkipClosingChar(key[0])) {
            evt.preventDefault();
            return;
        }
    } else if (std.mem.eql(u8, key, "Backspace")) {
        if (self.tryDeletePair()) {
            evt.preventDefault();
            return;
        }
    }
}

fn onKeyUp(self: *JsonEditor, evt: *Vapor.Event) void {
    const key = evt.key();
    if (std.mem.eql(u8, key, "Meta")) {
        self.holding_meta = false;
    } else if (std.mem.eql(u8, key, "Control")) {
        self.holding_ctrl = false;
    } else if (std.mem.eql(u8, key, "Shift")) {
        self.holding_shift = false;
    }
}

// ============================================================================
// Hover / Token Hit-Testing
// ============================================================================

const HoverTooltip = struct {
    visible: bool = false,
    binded: Vapor.Binded = .{},
    x: f32 = 0,
    y: f32 = 0,
    token_text: []const u8 = "",
    token_type: TokenType = .string_key,
    error_message: ?[]const u8 = null,
    detail: ?[]const u8 = null,
};

fn onPointerMove(self: *JsonEditor, evt: *Vapor.Event) void {
    const line_height = self.line_height;
    var editor_container = self.editor_container;
    const editor_padding_top = self.editor_padding_top;
    const editor_padding_left = self.editor_padding_left;
    const line_number_width = self.line_number_width;
    const char_width = self.char_width;
    var hover_tooltip = self.hover_tooltip;

    if (throttle(16)) return;
    const container_rect = editor_container.getBoundingClientRect() orelse return;
    const mouse_x = evt.pageX() - container_rect.left;
    const mouse_y = evt.pageY() - container_rect.top;
    const scroll_top: f32 = @floatFromInt(self.text_area.scrollTop());
    const code_area_left = editor_padding_left + line_number_width;

    if (mouse_x < code_area_left) {
        self.hideHoverTooltip();
        return;
    }

    const code_x = mouse_x - code_area_left;
    const code_y = mouse_y + scroll_top - editor_padding_top;
    const line_idx: usize = @intFromFloat(@max(0, @floor(code_y / line_height)));
    const col_idx: usize = @intFromFloat(@max(0, @floor(code_x / char_width)));

    const result = self.findTokenAtPosition(line_idx, col_idx);

    if (result) |hit| {
        hover_tooltip.token_text = hit.span.text;
        hover_tooltip.token_type = hit.span.token_type;
        hover_tooltip.error_message = if (hit.span.has_error) self.getErrorAtLine(hit.line, hit.col) else null;
        hover_tooltip.detail = getTokenDetail(hit.span);

        if (hit.span.has_error or shouldShowHover(hit.span)) {
            hover_tooltip.visible = true;
            hover_tooltip.x = mouse_x;
            hover_tooltip.y = mouse_y;
            _ = hover_tooltip.binded.translate3d(.{ .x = mouse_x + 12, .y = mouse_y - 40 });
            hover_tooltip.binded.mutateStyleString("display", "block");
            Vapor.cycle();
        } else {
            self.hideHoverTooltip();
        }
    } else {
        self.hideHoverTooltip();
    }
}

fn onPointerLeave(self: *JsonEditor, _: *Vapor.Event) void {
    self.hideHoverTooltip();
}

fn hideHoverTooltip(self: *JsonEditor) void {
    if (self.hover_tooltip.visible) {
        self.hover_tooltip.visible = false;
        self.hover_tooltip.binded.mutateStyleString("display", "none");
    }
}

const TokenHit = struct {
    span: CoalescedSpan,
    line: usize,
    col: usize,
};

fn findTokenAtPosition(self: *JsonEditor, line_idx: usize, col_idx: usize) ?TokenHit {
    const coalesced = self.highlighter.coalesced_lines orelse return null;
    if (line_idx >= coalesced.len) return null;
    const line_spans = coalesced[line_idx];
    var current_col: usize = 0;
    for (line_spans) |span| {
        const span_end = current_col + span.text.len;
        if (col_idx >= current_col and col_idx < span_end) {
            return TokenHit{ .span = span, .line = line_idx, .col = current_col };
        }
        current_col = span_end;
    }
    return null;
}

fn getErrorAtLine(self: *JsonEditor, line_idx: usize, _: usize) ?[]const u8 {
    var itr = self.highlighter.errors.iterator();
    while (itr.next()) |entry| {
        const err = entry.value_ptr;
        if (err.line == line_idx + 1) return err.message;
    }
    return null;
}

fn shouldShowHover(span: CoalescedSpan) bool {
    return switch (span.token_type) {
        .boolean, .null_literal, .invalid => true,
        else => false,
    };
}

fn getTokenDetail(span: CoalescedSpan) ?[]const u8 {
    return switch (span.token_type) {
        .string_key => "Object Key",
        .string_value => "String Value",
        .number => "Number",
        .boolean => "Boolean",
        .null_literal => "Null",
        .punctuation => "Punctuation",
        .comment => "Comment",
        .invalid => "Invalid Token",
        .whitespace, .newline => null,
    };
}

// ============================================================================
// Editor Functions
// ============================================================================

fn toggleLineComment(self: *JsonEditor, evt: *Vapor.Event) void {
    const selection = self.text_area.selection() orelse return;
    if (selection.start == selection.end) {
        self.toggleSingleLineComment(evt);
        return;
    }

    const line_start = if (std.mem.lastIndexOf(u8, self.text[0..selection.start], "\n")) |pos| pos + 1 else 0;
    const line_end = if (std.mem.indexOfPos(u8, self.text, selection.end, "\n")) |pos| pos else self.text.len;
    const selected_block = self.text[line_start..line_end];

    var all_commented = true;
    var check_iter = std.mem.splitSequence(u8, selected_block, "\n");
    while (check_iter.next()) |line| {
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "//")) {
            all_commented = false;
            break;
        }
    }

    var result = std.array_list.Managed(u8).init(Vapor.arena(.frame));
    var iter = std.mem.splitSequence(u8, selected_block, "\n");
    var first = true;

    while (iter.next()) |line| {
        if (!first) result.append('\n') catch unreachable;
        first = false;

        if (all_commented) {
            var cs: usize = 0;
            for (line) |c| {
                if (c == ' ' or c == '\t') {
                    cs += 1;
                } else break;
            }
            const content = line[cs..];
            if (std.mem.startsWith(u8, content, "// ")) {
                result.appendSlice(line[0..cs]) catch unreachable;
                result.appendSlice(content[3..]) catch unreachable;
            } else if (std.mem.startsWith(u8, content, "//")) {
                result.appendSlice(line[0..cs]) catch unreachable;
                result.appendSlice(content[2..]) catch unreachable;
            } else {
                result.appendSlice(line) catch unreachable;
            }
        } else {
            if (line.len == 0) continue;
            var cs: usize = 0;
            for (line) |c| {
                if (c == ' ' or c == '\t') {
                    cs += 1;
                } else break;
            }
            result.appendSlice(line[0..cs]) catch unreachable;
            result.appendSlice("// ") catch unreachable;
            result.appendSlice(line[cs..]) catch unreachable;
        }
    }

    self.replaceText(line_start, line_end, result.items);
    self.new_cursor_pos = line_start + result.items.len;
    self.recompile();
    Vapor.onEndCtx(updateCursorPosition, .{self});
}

fn toggleSingleLineComment(self: *JsonEditor, _: *Vapor.Event) void {
    const cursor_pos = self.text_area.cursorPosition();
    const line_bounds = self.getLineBounds(cursor_pos);
    const line = self.text[line_bounds.start..line_bounds.end];

    var content_start: usize = 0;
    for (line) |c| {
        if (c == ' ' or c == '\t') {
            content_start += 1;
        } else break;
    }
    const content = line[content_start..];
    var result: []const u8 = undefined;

    if (std.mem.startsWith(u8, content, "// ")) {
        result = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}", .{ line[0..content_start], content[3..] }) catch unreachable;
        self.new_cursor_pos = if (cursor_pos >= 3) cursor_pos - 3 else cursor_pos;
    } else if (std.mem.startsWith(u8, content, "//")) {
        result = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}", .{ line[0..content_start], content[2..] }) catch unreachable;
        self.new_cursor_pos = if (cursor_pos >= 2) cursor_pos - 2 else cursor_pos;
    } else {
        result = std.fmt.allocPrint(Vapor.arena(.frame), "{s}// {s}", .{ line[0..content_start], content }) catch unreachable;
        self.new_cursor_pos = cursor_pos + 3;
    }

    self.replaceText(line_bounds.start, line_bounds.end, result);
    self.recompile();
    Vapor.onEndCtx(updateCursorPosition, .{self});
}

fn insertAutoClosePair(self: *JsonEditor, open: u8, close: u8) void {
    const cursor_pos = self.text_area.cursorPosition();
    const selection = self.text_area.selection() orelse return;

    if (selection.start != selection.end) {
        const selected = self.text[selection.start..selection.end];
        const wrapped = std.fmt.allocPrint(Vapor.arena(.frame), "{c}{s}{c}", .{ open, selected, close }) catch unreachable;
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..selection.start], wrapped, self.text[selection.end..] }) catch unreachable;
        self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
        self.new_cursor_pos = selection.start + wrapped.len;
    } else {
        if (open == close and cursor_pos < self.text.len and self.text[cursor_pos] == close) {
            self.new_cursor_pos = cursor_pos + 1;
            Vapor.onEndCtx(updateCursorPosition, .{self});
            return;
        }
        const pair = std.fmt.allocPrint(Vapor.arena(.frame), "{c}{c}", .{ open, close }) catch unreachable;
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..cursor_pos], pair, self.text[cursor_pos..] }) catch unreachable;
        self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
        self.new_cursor_pos = cursor_pos + 1;
    }
    self.recompile();
    Vapor.onEndCtx(updateCursorPosition, .{self});
}

fn trySkipClosingChar(self: *JsonEditor, close: u8) bool {
    const cursor_pos = self.text_area.cursorPosition();
    if (cursor_pos < self.text.len and self.text[cursor_pos] == close) {
        self.new_cursor_pos = cursor_pos + 1;
        Vapor.onEndCtx(updateCursorPosition, .{self});
        return true;
    }
    return false;
}

fn tryDeletePair(self: *JsonEditor) bool {
    const cursor_pos = self.text_area.cursorPosition();
    if (cursor_pos == 0 or cursor_pos >= self.text.len) return false;
    const before = self.text[cursor_pos - 1];
    const after = self.text[cursor_pos];

    for (auto_close_pairs) |pair| {
        if (before == pair.open and after == pair.close) {
            const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}", .{ self.text[0 .. cursor_pos - 1], self.text[cursor_pos + 1 ..] }) catch unreachable;
            self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
            self.new_cursor_pos = cursor_pos - 1;
            self.recompile();
            Vapor.onEndCtx(updateCursorPosition, .{self});
            return true;
        }
    }
    return false;
}

fn handleEnter(self: *JsonEditor) void {
    const cursor_pos = self.text_area.cursorPosition();
    const line_start = std.mem.lastIndexOf(u8, self.text[0..cursor_pos], "\n") orelse 0;
    const actual_line_start = if (line_start == 0) 0 else line_start + 1;
    const current_line = self.text[actual_line_start..cursor_pos];

    var indent_count: usize = 0;
    for (current_line) |c| {
        if (c == ' ' or c == '\t') {
            indent_count += 1;
        } else break;
    }

    var extra_indent: usize = 0;
    const trimmed = std.mem.trim(u8, current_line, " \t");

    if (std.mem.endsWith(u8, trimmed, "{") or std.mem.endsWith(u8, trimmed, "[")) {
        extra_indent = 2;
    }

    const char_before = if (cursor_pos > 0) self.text[cursor_pos - 1] else @as(u8, 0);
    const char_after = if (cursor_pos < self.text.len) self.text[cursor_pos] else @as(u8, 0);
    const between_pair = (char_before == '{' and char_after == '}') or (char_before == '[' and char_after == ']');

    const total_indent = indent_count + extra_indent;
    @memset(self.indent_buffer[0..total_indent], ' ');

    if (between_pair) {
        @memset(self.indent_buffer[total_indent .. total_indent + indent_count], ' ');
        const insert = std.fmt.allocPrint(Vapor.arena(.frame), "\n{s}\n{s}", .{
            self.indent_buffer[0..total_indent],
            self.indent_buffer[0..indent_count],
        }) catch unreachable;
        self.new_cursor_pos = cursor_pos + 1 + total_indent;
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..cursor_pos], insert, self.text[cursor_pos..] }) catch unreachable;
        self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
    } else {
        const insert = std.fmt.allocPrint(Vapor.arena(.frame), "\n{s}", .{self.indent_buffer[0..total_indent]}) catch unreachable;
        self.new_cursor_pos = cursor_pos + insert.len;
        const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}{s}", .{ self.text[0..actual_line_start], current_line, insert, self.text[cursor_pos..] }) catch unreachable;
        self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
    }

    self.recompile();
    Vapor.onEndCtx(updateCursorPosition, .{self});
}

fn handleTab(self: *JsonEditor, shift: bool) void {
    const cursor_pos = self.text_area.cursorPosition();
    const selection = self.text_area.selection() orelse return;

    if (selection.start != selection.end) {
        if (shift) self.handleOutdent(selection.start, selection.end) else self.handleIndent(selection.start, selection.end);
    } else {
        if (shift) {
            self.outdentCurrentLine();
        } else {
            const indent = "  ";
            const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..cursor_pos], indent, self.text[cursor_pos..] }) catch unreachable;
            self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
            self.new_cursor_pos = cursor_pos + indent.len;
            self.recompile();
            Vapor.onEndCtx(updateCursorPosition, .{self});
        }
    }
}

fn handleIndent(self: *JsonEditor, start: usize, end: usize) void {
    const line_start = if (std.mem.lastIndexOf(u8, self.text[0..start], "\n")) |pos| pos + 1 else 0;
    const line_end = std.mem.indexOf(u8, self.text[end..], "\n") orelse self.text.len;
    const actual_end = end + line_end;
    var result = std.array_list.Managed(u8).init(Vapor.arena(.frame));
    var line_iter = std.mem.splitSequence(u8, self.text[line_start..actual_end], "\n");
    var first = true;
    while (line_iter.next()) |line| {
        if (!first) result.append('\n') catch unreachable;
        first = false;
        if (line.len > 0) result.appendSlice("  ") catch unreachable;
        result.appendSlice(line) catch unreachable;
    }
    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..line_start], result.items, self.text[actual_end..] }) catch unreachable;
    self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
    self.new_cursor_pos = start + 2;
    self.recompile();
    Vapor.onEndCtx(updateCursorPosition, .{self});
}

fn handleOutdent(self: *JsonEditor, start: usize, end: usize) void {
    const line_start = if (std.mem.lastIndexOf(u8, self.text[0..start], "\n")) |pos| pos + 1 else 0;
    const line_end = std.mem.indexOf(u8, self.text[end..], "\n") orelse self.text.len;
    const actual_end = end + line_end;
    var result = std.array_list.Managed(u8).init(Vapor.arena(.frame));
    var line_iter = std.mem.splitSequence(u8, self.text[line_start..actual_end], "\n");
    var first = true;
    while (line_iter.next()) |line| {
        if (!first) result.append('\n') catch unreachable;
        first = false;
        var skip: usize = 0;
        if (line.len > 0 and line[0] == ' ') {
            skip = 1;
            if (line.len > 1 and line[1] == ' ') skip = 2;
        }
        result.appendSlice(line[skip..]) catch unreachable;
    }
    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..line_start], result.items, self.text[actual_end..] }) catch unreachable;
    self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
    self.new_cursor_pos = if (start >= 2) start - 2 else start;
    self.recompile();
    Vapor.onEndCtx(updateCursorPosition, .{self});
}

fn outdentCurrentLine(self: *JsonEditor) void {
    const cursor_pos = self.text_area.cursorPosition();
    const line_bounds = self.getLineBounds(cursor_pos);
    const line = self.text[line_bounds.start..line_bounds.end];
    var skip: usize = 0;
    if (line.len > 0 and line[0] == ' ') {
        skip = 1;
        if (line.len > 1 and line[1] == ' ') skip = 2;
    }
    const outdented = line[skip..];
    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..line_bounds.start], outdented, self.text[line_bounds.end..] }) catch unreachable;
    self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
    self.new_cursor_pos = if (cursor_pos >= skip) cursor_pos - skip else cursor_pos;
    self.recompile();
    Vapor.onEndCtx(updateCursorPosition, .{self});
}

const LineBounds = struct { start: usize, end: usize };

fn getLineBounds(self: *JsonEditor, cursor_pos: usize) LineBounds {
    const line_start = if (std.mem.lastIndexOf(u8, self.text[0..cursor_pos], "\n")) |pos| pos + 1 else 0;
    const line_end = std.mem.indexOfPos(u8, self.text, cursor_pos, "\n") orelse self.text.len;
    return .{ .start = line_start, .end = line_end };
}

fn moveLineUp(self: *JsonEditor) void {
    const cursor_pos = self.text_area.cursorPosition();
    const line_bounds = self.getLineBounds(cursor_pos);
    if (line_bounds.start == 0) return;
    const prev_line_end = line_bounds.start - 1;
    const prev_line_start = if (std.mem.lastIndexOf(u8, self.text[0..prev_line_end], "\n")) |pos| pos + 1 else 0;
    const current_line = self.text[line_bounds.start..line_bounds.end];
    const prev_line = self.text[prev_line_start..prev_line_end];
    const swapped = std.fmt.allocPrint(Vapor.arena(.frame), "{s}\n{s}", .{ current_line, prev_line }) catch unreachable;
    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..prev_line_start], swapped, self.text[line_bounds.end..] }) catch unreachable;
    self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
    self.new_cursor_pos = prev_line_start + (cursor_pos - line_bounds.start);
    self.recompile();
    Vapor.onEndCtx(updateCursorPosition, .{self});
}

fn moveLineDown(self: *JsonEditor) void {
    const cursor_pos = self.text_area.cursorPosition();
    const line_bounds = self.getLineBounds(cursor_pos);
    if (line_bounds.end >= self.text.len) return;
    const next_line_start = line_bounds.end + 1;
    const next_line_end = std.mem.indexOfPos(u8, self.text, next_line_start, "\n") orelse self.text.len;
    const current_line = self.text[line_bounds.start..line_bounds.end];
    const next_line = self.text[next_line_start..next_line_end];
    const swapped = std.fmt.allocPrint(Vapor.arena(.frame), "{s}\n{s}", .{ next_line, current_line }) catch unreachable;
    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..line_bounds.start], swapped, self.text[next_line_end..] }) catch unreachable;
    self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
    self.new_cursor_pos = next_line_start + next_line.len + 1 + (cursor_pos - line_bounds.start);
    self.recompile();
    Vapor.onEndCtx(updateCursorPosition, .{self});
}

fn duplicateLine(self: *JsonEditor) void {
    const cursor_pos = self.text_area.cursorPosition();
    const line_bounds = self.getLineBounds(cursor_pos);
    const line = self.text[line_bounds.start..line_bounds.end];
    const duplicated = std.fmt.allocPrint(Vapor.arena(.frame), "{s}\n{s}", .{ line, line }) catch unreachable;
    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}{s}", .{ self.text[0..line_bounds.start], duplicated, self.text[line_bounds.end..] }) catch unreachable;
    self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
    self.new_cursor_pos = line_bounds.end + 1 + (cursor_pos - line_bounds.start);
    self.recompile();
    Vapor.onEndCtx(updateCursorPosition, .{self});
}

fn deleteLine(self: *JsonEditor) void {
    const cursor_pos = self.text_area.cursorPosition();
    const line_bounds = self.getLineBounds(cursor_pos);
    const delete_end = if (line_bounds.end < self.text.len) line_bounds.end + 1 else line_bounds.end;
    const total = std.fmt.allocPrint(Vapor.arena(.frame), "{s}{s}", .{ self.text[0..line_bounds.start], self.text[delete_end..] }) catch unreachable;
    self.text = std.fmt.bufPrint(&self.buffer, "{s}", .{total}) catch unreachable;
    self.new_cursor_pos = line_bounds.start;
    self.recompile();
    Vapor.onEndCtx(updateCursorPosition, .{self});
}

fn updateCursorPosition(self: *JsonEditor) void {
    self.text_area.setCursorPosition(self.new_cursor_pos);

    const cursor_pos = self.new_cursor_pos;
    std.log.info("cursor_pos {d} {d}", .{ self.text.len, cursor_pos });
    const text_before_cursor = self.text[0..cursor_pos];
    var line_count: usize = 1;
    for (text_before_cursor) |c| {
        if (c == '\n') line_count += 1;
    }
    const cursor_top = @as(f32, @floatFromInt(line_count - 1)) * self.line_height;
    const current_scroll: f32 = @floatFromInt(self.text_area.scrollTop());
    const viewport_height: f32 = self.container_height - 48;
    const padding = self.line_height * 2;
    if (cursor_top > current_scroll + viewport_height - padding) {
        const new_scroll = cursor_top + padding - viewport_height;
        self.text_area.scrollToTop(@intFromFloat(new_scroll));
    } else if (cursor_top < current_scroll + padding) {
        const new_scroll = @max(0, cursor_top - padding);
        self.text_area.scrollToTop(@intFromFloat(new_scroll));
    }
}

fn replaceText(self: *JsonEditor, start: usize, end: usize, replacement: []const u8) void {
    self.text_area.replaceRange(start, end, replacement);
    self.recompile();
}

fn onScroll(self: *JsonEditor, _: *Vapor.Event) void {
    if (throttle(8)) return;
    const scroll_top = self.text_area.scrollTop();
    binded_highlighter.scrollToTop(scroll_top);
    self.hideHoverTooltip();
}

var binded_highlighter: Vapor.Binded = .{};

var copied: bool = false;
fn copy(self: *JsonEditor) void {
    Vapor.Clipboard.copy(self.text);
    copied = true;
    Vapor.registerCtxTimeout("json_editor_copy", 1000, toggleCopyIcon, .{{}});
}

fn toggleCopyIcon(_: void) void {
    copied = false;
}

var size: f32 = 128 + 256;
fn onDrag(draggable: *Vapor.Draggable, _: *Vapor.Event) void {
    size += draggable.movement_y;
    container.mutateAttribute(.{ .height = .{ .value = size, .unit = .px } });
}

// ============================================================================
// Render
// ============================================================================

var container: Vapor.Binded = .{};

pub fn render(self: *JsonEditor) void {
    Vapor.Stack()
        .height(.expand)
        .width(.percent(100))
        .pos(.relative)
        .ref(&container)
        .children({
        // Header bar
        Box()
            .width(.percent(100))
            .padding(.horizontal(12))
            .height(.px(48))
            .background(.hex("#1e1e1e"))
            .layout(.x_between_center)
            .children({
            Box().layout(.left_center).spacing(12).children({
                Text("JSON")
                    .font(16, 600, .white)
                    .end();
            });
            Vapor.ButtonCtx(copy, .{self})
                .cursor(.pointer)
                .background(.transparent)
                .size(.square_px(24))
                .children({
                if (copied) {
                    Icon(.check)
                        .font(16, 400, .palette(.background))
                        .end();
                } else {
                    Icon(.clipboard)
                        .font(16, 400, .palette(.background))
                        .end();
                }
            });
        });

        // Editor area
        Box()
            .ref(&self.editor_container)
            .height(.grow)
            .width(.percent(100))
            .pos(.relative)
            .layout(.center)
            .spacing(16)
            .background(.hex("#282828"))
            .children({
            // Layer 1: Syntax highlighted background
            Box()
                .ref(&binded_highlighter)
                .height(.percent(100))
                .width(.percent(100))
                .padding(.horizontal(12))
                .scroll(.scroll_y())
                .pos(.tl(.percent(0), .percent(0), .absolute)).children({
                self.highlighter.render() catch unreachable;
            });

            // Layer 2: Transparent textarea overlay
            Box()
                .background(.transparent)
                .width(.percent(100))
                .height(.percent(100))
                .padding(.horizontal(12))
                .pos(.tl(.percent(0), .percent(0), .absolute)).children({
                TextArea()
                    .ref(&self.text_area)
                    .background(.transparent)
                    .val(&self.text)
                    .placeholder(self.text)
                    .width(.percent(100))
                    .outline(.none)
                    .border(.none)
                    .resize(.none)
                    .border(.simple(.transparent))
                    .height(.percent(100))
                    .whitespace(.pre)
                    .padding(.tblr(11, 0, 47, 0))
                    .fontFamily("DM Mono, monospace")
                    .caret(.{ .type = .block, .color = .white })
                    .textDecoration(.none)
                    .font(15, 400, .transparent)
                    .onEventCtx(.scroll, onScroll, .{self})
                    .onEventCtx(.input, onChange, .{self})
                    .onEventCtx(.keydown, onKeyDown, .{self})
                    .onEventCtx(.keyup, onKeyUp, .{self})
                    .onEventCtx(.pointermove, onPointerMove, .{self})
                    .onEventCtx(.pointerleave, onPointerLeave, .{self})
                    .end();
            });

            // Layer 3: Hover tooltip
            renderHoverTooltip(self);
        });
    });
}

fn renderHoverTooltip(self: *JsonEditor) void {
    Box()
        .ref(&self.hover_tooltip.binded)
        .pos(.tl(.px(0), .px(0), .absolute))
        .inlineStyle("pointer-events: none; display: none;", .{})
        .duration(80)
        .transition(.{
            .properties = &.{.transform},
            .duration = 80,
            .timing = .ease,
        })
        .zIndex(900)
        .children({
        if (self.hover_tooltip.error_message) |err_msg| {
            Box()
                .padding(.all(8))
                .background(.hex("#1e1e1e"))
                .border(.{ .thickness = .all(1), .color = .hex("#f44747"), .style = .solid })
                .width(.px(320))
                .spacing(8)
                .layout(.left_center)
                .children({
                Box()
                    .layout(.left_center)
                    .spacing(6)
                    .children({
                    Box()
                        .size(.square_px(6))
                        .radius(.all(3))
                        .background(.hex("#f44747"))
                        .children({});
                    Text(err_msg)
                        .font(12, 500, .hex("#f44747"))
                        .end();
                });
                if (self.hover_tooltip.visible) {
                    Box().children({
                        Text(self.hover_tooltip.token_text)
                            .fontFamily("DM Mono, monospace")
                            .font(11, 400, .hex("#808080"))
                            .end();
                    });
                }
            });
        } else if (self.hover_tooltip.visible and self.hover_tooltip.detail != null) {
            Box()
                .padding(.xy(10, 6))
                .background(.hex("#1e1e1e"))
                .border(.{ .thickness = .all(1), .color = .hex("#3d3d3d"), .style = .solid })
                .width(.px(280))
                .spacing(8)
                .layout(.left_center)
                .children({
                Box().layout(.left_center).children({
                    Text(self.hover_tooltip.token_text)
                        .fontFamily("DM Mono, monospace")
                        .font(13, 500, tokenTypeColor(self.hover_tooltip.token_type))
                        .end();
                });
                if (self.hover_tooltip.detail) |detail| {
                    Text(detail)
                        .font(11, 400, .hex("#808080"))
                        .end();
                }
            });
        }
    });
}

fn tokenTypeColor(token_type: TokenType) Vapor.Types.Color {
    return switch (token_type) {
        .string_key => .hex("#82AAFF"),
        .string_value => .hex("#C3E88D"),
        .number => .hex("#F78C6C"),
        .boolean => .hex("#C792EA"),
        .null_literal => .hex("#C792EA"),
        .punctuation => .hex("#89DDFF"),
        .comment => .hex("#546E7A"),
        .invalid => .hex("#FF5370"),
        .whitespace, .newline => .hex("#EEFFFF"),
    };
}
