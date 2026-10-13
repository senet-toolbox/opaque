const std = @import("std");
const Allocator = std.mem.Allocator;
const Vapor = @import("vapor");
const BoundedArray = @import("BoundedArray.zig").BoundedArray;
const ArrayList = std.array_list.Managed;

const Box = Vapor.Box;
const Text = Vapor.Text;
const CtxButton = Vapor.CtxButton;
const Icon = Vapor.Icon;
const Graphic = Vapor.Graphic;
const List = Vapor.List;
const ListItem = Vapor.ListItem;
const Opaque = @import("../../components/Opaque.zig");
const Tooltip = Opaque.Tooltip;

const svg_bug =
    \\<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="white" class="bi bi-bug-fill" viewBox="0 0 16 16">
    \\  <path d="M4.978.855a.5.5 0 1 0-.956.29l.41 1.352A5 5 0 0 0 3 6h10a5 5 0 0 0-1.432-3.503l.41-1.352a.5.5 0 1 0-.956-.29l-.291.956A5 5 0 0 0 8 1a5 5 0 0 0-2.731.811l-.29-.956z"/>
    \\  <path d="M13 6v1H8.5v8.975A5 5 0 0 0 13 11h.5a.5.5 0 0 1 .5.5v.5a.5.5 0 1 0 1 0v-.5a1.5 1.5 0 0 0-1.5-1.5H13V9h1.5a.5.5 0 0 0 0-1H13V7h.5A1.5 1.5 0 0 0 15 5.5V5a.5.5 0 0 0-1 0v.5a.5.5 0 0 1-.5.5zm-5.5 9.975V7H3V6h-.5a.5.5 0 0 1-.5-.5V5a.5.5 0 0 0-1 0v.5A1.5 1.5 0 0 0 2.5 7H3v1H1.5a.5.5 0 0 0 0 1H3v1h-.5A1.5 1.5 0 0 0 1 11.5v.5a.5.5 0 1 0 1 0v-.5a.5.5 0 0 1 .5-.5H3a5 5 0 0 0 4.5 4.975"/>
    \\</svg>
;

// ============================================================================
// Color Type (compatible with Vapor's color system)
// ============================================================================

pub const Color = union(enum) {
    hex: []const u8,
    palette: PaletteColor,
    transparent,

    pub const PaletteColor = enum {
        code_text_color,
        code_keyword_color,
        code_function_color,
        code_string_color,
        code_number_color,
        code_comment_color,
        code_type_color,
        code_builtin_color,
        code_operator_color,
        code_tint_color,
    };

    pub fn eql(self: Color, other: Color) bool {
        return switch (self) {
            .hex => |h| switch (other) {
                .hex => |oh| std.mem.eql(u8, h, oh),
                else => false,
            },
            .palette => |p| switch (other) {
                .palette => |op| p == op,
                else => false,
            },
            .transparent => other == .transparent,
        };
    }
};

// ============================================================================
// Token Types for JSON
// ============================================================================

pub const TokenType = enum {
    string_key, // Object property keys: "name"
    string_value, // String values: "hello"
    number, // 123, 45.67, -1, 1e10
    boolean, // true, false
    null_literal, // null
    punctuation, // { } [ ] , :
    whitespace,
    newline,
    comment, // // and /* */ (JSONC / JSON5 support)
    invalid, // Any invalid/unexpected characters
};

pub const Token = struct {
    type: TokenType,
    text: []const u8,
    color: Color,
    line: usize,
    column: usize,
};

// ============================================================================
// Coalesced Token Span for optimized rendering
// ============================================================================

pub const ColorCategory = enum {
    default,
    string_key,
    string_value,
    number,
    boolean,
    null_literal,
    punctuation,
    comment,
    invalid,
    transparent,
};

pub const CoalescedSpan = struct {
    text: []const u8,
    category: ColorCategory,
    token_type: TokenType,
    start_line: usize,
    start_column: usize,
    has_error: bool,
    is_added: bool = false,
    is_removed: bool = false,
};

// ============================================================================
// AST Node Types
// ============================================================================

pub const NodeType = enum {
    root,
    line,
    token,
    error_annotation,
};

pub const Node = struct {
    tag: NodeType,
    data: union {
        root: void,
        line: struct {
            number: usize,
            indent: usize,
            is_added: bool,
            is_removed: bool,
        },
        token: Token,
        error_annotation: struct {
            message: []const u8,
            start_pos: usize,
            end_pos: usize,
            line: usize,
            column: usize,
        },
    },
    child: ?*Node,
    next: ?*Node,
};

// ============================================================================
// JSON Tokenizer
// ============================================================================

