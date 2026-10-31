const paging = @import("stdx").arch.x86_64.paging;

const Reader = struct {
    pub const Error = error{};

    pub fn readEntry(_: *Reader, _: paging.PhysAddr) Error!paging.Entry {
        return .{};
    }
};

export fn instantiatePagingWalker() void {
    var reader = Reader{};
    const Walker = paging.Walker(Reader);
    const walker = Walker.init(.{
        .root = paging.PhysAddr.from(0),
        .mode = .level4,
        .physical_width = .bits_48,
    }, &reader) catch unreachable;
    _ = walker.translate(
        paging.LinearAddr.from(0),
        .read(.supervisor),
    ) catch unreachable;
}
