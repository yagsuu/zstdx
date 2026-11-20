pub const buffer = @import("buffer.zig");
pub const sg = @import("scatter_gather.zig");

pub const Buffer = buffer.Buffer;

pub const ScatterGather = struct {
    pub const Segment = sg.Segment;
    pub const List = sg.List;
    pub const Builder = sg.Builder;
};

test {
    _ = buffer.unit;
    _ = sg.unit;
}
