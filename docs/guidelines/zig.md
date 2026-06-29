# Zig engineering guidelines

Normative baseline for Zig source. Project-specific conventions may tighten these rules or define narrower vocabulary, but must do so explicitly.

## Priorities

Prefer designs in this order:

1. correctness and safety;
2. predictable performance;
3. developer experience.

Readable code is required, but readability serves correctness. Prefer explicit, bounded, boring designs over clever abstractions.

## Source of truth

- Approved specs and project convention documents define contracts.
- Planning notes, task lists, chats, and examples do not define stable APIs or behavior.
- If implementation needs an unresolved contract, stop at that boundary and resolve the contract before landing public API.
- Code comments may cite stable specs. They must not cite planning notes, milestones, task IDs, or conversations.

## File and module ownership

- Each file owns one concept or one type family.
- Split by responsibility, not arbitrary size.
- Keep dependency direction explicit. Lower layers must not import orchestration layers.
- Facades and root modules must be thin: re-exports and aliases only, no hidden allocation, validation, synchronization, probing, or policy.
- Avoid catch-all files such as `utils.zig`, `helpers.zig`, `common.zig`, and `misc.zig`.
- Use names that identify the owned concept: `parse.zig`, `validate.zig`, `alignment.zig`, `ring.zig`.

## Imports and declarations

Top-level imports and aliases must be grouped in this order, with one blank line between non-empty groups:

1. `std` and `builtin`;
2. external packages;
3. local modules;
4. type aliases;
5. value constants;
6. function aliases.

Within a group, keep dependency order only when reordering would obscure a top-to-bottom dependency. Otherwise sort
by alias name. Do not add comments that merely label obvious groups.

Module imports must use the module's natural name. Do not add `_mod` or `_module` suffixes to avoid a
collision; rename the local declaration instead.

Prefer a top-level type alias when a file repeatedly uses one type from a module. Keep the module namespace when
several declarations are used through the same namespace.

Facade and aggregate files must apply the same grouping rules to public re-exports.

## Formatting

- Run `zig fmt` on Zig source.
- Use 4 spaces; no hard tabs in source indentation.
- Keep lines at or below 120 columns unless a generated or external literal makes that worse than the alternative.
- Use trailing commas to let `zig fmt` wrap long parameter lists, calls, literals, and type declarations.
- Braces are required for multi-line `if`, `while`, `for`, and `switch` bodies.

## Naming

Default to Zig naming:

- `TitleCase` for types and type factories.
- `camelCase` for runtime functions and methods.
- `snake_case` for variables, fields, files, directories, and namespaces.

Rules:

- Names must encode domain meaning, ownership, units, and lifetime when those facts matter.
- Put units and qualifiers last: `size_bytes`, `offset_bytes`, `latency_ms_max`.
- Treat acronyms as words unless an external ABI or spec requires exact spelling.
- Avoid names that add no information: `Data`, `Value`, `Context`, `Manager`, `Utils`, `Misc`.
- Avoid namespace stutter in fully qualified names.
- Use allocator names that communicate ownership and lifetime, such as `gpa`, `arena`, `scratch`, or `pool`.
- Names must not imply guarantees stronger than the owning spec provides.
- Do not use vague labels such as `thread_safe`; state the access model and progress guarantee explicitly.

## Comments and docs

Omit comments unless they satisfy one of the allowed categories below.

Use comments for:

- module headers that state purpose and owning spec;
- exported API docs for semantic facts the type or signature cannot carry;
- non-obvious invariants, hazards, external constraints, and why the obvious alternative is wrong.

Module headers (`//!`) must be one to three terse lines. They state the module's purpose and owning spec path.
They must not describe project status, future work, implementation history, milestones, or process flow.

Exported `///` docs must state semantic facts the type or signature cannot carry: ownership, lifetime, units,
allocation behavior, blocking or waiting behavior, capacity behavior, concurrency/access contract,
pointer/index/iterator invalidation, memory ordering, and public error conditions.

Do not use comments for:

- narration of code;
- changelog notes;
- milestone, task, roadmap, or planning references;
- chat, review, or "per discussion" references;
- process narration such as "filled in later", "future phase", or "when a consumer needs it";
- commented-out code;
- decorative banners;
- TODO/FIXME/XXX in landed code;
- restating a function signature or field declaration.

Code comments may cite stable specs or ADRs. They must not cite planning docs, milestones, task IDs, roadmap
stages, chats, reviews, or informal agreements.

Comments are concise prose. Prefer one load-bearing paragraph over several vague paragraphs.

## Control flow

- Use simple, explicit control flow.
- Avoid recursion in critical, bounded, or hot code.
- Every loop must have an obvious bound, an asserted bound, or an intentional non-termination contract.
- Prefer positive conditions over negated conditions.
- Split complex boolean expressions when separate branches make cases easier to audit.
- Prefer exhaustive `switch` over broad `else` when the input domain is closed.
- Push branching up and keep leaf helpers narrow and predictable.

## Assertions and invariants

Assertions are part of the design.

- Assert function preconditions, postconditions, and internal invariants.
- Prefer several simple assertions over one compound assertion.
- Pair assertions across boundaries: caller/callee, producer/consumer, writer/reader, encoder/decoder.
- Add compile-time assertions for type sizes, alignments, field offsets, enum values, bit masks, and constant relationships; type-owned assertions live inside the type body.
- Assert both expected valid space and explicitly invalid space when data crosses a boundary.
- Assertions document programmer errors. User, input, environment, and resource failures must still be handled explicitly.

