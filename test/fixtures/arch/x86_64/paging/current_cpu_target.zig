const paging = @import("stdx").arch.x86_64.paging;

const Reader = struct {
    pub const Error = error{};

    pub fn readEntry(_: *Reader, _: paging.PhysAddr) Error!paging.Entry {
        unreachable;
    }
};

export fn instantiateCurrentCPUWalker() void {
    var reader = Reader{};
    _ = paging.Walker(Reader).initCurrent(&reader) catch unreachable;
}