pub const Tokenizer = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    column: usize,
    /// Tracks whether the next string token should be a key or a value.
    /// In JSON, a string is a key when it appears right after `{` or `,`
    /// inside an object context.
    expect_key: bool,
    /// Stack tracking nesting: true = object context, false = array context.
    context_stack: BoundedArray(bool, 256),

    pub fn init(source: []const u8) Tokenizer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
            .expect_key = false,
            .context_stack = BoundedArray(bool, 256){},
        };
    }

    pub fn next(self: *Tokenizer) ?Token {
        if (self.isAtEnd()) return null;

        const start_pos = self.pos;
        const start_line = self.line;
        const start_col = self.column;

        const char = self.peek();

        // Newline
        if (char == '\n') {
            _ = self.advance();
            self.line += 1;
            self.column = 1;
            return .{
                .type = .newline,
                .text = self.source[start_pos..self.pos],
                .color = .transparent,
                .line = start_line,
                .column = start_col,
            };
        }

        // Whitespace (excluding newline)
        if (isWhitespace(char) and char != '\n') {
            while (!self.isAtEnd() and isWhitespace(self.peek()) and self.peek() != '\n') {
                _ = self.advance();
            }
            return .{
                .type = .whitespace,
                .text = self.source[start_pos..self.pos],
                .color = .transparent,
                .line = start_line,
                .column = start_col,
            };
        }

        // Single-line comment (// ...) — JSONC support
        if (char == '/' and self.peekNext() == '/') {
            while (!self.isAtEnd() and self.peek() != '\n') {
                _ = self.advance();
            }
            return .{
                .type = .comment,
                .text = self.source[start_pos..self.pos],
                .color = .{ .palette = .code_comment_color },
                .line = start_line,
                .column = start_col,
            };
        }

        // Multi-line comment (/* ... */) — JSONC support
        if (char == '/' and self.peekNext() == '*') {
            _ = self.advance(); // consume /
            _ = self.advance(); // consume *
            while (!self.isAtEnd()) {
                if (self.peek() == '*' and self.peekNext() == '/') {
                    _ = self.advance();
                    _ = self.advance();
                    break;
                }
                if (self.peek() == '\n') {
                    self.line += 1;
                    self.column = 0;
                }
                _ = self.advance();
            }
            return .{
                .type = .comment,
                .text = self.source[start_pos..self.pos],
                .color = .{ .palette = .code_comment_color },
                .line = start_line,
                .column = start_col,
            };
        }

        // String literals (double quotes)
        if (char == '"') {
            return self.tokenizeString(start_pos, start_line, start_col);
        }

        // Numbers (including negative)
        if (std.ascii.isDigit(char) or (char == '-' and self.pos + 1 < self.source.len and (std.ascii.isDigit(self.source[self.pos + 1]) or self.source[self.pos + 1] == '.'))) {
            return self.tokenizeNumber(start_pos, start_line, start_col);
        }

        // Boolean: true / false
        if (char == 't' or char == 'f') {
            return self.tokenizeBooleanOrInvalid(start_pos, start_line, start_col);
        }

        // Null
        if (char == 'n') {
            return self.tokenizeNullOrInvalid(start_pos, start_line, start_col);
        }

        // Structural punctuation: { } [ ] , :
        if (char == '{' or char == '}' or char == '[' or char == ']' or char == ',' or char == ':') {
            return self.tokenizePunctuation(start_pos, start_line, start_col);
        }

        // Anything else is invalid
        _ = self.advance();
        return .{
            .type = .invalid,
            .text = self.source[start_pos..self.pos],
            .color = .{ .hex = "#FF5370" },
            .line = start_line,
            .column = start_col,
        };
    }

    fn tokenizeString(self: *Tokenizer, start_pos: usize, start_line: usize, start_col: usize) Token {
        _ = self.advance(); // consume opening quote
        var terminated = false;
        while (!self.isAtEnd()) {
            const c = self.peek();
            if (c == '\\') {
                // Skip escaped character
                _ = self.advance();
                if (!self.isAtEnd()) _ = self.advance();
                continue;
            }
            if (c == '"') {
                _ = self.advance();
                terminated = true;
                break;
            }
            // Stop at newline — don't let unterminated strings consume multiple lines
            if (c == '\n') {
                break;
            }
            _ = self.advance();
        }

        // Determine if this is a key or value based on context
        const is_key = self.expect_key;

        // After a string, if we're in key position the next non-ws token should be ':'
        // After a value string, the next should be ',' or '}'
        if (is_key) {
            self.expect_key = false; // colon will follow, then a value
        }

        const token_type: TokenType = if (is_key) .string_key else .string_value;
        const color: Color = if (is_key) .{ .palette = .code_tint_color } else .{ .palette = .code_string_color };

        return .{
            .type = token_type,
            .text = self.source[start_pos..self.pos],
            .color = color,
            .line = start_line,
            .column = start_col,
        };
    }

    fn tokenizeNumber(self: *Tokenizer, start_pos: usize, start_line: usize, start_col: usize) Token {
        // Optional leading minus
        if (!self.isAtEnd() and self.peek() == '-') {
            _ = self.advance();
        }
        // Integer part
        if (!self.isAtEnd() and self.peek() == '0') {
            _ = self.advance();
        } else {
            while (!self.isAtEnd() and std.ascii.isDigit(self.peek())) {
                _ = self.advance();
            }
        }
        // Fractional part
        if (!self.isAtEnd() and self.peek() == '.' and self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1])) {
            _ = self.advance(); // consume .
            while (!self.isAtEnd() and std.ascii.isDigit(self.peek())) {
                _ = self.advance();
            }
        }
        // Exponent part
        if (!self.isAtEnd() and (self.peek() == 'e' or self.peek() == 'E')) {
            _ = self.advance();
            if (!self.isAtEnd() and (self.peek() == '+' or self.peek() == '-')) {
                _ = self.advance();
            }
            while (!self.isAtEnd() and std.ascii.isDigit(self.peek())) {
                _ = self.advance();
            }
        }
        return .{
            .type = .number,
            .text = self.source[start_pos..self.pos],
            .color = .{ .palette = .code_number_color },
            .line = start_line,
            .column = start_col,
        };
    }

    fn tokenizeBooleanOrInvalid(self: *Tokenizer, start_pos: usize, start_line: usize, start_col: usize) Token {
        // Try to match "true" or "false"
        const remaining = self.source[self.pos..];
        if (std.mem.startsWith(u8, remaining, "true") and (remaining.len == 4 or !std.ascii.isAlphanumeric(remaining[4]))) {
            self.pos += 4;
            self.column += 4;
            return .{
                .type = .boolean,
                .text = self.source[start_pos..self.pos],
                .color = .{ .palette = .code_keyword_color },
                .line = start_line,
                .column = start_col,
            };
        }
        if (std.mem.startsWith(u8, remaining, "false") and (remaining.len == 5 or !std.ascii.isAlphanumeric(remaining[5]))) {
            self.pos += 5;
            self.column += 5;
            return .{
                .type = .boolean,
                .text = self.source[start_pos..self.pos],
                .color = .{ .palette = .code_keyword_color },
                .line = start_line,
                .column = start_col,
            };
        }
        // Not a valid boolean — consume as invalid identifier
        return self.tokenizeInvalidWord(start_pos, start_line, start_col);
    }

    fn tokenizeNullOrInvalid(self: *Tokenizer, start_pos: usize, start_line: usize, start_col: usize) Token {
        const remaining = self.source[self.pos..];
        if (std.mem.startsWith(u8, remaining, "null") and (remaining.len == 4 or !std.ascii.isAlphanumeric(remaining[4]))) {
            self.pos += 4;
            self.column += 4;
            return .{
                .type = .null_literal,
                .text = self.source[start_pos..self.pos],
                .color = .{ .palette = .code_keyword_color },
                .line = start_line,
                .column = start_col,
            };
        }
        return self.tokenizeInvalidWord(start_pos, start_line, start_col);
    }

    fn tokenizeInvalidWord(self: *Tokenizer, start_pos: usize, start_line: usize, start_col: usize) Token {
        while (!self.isAtEnd() and (std.ascii.isAlphanumeric(self.peek()) or self.peek() == '_')) {
            _ = self.advance();
        }
        return .{
            .type = .invalid,
            .text = self.source[start_pos..self.pos],
            .color = .{ .hex = "#FF5370" },
            .line = start_line,
            .column = start_col,
        };
    }

    fn tokenizePunctuation(self: *Tokenizer, start_pos: usize, start_line: usize, start_col: usize) Token {
        const char = self.advance();

        switch (char) {
            '{' => {
                // Entering object context — next string is a key
                self.context_stack.append(true) catch {};
                self.expect_key = true;
            },
            '[' => {
                // Entering array context — strings are values
                self.context_stack.append(false) catch {};
                self.expect_key = false;
            },
            '}' => {
                if (self.context_stack.len > 0) {
                    _ = self.context_stack.pop() catch {};
                }
                // Restore parent context
                self.updateExpectKey();
            },
            ']' => {
                if (self.context_stack.len > 0) {
                    _ = self.context_stack.pop() catch {};
                }
                self.updateExpectKey();
            },
            ',' => {
                // After comma in object → next string is a key
                // After comma in array → next string is a value
                if (self.context_stack.len > 0 and self.context_stack.buffer[self.context_stack.len - 1]) {
                    self.expect_key = true;
                } else {
                    self.expect_key = false;
                }
            },
            ':' => {
                // After colon → next token is a value
                self.expect_key = false;
            },
            else => {},
        }

        return .{
            .type = .punctuation,
            .text = self.source[start_pos..self.pos],
            .color = .{ .palette = .code_operator_color },
            .line = start_line,
            .column = start_col,
        };
    }

    fn updateExpectKey(self: *Tokenizer) void {
        // After closing a nested structure, the parent context determines
        // whether next string is key or value. Usually after a value,
        // so expect_key = false until a comma sets it.
        self.expect_key = false;
    }

    fn isAtEnd(self: *const Tokenizer) bool {
        return self.pos >= self.source.len;
    }

    fn peek(self: *const Tokenizer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.pos];
    }

    fn peekNext(self: *const Tokenizer) u8 {
        if (self.pos + 1 >= self.source.len) return 0;
        return self.source[self.pos + 1];
    }

    fn advance(self: *Tokenizer) u8 {
        if (self.isAtEnd()) return 0;
        const char = self.source[self.pos];
        self.pos += 1;
        self.column += 1;
        return char;
    }
};

