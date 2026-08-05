//! Scoped diagnostics primitives. See `docs/specs/diag/diagnostic.md` and
//! `docs/specs/diag/panic_log.md`.

pub const diagnostic = @import("diag/diagnostic.zig");
pub const panic_log = @import("diag/panic_log.zig");

pub const Diagnostics = diagnostic.Diagnostics;
pub const Scope = diagnostic.Scope;
pub const FormattedDetail = diagnostic.FormattedDetail;
pub const PanicLog = panic_log.PanicLog;

pub const fmt = diagnostic.fmt;
pub const scope = diagnostic.scope;
