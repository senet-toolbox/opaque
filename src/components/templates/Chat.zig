// =============================================================================
// CHAT/MESSAGING INTERFACE
// =============================================================================
// A real-time chat interface component styled to match the Dashboard theme.
// Features include: conversations list, message threads, typing indicators,
// WebSocket communication, reactions, and user presence.
//
// USAGE:
//   1. Call Chat.init() during application startup
//   2. Call Chat.render() in your main render loop
//   3. Optionally call Chat.initWss() to establish WebSocket connection
// =============================================================================

const std = @import("std");
const Vapor = @import("vapor");

// =============================================================================
// VAPOR FRAMEWORK IMPORTS
// =============================================================================

const Text = Vapor.Text;
const Box = Vapor.Box;
const Stack = Vapor.Stack;
const Center = Vapor.Center;
const Icon = Vapor.Icon;
const TextFmt = Vapor.TextFmt;
const TextField = Vapor.TextField;
const Animation = Vapor.Animation;
const ButtonCtx = Vapor.CtxButton;
const DateTime = Vapor.DateTime;

// =============================================================================
// UI COMPONENT IMPORTS
// =============================================================================

const SelectStruct = @import("../../components/Select.zig");
const ToastStruct = @import("../../components/Toast.zig");
const SheetStruct = @import("../../components/Sheet.zig");
const FieldStruct = @import("../../components/Field.zig");
const TooltipStruct = @import("../../components/Tooltip.zig");
const SwitchStruct = @import("../../components/Switch.zig");
const GroupStruct = @import("../../components/Group.zig");
const Button = @import("../../components/Button.zig").Button;
const Alert = @import("../../components/Opaque.zig").Alert;
const TextArea = @import("../../components/Opaque.zig").TextArea;

const Chat = @This();

// =============================================================================
// PUBLIC TYPE ALIASES
// =============================================================================
// Re-export component types for convenience when importing this module

pub const Select = SelectStruct.Select;
pub const Toast = ToastStruct;
pub const Sheet = SheetStruct;
pub const Field = FieldStruct;
pub const Tooltip = TooltipStruct;
pub const Switch = SwitchStruct;
pub const Group = GroupStruct;

// =============================================================================
// THEME CONFIGURATION
// =============================================================================
// Centralized color and styling constants. Modify these to customize appearance.

const Theme = struct {
    // Message bubble colors
    const message_sent = Vapor.Types.Color.hex("#6366f1");
    const message_received = Vapor.Types.Color.hex("#27272a");

    // Background colors
    const bg_base = Vapor.Types.Color.palette(.background);
    const bg_tint = Vapor.Types.Color.palette(.tint);
    const bg_card = Vapor.Types.Color.palette(.background);
    const bg_elevated = Vapor.Types.Color.palette(.background);
    const bg_hover = Vapor.Types.Color.hex("#3f3f46");

    // Border colors
    const border = Vapor.Types.Color.hex("#27272a");
    const border_light = Vapor.Types.Color.hex("#3f3f46");

    // Text colors
    const text = Vapor.Types.Color.palette(.text_color);
    const text_secondary = Vapor.Types.Color.hex("#a1a1aa");
    const text_muted = Vapor.Types.Color.hex("#71717a");

    // Accent and status colors
    const accent = Vapor.Types.Color.hex("#6366f1");
    const accent_hover = Vapor.Types.Color.hex("#818cf8");
    const success = Vapor.Types.Color.hex("#10b981");
    const warning = Vapor.Types.Color.hex("#F5590B");
    const err = Vapor.Types.Color.palette(.danger);

    // Gradient colors (for decorative elements)
    const gradient_start = Vapor.Types.Color.hex("#6366f1");
    const gradient_end = Vapor.Types.Color.hex("#8b5cf6");
};

// =============================================================================
// ANIMATIONS
// =============================================================================
// Pre-defined animations for UI interactions and transitions

const pulse_glow = Animation.init("chat-pulse-glow")
    .prop(.opacity, 1, 0.5)
    .duration(2000)
    .dir(.alternate)
    .infinite();

const slide_up = Animation.init("chat-slide-up")
    .prop(.translateY, 20, 0)
    .prop(.opacity, 0, 1)
    .duration(300)
    .easing(.easeOut)
    .fill(.forwards);

const message_enter = Animation.init("chat-message-enter")
    .prop(.translateY, 10, 0)
    .prop(.opacity, 0, 1)
    .duration(200)
    .easing(.easeOut)
    .fill(.forwards);

const typing_dot = Animation.init("chat-typing-dot")
    .prop(.opacity, 0.3, 1)
    .duration(600)
    .dir(.alternate)
    .delay(200)
    .infinite();

const fade_scale = Animation.init("chat-fade-scale")
    .prop(.scale, 0.95, 1)
    .prop(.opacity, 0, 1)
    .duration(200)
    .easing(.easeOut)
    .fill(.forwards);

// =============================================================================
// DATA TYPES - ENUMS
// =============================================================================

/// Represents the online status of a user
pub const UserStatus = enum {
    online,
    away,
    busy,
    offline,

    /// Returns the color associated with this status
    pub fn color(self: UserStatus) Vapor.Types.Color {
        return switch (self) {
            .online => .hex("#10b981"),
            .away => .hex("#f59e0b"),
            .busy => .hex("#ef4444"),
            .offline => .hex("#6b7280"),
        };
    }

    /// Returns a human-readable label for this status
    pub fn label(self: UserStatus) []const u8 {
        return switch (self) {
            .online => "Online",
            .away => "Away",
            .busy => "Do Not Disturb",
            .offline => "Offline",
        };
    }
};

/// Represents the type of message content
pub const MessageType = enum {
    text,
    image,
    file,
    system,

    /// Returns the icon associated with this message type
    pub fn icon(self: MessageType) *const Vapor.IconTokens {
        return switch (self) {
            .text => .chat,
            .image => .image,
            .file => .paperclip,
            .system => .info_circle,
        };
    }
};

/// Represents the delivery state of a message
pub const MessageState = enum {
    pending, // Sent to server, waiting for confirmation
    sent, // Server confirmed receipt
    delivered, // Delivered to recipient(s)
    read, // Read by recipient(s)
    failed, // Failed to send

    /// Returns the icon associated with this state
    pub fn icon(self: MessageState) *const Vapor.IconTokens {
        return switch (self) {
            .pending => .clock,
            .sent => .check2,
            .delivered => .check2_all,
            .read => .check2_all,
            .failed => .exclamation_circle,
        };
    }

    /// Returns the color associated with this state
    pub fn color(self: MessageState) Vapor.Types.Color {
        return switch (self) {
            .pending => Theme.text_muted,
            .sent => Theme.text_muted,
            .delivered => Theme.accent,
            .read => Theme.success,
            .failed => Theme.err,
        };
    }
};

/// Reaction types for message reactions
const ReactionType = enum {
    heart,
    thumbs_up,
    thumbs_down,
    exclamation,
};

// =============================================================================
// DATA TYPES - STRUCTS
// =============================================================================

/// Represents a user in the chat system
pub const User = struct {
    id: usize,
    name: []const u8,
    avatar: ?[]const u8,
    status: UserStatus,
    last_seen: ?[]const u8,
    wss: ?Vapor.Kit.Wss = null,
};

/// Represents a single chat message
pub const Message = struct {
    id: usize,
    conversation_id: usize,
    sender_id: usize,
    content: []const u8,
    message_type: MessageType,
    timestamp: i64, // Unix timestamp
    is_read: bool,
    reactions: Vapor.Array(Reaction),
    state: MessageState = .pending,
    retry_count: u8 = 0,

    const MAX_RETRIES = 3;

    /// Check if a failed message can be retried
    pub fn canRetry(self: *const Message) bool {
        return self.state == .failed and self.retry_count < MAX_RETRIES;
    }

    /// Format the timestamp for display
    pub fn formatTimestamp(self: *const Message) []const u8 {
        return formatRelativeTime(self.timestamp);
    }
};

/// Represents a reaction on a message
pub const Reaction = struct {
    emoji: []const u8,
    count: u32,
    user_reacted: bool,
};

/// Represents a conversation (chat thread)
pub const Conversation = struct {
    id: usize,
    name: []const u8,
    is_group: bool,
    participants: []const *User,
    last_message: ?[]const u8,
    last_message_time: ?[]const u8,
    unread_count: u32,
    is_pinned: bool,
    is_muted: bool,
};

