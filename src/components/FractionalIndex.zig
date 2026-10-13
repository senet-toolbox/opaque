// ============================================================================
// FractionalIndex.zig — Fractional indexing for ordered collections
// ============================================================================
//
// Generates lexicographically-ordered string keys for positioning items.
// When inserting between two items, a key is generated that sorts between
// their existing keys without needing to re-index the whole list.
//
// Keys use lowercase characters [a-z].
//
// SAFETY: All character index arithmetic uses i16 to prevent u8 underflow.
// If `before >= after` lexicographically (which can happen after reorders),
// we fall back to generateAfter(before) which always produces a valid key.

const std = @import("std");

const CHARSET = "abcdefghijklmnopqrstuvwxyz";
const BASE: i16 = 26;

/// Generate a key between `before` and `after`.
/// Pass null for either to indicate start/end of list.
/// Returns a slice from the provided buffer.
pub fn between(
    before: ?[]const u8,
    after: ?[]const u8,
    buf: []u8,
) []const u8 {
    if (before == null and after == null) {
        buf[0] = 'n';
        return buf[0..1];
    }

    if (before == null) {
        return generateBefore(after.?, buf);
    }

    if (after == null) {
        return generateAfter(before.?, buf);
    }

    // Safety check: if before >= after lexicographically,
    // the keys are out of order (can happen after reorders).
    // Fall back to generating a key after `before`.
    if (std.mem.order(u8, before.?, after.?) != .lt) {
        return generateAfter(before.?, buf);
    }

    return generateBetween(before.?, after.?, buf);
}

fn generateBefore(key: []const u8, buf: []u8) []const u8 {
    for (key, 0..) |c, i| {
        const idx = charToIndex(c);
        if (idx > 0) {
            @memcpy(buf[0..i], key[0..i]);
            buf[i] = CHARSET[@intCast(@divTrunc(idx, 2))];
            return buf[0 .. i + 1];
        }
        buf[i] = 'a';
    }
    @memcpy(buf[0..key.len], key);
    buf[key.len] = 'n';
    return buf[0 .. key.len + 1];
}

fn generateAfter(key: []const u8, buf: []u8) []const u8 {
    var i: usize = key.len;
    while (i > 0) {
        i -= 1;
        const idx = charToIndex(key[i]);
        if (idx < BASE - 1) {
            @memcpy(buf[0..i], key[0..i]);
            const half: i16 = @divTrunc(BASE - 1 - idx, 2) + 1;
            buf[i] = CHARSET[@intCast(idx + half)];
            return buf[0 .. i + 1];
        }
    }
    @memcpy(buf[0..key.len], key);
    buf[key.len] = 'n';
    return buf[0 .. key.len + 1];
}

fn generateBetween(before: []const u8, after: []const u8, buf: []u8) []const u8 {
    const min_len = @min(before.len, after.len);

    var common_prefix: usize = 0;
    while (common_prefix < min_len) {
        if (before[common_prefix] != after[common_prefix]) break;
        common_prefix += 1;
    }

    // Copy common prefix
    if (common_prefix > 0) {
        @memcpy(buf[0..common_prefix], before[0..common_prefix]);
    }

    if (common_prefix < min_len) {
        const before_idx = charToIndex(before[common_prefix]);
        const after_idx = charToIndex(after[common_prefix]);
        const gap = after_idx - before_idx;

        if (gap > 1) {
            // Room between the two characters
            buf[common_prefix] = CHARSET[@intCast(before_idx + @divTrunc(gap, 2))];
            return buf[0 .. common_prefix + 1];
        }

        // Characters are adjacent (gap == 1), go deeper.
        // Keep the before character and append something after
        // before[common_prefix+1..].
        buf[common_prefix] = before[common_prefix];

        if (common_prefix + 1 < before.len) {
            const sub_result = generateAfter(before[common_prefix + 1 ..], buf[common_prefix + 1 ..]);
            return buf[0 .. common_prefix + 1 + sub_result.len];
        } else {
            buf[common_prefix + 1] = 'n';
            return buf[0 .. common_prefix + 2];
        }
    }

    // One is a prefix of the other
    if (before.len < after.len) {
        const after_idx = charToIndex(after[before.len]);
        if (after_idx > 0) {
            @memcpy(buf[0..before.len], before);
            buf[before.len] = CHARSET[@intCast(@divTrunc(after_idx, 2))];
            return buf[0 .. before.len + 1];
        }
        @memcpy(buf[0..before.len], before);
        buf[before.len] = 'a';
        buf[before.len + 1] = 'n';
        return buf[0 .. before.len + 2];
    }

    // Fallback
    @memcpy(buf[0..before.len], before);
    buf[before.len] = 'n';
    return buf[0 .. before.len + 1];
}

fn charToIndex(c: u8) i16 {
    if (c >= 'a' and c <= 'z') {
        return @as(i16, c) - 'a';
    }
    return 0;
}

/// Generate initial keys for a list of `count` items,
/// evenly distributed across the keyspace.
pub fn initialKeys(
    count: usize,
    keys_buf: [][]const u8,
    char_buf: []u8,
) [][]const u8 {
    if (count == 0) return keys_buf[0..0];

    const step = @divTrunc(BASE, @as(i16, @intCast(count + 1)));
    var char_offset: usize = 0;

    for (0..count) |i| {
        const idx = step * (@as(i16, @intCast(i)) + 1);
        const clamped: usize = @intCast(@min(idx, BASE - 1));
        char_buf[char_offset] = CHARSET[clamped];
        keys_buf[i] = char_buf[char_offset .. char_offset + 1];
        char_offset += 1;
    }

    return keys_buf[0..count];
}
