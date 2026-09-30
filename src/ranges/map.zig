//! Sorted range maps. See `docs/specs/ranges/map.md`.

const std = @import("std");

const core = @import("../core.zig");

const Allocator = std.mem.Allocator;

pub const RangeMap = struct {
    pub fn Static(comptime T: type, comptime V: type, comptime capacity_entries: usize) type {
        comptime if (capacity_entries == 0) {
            @compileError("RangeMap.Static capacity_entries must be non-zero");
        };

        comptime requireRuntimeValue(V);

        return struct {
            buffer: [capacity_entries]Entry = undefined,
            count: usize = 0,

            const Self = @This();

            pub const Range = core.Range(T);
            pub const Entry = struct {
                range: Range,
                value: V,
            };

            pub const Error = error{ Full, InvalidRange, Overlap };
            pub const UpdateError = error{ Full, InvalidRange };

            pub const entry_capacity = capacity_entries;

            pub fn init() Self {
                return .{};
            }

            pub fn len(self: *const Self) usize {
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return entry_capacity;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == entry_capacity;
            }

            pub fn asConstSlice(self: *const Self) []const Entry {
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            pub fn insert(self: *Self, range: Range, value: V) Error!void {
                const plan = try planInsert(Range, Entry, self.asConstSlice(), range) orelse return;
                if (plan.count > self.capacity()) return error.Full;
                insertAtAssumeCapacity(Entry, self.buffer[0..], &self.count, plan.index, .{ .range = range, .value = value });
            }

            pub fn assign(self: *Self, range: Range, value: V) UpdateError!void {
                const plan = try planAssign(Range, Entry, self.asConstSlice(), range) orelse return;
                if (plan.count > self.capacity()) return error.Full;
                assignAssumeCapacity(Range, Entry, self.buffer[0..], &self.count, range, value);
            }

            pub fn remove(self: *Self, range: Range) UpdateError!void {
                const plan = try planRemove(Range, Entry, self.asConstSlice(), range) orelse return;
                if (plan.count > self.capacity()) return error.Full;
                removeAssumeCapacity(Range, Entry, self.buffer[0..], &self.count, range);
            }

            pub fn coalesceAdjacent(self: *Self, context: anytype, comptime eql: core.Eql(@TypeOf(context), V)) void {
                coalesceEntry(Range, Entry, V, self.buffer[0..], &self.count, context, eql);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.findContaining(value) != null;
            }

            pub fn get(self: *const Self, value: T) ?*const V {
                const entry = self.findContaining(value) orelse return null;
                return &entry.value;
            }

            pub fn containsRange(self: *const Self, range: Range) bool {
                return containsMappedRange(Range, Entry, self.asConstSlice(), range);
            }

            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.findIntersecting(range) != null;
            }

            pub fn findContaining(self: *const Self, value: T) ?*const Entry {
                return findContainingEntry(Range, Entry, self.asConstSlice(), value);
            }

            pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry {
                return findIntersectingEntry(Range, Entry, self.asConstSlice(), range);
            }

            pub fn assertValid(self: *const Self) void {
                assertEntries(Range, Entry, self.buffer[0..], self.count);
            }
        };
    }

    pub fn Bounded(comptime T: type, comptime V: type) type {
        comptime requireRuntimeValue(V);
        return struct {
            buffer: []Entry,
            count: usize = 0,

            const Self = @This();

            pub const Range = core.Range(T);
            pub const Entry = struct {
                range: Range,
                value: V,
            };

            pub const Error = error{ Full, InvalidRange, Overlap };
            pub const UpdateError = error{ Full, InvalidRange };

            pub fn wrap(buffer: []Entry) Self {
                return .{ .buffer = buffer };
            }

            pub fn len(self: *const Self) usize {
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                return self.buffer.len;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == self.capacity();
            }

            pub fn asConstSlice(self: *const Self) []const Entry {
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            pub fn insert(self: *Self, range: Range, value: V) Error!void {
                const plan = try planInsert(Range, Entry, self.asConstSlice(), range) orelse return;
                if (plan.count > self.capacity()) return error.Full;
                insertAtAssumeCapacity(Entry, self.buffer, &self.count, plan.index, .{ .range = range, .value = value });
            }

            pub fn assign(self: *Self, range: Range, value: V) UpdateError!void {
                const plan = try planAssign(Range, Entry, self.asConstSlice(), range) orelse return;
                if (plan.count > self.capacity()) return error.Full;
                assignAssumeCapacity(Range, Entry, self.buffer, &self.count, range, value);
            }

            pub fn remove(self: *Self, range: Range) UpdateError!void {
                const plan = try planRemove(Range, Entry, self.asConstSlice(), range) orelse return;
                if (plan.count > self.capacity()) return error.Full;
                removeAssumeCapacity(Range, Entry, self.buffer, &self.count, range);
            }

            pub fn coalesceAdjacent(self: *Self, context: anytype, comptime eql: core.Eql(@TypeOf(context), V)) void {
                coalesceEntry(Range, Entry, V, self.buffer, &self.count, context, eql);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.findContaining(value) != null;
            }

            pub fn get(self: *const Self, value: T) ?*const V {
                const entry = self.findContaining(value) orelse return null;
                return &entry.value;
            }

            pub fn containsRange(self: *const Self, range: Range) bool {
                return containsMappedRange(Range, Entry, self.asConstSlice(), range);
            }

            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.findIntersecting(range) != null;
            }

            pub fn findContaining(self: *const Self, value: T) ?*const Entry {
                return findContainingEntry(Range, Entry, self.asConstSlice(), value);
            }

            pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry {
                return findIntersectingEntry(Range, Entry, self.asConstSlice(), range);
            }

            pub fn assertValid(self: *const Self) void {
                assertEntries(Range, Entry, self.buffer, self.count);
            }
        };
    }
    pub fn Unmanaged(comptime T: type, comptime V: type) type {
        comptime requireRuntimeValue(V);
        return struct {
            buffer: []Entry = &.{},
            count: usize = 0,

            const Self = @This();

            pub const Range = core.Range(T);
            pub const Entry = struct {
                range: Range,
                value: V,
            };

            pub const Error = error{ OutOfMemory, InvalidRange, Overlap };
            pub const UpdateError = error{ OutOfMemory, InvalidRange };

            pub fn init() Self {
                return .{};
            }

            pub fn initCapacity(allocator: Allocator, capacity_entries: usize) Allocator.Error!Self {
                var self = init();
                try self.ensureTotalCapacity(allocator, capacity_entries);
                return self;
            }

            pub fn deinit(self: *Self, allocator: Allocator) void {
                self.clearAndFree(allocator);
                self.* = undefined;
            }

            pub fn len(self: *const Self) usize {
                return self.count;
            }

            pub fn capacity(self: *const Self) usize {
                return self.buffer.len;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.len() == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.len() == self.capacity();
            }

            pub fn asConstSlice(self: *const Self) []const Entry {
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            pub fn clearAndFree(self: *Self, allocator: Allocator) void {
                if (self.buffer.len != 0) allocator.free(self.buffer);
                self.buffer = &.{};
                self.count = 0;
            }

            pub fn ensureTotalCapacity(self: *Self, allocator: Allocator, capacity_entries: usize) Allocator.Error!void {
                if (capacity_entries <= self.capacity()) return;

                const new_capacity = growCapacity(self.capacity(), capacity_entries);
                if (self.buffer.len != 0) {
                    if (allocator.remap(self.buffer, new_capacity)) |buffer| {
                        self.buffer = buffer;
                        return;
                    }
                }

                const buffer = try allocator.alloc(Entry, new_capacity);
                @memcpy(buffer[0..self.count], self.buffer[0..self.count]);

                if (self.buffer.len != 0) {
                    allocator.free(self.buffer);
                }

                self.buffer = buffer;
            }

            pub fn insert(self: *Self, allocator: Allocator, range: Range, value: V) Error!void {
                const plan = try planInsert(Range, Entry, self.asConstSlice(), range) orelse return;
                try self.ensureTotalCapacity(allocator, plan.count);
                insertAtAssumeCapacity(Entry, self.buffer, &self.count, plan.index, .{ .range = range, .value = value });
            }

            pub fn assign(self: *Self, allocator: Allocator, range: Range, value: V) UpdateError!void {
                const plan = try planAssign(Range, Entry, self.asConstSlice(), range) orelse return;
                try self.ensureTotalCapacity(allocator, plan.count);
                assignAssumeCapacity(Range, Entry, self.buffer, &self.count, range, value);
            }

            pub fn remove(self: *Self, allocator: Allocator, range: Range) UpdateError!void {
                const plan = try planRemove(Range, Entry, self.asConstSlice(), range) orelse return;
                try self.ensureTotalCapacity(allocator, plan.count);
                removeAssumeCapacity(Range, Entry, self.buffer, &self.count, range);
            }

            pub fn coalesceAdjacent(self: *Self, context: anytype, comptime eql: core.Eql(@TypeOf(context), V)) void {
                coalesceEntry(Range, Entry, V, self.buffer, &self.count, context, eql);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.findContaining(value) != null;
            }

            pub fn get(self: *const Self, value: T) ?*const V {
                const entry = self.findContaining(value) orelse return null;
                return &entry.value;
            }

            pub fn containsRange(self: *const Self, range: Range) bool {
                return containsMappedRange(Range, Entry, self.asConstSlice(), range);
            }

            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.findIntersecting(range) != null;
            }

            pub fn findContaining(self: *const Self, value: T) ?*const Entry {
                return findContainingEntry(Range, Entry, self.asConstSlice(), value);
            }

            pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry {
                return findIntersectingEntry(Range, Entry, self.asConstSlice(), range);
            }

            pub fn assertValid(self: *const Self) void {
                assertEntries(Range, Entry, self.buffer, self.count);
            }
        };
    }

    pub fn Managed(comptime T: type, comptime V: type) type {
        const UnmanagedMap = Unmanaged(T, V);
        return struct {
            allocator: Allocator,
            map: UnmanagedMap,

            const Self = @This();

            pub const Range = UnmanagedMap.Range;
            pub const Entry = UnmanagedMap.Entry;
            pub const Error = UnmanagedMap.Error;
            pub const UpdateError = UnmanagedMap.UpdateError;

            pub fn init(allocator: Allocator) Self {
                return .{ .allocator = allocator, .map = UnmanagedMap.init() };
            }

            pub fn initCapacity(allocator: Allocator, capacity_entries: usize) Allocator.Error!Self {
                return .{
                    .allocator = allocator,
                    .map = try UnmanagedMap.initCapacity(allocator, capacity_entries),
                };
            }

            pub fn deinit(self: *Self) void {
                self.map.deinit(self.allocator);
                self.* = undefined;
            }

            pub fn len(self: *const Self) usize {
                return self.map.len();
            }

            pub fn capacity(self: *const Self) usize {
                return self.map.capacity();
            }

            pub fn remaining(self: *const Self) usize {
                return self.map.remaining();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.map.isEmpty();
            }

            pub fn isFull(self: *const Self) bool {
                return self.map.isFull();
            }

            pub fn asConstSlice(self: *const Self) []const Entry {
                return self.map.asConstSlice();
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.map.clearRetainingCapacity();
            }

            pub fn clearAndFree(self: *Self) void {
                self.map.clearAndFree(self.allocator);
            }

            pub fn ensureTotalCapacity(self: *Self, capacity_entries: usize) Allocator.Error!void {
                try self.map.ensureTotalCapacity(self.allocator, capacity_entries);
            }

            pub fn insert(self: *Self, range: Range, value: V) Error!void {
                try self.map.insert(self.allocator, range, value);
            }

            pub fn assign(self: *Self, range: Range, value: V) UpdateError!void {
                try self.map.assign(self.allocator, range, value);
            }

            pub fn remove(self: *Self, range: Range) UpdateError!void {
                try self.map.remove(self.allocator, range);
            }

            pub fn coalesceAdjacent(self: *Self, context: anytype, comptime eql: core.Eql(@TypeOf(context), V)) void {
                self.map.coalesceAdjacent(context, eql);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.map.contains(value);
            }

            pub fn get(self: *const Self, value: T) ?*const V {
                return self.map.get(value);
            }

            pub fn containsRange(self: *const Self, range: Range) bool {
                return self.map.containsRange(range);
            }

            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.map.overlaps(range);
            }

            pub fn findContaining(self: *const Self, value: T) ?*const Entry {
                return self.map.findContaining(value);
            }

            pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry {
                return self.map.findIntersecting(range);
            }

            pub fn assertValid(self: *const Self) void {
                self.map.assertValid();
            }
        };
    }
};

