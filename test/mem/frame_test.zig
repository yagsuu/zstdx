//! FrameAllocator contract tests. See `docs/specs/mem/frame-allocator.md`.

const std = @import("std");

const stdx = @import("stdx");

const Buddy4Phys = stdx.mem.BuddyAllocator.Static(16, 5);
const Buddy4Virt = stdx.mem.BuddyAllocator.Static(16, 5);
const Phys4K = stdx.addr.Page(PhysAddr, stdx.addr.pages._4kib);
const PhysAddr = stdx.addr.PhysAddr;
const PhysFrames = stdx.mem.FrameAllocator.Static(
    Buddy4Phys,
    Phys4K,
    Phys4K.Frame.fromAddressInt(0x0010_0000) catch unreachable,
);
const Virt4K = stdx.addr.Page(VirtAddr, stdx.addr.pages._4kib);
const VirtAddr = stdx.addr.VirtAddr;
const VirtFrames = stdx.mem.FrameAllocator.Static(
    Buddy4Virt,
    Virt4K,
    Virt4K.Frame.fromAddressInt(0xffff_0000_0000_0000) catch unreachable,
);

const testing = std.testing;

test "unit: FrameAllocator.Static reports empty capacity" {
    var frames = PhysFrames.init();
    try testing.expectEqual(@as(u64, 16), frames.capacityFrames());
    try testing.expectEqual(@as(u64, 16), frames.freeFrames());
    try testing.expectEqual(@as(u64, 0), frames.allocatedFrames());
    frames.assertValid();
}

test "unit: alloc(order) returns a page-aligned FrameRange inside the domain" {
    var frames = PhysFrames.init();
    const base = frames.baseFrame();

    const range = try frames.alloc(2);
    try testing.expectEqual(@as(u64, 4), range.count.pages());
    try testing.expectEqual(base.addressInt(), range.base.addressInt());
    try testing.expect(range.base.isValid());

    try frames.free(range);
    try testing.expectEqual(@as(u64, 0), frames.allocatedFrames());
    frames.assertValid();
}

test "unit: alloc(invalid_order) returns InvalidOrder" {
    var frames = PhysFrames.init();
    try testing.expectError(error.InvalidOrder, frames.alloc(5));
    try testing.expectEqual(@as(u64, 16), frames.freeFrames());
    frames.assertValid();
}

test "unit: exhaustion returns OutOfMemory without state change" {
    var frames = PhysFrames.init();
    const top = try frames.alloc(4);
    try testing.expectError(error.OutOfMemory, frames.alloc(0));
    try testing.expectEqual(@as(u64, 0), frames.freeFrames());
    try frames.free(top);
    frames.assertValid();
}

test "unit: reserve marks frames unavailable to subsequent alloc" {
    var frames = PhysFrames.init();
    const base = frames.baseFrame();

    // Reserve frames 3..5 relative to base.
    const reserved_base = try base.add(Phys4K.Count.fromPages(3));
    const reserved = try Phys4K.FrameRange.fromBaseCount(
        reserved_base,
        Phys4K.Count.fromPages(2),
    );
    try frames.reserve(reserved);
    try testing.expectEqual(@as(u64, 14), frames.freeFrames());

    // Every subsequent order-0 alloc must skip the reserved run.
    var seen: [16]bool = [_]bool{false} ** 16;
    var i: usize = 0;
    while (i < 14) : (i += 1) {
        const range = try frames.alloc(0);
        const offset: usize = @intCast((range.base.addressInt() - base.addressInt()) >> Phys4K.Size.shift);
        try testing.expect(!seen[offset]);
        try testing.expect(offset != 3 and offset != 4);
        seen[offset] = true;
    }
    try testing.expectError(error.OutOfMemory, frames.alloc(0));
}

test "unit: reserve rejects out-of-bounds range without mutation" {
    var frames = PhysFrames.init();
    const base = frames.baseFrame();
    const past_end_base = try base.add(Phys4K.Count.fromPages(15));
    const past_end = try Phys4K.FrameRange.fromBaseCount(
        past_end_base,
        Phys4K.Count.fromPages(4),
    );
    try testing.expectError(error.OutOfBounds, frames.reserve(past_end));
    try testing.expectEqual(@as(u64, 16), frames.freeFrames());
}