// ============================================================================
// Parser - Builds AST from tokens
// ============================================================================

pub const Parser = struct {
    allocator: Allocator,
    tokenizer: Tokenizer,

    pub fn init(allocator: Allocator, source: []const u8) Parser {
        return .{
            .allocator = allocator,
            .tokenizer = Tokenizer.init(source),
        };
    }

    pub fn parse(self: *Parser) !*Node {
        const root = try self.createNode(.root);

        var current_line: ?*Node = null;
        var current_line_number: usize = 1;
        var last_token_in_line: ?*Node = null;

        current_line = try self.createLineNode(current_line_number);
        root.child = current_line;

        while (self.tokenizer.next()) |token| {
            if (token.type == .newline) {
                const new_line = try self.createLineNode(current_line_number + 1);
                current_line_number += 1;

                if (current_line) |line| {
                    line.next = new_line;
                }
                current_line = new_line;
                last_token_in_line = null;
            } else {
                const token_node = try self.createTokenNode(token);

                if (last_token_in_line) |last| {
                    last.next = token_node;
                } else if (current_line) |line| {
                    line.child = token_node;
                }
                last_token_in_line = token_node;
            }
        }

        return root;
    }

    fn createNode(self: *Parser, tag: NodeType) !*Node {
        const node = try self.allocator.create(Node);
        node.* = .{
            .tag = tag,
            .data = .{ .root = {} },
            .child = null,
            .next = null,
        };
        return node;
    }

    fn createLineNode(self: *Parser, line_number: usize) !*Node {
        const node = try self.allocator.create(Node);
        node.* = .{
            .tag = .line,
            .data = .{
                .line = .{
                    .number = line_number,
                    .indent = 0,
                    .is_added = false,
                    .is_removed = false,
                },
            },
            .child = null,
            .next = null,
        };
        return node;
    }

    fn createTokenNode(self: *Parser, token: Token) !*Node {
        const node = try self.allocator.create(Node);
        node.* = .{
            .tag = .token,
            .data = .{ .token = token },
            .child = null,
            .next = null,
        };
        return node;
    }
};