const InsertPlan = struct {
    index: usize,
    count: usize,
};

const CountPlan = struct {
    count: usize,
};

fn insertionIndex(comptime Entry: type, entries: []const Entry, start: anytype) usize {
    var index: usize = 0;
    while (index < entries.len and entries[index].range.end <= start) : (index += 1) {}
    return index;
}

fn planInsert(
    comptime Range: type,
    comptime Entry: type,
    entries: []const Entry,
    range: Range,
) error{ InvalidRange, Overlap }!?InsertPlan {
    if (!range.isValid()) return error.InvalidRange;
    if (range.isEmpty()) return null;

    const index = insertionIndex(Entry, entries, range.start);

    if (index < entries.len and entries[index].range.start < range.end) {
        return error.Overlap;
    }

    return .{ .index = index, .count = entries.len + 1 };
}

fn planAssign(
    comptime Range: type,
    comptime Entry: type,
    entries: []const Entry,
    range: Range,
) error{InvalidRange}!?CountPlan {
    if (!range.isValid()) return error.InvalidRange;
    if (range.isEmpty()) return null;

    return .{ .count = assignedCount(Range, Entry, entries, range) };
}

fn planRemove(
    comptime Range: type,
    comptime Entry: type,
    entries: []const Entry,
    range: Range,
) error{InvalidRange}!?CountPlan {
    if (!range.isValid()) return error.InvalidRange;
    if (range.isEmpty()) return null;

    var count: usize = 0;
    for (entries) |entry| {
        switch (classify(Range, entry.range, range)) {
            .disjoint, .trim_left, .trim_right => count += 1,
            .covers => {},
            .split => count += 2,
        }
    }

    return .{ .count = count };
}