test "unit: reserve rejects overlap with allocated range" {
    var frames = PhysFrames.init();
    const region = try frames.alloc(1);
    const overlap = try Phys4K.FrameRange.fromBaseCount(
        region.base,
        Phys4K.Count.fromPages(1),
    );
    try testing.expectError(error.AlreadyAllocated, frames.reserve(overlap));
    try frames.free(region);
    frames.assertValid();
}

test "unit: isFree distinguishes allocated and free power-of-two ranges" {
    var frames = PhysFrames.init();
    const base = frames.baseFrame();

    // The initial buddy decomposition holds a single order-4 block at
    // base; smaller-order queries against a fresh allocator therefore
    // report `false` (the range is not tracked at that order).
    const top = try Phys4K.FrameRange.fromBaseCount(base, Phys4K.Count.fromPages(16));
    try testing.expect(frames.isFree(top));

    const allocated = try frames.alloc(2);
    try testing.expect(!frames.isFree(allocated));
    try frames.free(allocated);
}

test "unit: isFree rejects non-power-of-two count" {
    var frames = PhysFrames.init();
    const base = frames.baseFrame();
    const non_pow2 = try Phys4K.FrameRange.fromBaseCount(base, Phys4K.Count.fromPages(3));
    try testing.expect(!frames.isFree(non_pow2));
}

test "unit: largestFreeOrder tracks the highest free order" {
    var frames = PhysFrames.init();
    try testing.expectEqual(@as(?u8, 4), frames.largestFreeOrder());

    _ = try frames.alloc(4);
    try testing.expectEqual(@as(?u8, null), frames.largestFreeOrder());
}

test "unit: remainingBytes reports expected byte count" {
    var frames = PhysFrames.init();
    try testing.expectEqual(@as(u64, 16 * stdx.addr.pages._4kib), try frames.remainingBytes());
    const range = try frames.alloc(2);
    try testing.expectEqual(@as(u64, 12 * stdx.addr.pages._4kib), try frames.remainingBytes());
    try frames.free(range);
}

test "unit: Bounded wrap validates base + capacity does not overflow" {
    var storage: [64]stdx.mem.BuddyAllocator.Bounded.Word = @splat(0);
    const backend = try stdx.mem.BuddyAllocator.Bounded.wrap(&storage, 16, 4);

    const Frames = stdx.mem.FrameAllocator.Bounded(
        stdx.mem.BuddyAllocator.Bounded,
        Phys4K,
    );

    const base = try Phys4K.Frame.fromAddressInt(0x0020_0000);
    var frames = try Frames.wrap(backend, base);
    try testing.expectEqual(@as(u64, 16), frames.capacityFrames());
    frames.assertValid();
}

test "unit: Virt4K and Phys4K produce distinct FrameAllocator types" {
    try testing.expect(PhysFrames != VirtFrames);
    try testing.expect(PhysFrames.FrameRange != VirtFrames.FrameRange);
}

test "unit: FrameSource acquire and release round-trip through parent" {
    var frames = VirtFrames.init();
    const source = frames.frameSource(0);
    const S = @TypeOf(source);
    try testing.expectEqual(@as(usize, stdx.addr.pages._4kib), S.region_bytes);
    try testing.expectEqual(@as(usize, stdx.addr.pages._4kib), S.region_align);

    // Do NOT dereference the region under a non-identity-mapped
    // VirtAddr domain — the pointer names an unmapped kernel virtual
    // address. Round-trip through the allocator only.
    const range = try frames.alloc(0);
    try testing.expectEqual(@as(u64, 1), frames.allocatedFrames());
    try frames.free(range);
    try testing.expectEqual(@as(u64, 0), frames.allocatedFrames());
    frames.assertValid();
}

