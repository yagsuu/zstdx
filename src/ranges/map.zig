//! Sorted range maps. See `docs/specs/ranges/map.md`.

const std = @import("std");

const core = @import("core");

const RangeType = @import("range.zig").Range;
const Allocator = std.mem.Allocator;

pub const RangeMap = struct {
    pub fn Static(comptime T: type, comptime V: type, comptime capacity_entries: usize) type {
        comptime if (capacity_entries == 0) {
            @compileError("RangeMap.Static capacity_entries must be non-zero");
        };

        comptime Impl.requireRuntimeValue(V);

        return struct {
            buffer: [capacity_entries]Entry = undefined,
            count: usize = 0,

            const Self = @This();

            pub const Range = RangeType(T);
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

            pub fn asSlice(self: *const Self) []const Entry {
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            pub fn insert(self: *Self, range: Range, value: V) Error!void {
                const plan = try Impl.planInsert(Range, Entry, self.asSlice(), range) orelse return;
                if (plan.count > self.capacity()) {
                    return error.Full;
                }

                Impl.insertAtAssumeCapacity(Entry, self.buffer[0..], &self.count, plan.index, .{ .range = range, .value = value });
            }

            pub fn assign(self: *Self, range: Range, value: V) UpdateError!void {
                const plan = try Impl.planAssign(Range, Entry, self.asSlice(), range) orelse return;
                if (plan.count > self.capacity()) {
                    return error.Full;
                }

                Impl.assignAssumeCapacity(Range, Entry, self.buffer[0..], &self.count, range, value);
            }

            pub fn remove(self: *Self, range: Range) UpdateError!void {
                const plan = try Impl.planRemove(Range, Entry, self.asSlice(), range) orelse return;
                if (plan.count > self.capacity()) {
                    return error.Full;
                }

                Impl.removeAssumeCapacity(Range, Entry, self.buffer[0..], &self.count, range);
            }

            pub fn coalesceAdjacent(self: *Self, context: anytype, comptime eql: core.Eql(@TypeOf(context), V)) void {
                Impl.coalesceEntry(Entry, V, self.buffer[0..], &self.count, context, eql);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.findContaining(value) != null;
            }

            pub fn get(self: *const Self, value: T) ?*const V {
                const entry = self.findContaining(value) orelse return null;
                return &entry.value;
            }

            pub fn containsRange(self: *const Self, range: Range) bool {
                return Impl.containsMappedRange(Range, Entry, self.asSlice(), range);
            }

            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.findIntersecting(range) != null;
            }

            pub fn findContaining(self: *const Self, value: T) ?*const Entry {
                return Impl.findContainingEntry(Entry, self.asSlice(), value);
            }

            pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry {
                return Impl.findIntersectingEntry(Range, Entry, self.asSlice(), range);
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertEntries(Entry, self.buffer[0..], self.count);
            }
        };
    }

    pub fn Bounded(comptime T: type, comptime V: type) type {
        comptime Impl.requireRuntimeValue(V);
        return struct {
            buffer: []Entry,
            count: usize = 0,

            const Self = @This();

            pub const Range = RangeType(T);
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

            pub fn asSlice(self: *const Self) []const Entry {
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            pub fn insert(self: *Self, range: Range, value: V) Error!void {
                const plan = try Impl.planInsert(Range, Entry, self.asSlice(), range) orelse return;
                if (plan.count > self.capacity()) {
                    return error.Full;
                }
                Impl.insertAtAssumeCapacity(Entry, self.buffer, &self.count, plan.index, .{ .range = range, .value = value });
            }

            pub fn assign(self: *Self, range: Range, value: V) UpdateError!void {
                const plan = try Impl.planAssign(Range, Entry, self.asSlice(), range) orelse return;
                if (plan.count > self.capacity()) {
                    return error.Full;
                }
                Impl.assignAssumeCapacity(Range, Entry, self.buffer, &self.count, range, value);
            }

            pub fn remove(self: *Self, range: Range) UpdateError!void {
                const plan = try Impl.planRemove(Range, Entry, self.asSlice(), range) orelse return;
                if (plan.count > self.capacity()) {
                    return error.Full;
                }
                Impl.removeAssumeCapacity(Range, Entry, self.buffer, &self.count, range);
            }

            pub fn coalesceAdjacent(self: *Self, context: anytype, comptime eql: core.Eql(@TypeOf(context), V)) void {
                Impl.coalesceEntry(Entry, V, self.buffer, &self.count, context, eql);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.findContaining(value) != null;
            }

            pub fn get(self: *const Self, value: T) ?*const V {
                const entry = self.findContaining(value) orelse return null;
                return &entry.value;
            }

            pub fn containsRange(self: *const Self, range: Range) bool {
                return Impl.containsMappedRange(Range, Entry, self.asSlice(), range);
            }

            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.findIntersecting(range) != null;
            }

            pub fn findContaining(self: *const Self, value: T) ?*const Entry {
                return Impl.findContainingEntry(Entry, self.asSlice(), value);
            }

            pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry {
                return Impl.findIntersectingEntry(Range, Entry, self.asSlice(), range);
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertEntries(Entry, self.buffer, self.count);
            }
        };
    }
    pub fn Unmanaged(comptime T: type, comptime V: type) type {
        comptime Impl.requireRuntimeValue(V);
        return struct {
            buffer: []Entry = &.{},
            count: usize = 0,

            const Self = @This();

            pub const Range = RangeType(T);
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

            pub fn asSlice(self: *const Self) []const Entry {
                return self.buffer[0..self.count];
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.count = 0;
            }

            pub fn clearAndFree(self: *Self, allocator: Allocator) void {
                if (self.buffer.len != 0) {
                    allocator.free(self.buffer);
                }
                self.buffer = &.{};
                self.count = 0;
            }

            pub fn ensureTotalCapacity(self: *Self, allocator: Allocator, capacity_entries: usize) Allocator.Error!void {
                if (capacity_entries <= self.capacity()) {
                    return;
                }

                const new_capacity = Impl.growCapacity(self.capacity(), capacity_entries);
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
                const plan = try Impl.planInsert(Range, Entry, self.asSlice(), range) orelse return;
                try self.ensureTotalCapacity(allocator, plan.count);
                Impl.insertAtAssumeCapacity(Entry, self.buffer, &self.count, plan.index, .{ .range = range, .value = value });
            }

            pub fn assign(self: *Self, allocator: Allocator, range: Range, value: V) UpdateError!void {
                const plan = try Impl.planAssign(Range, Entry, self.asSlice(), range) orelse return;
                try self.ensureTotalCapacity(allocator, plan.count);
                Impl.assignAssumeCapacity(Range, Entry, self.buffer, &self.count, range, value);
            }

            pub fn remove(self: *Self, allocator: Allocator, range: Range) UpdateError!void {
                const plan = try Impl.planRemove(Range, Entry, self.asSlice(), range) orelse return;
                try self.ensureTotalCapacity(allocator, plan.count);
                Impl.removeAssumeCapacity(Range, Entry, self.buffer, &self.count, range);
            }

            pub fn coalesceAdjacent(self: *Self, context: anytype, comptime eql: core.Eql(@TypeOf(context), V)) void {
                Impl.coalesceEntry(Entry, V, self.buffer, &self.count, context, eql);
            }

            pub fn contains(self: *const Self, value: T) bool {
                return self.findContaining(value) != null;
            }

            pub fn get(self: *const Self, value: T) ?*const V {
                const entry = self.findContaining(value) orelse return null;
                return &entry.value;
            }

            pub fn containsRange(self: *const Self, range: Range) bool {
                return Impl.containsMappedRange(Range, Entry, self.asSlice(), range);
            }

            pub fn overlaps(self: *const Self, range: Range) bool {
                return self.findIntersecting(range) != null;
            }

            pub fn findContaining(self: *const Self, value: T) ?*const Entry {
                return Impl.findContainingEntry(Entry, self.asSlice(), value);
            }

            pub fn findIntersecting(self: *const Self, range: Range) ?*const Entry {
                return Impl.findIntersectingEntry(Range, Entry, self.asSlice(), range);
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertEntries(Entry, self.buffer, self.count);
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

            pub fn asSlice(self: *const Self) []const Entry {
                return self.map.asSlice();
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

const Impl = struct {
    const InsertPlan = struct {
        index: usize,
        count: usize,
    };

    const CountPlan = struct {
        count: usize,
    };

    fn insertionIndex(comptime Entry: type, entries: []const Entry, start: anytype) usize {
        const Search = struct {
            fn before(point: @TypeOf(start), entry: Entry) bool {
                return entry.range.end <= point;
            }
        };
        return std.sort.partitionPoint(Entry, entries, start, Search.before);
    }

    fn planInsert(
        comptime Range: type,
        comptime Entry: type,
        entries: []const Entry,
        range: Range,
    ) error{ InvalidRange, Overlap }!?InsertPlan {
        if (!range.isValid()) {
            return error.InvalidRange;
        }

        if (range.isEmpty()) {
            return null;
        }

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
        const removal = try planRemove(Range, Entry, entries, range) orelse return null;
        return .{ .count = removal.count + 1 };
    }

    fn planRemove(
        comptime Range: type,
        comptime Entry: type,
        entries: []const Entry,
        range: Range,
    ) error{InvalidRange}!?CountPlan {
        if (!range.isValid()) {
            return error.InvalidRange;
        }

        if (range.isEmpty()) {
            return null;
        }

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

    fn growCapacity(current: usize, required: usize) usize {
        var capacity = current;
        while (capacity < required) {
            capacity = capacity +| (capacity / 2 +| 8);
        }
        return capacity;
    }

    fn coalesceEntry(
        comptime Entry: type,
        comptime V: type,
        buffer: []Entry,
        count: *usize,
        context: anytype,
        comptime eql: core.Eql(@TypeOf(context), V),
    ) void {
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
        comptime Entry: type,
        entries: []const Entry,
        value: anytype,
    ) ?*const Entry {
        const Search = struct {
            fn compare(point: @TypeOf(value), entry: Entry) std.math.Order {
                if (point < entry.range.start) {
                    return .lt;
                }
                if (point >= entry.range.end) {
                    return .gt;
                }
                return .eq;
            }
        };
        const index = std.sort.binarySearch(Entry, entries, value, Search.compare) orelse return null;
        return &entries[index];
    }

    fn containsMappedRange(comptime Range: type, comptime Entry: type, entries: []const Entry, range: Range) bool {
        std.debug.assert(range.isValid());
        if (range.isEmpty()) {
            return containsEmptyBoundary(Entry, entries, range.start);
        }

        const first = findContainingEntry(Entry, entries, range.start) orelse return false;
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
        comptime Entry: type,
        entries: []const Entry,
        point: anytype,
    ) bool {
        for (entries) |entry| {
            if (entry.range.start <= point and point <= entry.range.end) {
                return true;
            }
            if (point < entry.range.start) {
                return false;
            }
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
        if (range.isEmpty()) {
            return null;
        }

        const index = insertionIndex(Entry, entries, range.start);
        if (index < entries.len and entries[index].range.start < range.end) {
            return &entries[index];
        }

        return null;
    }

    fn assertEntries(comptime Entry: type, buffer: []const Entry, count: usize) void {
        std.debug.assert(count <= buffer.len);

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
        if (!stored.overlaps(range)) {
            return .disjoint;
        }

        if (range.start <= stored.start and range.end >= stored.end) {
            return .covers;
        }

        if (range.start <= stored.start) {
            return .trim_left;
        }

        if (range.end >= stored.end) {
            return .trim_right;
        }

        return .split;
    }

    fn requireRuntimeValue(comptime V: type) void {
        if (@sizeOf(V) == 0) {
            @compileError("range map value type must have nonzero size");
        }
    }
};

pub const unit = struct {
    const testing = std.testing;

    const Kind = enum { a, b, c };

    fn eqlKind(_: void, lhs: *const Kind, rhs: *const Kind) bool {
        return lhs.* == rhs.*;
    }

    fn neverEql(_: void, _: *const Kind, _: *const Kind) bool {
        return false;
    }

    test "unit: RangeMap construction and capacity" {
        var backing: [3]RangeMap.Bounded(u64, Kind).Entry = undefined;
        var bounded = RangeMap.Bounded(u64, Kind).wrap(&backing);

        try testing.expectEqual(@as(usize, 3), bounded.capacity());

        try bounded.insert(@TypeOf(bounded).Range.of(1, 2), .a);
        bounded.clearRetainingCapacity();

        try testing.expect(bounded.isEmpty());
        try testing.expectEqual(@as(usize, 3), bounded.capacity());

        var zero_backing: [0]RangeMap.Bounded(u8, Kind).Entry = .{};
        var zero_bounded = RangeMap.Bounded(u8, Kind).wrap(&zero_backing);
        try testing.expect(zero_bounded.isEmpty());
        try testing.expect(zero_bounded.isFull());
    }

    test "unit: RangeMap dynamic construction capacity and release" {
        const Unmanaged = RangeMap.Unmanaged(u64, Kind);
        const UnmanagedRange = Unmanaged.Range;

        var unmanaged = Unmanaged.init();
        defer unmanaged.deinit(testing.allocator);

        try unmanaged.ensureTotalCapacity(testing.allocator, 2);
        try testing.expect(unmanaged.capacity() >= 2);

        try unmanaged.insert(testing.allocator, UnmanagedRange.of(1, 2), .a);

        unmanaged.assertValid();
        unmanaged.clearRetainingCapacity();
        try testing.expect(unmanaged.isEmpty());
        try testing.expect(unmanaged.capacity() >= 2);

        unmanaged.clearAndFree(testing.allocator);
        try testing.expectEqual(@as(usize, 0), unmanaged.capacity());

        const Managed = RangeMap.Managed(u64, Kind);
        const ManagedRange = Managed.Range;

        var managed = try Managed.initCapacity(testing.allocator, 2);
        defer managed.deinit();

        try testing.expect(managed.capacity() >= 2);

        try managed.assign(ManagedRange.of(10, 20), .b);

        try testing.expectEqual(Kind.b, managed.get(15).?.*);

        managed.assertValid();
        managed.clearAndFree();
        try testing.expect(managed.isEmpty());
        try testing.expectEqual(@as(usize, 0), managed.capacity());

        try managed.insert(ManagedRange.of(20, 30), .c);

        try testing.expect(managed.capacity() > 0);
        try testing.expectEqual(Kind.c, managed.get(25).?.*);

        managed.assertValid();
    }

    test "unit: RangeMap dynamic mutations grow and preserve entries on allocation failure" {
        try testing.checkAllAllocationFailures(testing.allocator, dynamicAllocationFailures, .{});
        try expectDynamicInsertOutOfMemory();
        try expectDynamicAssignOutOfMemory();
        try expectDynamicRemoveOutOfMemory();
    }

    fn dynamicAllocationFailures(allocator: std.mem.Allocator) !void {
        const Map = RangeMap.Unmanaged(u8, Kind);
        const Range = Map.Range;

        var map = Map.init();
        defer map.deinit(allocator);

        try map.insert(allocator, Range.of(0, 5), .a);
        var before: [1]Map.Entry = undefined;
        @memcpy(before[0..], map.asSlice());

        map.ensureTotalCapacity(allocator, map.capacity() + 1) catch |err| {
            try testing.expectEqualSlices(Map.Entry, &before, map.asSlice());
            return err;
        };
    }

    fn expectDynamicInsertOutOfMemory() !void {
        const Map = RangeMap.Unmanaged(u8, Kind);
        const Range = Map.Range;

        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
        const allocator = failing.allocator();

        var map = Map.init();
        defer map.deinit(allocator);

        try map.ensureTotalCapacity(allocator, 8);
        for (0..8) |index| {
            const start: u8 = @intCast(index * 10);
            try map.insert(allocator, try Range.init(start, start + 5), .a);
        }

        var before: [8]Map.Entry = undefined;
        @memcpy(before[0..], map.asSlice());

        try testing.expectError(error.OutOfMemory, map.insert(allocator, Range.of(80, 85), .b));
        try testing.expectEqualSlices(Map.Entry, &before, map.asSlice());
    }

    fn expectDynamicAssignOutOfMemory() !void {
        const Map = RangeMap.Unmanaged(u8, Kind);
        const Range = Map.Range;

        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
        const allocator = failing.allocator();

        var map = Map.init();
        defer map.deinit(allocator);

        try map.ensureTotalCapacity(allocator, 8);
        for (0..8) |index| {
            const start: u8 = @intCast(index * 10);
            try map.insert(allocator, try Range.init(start, start + 5), .a);
        }

        var before: [8]Map.Entry = undefined;
        @memcpy(before[0..], map.asSlice());

        try testing.expectError(error.OutOfMemory, map.assign(allocator, Range.of(1, 4), .b));
        try testing.expectEqualSlices(Map.Entry, &before, map.asSlice());
    }

    fn expectDynamicRemoveOutOfMemory() !void {
        const Map = RangeMap.Unmanaged(u8, Kind);
        const Range = Map.Range;

        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
        const allocator = failing.allocator();

        var map = Map.init();
        defer map.deinit(allocator);

        try map.ensureTotalCapacity(allocator, 8);
        for (0..8) |index| {
            const start: u8 = @intCast(index * 10);
            try map.insert(allocator, try Range.init(start, start + 5), .a);
        }

        var before: [8]Map.Entry = undefined;
        @memcpy(before[0..], map.asSlice());

        try testing.expectError(error.OutOfMemory, map.remove(allocator, Range.of(1, 4)));
        try testing.expectEqualSlices(Map.Entry, &before, map.asSlice());
    }

    test "unit: RangeMap insert sorts allows adjacency and rejects overlap" {
        const Map = RangeMap.Static(u64, Kind, 4);
        const Range = Map.Range;

        var map = Map.init();

        const last = (try Impl.planInsert(Range, Map.Entry, map.asSlice(), Range.of(30, 40))).?;
        Impl.insertAtAssumeCapacity(Map.Entry, &map.buffer, &map.count, last.index, .{ .range = Range.of(30, 40), .value = .c });

        const first = (try Impl.planInsert(Range, Map.Entry, map.asSlice(), Range.of(10, 20))).?;
        Impl.insertAtAssumeCapacity(Map.Entry, &map.buffer, &map.count, first.index, .{ .range = Range.of(10, 20), .value = .a });

        const middle = (try Impl.planInsert(Range, Map.Entry, map.asSlice(), Range.of(20, 30))).?;
        Impl.insertAtAssumeCapacity(Map.Entry, &map.buffer, &map.count, middle.index, .{ .range = Range.of(20, 30), .value = .a });

        try testing.expectEqualSlices(Map.Entry, &.{
            .{ .range = Range.of(10, 20), .value = .a },
            .{ .range = Range.of(20, 30), .value = .a },
            .{ .range = Range.of(30, 40), .value = .c },
        }, map.asSlice());

        try testing.expect((try Impl.planInsert(Range, Map.Entry, map.asSlice(), Range.empty(25))) == null);
        try testing.expectEqual(@as(usize, 3), map.len());

        try testing.expectError(error.Overlap, Impl.planInsert(Range, Map.Entry, map.asSlice(), Range.of(19, 21)));
        try testing.expectError(error.InvalidRange, Impl.planInsert(Range, Map.Entry, map.asSlice(), .{ .start = 9, .end = 8 }));

        try testing.expectEqualSlices(Map.Entry, &.{
            .{ .range = Range.of(10, 20), .value = .a },
            .{ .range = Range.of(20, 30), .value = .a },
            .{ .range = Range.of(30, 40), .value = .c },
        }, map.asSlice());
    }

    test "unit: RangeMap insert full leaves unchanged" {
        const Map = RangeMap.Static(u8, Kind, 1);
        const Range = Map.Range;

        var map = Map.init();
        try map.insert(Range.of(10, 20), .a);

        try testing.expectError(error.Full, map.insert(Range.of(30, 40), .b));

        try testing.expectEqualSlices(Map.Entry, &.{.{ .range = Range.of(10, 20), .value = .a }}, map.asSlice());
    }

    test "unit: RangeMap assign overlays gaps and entries without auto-coalescing" {
        const Map = RangeMap.Static(u64, Kind, 8);
        const Range = Map.Range;

        var map = Map.init();

        try testing.expect((try Impl.planAssign(Range, Map.Entry, map.asSlice(), Range.empty(3))) == null);
        try testing.expect(map.isEmpty());

        Impl.assignAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, Range.of(0, 10), .a);
        Impl.assignAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, Range.of(20, 30), .b);
        Impl.assignAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, Range.of(5, 25), .c);

        try testing.expectEqualSlices(Map.Entry, &.{
            .{ .range = Range.of(0, 5), .value = .a },
            .{ .range = Range.of(5, 25), .value = .c },
            .{ .range = Range.of(25, 30), .value = .b },
        }, map.asSlice());

        map.clearRetainingCapacity();

        Impl.assignAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, Range.of(0, 100), .a);
        Impl.assignAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, Range.of(40, 60), .b);

        try testing.expectEqualSlices(Map.Entry, &.{
            .{ .range = Range.of(0, 40), .value = .a },
            .{ .range = Range.of(40, 60), .value = .b },
            .{ .range = Range.of(60, 100), .value = .a },
        }, map.asSlice());

        Impl.assignAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, Range.of(100, 110), .a);

        try testing.expectEqual(@as(usize, 4), map.len());
        map.assertValid();
    }

    test "unit: RangeMap assign full and invalid leave unchanged" {
        const Map = RangeMap.Static(u8, Kind, 2);
        const Range = Map.Range;

        var map = Map.init();
        try map.insert(Range.of(0, 10), .a);

        try testing.expectError(error.Full, map.assign(Range.of(3, 7), .b));
        try testing.expectEqualSlices(Map.Entry, &.{.{ .range = Range.of(0, 10), .value = .a }}, map.asSlice());

        try testing.expectError(error.InvalidRange, map.assign(.{ .start = 8, .end = 7 }, .b));
        try testing.expectEqualSlices(Map.Entry, &.{.{ .range = Range.of(0, 10), .value = .a }}, map.asSlice());
    }

    test "unit: RangeMap remove deletes shrinks splits spans and preserves values" {
        const Map = RangeMap.Static(u64, Kind, 6);
        const Range = Map.Range;
        var map = Map.init();

        try map.insert(Range.of(10, 30), .a);

        try testing.expect((try Impl.planRemove(Range, Map.Entry, map.asSlice(), Range.empty(11))) == null);

        Impl.removeAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, Range.of(40, 50));

        try testing.expectEqualSlices(Map.Entry, &.{.{ .range = Range.of(10, 30), .value = .a }}, map.asSlice());

        Impl.removeAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, Range.of(10, 15));
        Impl.removeAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, Range.of(25, 30));
        Impl.removeAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, Range.of(18, 20));

        try testing.expectEqualSlices(Map.Entry, &.{
            .{ .range = Range.of(15, 18), .value = .a },
            .{ .range = Range.of(20, 25), .value = .a },
        }, map.asSlice());

        try map.insert(Range.of(40, 50), .b);
        try map.insert(Range.of(60, 70), .c);

        Impl.removeAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, Range.of(17, 65));

        try testing.expectEqualSlices(Map.Entry, &.{
            .{ .range = Range.of(15, 17), .value = .a },
            .{ .range = Range.of(65, 70), .value = .c },
        }, map.asSlice());

        Impl.removeAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, Range.of(15, 17));

        try testing.expectEqualSlices(Map.Entry, &.{.{ .range = Range.of(65, 70), .value = .c }}, map.asSlice());
    }

    test "unit: RangeMap remove full split and invalid leave unchanged" {
        const Map = RangeMap.Static(u8, Kind, 1);
        const Range = Map.Range;

        var map = Map.init();
        try map.insert(Range.of(10, 30), .a);

        try testing.expectError(error.Full, map.remove(Range.of(15, 20)));
        try testing.expectEqualSlices(Map.Entry, &.{.{ .range = Range.of(10, 30), .value = .a }}, map.asSlice());

        try testing.expectError(error.InvalidRange, map.remove(.{ .start = 8, .end = 7 }));
        try testing.expectEqualSlices(Map.Entry, &.{.{ .range = Range.of(10, 30), .value = .a }}, map.asSlice());
    }

    test "unit: RangeMap queries cover adjacent entries and gaps" {
        const Map = RangeMap.Static(u64, Kind, 4);
        const Range = Map.Range;

        var map = Map.init();

        try map.insert(Range.of(10, 20), .a);
        try map.insert(Range.of(20, 30), .b);
        try map.insert(Range.of(40, 50), .c);

        try testing.expect(Impl.findContainingEntry(Map.Entry, map.asSlice(), 10) != null);
        try testing.expect(Impl.findContainingEntry(Map.Entry, map.asSlice(), 30) == null);
        try testing.expectEqual(Kind.a, Impl.findContainingEntry(Map.Entry, map.asSlice(), @as(u64, 19)).?.value);
        try testing.expect(Impl.findContainingEntry(Map.Entry, map.asSlice(), @as(u64, 30)) == null);
        try testing.expectEqual(Range.of(20, 30), Impl.findContainingEntry(Map.Entry, map.asSlice(), 20).?.range);
        try testing.expect(Impl.containsMappedRange(Range, Map.Entry, map.asSlice(), Range.of(12, 18)));
        try testing.expect(Impl.containsMappedRange(Range, Map.Entry, map.asSlice(), Range.of(12, 30)));
        try testing.expect(!Impl.containsMappedRange(Range, Map.Entry, map.asSlice(), Range.of(12, 40)));
        try testing.expect(Impl.containsMappedRange(Range, Map.Entry, map.asSlice(), Range.empty(10)));
        try testing.expect(Impl.containsMappedRange(Range, Map.Entry, map.asSlice(), Range.empty(30)));
        try testing.expect(!Impl.containsMappedRange(Range, Map.Entry, map.asSlice(), Range.empty(35)));
        try testing.expect(Impl.findIntersectingEntry(Range, Map.Entry, map.asSlice(), Range.of(30, 40)) == null);
        try testing.expect(Impl.findIntersectingEntry(Range, Map.Entry, map.asSlice(), Range.empty(15)) == null);
        try testing.expectEqual(Range.of(40, 50), Impl.findIntersectingEntry(Range, Map.Entry, map.asSlice(), Range.of(35, 45)).?.range);
    }

    test "unit: RangeMap coalesceAdjacent is explicit and callback-driven" {
        const Map = RangeMap.Static(u64, Kind, 5);
        const Range = Map.Range;

        var map = Map.init();

        try map.insert(Range.of(0, 10), .a);
        try map.insert(Range.of(10, 20), .a);
        try map.insert(Range.of(20, 30), .b);
        try map.insert(Range.of(40, 50), .a);

        try testing.expectEqual(@as(usize, 4), map.len());

        Impl.coalesceEntry(Map.Entry, Kind, &map.buffer, &map.count, {}, neverEql);

        try testing.expectEqual(@as(usize, 4), map.len());

        Impl.coalesceEntry(Map.Entry, Kind, &map.buffer, &map.count, {}, eqlKind);

        try testing.expectEqualSlices(Map.Entry, &.{
            .{ .range = Range.of(0, 20), .value = .a },
            .{ .range = Range.of(20, 30), .value = .b },
            .{ .range = Range.of(40, 50), .value = .a },
        }, map.asSlice());
    }

    test "unit: RangeMap coalesceAdjacent merges complete adjacent runs" {
        const Map = RangeMap.Static(u64, Kind, 3);
        const Range = Map.Range;

        var map = Map.init();
        try map.insert(Range.of(0, 10), .a);
        try map.insert(Range.of(10, 20), .a);
        try map.insert(Range.of(20, 30), .a);

        Impl.coalesceEntry(Map.Entry, Kind, &map.buffer, &map.count, {}, eqlKind);

        try testing.expectEqualSlices(Map.Entry, &.{
            .{ .range = Range.of(0, 30), .value = .a },
        }, map.asSlice());
    }

    test "model: RangeMap matches optional array over small domain" {
        const Map = RangeMap.Static(u8, Kind, 32);
        const Range = Map.Range;

        var map = Map.init();
        var model = [_]?Kind{null} ** 32;

        var prng = std.Random.Xoshiro256.init(0x87654321);
        const random = prng.random();

        var step: usize = 0;
        while (step < 180) : (step += 1) {
            const a = random.uintLessThan(u8, 32);
            const b = random.uintLessThan(u8, 32);

            const start = @min(a, b);
            const end = @max(a, b);

            const range = try Range.init(start, end);
            const value: Kind = switch (random.uintLessThan(u8, 3)) {
                0 => .a,
                1 => .b,
                else => .c,
            };

            switch (random.uintLessThan(u8, 4)) {
                0 => if (Impl.planInsert(Range, Map.Entry, map.asSlice(), range)) |maybe_plan| {
                    if (maybe_plan) |plan| {
                        std.debug.assert(plan.count <= map.buffer.len);
                        Impl.insertAtAssumeCapacity(Map.Entry, &map.buffer, &map.count, plan.index, .{ .range = range, .value = value });
                    }
                    for (model[start..end]) |*slot| {
                        slot.* = value;
                    }
                } else |err| switch (err) {
                    error.Overlap => {},
                    else => return err,
                },
                1, 2 => {
                    if (try Impl.planAssign(Range, Map.Entry, map.asSlice(), range)) |plan| {
                        std.debug.assert(plan.count <= map.buffer.len);
                        Impl.assignAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, range, value);
                    }

                    for (model[start..end]) |*slot| {
                        slot.* = value;
                    }
                },
                else => {
                    if (try Impl.planRemove(Range, Map.Entry, map.asSlice(), range)) |plan| {
                        std.debug.assert(plan.count <= map.buffer.len);
                        Impl.removeAssumeCapacity(Range, Map.Entry, &map.buffer, &map.count, range);
                    }

                    for (model[start..end]) |*slot| {
                        slot.* = null;
                    }
                },
            }

            if (random.boolean()) {
                Impl.coalesceEntry(Map.Entry, Kind, &map.buffer, &map.count, {}, eqlKind);
            }

            for (model, 0..) |slot, index| {
                const got = Impl.findContainingEntry(Map.Entry, map.asSlice(), @as(u8, @intCast(index)));
                if (slot) |want| {
                    try testing.expectEqual(want, got.?.value);
                } else {
                    try testing.expectEqual(@as(?*const Map.Entry, null), got);
                }
            }

            for (map.asSlice()) |entry| {
                try testing.expect(entry.range.start < entry.range.end);
                for (entry.range.start..entry.range.end) |index| {
                    try testing.expectEqual(entry.value, model[index].?);
                }
            }
        }
    }

    test "comptime: RangeMap mutates at compile time" {
        comptime {
            const Map = RangeMap.Static(u8, enum { a, b }, 4);
            const Range = Map.Range;

            var map = Map.init();
            try map.insert(Range.of(1, 3), .a);
            try map.assign(Range.of(2, 5), .b);

            std.debug.assert(map.contains(4));
            std.debug.assert(map.get(1).?.* == .a);
            std.debug.assert(map.get(2).?.* == .b);
            std.debug.assert(!map.contains(5));
        }
    }
};
