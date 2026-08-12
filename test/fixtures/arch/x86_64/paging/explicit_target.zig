const paging = @import("stdx").arch.x86_64.paging;

const Reader = struct {
    pub const Error = error{};

    pub fn readEntry(_: *Reader, _: paging.PhysAddr) Error!paging.PagingStructureEntry {
        return paging.PagingStructureEntry.empty();
    }
};

export fn instantiatePagingWalker() void {
    var reader = Reader{};
    const Walker = paging.Walker(Reader);
    const walker = Walker.init(.{
        .root_table_base = paging.PhysAddr.fromInt(0),
        .mode = .level4,
        .physical_address_width = .bits_48,
    }, &reader) catch unreachable;
    _ = walker.translate(
        paging.LinearAddress.fromInt(0),
        .read(.supervisor),
    ) catch unreachable;
}