/// WebSocket message format for wire communication
pub const WebSocketMessage = struct {
    id: []const u8,
    conversation_id: []const u8,
    sender_id: []const u8,
    content: []const u8,
    timestamp: i64,
    msg_type: []const u8 = "message", // message, typing, read_receipt, ack
};

// =============================================================================
// APPLICATION STATE
// =============================================================================

// --- Core Data Collections ---
var users: Vapor.Array(User) = undefined;
var messages: Vapor.Array(Message) = undefined;
var conversations: Vapor.Array(Conversation) = undefined;

// --- Current Session State ---
var current_user: *User = undefined;
var selected_conversation: ?*Conversation = null;

// --- UI Input State ---
var message_input: []const u8 = "";
var search_query: []const u8 = "";

// --- UI Toggle State ---
var show_emoji_picker: bool = false;
var show_attachment_menu: bool = false;
var show_user_profile: bool = false;
var show_new_chat_modal: bool = false;
var is_typing: bool = false;

// --- Filter State ---
var filter_unread: bool = false;
var filter_pinned: bool = false;

// --- Selected Items ---
var selected_user: ?*const User = null;

// --- UI References ---
var scroll_container: Vapor.Binded = .{};

// --- Typing Indicator State ---
var typing_timer: ?u64 = null;
var last_typing_sent: i64 = 0;

// =============================================================================
// COMPONENT INSTANCES
// =============================================================================

var profile_sheet: Sheet = undefined;
var new_chat_alert: Alert = undefined;
var status_select: Select(UserStatus) = undefined;
var select_user: Select(User) = undefined;

// --- Select Options ---
var status_options = [_]Select(UserStatus).Item{
    .{ .value = .online, .label = "Online" },
    .{ .value = .away, .label = "Away" },
    .{ .value = .busy, .label = "Do Not Disturb" },
    .{ .value = .offline, .label = "Appear Offline" },
};

// =============================================================================
// MESSAGE STORAGE
// =============================================================================
// Messages are stored per-conversation for efficient retrieval

var conversation_messages: std.AutoHashMap(usize, Vapor.Array(Message)) = undefined;
var pending_messages: Vapor.Array(*Message) = undefined;

/// Initialize the per-conversation message storage system
pub fn initMessageStorage() void {
    conversation_messages = std.AutoHashMap(usize, Vapor.Array(Message)).init(Vapor.arena(.persist));
    pending_messages = Vapor.array(*Message, .persist);
}

/// Get or create the message array for a specific conversation
pub fn getMessagesForConversation(conv_id: usize) *Vapor.Array(Message) {
    if (conversation_messages.getPtr(conv_id)) |msgs| {
        return msgs;
    }

    // Create new message array for this conversation
    conversation_messages.put(conv_id, Vapor.array(Message, .persist)) catch {
        std.log.err("Failed to create message array for conversation {d}", .{conv_id});
        unreachable;
    };

    return conversation_messages.getPtr(conv_id).?;
}

/// Get messages for the currently selected conversation
pub fn getCurrentMessages() *Vapor.Array(Message) {
    if (selected_conversation) |conv| {
        return getMessagesForConversation(conv.id);
    }
    return &messages; // fallback
}

// =============================================================================
// SAMPLE DATA
// =============================================================================
// Demo data for testing and development. Replace with real data in production.

var sample_users: [6]User = undefined;
var sample_conversations: [5]Conversation = undefined;

fn initSampleData() void {
    // Initialize users
    sample_users = .{
        .{ .id = 1, .name = "You", .avatar = "/assets/avatar1.webp", .status = .online, .last_seen = null },
        .{ .id = 2, .name = "Sarah Chen", .avatar = "/assets/avatar2.webp", .status = .online, .last_seen = null },
        .{ .id = 3, .name = "Mike Johnson", .avatar = "/assets/avatar3.webp", .status = .away, .last_seen = "5 min ago" },
        .{ .id = 4, .name = "Emily Davis", .avatar = "/assets/avatar4.webp", .status = .busy, .last_seen = null },
        .{ .id = 5, .name = "Alex Thompson", .avatar = "/assets/avatar5.webp", .status = .offline, .last_seen = "2 hours ago" },
        .{ .id = 6, .name = "Jordan Lee", .avatar = "/assets/avatar6.webp", .status = .online, .last_seen = null },
    };

    // Initialize user select dropdown
    select_user = .fromItems(&.{
        .{ .value = sample_users[0], .label = sample_users[0].name },
        .{ .value = sample_users[1], .label = sample_users[1].name },
        .{ .value = sample_users[2], .label = sample_users[2].name },
        .{ .value = sample_users[3], .label = sample_users[3].name },
        .{ .value = sample_users[4], .label = sample_users[4].name },
        .{ .value = sample_users[5], .label = sample_users[5].name },
    });
    select_user.trigger = "Select user";
    select_user.on_select = handleSelectUser;

    for (&sample_users) |*user| {
        users.append(user.*) catch continue;
    }

    current_user = &sample_users[0];

    // Initialize conversations
    sample_conversations = .{
        .{ .id = 1, .name = "Sarah Chen", .is_group = false, .participants = &.{ &sample_users[0], &sample_users[1] }, .last_message = "Sounds good! Let me know when you're free", .last_message_time = "2 min", .unread_count = 2, .is_pinned = true, .is_muted = false },
        .{ .id = 2, .name = "Design Team", .is_group = true, .participants = &.{ &sample_users[0], &sample_users[1], &sample_users[2], &sample_users[3] }, .last_message = "Mike: Updated the mockups", .last_message_time = "15 min", .unread_count = 0, .is_pinned = true, .is_muted = false },
        .{ .id = 3, .name = "Mike Johnson", .is_group = false, .participants = &.{ &sample_users[0], &sample_users[2] }, .last_message = "Can you review the PR?", .last_message_time = "1 hour", .unread_count = 1, .is_pinned = false, .is_muted = false },
        .{ .id = 4, .name = "Project Alpha", .is_group = true, .participants = &.{ &sample_users[0], &sample_users[1], &sample_users[4], &sample_users[5] }, .last_message = "Alex: Meeting at 3pm", .last_message_time = "3 hours", .unread_count = 0, .is_pinned = false, .is_muted = true },
        .{ .id = 5, .name = "Emily Davis", .is_group = false, .participants = &.{ &sample_users[0], &sample_users[3] }, .last_message = "Thanks for your help!", .last_message_time = "Yesterday", .unread_count = 0, .is_pinned = false, .is_muted = false },
    };

    for (&sample_conversations) |*conv| {
        conversations.append(conv.*) catch continue;
    }

    // Initialize sample messages for conversation 1
    const base_time = std.time.timestamp() - 3600; // 1 hour ago
    const conv1_messages = getMessagesForConversation(1);

    conv1_messages.appendSlice(&.{
        .{ .id = 1, .conversation_id = 1, .sender_id = 2, .content = "Hey! How's the project going?", .message_type = .text, .timestamp = base_time, .is_read = true, .reactions = Vapor.array(Reaction, .persist), .state = .delivered },
        .{ .id = 2, .conversation_id = 1, .sender_id = 1, .content = "Going well! Just finished the main features", .message_type = .text, .timestamp = base_time + 120, .is_read = true, .reactions = Vapor.array(Reaction, .persist), .state = .read },
        .{ .id = 3, .conversation_id = 1, .sender_id = 2, .content = "That's awesome! Can you share a demo?", .message_type = .text, .timestamp = base_time + 180, .is_read = true, .reactions = Vapor.array(Reaction, .persist), .state = .delivered },
        .{ .id = 4, .conversation_id = 1, .sender_id = 1, .content = "Sure, let me put together a quick video", .message_type = .text, .timestamp = base_time + 300, .is_read = true, .reactions = Vapor.array(Reaction, .persist), .state = .read },
        .{ .id = 5, .conversation_id = 1, .sender_id = 2, .content = "Perfect! No rush though", .message_type = .text, .timestamp = base_time + 360, .is_read = true, .reactions = Vapor.array(Reaction, .persist), .state = .delivered },
        .{ .id = 6, .conversation_id = 1, .sender_id = 1, .content = "I'll have it ready by end of day", .message_type = .text, .timestamp = base_time + 600, .is_read = true, .reactions = Vapor.array(Reaction, .persist), .state = .read },
        .{ .id = 7, .conversation_id = 1, .sender_id = 2, .content = "Sounds good! Let me know when you're free", .message_type = .text, .timestamp = base_time + 720, .is_read = false, .reactions = Vapor.array(Reaction, .persist), .state = .delivered },
    }) catch |err| Vapor.printErr("Failed to init messages: {any}", .{err});

    selected_conversation = &sample_conversations[0];
}

