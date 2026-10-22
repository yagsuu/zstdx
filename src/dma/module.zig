//! DMA primitives. See `docs/specs/dma/buffer.md` and
//! `docs/specs/dma/scatter_gather.md`.

pub const buffer = @import("buffer.zig");
pub const scatter_gather = @import("scatter_gather.zig");

pub const Buffer = buffer.Buffer;

pub const ScatterGather = struct {
    pub const Segment = scatter_gather.Segment;
    pub const List = scatter_gather.List;
    pub const Builder = scatter_gather.Builder;
};