// ============================================================================
// JSON Syntax Highlighter
// ============================================================================

const ErrorAnnotation = struct {
    line: usize,
    column: usize,
    message: []const u8,
};

pub const JSONHighlighter = struct {
    allocator: Allocator,
    root: ?*Node,
    local_copy_code: []const u8 = undefined,
    show_cpy_btn: bool = false,
    use_cpy_btn: bool = true,
    errors: std.AutoHashMap(usize, ErrorAnnotation),
    show_toolbar: bool = false,
    coalesced_lines: ?[][]CoalescedSpan = null,

    pub fn init(allocator: Allocator) JSONHighlighter {
        return .{
            .allocator = allocator,
            .root = null,
            .errors = std.AutoHashMap(usize, ErrorAnnotation).init(allocator),
            .coalesced_lines = null,
        };
    }

    pub fn deinit(self: *JSONHighlighter) void {
        if (self.coalesced_lines) |lines| {
            for (lines) |line| {
                self.allocator.free(line);
            }
            self.allocator.free(lines);
        }
        self.errors.deinit();
    }

    pub fn parse(self: *JSONHighlighter, source: []const u8) !void {
        var parser = Parser.init(self.allocator, source);
        const new_source = self.allocator.dupe(u8, source) catch unreachable;
        self.local_copy_code = new_source;
        self.root = try parser.parse();
        try self.buildCoalescedSpans();
    }

    pub fn recompile(self: *JSONHighlighter, source: []const u8) !void {
        const new_source = self.allocator.dupe(u8, source) catch unreachable;
        self.allocator.free(self.local_copy_code);
        self.local_copy_code = new_source;

        var parser = Parser.init(self.allocator, self.local_copy_code);
        self.root = try parser.parse();
        try self.buildCoalescedSpans();
    }

    fn buildCoalescedSpans(self: *JSONHighlighter) !void {
        if (self.root == null) return;

        if (self.coalesced_lines) |old_lines| {
            for (old_lines) |line| {
                self.allocator.free(line);
            }
            self.allocator.free(old_lines);
            self.coalesced_lines = null;
        }

        var line_count: usize = 0;
        var line_iter = self.root.?.child;
        while (line_iter) |line| : (line_iter = line.next) {
            line_count += 1;
        }

        var lines = try self.allocator.alloc([]CoalescedSpan, line_count);
        errdefer self.allocator.free(lines);

        var line_idx: usize = 0;
        line_iter = self.root.?.child;

        while (line_iter) |line_node| : (line_iter = line_node.next) {
            var spans = std.array_list.Managed(CoalescedSpan).init(self.allocator);
            errdefer spans.deinit();

            var token_iter = line_node.child;
            var current_span: ?CoalescedSpan = null;

            while (token_iter) |token_node| : (token_iter = token_node.next) {
                if (token_node.tag != .token) continue;

                const token = token_node.data.token;
                const category = getColorCategory(token);
                if (category == .transparent) continue;

                const has_error = self.errors.contains(token.line + token.column);

                var merged = false;
                if (current_span) |*span| {
                    const prev_end_ptr = @intFromPtr(span.text.ptr) + span.text.len;
                    const current_start_ptr = @intFromPtr(token.text.ptr);

                    if (!span.has_error and !has_error and
                        span.category == category and
                        prev_end_ptr == current_start_ptr)
                    {
                        span.text = span.text.ptr[0 .. span.text.len + token.text.len];
                        merged = true;
                    }
                }

                if (!merged) {
                    if (current_span) |span| {
                        try spans.append(span);
                    }
                    current_span = CoalescedSpan{
                        .text = token.text,
                        .category = category,
                        .token_type = token.type,
                        .start_line = token.line,
                        .start_column = token.column,
                        .has_error = has_error,
                    };
                }
            }

            if (current_span) |span| {
                try spans.append(span);
            }

            lines[line_idx] = try spans.toOwnedSlice();
            line_idx += 1;
        }
        self.coalesced_lines = lines;
    }

    fn getColorCategory(token: Token) ColorCategory {
        return switch (token.type) {
            .string_key => .string_key,
            .string_value => .string_value,
            .number => .number,
            .boolean => .boolean,
            .null_literal => .null_literal,
            .punctuation => .punctuation,
            .comment => .comment,
            .invalid => .invalid,
            .newline => .transparent,
            .whitespace => .default,
        };
    }

    // ========================================================================
    // JSON Validation
    // ========================================================================

    pub fn validateJSON(self: *JSONHighlighter) !void {
        self.errors.clearRetainingCapacity();

        if (self.root == null) return;

        var brace_count: i32 = 0; // { }
        var bracket_count: i32 = 0; // [ ]
        var last_significant_token: ?Token = null;
        var last_was_comma: bool = false;
        var expecting_colon: bool = false;
        var expecting_value: bool = false;
        var in_object_depth: i32 = 0;

        var line_iter = self.root.?.child;
        while (line_iter) |line| {
            var token_iter = line.child;
            while (token_iter) |token_node| {
                if (token_node.tag == .token) {
                    const token = token_node.data.token;

                    // Skip whitespace, newlines, and comments for validation
                    if (token.type == .whitespace or token.type == .newline or token.type == .comment) {
                        token_iter = token_node.next;
                        continue;
                    }

                    // Check for invalid tokens
                    if (token.type == .invalid) {
                        try self.addError(token, "Unexpected token");
                    }

                    // Check for unterminated strings
                    if (token.type == .string_key or token.type == .string_value) {
                        if (!std.mem.endsWith(u8, token.text, "\"")) {
                            try self.addError(token, "Unterminated string literal");
                        }
                    }

                    // Track braces
                    if (std.mem.eql(u8, token.text, "{")) {
                        brace_count += 1;
                        in_object_depth += 1;
                        expecting_value = false;
                        expecting_colon = false;
                        last_was_comma = false;
                    }
                    if (std.mem.eql(u8, token.text, "}")) {
                        brace_count -= 1;
                        in_object_depth -= 1;
                        if (brace_count < 0) {
                            try self.addError(token, "Unmatched closing brace '}'");
                        }
                        // Check for trailing comma before }
                        if (last_was_comma and last_significant_token != null) {
                            try self.addError(last_significant_token.?, "Trailing comma before '}'");
                        }
                        expecting_value = false;
                        expecting_colon = false;
                        last_was_comma = false;
                    }

                    // Track brackets
                    if (std.mem.eql(u8, token.text, "[")) {
                        bracket_count += 1;
                        expecting_value = false;
                        last_was_comma = false;
                    }
                    if (std.mem.eql(u8, token.text, "]")) {
                        bracket_count -= 1;
                        if (bracket_count < 0) {
                            try self.addError(token, "Unmatched closing bracket ']'");
                        }
                        // Check for trailing comma before ]
                        if (last_was_comma and last_significant_token != null) {
                            try self.addError(last_significant_token.?, "Trailing comma before ']'");
                        }
                        expecting_value = false;
                        last_was_comma = false;
                    }

                    // Colon handling
                    if (std.mem.eql(u8, token.text, ":")) {
                        if (!expecting_colon and in_object_depth <= 0) {
                            try self.addError(token, "Unexpected ':'");
                        }
                        expecting_colon = false;
                        expecting_value = true;
                    }

                    // After a key string in object context, expect colon
                    if (token.type == .string_key) {
                        expecting_colon = true;
                    }

                    // Check for double commas
                    if (std.mem.eql(u8, token.text, ",")) {
                        if (last_was_comma) {
                            try self.addError(token, "Unexpected comma");
                        }
                        last_was_comma = true;
                        expecting_value = false;
                    } else if (token.type != .whitespace) {
                        last_was_comma = false;
                    }

                    // Check for non-string keys in objects
                    if (expecting_colon and token.type != .string_key and !std.mem.eql(u8, token.text, ":")) {
                        // The previous token should have been a string key
                    }

                    last_significant_token = token;
                }
                token_iter = token_node.next;
            }
            line_iter = line.next;
        }

        // Check for unclosed braces/brackets
        if (brace_count != 0 and last_significant_token != null) {
            const msg = if (brace_count > 0) "Unclosed brace '{'" else "Extra closing brace '}'";
            try self.addError(last_significant_token.?, msg);
        }
        if (bracket_count != 0 and last_significant_token != null) {
            const msg = if (bracket_count > 0) "Unclosed bracket '['" else "Extra closing bracket ']'";
            try self.addError(last_significant_token.?, msg);
        }

        // Rebuild coalesced spans after validation
        try self.buildCoalescedSpans();
    }

    fn addError(self: *JSONHighlighter, token: Token, message: []const u8) !void {
        try self.errors.put(token.line + token.column, .{
            .line = token.line,
            .column = token.column,
            .message = message,
        });
    }

    fn copy(highlighter: *JSONHighlighter) void {
        Vapor.Clipboard.copy(highlighter.local_copy_code);
        highlighter.show_cpy_btn = true;
        Vapor.registerCtxTimeout("copy_btn_json_editor", 500, toggleIcon, .{highlighter});
    }

    fn toggleIcon(highlighter: *JSONHighlighter) void {
        highlighter.show_cpy_btn = false;
        Vapor.cycle();
    }

    pub fn renderErrors(highlighter: *JSONHighlighter) !void {
        if (highlighter.errors.count() > 0) {
            List()
                .width(.percent(100))
                .height(.percent(100))
                .padding(.all(0))
                .listStyle(.none)
                .direction(.column)
                .children({
                var itr = highlighter.errors.iterator();
                while (itr.next()) |err| {
                    ListItem()
                        .height(.px(64))
                        .width(.percent(100))
                        .background(.hex("#CE1720"))
                        .padding(.all(4))
                        .layout(.left_center)
                        .spacing(8)
                        .children({
                        Box()
                            .padding(.all(8))
                            .layout(.center)
                            .background(.transparentizeHex(.black, 0.2))
                            .children({
                            Vapor.Svg(.{ .svg = svg_bug }).style(&.{
                                .size = .{ .height = .px(16), .width = .px(16) },
                                .visual = .{ .fill = .white },
                            }).end();
                        });

                        Vapor.Stack().children({
                            Text(err.value_ptr.message).style(&.{
                                .visual = .{
                                    .font_size = 15,
                                    .font_weight = 500,
                                    .text_color = .white,
                                    .font_style = .italic,
                                },
                            }).end();
                            Text(Vapor.fmtln("Column {d}, Line: {d}", .{ err.value_ptr.column, err.value_ptr.line })).style(&.{
                                .visual = .{
                                    .font_size = 15,
                                    .font_weight = 500,
                                    .text_color = .white,
                                },
                            }).end();
                        });
                    });
                }
            });
        }
    }

    pub fn render(highlighter: *JSONHighlighter) !void {
        Box().style(&.{
            .position = .relative,
            .direction = .column,
            .layout = .{ .x = .start, .y = .start },
        }).children({
            if (highlighter.show_toolbar) {
                highlighter.renderToolbar();
            }

            Box().style(&.{
                .direction = .column,
                .layout = .{ .x = .start, .y = .start },
                .padding = .all(12),
            }).children({
                Code(&.{ .size = .{ .width = .percent(100), .height = .percent(100) } })({
                    try highlighter.renderOptimized();
                });
            });
        });
    }

    fn renderToolbar(highlighter: *JSONHighlighter) void {
        Box().style(&.{
            .layout = .right_center,
            .size = .w(.percent(100)),
            .padding = .xy(8, 6),
        }).children({
            Box().style(&.{
                .size = .w(.px(72)),
                .layout = .x_even_center,
            }).children({
                CtxButton(copy, .{highlighter})
                    .ariaLabel("copy-json-button")
                    .style(&.{
                        .position = .relative,
                        .size = .square_px(22),
                        .transition = .{ .duration = 100 },
                        .visual = .{
                            .border_radius = .all(4),
                            .background = .transparent,
                            .text_color = .palette(.disabled),
                            .cursor = .pointer,
                        },
                        .interactive = .{
                            .hover = .{ .text_color = .white },
                        },
                        .layout = .center,
                    }).children({
                    if (highlighter.show_cpy_btn) {
                        Icon(.check).style(&.{
                            .visual = .{ .font_size = 16 },
                        }).end();
                    } else {
                        Icon(.clipboard).style(&.{
                            .visual = .{ .font_size = 16 },
                        }).end();
                    }
                });
            });
        });
    }

    pub fn renderOptimized(highlighter: *JSONHighlighter) !void {
        const coalesced = highlighter.coalesced_lines orelse return;

        for (coalesced, 0..) |line_spans, line_idx| {
            var is_added: bool = false;
            var is_removed: bool = false;
            if (line_spans.len > 0) {
                is_added = line_spans[0].is_added;
                is_removed = line_spans[0].is_removed;
            }
            Box().style(&.{
                .size = .hw(.px(22.5), .percent(100)),
                .layout = .left_center,
                .visual = .{ .background = if (is_added) .palette(.code_is_added_color) else if (is_removed) .hex("#FF0000") else .transparent },
            }).children({
                // Line number
                Text(line_idx + 1)
                    .font(14, 600, .palette(.disabled))
                    .fontFamily("DM Mono, monospace")
                    .width(.px(24))
                    .end();

                // Line content - ONE box containing coalesced spans
                Box().style(&.{
                    .size = .h(.px(22.5)),
                    .visual = .{ .white_space = .pre },
                    .layout = .left_center,
                    .padding = .l(12),
                    .font_family = "DM Mono, monospace",
                }).children({
                    for (line_spans) |span| {
                        highlighter.renderSpan(span);
                    }
                });
            });
        }
    }

    fn renderSpan(highlighter: *JSONHighlighter, span: CoalescedSpan) void {
        _ = highlighter;

        const text_decoration: ?Vapor.Types.TextDecoration = if (span.has_error)
            .{ .type = .underline, .style = .wavy, .color = .palette(.danger) }
        else
            null;

        const font_size: u8 = if (Vapor.isMobile()) 16 else 15;

        const color: Vapor.Types.Color = switch (span.category) {
            .string_key => .hex("#82AAFF"), // Keys in blue
            .string_value => .hex("#C3E88D"), // String values in green
            .number => .hex("#F78C6C"), // Numbers in orange
            .boolean => .hex("#C792EA"), // Booleans in purple
            .null_literal => .hex("#C792EA"), // null in purple
            .punctuation => .hex("#89DDFF"), // Structural chars in cyan
            .comment => .hex("#546E7A"), // Comments in gray
            .invalid => .hex("#FF5370"), // Errors in red
            else => .hex("#EEFFFF"),
        };

        if (span.has_error) {
            Tooltip.create(.{ .title = "Error" })
                .Trigger(ErrorText, .{ span.text, font_size, color, text_decoration })
                .end();
        } else {
            Text(span.text)
                .unmanaged()
                .style(&.{
                    .font_family = "DM Mono, monospace",
                    .visual = .{
                        .font_size = font_size,
                        .font_weight = 400,
                        .text_color = color,
                        .text_decoration = text_decoration,
                    },
                }).end();
        }
    }
};