// =============================================================================
// TIME FORMATTING UTILITIES
// =============================================================================

/// Format a timestamp as a relative time string (e.g., "5 min ago", "Yesterday")
fn formatRelativeTime(timestamp: i64) []const u8 {
    const now = Vapor.DateTime.now();
    const msg_time = Vapor.DateTime.fromTimestamp(timestamp) catch unreachable;
    const now_ts = now.toTimestamp();
    const diff = now_ts - timestamp;

    if (diff < 60) {
        return "Just now";
    } else if (diff < 3600) {
        const mins = @divFloor(diff, 60);
        return Vapor.fmtln("{d} min ago", .{mins});
    } else if (diff < 86400) {
        const hours = @divFloor(diff, 3600);
        return Vapor.fmtln("{d}h ago", .{hours});
    } else if (diff < 172800) {
        return Vapor.fmtln("Yesterday {d:0>2}:{d:0>2}", .{ msg_time.hour, msg_time.minute });
    } else if (diff < 604800) {
        const days = @divFloor(diff, 86400);
        return Vapor.fmtln("{d} days ago", .{days});
    } else {
        return Vapor.fmtln("{d:0>2}/{d:0>2}/{d}", .{ msg_time.day, msg_time.month, msg_time.year });
    }
}

/// Format a timestamp as HH:MM
fn formatMessageTime(timestamp: i64) []const u8 {
    const msg_time = Vapor.DateTime.fromTimestamp(timestamp) catch unreachable;
    return Vapor.fmtln("{d:0>2}:{d:0>2}", .{ msg_time.hour, msg_time.minute });
}

// =============================================================================
// WEBSOCKET - CONNECTION MANAGEMENT
// =============================================================================

/// Initialize WebSocket connection for the current user
pub fn initWss() void {
    if (current_user.wss != null) {
        return; // Already connected
    }

    const wss = Vapor.Kit.useWss(.{
        .key = "vapor-chat",
        .query = Vapor.fmtln("?user_id={d}&name={s}", .{ current_user.id, current_user.name }),
        .port = 8080,
        .on_message = onMessage,
        .on_connection = onOpen,
        .on_close = onClose,
    }) catch |err| {
        std.log.err("WebSocket connection failed: {any}", .{err});
        Toast.err(.{ .title = "Connection Failed", .description = "Could not connect to server" });
        return;
    };

    current_user.wss = wss;
}

fn onOpen() void {
    std.log.info("WebSocket connected for user {d}", .{current_user.id});
    Toast.success(.{ .title = "Connected", .description = "" });
    retryFailedMessages();
}

fn onClose() void {
    std.log.info("WebSocket disconnected", .{});
    current_user.wss = null;

    // Mark pending messages as potentially failed
    for (pending_messages.items) |msg| {
        if (msg.state == .pending) {
            msg.state = .failed;
        }
    }

    Toast.warning(.{ .title = "Disconnected", .description = "Attempting to reconnect..." });
}

// =============================================================================
// WEBSOCKET - SENDING MESSAGES
// =============================================================================

/// Send the current message input to the selected conversation
fn sendMessage() void {
    if (message_input.len == 0) return;

    const conv = selected_conversation orelse {
        Toast.err(.{ .title = "No Conversation", .description = "Select a conversation first" });
        return;
    };

    const wss = current_user.wss orelse {
        Toast.err(.{ .title = "Not Connected", .description = "Waiting for connection..." });
        return;
    };

    const msg_list = getMessagesForConversation(conv.id);
    const msg_id = generateMessageId();
    const timestamp = std.time.timestamp();

    // Create local message (optimistic UI update)
    const local_msg = Message{
        .id = msg_id,
        .conversation_id = conv.id,
        .sender_id = current_user.id,
        .content = Vapor.arena(.persist).dupe(u8, message_input) catch return,
        .message_type = .text,
        .timestamp = timestamp,
        .is_read = true,
        .reactions = Vapor.array(Reaction, .persist),
        .state = .pending,
        .retry_count = 0,
    };

    // Add to conversation messages
    msg_list.append(local_msg) catch |err| {
        std.log.err("Failed to append message: {any}", .{err});
        return;
    };

    // Track as pending
    const msg_ptr = &msg_list.items[msg_list.items.len - 1];
    pending_messages.append(msg_ptr) catch {};

    // Create wire message and send
    const wire_msg = WebSocketMessage{
        .id = Vapor.fmtln("{d}", .{msg_id}),
        .conversation_id = Vapor.fmtln("{d}", .{conv.id}),
        .sender_id = Vapor.fmtln("{d}", .{current_user.id}),
        .content = message_input,
        .timestamp = timestamp,
        .msg_type = "message",
    };

    sendWsMessage(wss, wire_msg);

    // Update conversation preview
    conv.last_message = local_msg.content;
    conv.last_message_time = formatRelativeTime(timestamp);

    // Clear input and scroll to bottom
    message_input = "";
    Vapor.onEnd(autoScroll);
}

/// Send a WebSocket message over the wire
fn sendWsMessage(wss: Vapor.Kit.Wss, msg: WebSocketMessage) void {
    const payload = std.json.Stringify.valueAlloc(Vapor.arena(.frame), msg, .{}) catch |err| {
        std.log.err("Failed to serialize message: {any}", .{err});
        return;
    };
    wss.send(payload);
}

/// Retry sending a failed message
fn retryMessage(msg: *Message) void {
    if (!msg.canRetry()) {
        Toast.err(.{ .title = "Message Failed", .description = "Maximum retries exceeded" });
        return;
    }

    const wss = current_user.wss orelse {
        Toast.err(.{ .title = "Not Connected", .description = "" });
        return;
    };

    msg.state = .pending;
    msg.retry_count += 1;

    const wire_msg = WebSocketMessage{
        .id = Vapor.fmtln("{d}", .{msg.id}),
        .conversation_id = Vapor.fmtln("{d}", .{msg.conversation_id}),
        .sender_id = Vapor.fmtln("{d}", .{msg.sender_id}),
        .content = msg.content,
        .timestamp = msg.timestamp,
        .msg_type = "message",
    };

    sendWsMessage(wss, wire_msg);
    Toast.info(.{ .title = "Retrying...", .description = "" });
}

/// Retry all failed messages that can be retried
fn retryFailedMessages() void {
    for (pending_messages.items) |msg| {
        if (msg.state == .failed and msg.canRetry()) {
            retryMessage(msg);
        }
    }
}

/// Generate a unique message ID
fn generateMessageId() usize {
    const timestamp: u64 = @intCast(std.time.timestamp());
    return @as(usize, @truncate(timestamp)) +% current_user.id;
}

// =============================================================================
// WEBSOCKET - RECEIVING MESSAGES
// =============================================================================

/// Main message handler for incoming WebSocket messages
fn onMessage(raw: []const u8) void {
    const parsed = std.json.parseFromSlice(
        WebSocketMessage,
        Vapor.arena(.frame),
        raw,
        .{},
    ) catch |err| {
        std.log.err("Failed to parse message: {any} | raw: {s}", .{ err, raw });
        return;
    };
    defer parsed.deinit();

    const ws_msg = parsed.value;

    // Route based on message type
    if (std.mem.eql(u8, ws_msg.msg_type, "ack")) {
        handleAck(ws_msg);
    } else if (std.mem.eql(u8, ws_msg.msg_type, "typing")) {
        handleTypingIndicator(ws_msg);
    } else if (std.mem.eql(u8, ws_msg.msg_type, "read_receipt")) {
        handleReadReceipt(ws_msg);
    } else {
        handleIncomingMessage(ws_msg);
    }
}

/// Handle message acknowledgment from server
fn handleAck(ws_msg: WebSocketMessage) void {
    const msg_id = std.fmt.parseInt(usize, ws_msg.id, 10) catch return;
    const conv_id = std.fmt.parseInt(usize, ws_msg.conversation_id, 10) catch return;

    const msg_list = getMessagesForConversation(conv_id);

    for (msg_list.items) |*msg| {
        if (msg.id == msg_id and msg.state == .pending) {
            msg.state = .sent;
            removePendingMessage(msg);
            return;
        }
    }
}

