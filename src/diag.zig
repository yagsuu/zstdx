//! Scoped diagnostics primitives. Spec: docs/specs/diag/diagnostic.md.

pub const diagnostic = @import("diag/diagnostic.zig");

pub const Diagnostics = diagnostic.Diagnostics;
pub const Scope = diagnostic.Scope;
pub const FormattedDetail = diagnostic.FormattedDetail;
pub const fmt = diagnostic.fmt;
pub const scope = diagnostic.scope;