fn ErrorText(text: []const u8, font_size: u8, color: Vapor.Types.Color, text_decoration: ?Vapor.Types.TextDecoration) void {
    Text(text)
        .unmanaged()
        .style(&.{
            .font_family = "DM Mono, monospace",
            .visual = .{
                .font_size = font_size,
                .font_weight = 400,
                .text_color = color,
                .text_decoration = text_decoration,
            },
        }).end();
}

// ============================================================================
// Helper Functions
// ============================================================================

fn isWhitespace(char: u8) bool {
    return char == ' ' or char == '\t' or char == '\r' or char == '\n';
}

pub inline fn Code(style: *const Vapor.Types.Style) fn (void) void {
    const elem_decl = Vapor.ElementDecl{
        .state_type = .static,
        .elem_type = .Code,
        .style = style,
    };
    _ = Vapor.LifeCycle.open(elem_decl);
    Vapor.LifeCycle.configure(elem_decl);
    return Vapor.LifeCycle.close;
}

// ============================================================================
// Tests
// ============================================================================

test "tokenize simple JSON object" {
    const source =
        \\{"name": "Alice", "age": 30}
    ;

    var tokenizer = Tokenizer.init(source);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var tokens = std.array_list.Managed(Token).init(arena.allocator());
    defer tokens.deinit();

    while (tokenizer.next()) |token| {
        try tokens.append(token);
    }

    try std.testing.expect(tokens.items.len > 0);
    // First token should be '{'
    try std.testing.expectEqualStrings("{", tokens.items[0].text);
    try std.testing.expectEqual(TokenType.punctuation, tokens.items[0].type);
}

