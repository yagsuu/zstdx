const paging = @import("stdx").arch.x86_64.paging;

const Reader = struct {
    pub const Error = error{};

    pub fn readEntry(_: *Reader, _: paging.PhysAddr) Error!paging.PagingStructureEntry {
        unreachable;
    }
};

export fn instantiateCurrentCPUWalker() void {
    var reader = Reader{};
    _ = paging.Walker(Reader).initCurrentCPU(&reader) catch unreachable;
}
