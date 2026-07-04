//! Scoped diagnostics primitives. Specs: docs/specs/diag/diagnostic.md,
//! docs/specs/diag/panic-log.md.

pub const diagnostic = @import("diag/diagnostic.zig");
pub const panic_log = @import("diag/panic_log.zig");

pub const Diagnostics = diagnostic.Diagnostics;
pub const Scope = diagnostic.Scope;
pub const FormattedDetail = diagnostic.FormattedDetail;
pub const fmt = diagnostic.fmt;
pub const scope = diagnostic.scope;

pub const PanicLog = panic_log.PanicLog;
