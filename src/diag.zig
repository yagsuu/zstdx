//! Scoped diagnostics primitives. Spec: docs/specs/diag/diagnostic.md.

pub const diagnostic = @import("diag/diagnostic.zig");

pub const Diagnostics = diagnostic.Diagnostics;
pub const ScopeOptions = diagnostic.ScopeOptions;
pub const Scope = diagnostic.Scope;
pub const LazyDetail = diagnostic.LazyDetail;
pub const lazy = diagnostic.lazy;