/// Handle read receipt from recipient
fn handleReadReceipt(ws_msg: WebSocketMessage) void {
    const conv_id = std.fmt.parseInt(usize, ws_msg.conversation_id, 10) catch return;
    const msg_list = getMessagesForConversation(conv_id);

    for (msg_list.items) |*msg| {
        if (msg.sender_id == current_user.id and msg.state == .delivered) {
            msg.state = .read;
        }
    }
}

/// Handle incoming message from another user
fn handleIncomingMessage(ws_msg: WebSocketMessage) void {
    const sender_id = std.fmt.parseInt(usize, ws_msg.sender_id, 10) catch return;
    const conv_id = std.fmt.parseInt(usize, ws_msg.conversation_id, 10) catch return;
    const msg_id = std.fmt.parseInt(usize, ws_msg.id, 10) catch return;

    // If this is our own message, it's a server echo - mark as sent
    if (sender_id == current_user.id) {
        markMessageSent(conv_id, msg_id);
        return;
    }

    if (ws_msg.content.len == 0) return;

    // Hide typing indicator
    is_typing = false;

    // Add incoming message
    const msg_list = getMessagesForConversation(conv_id);

    const incoming_msg = Message{
        .id = msg_id,
        .conversation_id = conv_id,
        .sender_id = sender_id,
        .content = Vapor.arena(.persist).dupe(u8, ws_msg.content) catch return,
        .message_type = .text,
        .timestamp = ws_msg.timestamp,
        .is_read = false,
        .reactions = Vapor.array(Reaction, .persist),
        .state = .delivered,
    };

    msg_list.append(incoming_msg) catch |err| {
        std.log.err("Failed to append incoming message: {any}", .{err});
        return;
    };

    // Update conversation preview
    updateConversationPreview(conv_id, ws_msg.content, ws_msg.timestamp);

    // Notify if not in this conversation
    if (selected_conversation) |conv| {
        if (conv.id == conv_id) {
            Vapor.onEnd(autoScroll);
        } else {
            incrementUnreadCount(conv_id);
            Toast.info(.{ .title = "New Message", .description = ws_msg.content });
        }
    } else {
        incrementUnreadCount(conv_id);
        Toast.info(.{ .title = "New Message", .description = ws_msg.content });
    }
}

/// Handle typing indicator from another user
fn handleTypingIndicator(ws_msg: WebSocketMessage) void {
    const sender_id = std.fmt.parseInt(usize, ws_msg.sender_id, 10) catch return;
    const conv_id = std.fmt.parseInt(usize, ws_msg.conversation_id, 10) catch return;

    if (selected_conversation) |conv| {
        if (conv.id == conv_id and sender_id != current_user.id) {
            is_typing = true;
        }
    }
}

// =============================================================================
// WEBSOCKET - HELPER FUNCTIONS
// =============================================================================

fn markMessageSent(conv_id: usize, msg_id: usize) void {
    const msg_list = getMessagesForConversation(conv_id);

    for (msg_list.items) |*msg| {
        if (msg.id == msg_id and msg.state == .pending) {
            msg.state = .sent;
            removePendingMessage(msg);
            return;
        }
    }
}

fn updateConversationPreview(conv_id: usize, content: []const u8, timestamp: i64) void {
    for (conversations.items) |*conv| {
        if (conv.id == conv_id) {
            conv.last_message = Vapor.arena(.persist).dupe(u8, content) catch return;
            conv.last_message_time = formatRelativeTime(timestamp);
            return;
        }
    }
}

fn incrementUnreadCount(conv_id: usize) void {
    for (conversations.items) |*conv| {
        if (conv.id == conv_id) {
            conv.unread_count += 1;
            return;
        }
    }
}

fn removePendingMessage(msg: *Message) void {
    for (pending_messages.items, 0..) |pending, i| {
        if (pending == msg) {
            _ = pending_messages.orderedRemove(i);
            return;
        }
    }
}

fn appendIncomingMessage(ws_msg: WebSocketMessage, sender_id: usize) void {
    const msg = Message{
        .id = messages.items.len + 1,
        .sender_id = sender_id,
        .content = Vapor.arena(.persist).dupe(u8, ws_msg.content) catch return,
        .message_type = .text,
        .timestamp = "Just now",
        .is_read = false,
        .reactions = Vapor.array(Reaction, .persist),
        .state = .received,
    };

    messages.append(msg) catch |err| {
        std.log.err("Failed to append incoming message: {any}", .{err});
        return;
    };

    Toast.success(.{ .title = "New Message", .description = "" });
    Vapor.onEnd(autoScroll);
}

// =============================================================================
// TYPING INDICATOR
// =============================================================================

/// Send a typing indicator to the current conversation
fn sendTypingIndicator() void {
    const conv = selected_conversation orelse return;
    const wss = current_user.wss orelse return;

    const now = std.time.timestamp();

    // Throttle: only send every 2 seconds
    if (now - last_typing_sent < 2) return;
    last_typing_sent = now;

    const typing_msg = WebSocketMessage{
        .id = "0",
        .conversation_id = Vapor.fmtln("{d}", .{conv.id}),
        .sender_id = Vapor.fmtln("{d}", .{current_user.id}),
        .content = "",
        .timestamp = now,
        .msg_type = "typing",
    };

    sendWsMessage(wss, typing_msg);
}

fn hideTyping() void {
    is_typing = false;
}

// =============================================================================
// EVENT HANDLERS - CONVERSATION
// =============================================================================

/// Select a conversation and load its messages
fn selectConversation(conv: *Conversation) void {
    selected_conversation = conv;
    conv.unread_count = 0;

    // Load messages for this conversation
    const msg_list = getMessagesForConversation(conv.id);

    // If no messages, could fetch from server here
    if (msg_list.items.len == 0) {
        loadConversationHistory(conv.id);
    }

    // Send read receipts for unread messages
    markConversationAsRead(conv.id);

    // Scroll to bottom
    Vapor.onEnd(autoScroll);
}

/// Load conversation history from server (placeholder for API integration)
fn loadConversationHistory(conv_id: usize) void {
    // In a real app, this would make an HTTP request to load message history
    if (conv_id == 1) {
        const msg_list = getMessagesForConversation(conv_id);
        const base_time = std.time.timestamp() - 3600;

        const sample_messages = [_]Message{
            .{ .id = 1, .conversation_id = 1, .sender_id = 2, .content = "Hey! How's the project going?", .message_type = .text, .timestamp = base_time, .is_read = true, .reactions = Vapor.array(Reaction, .persist), .state = .delivered },
            .{ .id = 2, .conversation_id = 1, .sender_id = 1, .content = "Going well! Just finished the main features", .message_type = .text, .timestamp = base_time + 120, .is_read = true, .reactions = Vapor.array(Reaction, .persist), .state = .read },
            .{ .id = 3, .conversation_id = 1, .sender_id = 2, .content = "That's awesome! Can you share a demo?", .message_type = .text, .timestamp = base_time + 180, .is_read = true, .reactions = Vapor.array(Reaction, .persist), .state = .delivered },
            .{ .id = 4, .conversation_id = 1, .sender_id = 1, .content = "Sure, let me put together a quick video", .message_type = .text, .timestamp = base_time + 300, .is_read = true, .reactions = Vapor.array(Reaction, .persist), .state = .read },
            .{ .id = 5, .conversation_id = 1, .sender_id = 2, .content = "Perfect! No rush though", .message_type = .text, .timestamp = base_time + 360, .is_read = true, .reactions = Vapor.array(Reaction, .persist), .state = .delivered },
            .{ .id = 6, .conversation_id = 1, .sender_id = 1, .content = "I'll have it ready by end of day", .message_type = .text, .timestamp = base_time + 600, .is_read = true, .reactions = Vapor.array(Reaction, .persist), .state = .read },
            .{ .id = 7, .conversation_id = 1, .sender_id = 2, .content = "Sounds good! Let me know when you're free", .message_type = .text, .timestamp = base_time + 720, .is_read = false, .reactions = Vapor.array(Reaction, .persist), .state = .delivered },
        };

        msg_list.appendSlice(&sample_messages) catch {};
    }
}