fn insertAtAssumeCapacity(
    comptime Entry: type,
    buffer: []Entry,
    count: *usize,
    index: usize,
    entry: Entry,
) void {
    std.debug.assert(count.* < buffer.len);
    std.mem.copyBackwards(Entry, buffer[index + 1 .. count.* + 1], buffer[index..count.*]);
    buffer[index] = entry;
    count.* += 1;
}

fn eraseAt(comptime Entry: type, buffer: []Entry, count: *usize, index: usize) void {
    std.debug.assert(index < count.*);
    std.mem.copyForwards(Entry, buffer[index .. count.* - 1], buffer[index + 1 .. count.*]);
    count.* -= 1;
}

fn assignAssumeCapacity(
    comptime Range: type,
    comptime Entry: type,
    buffer: []Entry,
    count: *usize,
    range: Range,
    value: anytype,
) void {
    removeAssumeCapacity(Range, Entry, buffer, count, range);

    const index = insertionIndex(Entry, buffer[0..count.*], range.start);
    std.debug.assert(index == count.* or buffer[index].range.start >= range.end);
    insertAtAssumeCapacity(Entry, buffer, count, index, .{ .range = range, .value = value });
}

fn removeAssumeCapacity(
    comptime Range: type,
    comptime Entry: type,
    buffer: []Entry,
    count: *usize,
    range: Range,
) void {
    std.debug.assert(range.isValid());
    std.debug.assert(!range.isEmpty());

    var index: usize = 0;
    while (index < count.*) {
        const stored = buffer[index];
        switch (classify(Range, stored.range, range)) {
            .disjoint => index += 1,
            .covers => eraseAt(Entry, buffer, count, index),
            .trim_left => {
                buffer[index].range.start = range.end;
                index += 1;
            },
            .trim_right => {
                buffer[index].range.end = range.start;
                index += 1;
            },
            .split => {
                buffer[index].range.end = range.start;
                insertAtAssumeCapacity(
                    Entry,
                    buffer,
                    count,
                    index + 1,
                    .{ .range = .{ .start = range.end, .end = stored.range.end }, .value = stored.value },
                );
                index += 2;
            },
        }
    }
}