test "tokenize JSON with booleans and null" {
    const source =
        \\{"active": true, "deleted": false, "notes": null}
    ;

    var tokenizer = Tokenizer.init(source);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var tokens = std.array_list.Managed(Token).init(arena.allocator());
    defer tokens.deinit();

    while (tokenizer.next()) |token| {
        try tokens.append(token);
    }

    // Find the "true" token
    var found_true = false;
    var found_false = false;
    var found_null = false;
    for (tokens.items) |tok| {
        if (tok.type == .boolean and std.mem.eql(u8, tok.text, "true")) found_true = true;
        if (tok.type == .boolean and std.mem.eql(u8, tok.text, "false")) found_false = true;
        if (tok.type == .null_literal) found_null = true;
    }
    try std.testing.expect(found_true);
    try std.testing.expect(found_false);
    try std.testing.expect(found_null);
}

test "tokenize JSON comment (JSONC)" {
    const source =
        \\// This is a comment
        \\{"key": "value"}
    ;

    var tokenizer = Tokenizer.init(source);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var tokens = std.array_list.Managed(Token).init(arena.allocator());
    defer tokens.deinit();

    while (tokenizer.next()) |token| {
        try tokens.append(token);
    }

    try std.testing.expect(tokens.items.len > 0);
    try std.testing.expectEqual(TokenType.comment, tokens.items[0].type);
}

test "parse and validate valid JSON" {
    const source =
        \\{
        \\  "name": "Alice",
        \\  "age": 30,
        \\  "tags": ["a", "b"],
        \\  "active": true
        \\}
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var highlighter = JSONHighlighter.init(arena.allocator());
    defer highlighter.deinit();
    try highlighter.parse(source);
    try highlighter.validateJSON();

    try std.testing.expect(highlighter.errors.count() == 0);
}

test "validate JSON with trailing comma" {
    const source =
        \\{"name": "Alice",}
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var highlighter = JSONHighlighter.init(arena.allocator());
    defer highlighter.deinit();
    try highlighter.parse(source);
    try highlighter.validateJSON();

    try std.testing.expect(highlighter.errors.count() > 0);
}

test "validate JSON with unmatched braces" {
    const source =
        \\{"name": "Alice"
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var highlighter = JSONHighlighter.init(arena.allocator());
    defer highlighter.deinit();
    try highlighter.parse(source);
    try highlighter.validateJSON();

    try std.testing.expect(highlighter.errors.count() > 0);
}