/// Mark all messages in a conversation as read
fn markConversationAsRead(conv_id: usize) void {
    const wss = current_user.wss orelse return;

    const read_receipt = WebSocketMessage{
        .id = "0",
        .conversation_id = Vapor.fmtln("{d}", .{conv_id}),
        .sender_id = Vapor.fmtln("{d}", .{current_user.id}),
        .content = "",
        .timestamp = std.time.timestamp(),
        .msg_type = "read_receipt",
    };

    sendWsMessage(wss, read_receipt);
}

// =============================================================================
// EVENT HANDLERS - UI ACTIONS
// =============================================================================

fn onMessageEnter(_: *Vapor.Event) void {
    sendMessage();
}

fn autoScroll() void {
    const height = scroll_container.scrollHeight();
    scroll_container.scrollTo(.{ .top = @as(f32, @floatFromInt(height)), .behavior = .smooth });
    scroll_container.scrollToTop(height);
}

fn startAutoScroll() void {
    Vapor.lib.runOnAnimationFrame(autoScroll, .{});
}

fn toggleEmojiPicker() void {
    show_emoji_picker = !show_emoji_picker;
    show_attachment_menu = false;
}

fn toggleAttachmentMenu() void {
    show_attachment_menu = !show_attachment_menu;
    show_emoji_picker = false;
}

fn openNewChatModal() void {
    new_chat_alert.open();
}

fn closeNewChatModal() void {
    new_chat_alert.close();
}

fn viewUserProfile(user: *const User) void {
    selected_user = user;
    profile_sheet.open();
}

fn closeProfileSheet() void {
    profile_sheet.close();
    selected_user = null;
}

fn togglePinConversation(conv: *Conversation) void {
    conv.is_pinned = !conv.is_pinned;
    if (conv.is_pinned) {
        Toast.info(.{ .title = "Conversation Pinned", .description = "" });
    } else {
        Toast.info(.{ .title = "Conversation Unpinned", .description = "" });
    }
}

fn toggleMuteConversation(conv: *Conversation) void {
    conv.is_muted = !conv.is_muted;
    if (conv.is_muted) {
        Toast.info(.{ .title = "Notifications Muted", .description = "" });
    } else {
        Toast.info(.{ .title = "Notifications Enabled", .description = "" });
    }
}

fn toggleFilterUnread() void {
    filter_unread = !filter_unread;
}

fn toggleFilterPinned() void {
    filter_pinned = !filter_pinned;
}

fn handleStatusChange(_: *Select(UserStatus), item: *Select(UserStatus).Item) void {
    current_user.status = item.value;
    Toast.success(.{ .title = "Status Updated", .description = item.value.label() });
}

fn handleSelectUser(_: *Select(User), item: *Select(User).Item) void {
    current_user = &item.value;
    initWss();
}

fn handleAttachment(attachment_type: []const u8) void {
    show_attachment_menu = false;
    Toast.info(.{ .title = "Attachment", .description = attachment_type });
}

fn handleSearch() void {
    Toast.info(.{ .title = "Search", .description = "Search in conversation" });
}

fn handleMoreOptions() void {
    Toast.info(.{ .title = "Options", .description = "More options" });
}

// =============================================================================
// EVENT HANDLERS - REACTIONS
// =============================================================================

fn addReaction(msg: *Message, reaction_type: ReactionType) void {
    if (msg.sender_id == current_user.id) {
        return;
    }

    switch (reaction_type) {
        .heart => msg.reactions.append(.{
            .emoji = "🖤",
            .count = 1,
            .user_reacted = true,
        }) catch return,
        .thumbs_up => msg.reactions.append(.{
            .emoji = "👍",
            .count = 1,
            .user_reacted = true,
        }) catch return,
        .thumbs_down => msg.reactions.append(.{
            .emoji = "👎",
            .count = 1,
            .user_reacted = true,
        }) catch return,
        .exclamation => msg.reactions.append(.{
            .emoji = "❗",
            .count = 1,
            .user_reacted = true,
        }) catch return,
    }
}

// =============================================================================
// FILTER UTILITIES
// =============================================================================

fn matchesConversationFilter(conv: *const Conversation) bool {
    if (filter_unread and conv.unread_count == 0) return false;
    if (filter_pinned and !conv.is_pinned) return false;

    if (search_query.len > 0) {
        const name_lower = std.ascii.allocLowerString(Vapor.arena(.frame), conv.name) catch return true;
        const query_lower = std.ascii.allocLowerString(Vapor.arena(.frame), search_query) catch return true;
        if (std.mem.indexOf(u8, name_lower, query_lower) == null) return false;
    }

    return true;
}

// =============================================================================
// INITIALIZATION
// =============================================================================

/// Initialize the chat interface. Call this once during application startup.
pub fn init() void {
    // Build animations
    pulse_glow.build();
    slide_up.build();
    message_enter.build();
    typing_dot.build();
    fade_scale.build();

    // Initialize component libraries
    SelectStruct.new();
    ToastStruct.new();
    SheetStruct.new();
    FieldStruct.new();
    TooltipStruct.new();
    SwitchStruct.new();
    GroupStruct.new();

    // Initialize data collections
    users = Vapor.array(User, .persist);
    messages = Vapor.array(Message, .persist);
    conversations = Vapor.array(Conversation, .persist);
    initMessageStorage();
    initSampleData();

    // Initialize component instances
    status_select = .fromItems(&status_options);
    status_select.trigger = "Status";
    status_select.on_select = handleStatusChange;

    profile_sheet = Sheet.init(.right);
    profile_sheet.content = renderProfileSheetContent;

    new_chat_alert = .init(renderNewChatModal);
}

// =============================================================================
// RENDER - SIDEBAR
// =============================================================================

fn renderSidebar() void {
    Stack()
        .width(.px(320))
        .height(.percent(100))
        .border(.right(1, .palette(.border_color_light)))
        .children({
        // Header
        Box()
            .width(.percent(100))
            .height(.px(72))
            .padding(.horizontal(20))
            .layout(.x_between_center)
            .border(.bottom(1, .palette(.border_color_light)))
            .children({
            Box()
                .layout(.left_center)
                .spacing(12)
                .children({
                Box()
                    .width(.px(36))
                    .height(.px(36))
                    .background(.black)
                    .border(.round(.black, .all(8)))
                    .layout(.center)
                    .children({
                    Icon(.chat_dots)
                        .font(20, 700, .white)
                        .end();
                });
                Text("Messages")
                    .font(20, 300, Theme.text)
                    .fontFamily("Montserrat")
                    .end();
            });

            Button(openNewChatModal, .{})
                .width(.px(36))
                .height(.px(36))
                .layout(.center)
                .pointer()
                .children({
                Icon(.pencil_square)
                    .font(18, 400, Theme.text_secondary)
                    .end();
            });
        });

        // Search and filters
        Box()
            .width(.percent(100))
            .padding(.all(16))
            .direction(.column)
            .spacing(12)
            .children({
            // Search input
            Box()
                .width(.percent(100))
                .children({
                Field.render(.{ .label = "Search conversations...", .value = .{ .string = &search_query } });
            });

            // Filter buttons
            Box()
                .layout(.left_center)
                .spacing(8)
                .children({
                Button(toggleFilterUnread, .{})
                    .padding(.xy(12, 6))
                    .background(if (filter_unread) .palette(.tint) else .transparent)
                    .border(.round(if (filter_unread) .palette(.tint) else .palette(.border_color_light), .all(6)))
                    .children({
                    Text("Unread")
                        .font(12, 500, if (filter_unread) .palette(.background) else Theme.text_secondary)
                        .fontFamily("Montserrat")
                        .end();
                });
                Button(toggleFilterPinned, .{})
                    .padding(.xy(12, 6))
                    .background(if (filter_pinned) .palette(.tint) else .transparent)
                    .border(.round(if (filter_pinned) .palette(.tint) else .palette(.border_color_light), .all(6)))
                    .children({
                    Text("Pinned")
                        .font(12, 500, if (filter_pinned) .palette(.background) else Theme.text_secondary)
                        .fontFamily("Montserrat")
                        .end();
                });
            });
        });

        // Conversation list
        Stack()
            .width(.percent(100))
            .height(.grow)
            .padding(.all(16))
            .spacing(16)
            .scroll(.scroll_y())
            .children({
            for (conversations.items) |*conv| {
                if (!matchesConversationFilter(conv)) continue;
                renderConversationItem(conv);
            }
        });

        // User status footer
        Box()
            .width(.percent(100))
            .padding(.all(16))
            .height(.px(72))
            .layout(.x_between_center)
            .children({
            Box()
                .layout(.left_center)
                .spacing(8)
                .children({
                // Avatar with status indicator
                Box()
                    .width(.px(32))
                    .height(.px(32))
                    .pos(.relative)
                    .children({
                    Box()
                        .hw(.full, .full)
                        .background(.hex("#4f46e5"))
                        .border(.round(.hex("#4f46e5"), .all(99)))
                        .layout(.center)
                        .children({
                        Text("Y")
                            .font(14, 600, .white)
                            .fontFamily("Montserrat")
                            .end();
                    });
                    Box()
                        .width(.px(12))
                        .height(.px(12))
                        .pos(.br(.px(0), .px(0), .absolute))
                        .background(.{ .color = current_user.status.color() })
                        .border(.round(current_user.status.color(), .all(99)))
                        .children({});
                });
                Stack()
                    .spacing(2)
                    .children({
                    Text(current_user.name)
                        .font(12, 500, Theme.text)
                        .fontFamily("Montserrat")
                        .end();
                    Text(current_user.status.label())
                        .font(12, 400, current_user.status.color())
                        .fontFamily("Montserrat")
                        .end();
                });
            });

            Box()
                .width(.px(156))
                .children({
                status_select.renderPos(.top);
            });
        });
    });
}