## Types, ABI, and layout

- Use explicit integer widths for persisted, ABI, wire, and cross-platform data.
- Use `usize` for host memory sizes, indexes, and APIs where pointer width is actually the unit.
- Use strong types for addresses, sizes, pages, offsets, IDs, and handles when mixing them would be a bug.
- Model flag words as typed structures or enums with named operations; avoid raw mask arithmetic in high-level code.
- ABI-boundary types must use the layout required by their ABI and carry scoped compile-time layout assertions inside the type body.
- Reserved bits and fields must be zeroed on output and validated on input when the contract requires it.
- Keep `@ptrCast`, `@alignCast`, `@bitCast`, and narrowing integer casts close to the boundary that justifies them.

## Memory and allocation

Allocation behavior is part of the public contract.

- Public APIs must not hide allocation.
- Hot paths, panic paths, interrupt/signal paths, ABI callbacks, and dispatch loops must not allocate unless their contract explicitly allows it.
- Prefer caller-provided storage, fixed buffers, bounded containers, and precomputed immutable tables when bounds are known.
- Initialize and freeze hot-path structures before entering the hot path.
- Put `defer` or `errdefer` immediately after successful acquisition.
- Owned types should expose `deinit`; borrowed views must be named and documented as borrowed.
- Pass large immutable inputs by `*const` when copying would be accidental or expensive.
- Construct large or pointer-stable values in place when move copies would be risky or costly.

## Errors

- All errors must be handled, translated, or propagated.
- Use narrow, domain-owned error sets at module boundaries.
- Use `anyerror` only at true orchestration boundaries where narrower sets would hide real dependencies.
- Log or diagnose errors at the point with the most context; avoid duplicate noisy logs up the stack.
- `catch unreachable` requires local proof that the error is impossible.
- Degradation must be explicit and observable. Do not silently continue in a half-valid state.

## API shape

- Constructors and operations must live on the type they affect.
- Use `Type.init(...)` for non-allocating initialization unless the owning convention defines a different constructor
  vocabulary.
- Use distinct methods or enums instead of public boolean mode parameters.
- Use an options struct when same-typed arguments can be confused.
- Pass dependencies and allocators explicitly.
- Pass callbacks last.
- Explicitly pass load-bearing options at call sites instead of relying on defaults.
- Separate pure transforms from I/O, allocation, synchronization, syscalls, architecture probing, and privileged
  operations.
- Do not leave compatibility aliases after a rename; update callers.
- Public `anytype` requires an intentional comptime interface. Do not use it to avoid naming a contract.
- Do not introduce catch-all registries, object systems, or vtables unless the owning spec defines that abstraction.
- Avoid ambiguous `usize` APIs when the value has units. Use strong types or names that encode the unit.

Construction-related `Error`, option/parameter structs, iterators, handles, and owned helper types must nest under
the type they serve.

Avoid module-scope `build*`, `make*`, or `from*` free functions when the result type can own the constructor.

Use `from` for pure reinterpretation or conversion from one input. Project overlays may define narrower constructor
vocabulary such as `build`, `validate`, `wrap`, or `seal`.

## Public contracts

Every non-trivial public API must document the contracts it exposes:

- allocation behavior;
- blocking, waiting, and spinning behavior;
- capacity model;
- execution bounds;
- concurrency/access contract;
- progress guarantee where concurrent;
- pointer, index, handle, and iterator stability;
- invalidation rules;
- deterministic iteration behavior;
- memory ordering where relevant.

## Concurrency and ordering

- Public APIs must not hide blocking, sleeping, spinning, or waiting.
- State access contracts explicitly: single-threaded, externally synchronized, SPSC, MPSC, MPMC, owner/thief, interrupt-safe, or signal-safe.
- Atomic operations must name the ordering at the operation site.
- Ordering comments must sit near the operation that enforces the ordering.
- Compiler barriers, CPU fences, I/O barriers, and DMA barriers must not promise effects outside their documented scope.

## Performance

- Consider network, disk, memory, and CPU costs early enough to shape the design.
- Optimize the slowest or most frequently paid resource first.
- Batch external events and expensive operations where latency contracts allow it.
- Avoid avoidable allocation, copying, formatting, syscalls, locks, and indirect dispatch in hot paths.
- Prefer simple immutable tables and direct data layouts when they make costs predictable.
- Use explicit arithmetic operations that state rounding, wrapping, saturation, and overflow intent.
- Do not accept cleverness solely because it benchmarks well on one workload.

## Tests and verification

- Test behavior and invariants, not incidental implementation shape.
- Cover valid inputs, invalid inputs, boundary values, and every public error variant.
- Allocation behavior, waiting behavior, invalidation, and ordering are testable contracts when public APIs expose them.
- Optimized structures should be compared against a simple reference model when practical.
- Layout and ABI properties belong in compile-time assertions colocated with the type; tests may add behavior coverage.
- Integration or target-specific checks must be gated when the required target, hardware, or permission is unavailable.

## Agentic implementation workflow

Automated implementation agents must follow the same rules as human contributors.

- Read the owning spec and conventions before editing.
- Identify the module owner before adding code.
- Make the smallest complete change that satisfies the approved contract.
- Update every callsite; do not leave compatibility aliases unless explicitly requested.
- Add assertions where a new invariant is created and where it is consumed.
- Add or update tests for changed behavior.
- Do not land placeholders, fake fallbacks, TODOs, or speculative extension points.
- Do not invent unresolved contracts. Resolve the contract first.
