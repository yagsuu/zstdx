pub fn requireBackend(comptime Backend: type, comptime label: []const u8) void {
    if (!@hasDecl(Backend, "WaitError")) {
        @compileError(label ++ ": Backend must declare pub const WaitError");
    }

    const info = @typeInfo(Backend.WaitError);
    if (info != .error_set) {
        @compileError(label ++ ": Backend.WaitError must be an error set");
    }

    if (info.error_set == null) {
        @compileError(
            label ++ ": Backend.WaitError must be an explicit error set; " ++
                "anyerror is not approved",
        );
    }

    if (!@hasDecl(Backend, "wait")) {
        @compileError(
            label ++ ": Backend must declare " ++
                "pub fn wait(*Backend, *const State, Token) WaitError!void",
        );
    }

    if (!@hasDecl(Backend, "wakeAll")) {
        @compileError(
            label ++ ": Backend must declare " ++
                "pub fn wakeAll(*Backend, *const State) void",
        );
    }
}