fn renderConversationItem(conv: *Conversation) void {
    const is_selected = if (selected_conversation) |sel| sel.id == conv.id else false;

    const shadow = if (is_selected) Vapor.Types.NewShadow.init()
        .drop(4, 4, 4, .transparentizeHex(.black, 0.1)) else null;
    ButtonCtx(selectConversation, .{conv})
        .width(.percent(100))
        .padding(.xy(12, 4))
        .border(.round(.transparent, .all(20)))
        .newShadow(shadow)
        .background(if (is_selected) .palette(.highlight_color) else .transparent)
        .layout(.left_center)
        .spacing(8)
        .pointer()
        .duration(150)
        .hover(.{
            .background = .palette(.highlight_color),
        })
        .children({
        // Avatar
        Box()
            .width(.px(36))
            .height(.px(36))
            .pos(.relative)
            .children({
            if (conv.is_group) {
                Box()
                    .width(.percent(100))
                    .height(.percent(100))
                    .background(Theme.bg_tint)
                    .border(.round(.transparent, .all(99)))
                    .layout(.center)
                    .children({
                    Icon(.people)
                        .font(20, 400, .white)
                        .end();
                });
            } else {
                Box()
                    .width(.percent(100))
                    .height(.percent(100))
                    .border(.round(.transparent, .all(99)))
                    .layout(.center)
                    .children({
                    Vapor.Image(.{ .src = "/assets/Picasso-Bull-11.webp" })
                        .size(.full)
                        .radius(.all(999))
                        .end();
                });
                // Online indicator for direct messages
                if (conv.participants.len > 1) {
                    const other = conv.participants[1];
                    if (other.status == .online) {
                        Box()
                            .width(.px(14))
                            .height(.px(14))
                            .pos(.br(.px(0), .px(0), .absolute))
                            .background(.{ .color = Theme.success })
                            .border(.round(Theme.success, .all(99)))
                            .children({});
                    }
                }
            }
        });

        // Content
        Stack()
            .width(.grow)
            .spacing(4)
            .children({
            Box()
                .layout(.x_between_center)
                .children({
                Box()
                    .layout(.left_center)
                    .spacing(6)
                    .children({
                    if (conv.is_pinned) {
                        Icon(.pin_fill)
                            .font(12, 400, .palette(.text_color))
                            .end();
                    }
                    Text(conv.name)
                        .font(14, if (conv.unread_count > 0) 600 else 200, Theme.text)
                        .fontFamily("Montserrat")
                        .end();
                    if (conv.is_muted) {
                        Icon(.bell_slash)
                            .font(12, 400, Theme.text_muted)
                            .end();
                    }
                });
                if (conv.last_message_time) |time| {
                    Text(time)
                        .font(12, 400, Theme.text_muted)
                        .fontFamily("Montserrat")
                        .end();
                }
            });

            Box()
                .layout(.x_between_center)
                .children({
                if (conv.last_message) |msg| {
                    Text(msg)
                        .font(13, 400, if (conv.unread_count > 0) Theme.text else Theme.text_secondary)
                        .fontFamily("Montserrat")
                        .width(.px(180))
                        .ellipsis(.dot)
                        .end();
                }
                if (conv.unread_count > 0) {
                    Box()
                        .layout(.center)
                        .children({
                        TextFmt("{d}", .{conv.unread_count})
                            .font(11, 600, Theme.text)
                            .fontFamily("Montserrat")
                            .end();
                    });
                }
            });
        });
    });
}

// =============================================================================
// RENDER - CHAT AREA
// =============================================================================

fn renderChatArea() void {
    if (selected_conversation) |conv| {
        const msg_list = getMessagesForConversation(conv.id);
        Stack()
            .width(.grow)
            .height(.percent(100))
            .children({
            // Chat header
            renderChatHeader(conv);

            // Messages area
            Stack()
                .ref(&scroll_container)
                .width(.percent(100))
                .height(.grow)
                .padding(.all(24))
                .spacing(12)
                .scroll(.scroll_y())
                .children({
                for (msg_list.items) |*msg| {
                    renderMessage(msg);
                }

                if (is_typing) {
                    renderTypingIndicator();
                }
            });

            // Message input
            renderMessageInput();
        });
    } else {
        // No conversation selected - show empty state
        renderEmptyState();
    }
}

fn renderChatHeader(conv: *const Conversation) void {
    Box()
        .width(.percent(100))
        .height(.px(72))
        .padding(.horizontal(24))
        .border(.bottom(1, .palette(.border_color_light)))
        .layout(.x_between_center)
        .layer(.line(1, 4, .diagonal_down, .palette(.grid_color)))
        .children({
        Box()
            .layout(.left_center)
            .spacing(16)
            .children({
            // Avatar
            Box()
                .width(.px(36))
                .height(.px(36))
                .border(.round(.transparent, .all(99)))
                .layout(.center)
                .children({
                if (conv.is_group) {
                    Icon(.people)
                        .font(20, 400, .white)
                        .end();
                } else {
                    Vapor.Image(.{ .src = "/assets/me.webp" })
                        .width(.percent(100))
                        .height(.percent(100))
                        .radius(.all(999))
                        .end();
                }
            });
            Stack()
                .spacing(2)
                .children({
                Text(conv.name)
                    .font(16, 600, Theme.text)
                    .fontFamily("Montserrat")
                    .end();
                if (conv.is_group) {
                    TextFmt("{d} members", .{conv.participants.len})
                        .font(13, 400, Theme.text_secondary)
                        .fontFamily("Montserrat")
                        .end();
                } else {
                    Text("Online")
                        .font(13, 400, Theme.success)
                        .fontFamily("Montserrat")
                        .end();
                }
            });
        });

        // Header actions
        Box()
            .layout(.right_center)
            .spacing(8)
            .children({
            Button(togglePinConversation, .{@constCast(conv)})
                .background(if (conv.is_pinned) .transparentizeHex(.palette(.tint), 0.8) else .palette(.text_color))
                .width(.px(36))
                .height(.px(36))
                .layout(.center)
                .pointer()
                .children({
                Icon(if (conv.is_pinned) .pin_fill else .pin)
                    .font(18, 400, if (conv.is_pinned) .palette(.background) else Theme.text_secondary)
                    .end();
            });
            Button(toggleMuteConversation, .{@constCast(conv)})
                .width(.px(36))
                .height(.px(36))
                .layout(.center)
                .pointer()
                .children({
                Icon(if (conv.is_muted) .bell_slash_fill else .bell)
                    .font(18, 400, if (conv.is_muted) Theme.warning else Theme.text_secondary)
                    .end();
            });
            Button(handleSearch, .{})
                .width(.px(36))
                .height(.px(36))
                .layout(.center)
                .pointer()
                .children({
                Icon(.search)
                    .font(18, 400, Theme.text_secondary)
                    .end();
            });
            select_user.renderPos(.bottom);
        });
    });
}