fn assignedCount(
    comptime Range: type,
    comptime Entry: type,
    entries: []const Entry,
    range: Range,
) usize {
    var result: usize = 1;
    for (entries) |entry| {
        if (entry.range.overlaps(range)) {
            if (entry.range.start < range.start) result += 1;
            if (range.end < entry.range.end) result += 1;
        } else {
            result += 1;
        }
    }
    return result;
}

fn growCapacity(current: usize, required: usize) usize {
    var capacity = current;
    while (capacity < required) {
        capacity = capacity +| (capacity / 2 +| 8);
    }
    return capacity;
}

fn coalesceEntry(
    comptime Range: type,
    comptime Entry: type,
    comptime V: type,
    buffer: []Entry,
    count: *usize,
    context: anytype,
    comptime eql: core.Eql(@TypeOf(context), V),
) void {
    _ = Range;

    var index: usize = 0;
    while (index + 1 < count.*) {
        const left = &buffer[index];
        const right = &buffer[index + 1];

        if (left.range.end != right.range.start or !eql(context, &left.value, &right.value)) {
            index += 1;
            continue;
        }

        left.range.end = right.range.end;
        eraseAt(Entry, buffer, count, index + 1);
    }
}

fn findContainingEntry(
    comptime Range: type,
    comptime Entry: type,
    entries: []const Entry,
    value: anytype,
) ?*const Entry {
    _ = Range;
    var low: usize = 0;
    var high: usize = entries.len;
    while (low < high) {
        const mid = low + @divFloor(high - low, 2);
        if (value < entries[mid].range.start) {
            high = mid;
        } else if (value >= entries[mid].range.end) {
            low = mid + 1;
        } else {
            return &entries[mid];
        }
    }
    return null;
}