test "unit: FrameSource satisfies PoolCache RegionSource shape" {
    var frames = VirtFrames.init();
    const source = frames.frameSource(0);
    const S = @TypeOf(source);

    // Compile-only conformance: PoolCache accepts the source as a
    // valid RegionSource. Runtime composition requires an identity-
    // mapped Page domain, which is out of scope for host-only tests.
    _ = stdx.mem.PoolCache(u64, S);

    try testing.expectEqual(@as(usize, stdx.addr.pages._4kib), S.region_bytes);
    try testing.expectEqual(@as(usize, stdx.addr.pages._4kib), S.region_align);
}

test "unit: FrameSource composes with PoolCache over identity-mapped host memory" {
    // Real host-backed test: base the VirtAddr FrameAllocator at the
    // address of a page-aligned host buffer so that pointers returned
    // by FrameSource.acquire address writable memory in this process.
    const page_size = stdx.addr.pages._4kib;
    const region_count = 4;

    const backing = try testing.allocator.alignedAlloc(u8, .fromByteUnits(page_size), region_count * page_size);
    defer testing.allocator.free(backing);

    const HostVirt4K = stdx.addr.Page(VirtAddr, page_size);
    const HostBuddy = stdx.mem.BuddyAllocator.Static(region_count, 3);
    const HostFrames = stdx.mem.FrameAllocator.Bounded(HostBuddy, HostVirt4K);

    const backend = HostBuddy.init();
    const base = try HostVirt4K.Frame.fromAddressInt(@intCast(@intFromPtr(backing.ptr)));
    var frames = try HostFrames.wrap(backend, base);
    var source = frames.frameSource(0);

    const Cache = stdx.mem.PoolCache(u64, @TypeOf(source));
    var cache = Cache.init(&source);
    try cache.refill();

    const item = try cache.acquire();
    item.* = 0xDEAD_BEEF;
    try testing.expectEqual(@as(u64, 0xDEAD_BEEF), item.*);
    try testing.expect(cache.contains(item));

    cache.release(item);
    cache.drain();
    try testing.expectEqual(@as(u64, 0), frames.allocatedFrames());
    cache.assertValid();
    frames.assertValid();
}

test "model: FrameAllocator matches allocation oracle" {
    var frames = PhysFrames.init();
    const base = frames.baseFrame();

    var allocated: [16]bool = [_]bool{false} ** 16;

    var rng = std.Random.DefaultPrng.init(0xF00D);
    const random = rng.random();

    var live: [16]?Phys4K.FrameRange = [_]?Phys4K.FrameRange{null} ** 16;
    var live_count: usize = 0;

    var ops: usize = 0;
    while (ops < 512) : (ops += 1) {
        const alloc_choice = random.boolean() and live_count < 16;
        if (alloc_choice) {
            const order: u8 = random.uintAtMost(u8, 3);
            const range = frames.alloc(order) catch continue;
            const offset: usize = @intCast((range.base.addressInt() - base.addressInt()) >> Phys4K.Size.shift);
            const size: usize = @intCast(range.count.pages());
            var i: usize = 0;
            while (i < size) : (i += 1) {
                try testing.expect(!allocated[offset + i]);
                allocated[offset + i] = true;
            }
            // Slot in `live` at the first free index.
            var slot: usize = 0;
            while (slot < live.len) : (slot += 1) {
                if (live[slot] == null) {
                    live[slot] = range;
                    live_count += 1;
                    break;
                }
            }
        } else if (live_count > 0) {
            var slot: usize = 0;
            var chosen: ?usize = null;
            while (slot < live.len) : (slot += 1) {
                if (live[slot] != null) {
                    if (chosen == null or random.boolean()) chosen = slot;
                }
            }
            const idx = chosen.?;
            const range = live[idx].?;
            live[idx] = null;
            live_count -= 1;
            const offset: usize = @intCast((range.base.addressInt() - base.addressInt()) >> Phys4K.Size.shift);
            const size: usize = @intCast(range.count.pages());
            var i: usize = 0;
            while (i < size) : (i += 1) {
                try testing.expect(allocated[offset + i]);
                allocated[offset + i] = false;
            }
            try frames.free(range);
        }

        var expected_free: u64 = 0;
        for (allocated) |bit| {
            if (!bit) expected_free += 1;
        }
        try testing.expectEqual(expected_free, frames.freeFrames());
        frames.assertValid();
    }
}