fn renderEmptyState() void {
    Center()
        .width(.grow)
        .height(.percent(100))
        .children({
        Stack()
            .layout(.center)
            .spacing(16)
            .children({
            Box()
                .width(.px(80))
                .height(.px(80))
                .background(.palette(.highlight_color))
                .border(.round(.palette(.border_color_light), .all(99)))
                .layout(.center)
                .children({
                Icon(.chat_dots)
                    .font(36, 400, Theme.text_muted)
                    .end();
            });
            Text("Select a conversation")
                .font(18, 500, Theme.text_secondary)
                .fontFamily("Montserrat")
                .end();
            Text("Choose from your existing conversations or start a new one")
                .font(14, 400, Theme.text_muted)
                .fontFamily("Montserrat")
                .end();
            Button(openNewChatModal, .{})
                .padding(.xy(20, 12))
                .background(.palette(.tint))
                .margin(.t(8))
                .children({
                Icon(.plus)
                    .font(16, 600, .palette(.background))
                    .end();
                Text("New Conversation")
                    .font(14, 500, .palette(.background))
                    .fontFamily("Montserrat")
                    .end();
            });
        });
    });
}

// =============================================================================
// RENDER - MESSAGE COMPONENTS
// =============================================================================

fn renderMessage(msg: *Message) void {
    const is_own_message = msg.sender_id == current_user.id;

    Box()
        .width(.percent(100))
        .minHeight(.px(52))
        .layout(if (is_own_message) .top_right else .top_left)
        .animationEnter("chat-message-enter")
        .children({
        Box()
            .direction(.column)
            .spacing(4)
            .width(.elastic(72, 512))
            .layout(if (is_own_message) .top_right else .top_left)
            .children({
            // Message bubble with tooltip for reactions
            Tooltip.create(.{
                .background = .transparentize(.palette(.border_color_light), 0.3),
                .stroke_color = .palette(.border_color_light),
                .border = .round(.transparent, .all(12)),
            })
                .Trigger(TriggerContent, .{msg})
                .Component(Reactions, .{msg})
                .end();

            // Timestamp and status
            Box()
                .layout(if (is_own_message) .right_center else .left_center)
                .width(.percent(100))
                .spacing(6)
                .children({
                Text(formatMessageTime(msg.timestamp))
                    .font(11, 400, Theme.text_muted)
                    .fontFamily("Montserrat")
                    .end();

                if (is_own_message) {
                    Icon(msg.state.icon())
                        .font(12, 400, msg.state.color())
                        .end();

                    // Retry button for failed messages
                    if (msg.state == .failed) {
                        ButtonCtx(retryMessage, .{msg})
                            .padding(.xy(8, 4))
                            .background(.transparent)
                            .border(.round(Theme.err, .all(4)))
                            .layout(.center)
                            .spacing(4)
                            .pointer()
                            .children({
                            Icon(.arrow_clockwise)
                                .font(10, 400, Theme.err)
                                .end();
                            Text("Retry")
                                .font(10, 500, Theme.err)
                                .fontFamily("Montserrat")
                                .end();
                        });
                    }
                }
            });

            // Reactions display
            if (msg.reactions.items.len > 0) {
                Box()
                    .layout(.left_center)
                    .spacing(4)
                    .children({
                    for (msg.reactions.items) |reaction| {
                        Box()
                            .padding(.xy(6, 3))
                            .background(if (reaction.user_reacted) .transparentizeHex(.palette(.tint), 0.2) else .palette(.highlight_color))
                            .border(.round(.transparent, .all(12)))
                            .layout(.center)
                            .spacing(4)
                            .children({
                            Text(reaction.emoji)
                                .font(12, 400, Theme.text)
                                .end();
                            if (reaction.count > 1) {
                                TextFmt("{d}", .{reaction.count})
                                    .font(11, 500, Theme.text_secondary)
                                    .fontFamily("Montserrat")
                                    .end();
                            }
                        });
                    }
                });
            }
        });
    });
}

/// Render the message bubble content (used as tooltip trigger)
fn TriggerContent(msg: *Message) void {
    const is_own_message = msg.sender_id == current_user.id;
    Box()
        .padding(.xy(16, 8))
        .background(if (is_own_message) .palette(.tint) else Theme.message_received)
        .border(.round(.transparent, .all(16)))
        .pos(.relative)
        .newShadow(Vapor.Types.NewShadow.init()
            .inset(0, -2, .transparentizeHex(.black, 0.2))
            .drop(0, 1, 3, .transparentizeHex(.black, 0.1)))
        .children({
        Text(msg.content)
            .font(14, 400, if (is_own_message) .palette(.background) else .white)
            .fontFamily("Montserrat")
            .end();
    });
}

/// Render the reactions picker tooltip content
fn Reactions(msg: *Message) void {
    Box()
        .width(.px(172))
        .layout(.x_even_center)
        .spacing(8)
        .padding(.all(4)).children({
        reactionBtn(msg, .heart, ReactionType.heart);
        reactionBtn(msg, .thumbs_up, ReactionType.thumbs_up);
        reactionBtn(msg, .thumbs_down, ReactionType.thumbs_down);
        reactionBtn(msg, .exclamation, ReactionType.exclamation);
    });
}

fn reactionBtn(msg: *Message, icon: *const Vapor.IconTokens, reaction_type: ReactionType) void {
    ButtonCtx(addReaction, .{ msg, reaction_type })
        .layout(.center)
        .duration(100)
        .hw(.px(28), .px(28))
        .border(.round(.transparent, .all(8)))
        .hover(.{
            .transform = .scaleDecimal(1.1),
            .background = .palette(.tint),
            .text_color = .palette(.background),
        })
        .textColor(.palette(.text_color))
        .children({
        Icon(icon)
            .font(16, 700, null)
            .end();
    });
}

fn renderTypingIndicator() void {
    Box()
        .layout(.left_center)
        .spacing(8)
        .children({
        Box()
            .width(.px(32))
            .height(.px(32))
            .background(.hex("#3b82f6"))
            .border(.round(.hex("#3b82f6"), .all(99)))
            .layout(.center)
            .children({
            Text("S")
                .font(14, 600, .white)
                .fontFamily("Montserrat")
                .end();
        });
        Box()
            .padding(.xy(16, 12))
            .background(Theme.message_received)
            .border(.round(.palette(.border_color_light), .all(16)))
            .layout(.center)
            .spacing(4)
            .children({
            Box()
                .width(.px(6))
                .height(.px(6))
                .background(.{ .color = Theme.text_muted })
                .border(.round(Theme.text_muted, .all(99)))
                .animation("chat-typing-dot")
                .children({});
            Box()
                .width(.px(6))
                .height(.px(6))
                .background(.{ .color = Theme.text_muted })
                .border(.round(Theme.text_muted, .all(99)))
                .animation("chat-typing-dot")
                .children({});
            Box()
                .width(.px(6))
                .height(.px(6))
                .background(.{ .color = Theme.text_muted })
                .border(.round(Theme.text_muted, .all(99)))
                .animation("chat-typing-dot")
                .children({});
        });
    });
}

// =============================================================================
// RENDER - MESSAGE INPUT
// =============================================================================

fn renderMessageInput() void {
    Box()
        .width(.percent(100))
        .height(.clamp(72, 72, 256))
        .padding(.all(16))
        .spacing(12)
        .children({
        // Attachment button with dropdown
        Box()
            .layout(.bottom_center)
            .pos(.relative)
            .children({
            ButtonCtx(toggleAttachmentMenu, .{})
                .width(.px(36))
                .height(.px(36))
                .layout(.center)
                .pointer()
                .children({
                Icon(.plus_circle)
                    .font(22, 400, Theme.text_secondary)
                    .end();
            });

            if (show_attachment_menu) {
                Box()
                    .pos(.bl(.px(-8), .px(48), .absolute))
                    .padding(.all(8))
                    .background(Theme.bg_card)
                    .border(.round(.palette(.border_color_light), .all(12)))
                    .direction(.column)
                    .spacing(4)
                    .zIndex(100)
                    .animationEnter("chat-fade-scale")
                    .children({
                    renderAttachmentOption(.image, "Photo");
                    renderAttachmentOption(.file, "File");
                    renderAttachmentOption(.camera, "Camera");
                    renderAttachmentOption(.mic, "Voice");
                });
            }
        });

        // Text input
        Box()
            .width(.grow)
            .layout(.bottom_center)
            .children({
            TextArea.render(.{ .label = "Type a message...", .value = .{ .string = &message_input }, .type = .string, .on_enter = onMessageEnter });
        });

        // Send button
        Box()
            .layout(.bottom_center)
            .children({
            Button(sendMessage, .{})
                .width(.px(36))
                .height(.px(36))
                .background(if (message_input.len > 0) .palette(.tint) else .palette(.highlight_color))
                .border(.round(if (message_input.len > 0) .palette(.tint) else .palette(.border_color_light), .all(99)))
                .layout(.center)
                .pointer()
                .children({
                Icon(.send)
                    .font(18, 400, if (message_input.len > 0) .palette(.background) else Theme.text_muted)
                    .end();
            });
        });
    });
}