fn containsMappedRange(comptime Range: type, comptime Entry: type, entries: []const Entry, range: Range) bool {
    std.debug.assert(range.isValid());
    if (range.isEmpty()) {
        return containsEmptyBoundary(Range, Entry, entries, range.start);
    }

    const first = findContainingEntry(Range, Entry, entries, range.start) orelse return false;
    var covered_end = first.range.end;
    if (covered_end >= range.end) {
        return true;
    }

    var index = @divExact(@intFromPtr(first) - @intFromPtr(entries.ptr), @sizeOf(Entry)) + 1;
    while (index < entries.len and entries[index].range.start <= covered_end) : (index += 1) {
        covered_end = entries[index].range.end;
        if (covered_end >= range.end) {
            return true;
        }
    }

    return false;
}

fn containsEmptyBoundary(
    comptime Range: type,
    comptime Entry: type,
    entries: []const Entry,
    point: anytype,
) bool {
    _ = Range;
    for (entries) |entry| {
        if (entry.range.start <= point and point <= entry.range.end) return true;
        if (point < entry.range.start) return false;
    }
    return false;
}

fn findIntersectingEntry(
    comptime Range: type,
    comptime Entry: type,
    entries: []const Entry,
    range: Range,
) ?*const Entry {
    std.debug.assert(range.isValid());
    if (range.isEmpty()) return null;

    var low: usize = 0;
    var high: usize = entries.len;
    while (low < high) {
        const mid = low + @divFloor(high - low, 2);
        if (entries[mid].range.end <= range.start) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }

    if (low < entries.len and entries[low].range.start < range.end) {
        return &entries[low];
    }

    return null;
}

fn assertEntries(comptime Range: type, comptime Entry: type, buffer: []const Entry, count: usize) void {
    std.debug.assert(count <= buffer.len);

    _ = Range;

    var previous: ?Entry = null;
    for (buffer[0..count]) |entry| {
        std.debug.assert(entry.range.isValid());
        std.debug.assert(!entry.range.isEmpty());

        if (previous) |prev| {
            std.debug.assert(prev.range.end <= entry.range.start);
        }

        previous = entry;
    }
}

const Topology = enum { disjoint, covers, trim_left, trim_right, split };

fn classify(comptime Range: type, stored: Range, range: Range) Topology {
    if (!stored.overlaps(range)) return .disjoint;
    if (range.start <= stored.start and range.end >= stored.end) return .covers;
    if (range.start <= stored.start) return .trim_left;
    if (range.end >= stored.end) return .trim_right;
    return .split;
}

fn requireRuntimeValue(comptime V: type) void {
    if (@sizeOf(V) == 0) @compileError("range map value type must have nonzero size");
}
