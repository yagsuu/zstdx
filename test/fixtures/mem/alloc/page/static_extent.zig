const std = @import("std");
const stdx = @import("stdx");

const Page = stdx.addr.Page(stdx.addr.PhysAddr, 4096);
const Backend = stdx.mem.alloc.BuddyAllocator.Static(16, 5);
const origin = Page.Base.fromInt(std.math.maxInt(Page.Int) & ~Page.mask) catch unreachable;
const Pages = stdx.mem.alloc.PageAllocator.Static(Backend, Page, origin);

export fn invalidExtent() void {
    _ = Pages.init();
}