fn renderAttachmentOption(icon_type: *const Vapor.IconTokens, label: []const u8) void {
    ButtonCtx(handleAttachment, .{label})
        .width(.percent(100))
        .padding(.xy(12, 10))
        .layout(.left_center)
        .spacing(10)
        .pointer()
        .hover(.{ .background = .palette(.highlight_color) })
        .children({
        Icon(icon_type)
            .font(16, 400, Theme.text_secondary)
            .end();
        Text(label)
            .font(13, 400, Theme.text)
            .fontFamily("Montserrat")
            .end();
    });
}

// =============================================================================
// RENDER - MODALS AND SHEETS
// =============================================================================

fn renderProfileSheetContent(_: *Sheet) void {
    if (selected_user) |user| {
        Stack()
            .width(.percent(100))
            .height(.percent(100))
            .padding(.all(24))
            .spacing(24)
            .children({
            // Header
            Box()
                .layout(.x_between_center)
                .children({
                Text("Profile")
                    .font(20, 700, Theme.text)
                    .fontFamily("Montserrat")
                    .end();
                Button(closeProfileSheet, .{})
                    .width(.px(36))
                    .height(.px(36))
                    .layout(.center)
                    .pointer()
                    .children({
                    Icon(.x_lg)
                        .font(16, 400, Theme.text_secondary)
                        .end();
                });
            });

            // Avatar and name
            Stack()
                .width(.percent(100))
                .layout(.center)
                .spacing(16)
                .children({
                Box()
                    .width(.px(80))
                    .height(.px(80))
                    .pos(.relative)
                    .children({
                    Box()
                        .width(.percent(100))
                        .height(.percent(100))
                        .background(.hex("#3b82f6"))
                        .border(.round(.hex("#3b82f6"), .all(99)))
                        .layout(.center)
                        .children({
                        Text(user.name[0..1])
                            .font(32, 600, .white)
                            .fontFamily("Montserrat")
                            .end();
                    });
                    Box()
                        .width(.px(20))
                        .height(.px(20))
                        .pos(.br(.px(0), .px(0), .absolute))
                        .background(.{ .color = user.status.color() })
                        .border(.round(user.status.color(), .all(99)))
                        .children({});
                });
                Text(user.name)
                    .font(24, 700, Theme.text)
                    .fontFamily("Montserrat")
                    .end();
                Text(user.status.label())
                    .font(14, 400, user.status.color())
                    .fontFamily("Montserrat")
                    .end();
            });

            // Info section
            Stack()
                .width(.percent(100))
                .spacing(16)
                .children({
                if (user.last_seen) |last_seen| {
                    renderProfileRow("Last seen", last_seen);
                }
                renderProfileRow("Member since", "January 2024");
            });

            // Actions
            Box()
                .width(.percent(100))
                .layout(.center)
                .spacing(12)
                .children({
                Button(closeProfileSheet, .{})
                    .padding(.xy(20, 12))
                    .background(.palette(.tint))
                    .children({
                    Icon(.chat)
                        .font(16, 400, .palette(.background))
                        .end();
                    Text("Message")
                        .font(14, 500, .palette(.background))
                        .fontFamily("Montserrat")
                        .end();
                });
                Button(closeProfileSheet, .{})
                    .padding(.xy(20, 12))
                    .border(.round(.palette(.border_color_light), .all(8)))
                    .children({
                    Icon(.telephone)
                        .font(16, 400, Theme.text_secondary)
                        .end();
                    Text("Call")
                        .font(14, 500, Theme.text_secondary)
                        .fontFamily("Montserrat")
                        .end();
                });
            });
        });
    }
}

fn renderProfileRow(label: []const u8, value: []const u8) void {
    Box()
        .width(.percent(100))
        .layout(.x_between_center)
        .padding(.vertical(12))
        .border(.bottom(1, .palette(.border_color_light)))
        .children({
        Text(label)
            .font(14, 400, Theme.text_muted)
            .fontFamily("Montserrat")
            .end();
        Text(value)
            .font(14, 500, Theme.text)
            .fontFamily("Montserrat")
            .end();
    });
}

fn renderNewChatModal(_: *Alert) void {
    Box()
        .width(.px(400))
        .padding(.all(24))
        .direction(.column)
        .spacing(20)
        .animationEnter("chat-fade-scale")
        .children({
        // Header
        Box()
            .layout(.x_between_center)
            .children({
            Text("New Conversation")
                .font(20, 700, Theme.text)
                .fontFamily("Montserrat")
                .end();
            Button(closeNewChatModal, .{})
                .width(.px(36))
                .height(.px(36))
                .layout(.center)
                .pointer()
                .children({
                Icon(.x_lg)
                    .font(16, 400, Theme.text_secondary)
                    .end();
            });
        });

        // Search users
        Box()
            .width(.percent(100))
            .children({
            Field.render(.{ .label = "Search users...", .value = .{ .string = &search_query } });
        });

        // User list
        Stack()
            .width(.percent(100))
            .height(.px(300))
            .spacing(8)
            .scroll(.scroll_y())
            .children({
            for (users.items[1..]) |*user| {
                renderUserOption(user);
            }
        });

        // Actions
        Box()
            .layout(.right_center)
            .spacing(12)
            .children({
            Button(closeNewChatModal, .{})
                .padding(.xy(16, 10))
                .border(.round(.palette(.border_color_light), .all(8)))
                .children({
                Text("Cancel")
                    .font(14, 500, Theme.text_secondary)
                    .fontFamily("Montserrat")
                    .end();
            });
            Button(closeNewChatModal, .{})
                .padding(.xy(16, 10))
                .background(.palette(.tint))
                .children({
                Text("Start Chat")
                    .font(14, 500, .palette(.background))
                    .fontFamily("Montserrat")
                    .end();
            });
        });
    });
}

fn renderUserOption(user: *const User) void {
    Box()
        .width(.percent(100))
        .padding(.all(12))
        .layout(.left_center)
        .spacing(12)
        .pointer()
        .hover(.{ .background = .palette(.highlight_color) })
        .border(.round(.palette(.border_color_light), .all(8)))
        .children({
        // Avatar
        Box()
            .width(.px(40))
            .height(.px(40))
            .pos(.relative)
            .children({
            Box()
                .width(.percent(100))
                .height(.percent(100))
                .background(.hex("#3b82f6"))
                .border(.round(.hex("#3b82f6"), .all(99)))
                .layout(.center)
                .children({
                Text(user.name[0..1])
                    .font(16, 600, .white)
                    .fontFamily("Montserrat")
                    .end();
            });
            Box()
                .width(.px(12))
                .height(.px(12))
                .pos(.br(.px(0), .px(0), .absolute))
                .background(.{ .color = user.status.color() })
                .border(.round(user.status.color(), .all(99)))
                .children({});
        });
        Stack()
            .spacing(2)
            .children({
            Text(user.name)
                .font(14, 500, Theme.text)
                .fontFamily("Montserrat")
                .end();
            Text(user.status.label())
                .font(12, 400, user.status.color())
                .fontFamily("Montserrat")
                .end();
        });
    });
}

// =============================================================================
// MAIN RENDER
// =============================================================================

/// Main render function. Call this in your application's render loop.
pub fn render() void {
    Box()
        .width(.percent(100))
        .height(.percent(100))
        .margin(.b(128))
        .background(Theme.bg_base)
        .layout(.top_left)
        .border(.round(.transparent, .all(24)))
        .newShadow(Vapor.Types.NewShadow.init()
            .drop(8, 8, 6, .transparentizeHex(.black, 0.1)))
        .layer(.line(2, 4, .diagonal_up, .palette(.grid_color)))
        .children({
        // Sidebar with conversations list
        renderSidebar();

        // Main chat area
        renderChatArea();

        // Overlay components
        profile_sheet.render();
        new_chat_alert.render();
    });
}
