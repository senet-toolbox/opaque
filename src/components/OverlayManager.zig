const Vapor = @import("vapor");
const std = @import("std");
const EvtInstNode = Vapor.lib.EvtInstNode;
const EvtInst = Vapor.lib.EvtInst;
const Event = Vapor.Event;
const EventType = Vapor.Types.EventType;
const OverlayManager = @This();

const Item = struct { id: usize, erased_cb: Vapor.lib.ErasedEventCallback };

var stack: Vapor.Array(Item) = undefined;

pub fn init() void {
    stack = Vapor.array(Item, .persist);
    _ = Vapor.addGlobalListener(.keydown, onKeyDown);
}

fn call(evt: *Vapor.Event) void {
    const last = stack.items.len - 1;
    const item = stack.items[last];
    item.erased_cb.call(evt);
}

fn onKeyDown(evt: *Vapor.Event) void {
    if (stack.items.len == 0) return;
    const key = evt.key();
    if (std.mem.eql(u8, key, "Escape") or std.mem.eql(u8, "Return", key) or std.mem.eql(u8, "Enter", key) or std.mem.eql(u8, "Tab", key)) {
        call(evt);
    }

    if (std.mem.eql(u8, key, "0") or std.mem.eql(u8, key, "1") or std.mem.eql(u8, key, "2") or std.mem.eql(u8, key, "3") or std.mem.eql(u8, key, "4") or std.mem.eql(u8, key, "5") or std.mem.eql(u8, key, "6") or std.mem.eql(u8, key, "7") or std.mem.eql(u8, key, "8") or std.mem.eql(u8, key, "9")) {
        call(evt);
    }

    if ((std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "x")) and evt.metaKey()) {
        call(evt);
    }

    if (std.mem.eql(u8, key, "ArrowDown") or std.mem.eql(u8, key, "ArrowUp") or std.mem.eql(u8, key, "ArrowLeft") or std.mem.eql(u8, key, "ArrowRight")) {
        call(evt);
    }
}

pub fn register(event_type: EventType, cb: anytype, args: anytype) void {
    const erased = Vapor.lib.ErasedEventCallback.make(Vapor.arena(.persist), event_type, cb, args) catch unreachable;

    const stable_id = @intFromEnum(event_type);
    stack.append(.{ .id = stable_id, .erased_cb = erased }) catch unreachable;
}

pub fn unregister(event_type: EventType, args: anytype) void {
    _ = args;
    _ = event_type;
    _ = stack.pop();
}
