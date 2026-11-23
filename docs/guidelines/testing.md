# Testing

Test requirements for zstdx implementation work.

## Required commands

- `zig build test` runs unit and integration tests on the host.
- `zig build test-unit` runs every source module's unit suite.
- `zig build test-<category>` runs one category's unit suite, such as `test-dispatch`.
- `zig build test-integration` runs cross-module consumer workflows.
- Pure primitive modules must not require target-specific checks.
- External tools are not required by the default test command.
- Architecture-specific tests are gated by target and feature checks.

## Test locations

- Source modules own single-category behavioral, model, allocation, and stress tests in a `pub const unit = struct`.
- Keep test helpers inside the owning `unit` namespace. Do not create source test sidecars.
- Define named test-case and substantial fixture types under `unit`, before the tests that use them.
- Do not define struct types inside array initializers. Put each struct field on a separate line.
- `test/` contains integration workflows that exercise interactions across module categories.
- Integration tests import the public `stdx` facade, not implementation files.
- Benchmarks live outside the default correctness test path unless a spec says otherwise.

## Test aggregation

- Each category module aggregates its implementation files' `unit` namespaces once.
- `test/all.zig` imports workflow leaves or immediate child facades.
- Each integration leaf has exactly one aggregation path from that root.
- Aggregation facades contain imports only; leaf tests do not import other leaf tests.
- Integration files are grouped by workflow, not by source category.
- A category target and `test-unit` share the same registered test artifact.
- `test` depends on the unit and integration aggregates without registering more artifacts.

## Test naming

Use category prefixes. Keep source tests in the owning `unit` namespace regardless of prefix.

```zig
test "unit: static list rejects push when full" { ... }
test "model: ring matches reference queue under random operations" { ... }
test "contract: bounded list never touches allocator" { ... }
test "ordering: spsc ring publishes item before tail" { ... }
test "stress: mpsc queue preserves all produced items" { ... }
test "integration: queued work invokes delegates in FIFO order" { ... }
```

## Required per-public-type test set

Each implemented public type must include tests for:

- successful construction;
- empty state;
- smallest valid capacity where applicable;
- non-trivial capacity/value set;
- every public error variant;
- boundary lengths and capacities;
- clear/deinit behavior;
- invalidation behavior where documented;
- `assertValid` success after public mutations;
- debug assertion behavior where practical.

Cover failure state, lifetime, ordering, progress, and representation where
applicable. Match verification to the risk: deterministic unit or model tests
establish outcomes and transitions; stress tests exercise contention but do not
replace an ordering proof; layout tests verify contractual representation.

## Allocation contract tests

Allocation behavior is part of the public contract.

Required checks:

- `Static` and `Bounded` variants do not allocate.
- `Managed` variants allocate only through the stored allocator.
- `Unmanaged` variants allocate only through allocator-taking methods.
- reserve-only APIs do not allocate after successful reservation until capacity is exceeded.
- full-capacity behavior matches the spec: `error.Full`, overwrite, drop, block, or resize.

## Collection model tests

Optimized containers require model tests against a simple reference implementation when practical.

Required areas:

- static and bounded lists, rings, deques, stacks, queues;
- hash maps and hash sets;
- slot maps and handle maps;
- sparse sets;
- heaps and priority queues;
- range sets and range maps.

Randomized operation sequences must assert the optimized structure and reference model produce the same observable results.

## Intrusive tests

Intrusive collections must cover:

- insert/remove at every position;
- removal of the only element;
- re-insertion after removal where allowed;
- multi-membership using distinct embedded nodes;
- debug detection of double insert/remove where the spec requires it;
- object pointer stability.

## Ordering and concurrency tests

Concurrent primitives require concurrent coverage in addition to single-thread contract tests.

Required checks where applicable:

- single-thread contract tests for edge behavior;
- stress tests with multiple producers/consumers/thieves as specified;
- randomized interleavings when a deterministic model is practical;
- memory-ordering comments tied to the implementation points that enforce them;
- target-gated architecture tests for fence wrappers.

Stress tests demonstrate exercised behavior; they do not replace a written ordering proof in the owning spec.

## Barrier and architecture tests

Barrier tests must not pretend to prove hardware ordering through ordinary unit tests.

Required checks:

- emitted-instruction checks only when the build/test harness explicitly supports them;
- feature-gated tests for optional instructions;
- semantic documentation in specs for ordering guarantees and non-guarantees.

## Layout and byte tests

Layout and binary helpers must cover:

- endian round trips;
- unaligned loads/stores at every supported width;
- offset overflow and truncation;
- packed-field masks and shifts;
- compile-time size, alignment, and bit-size assertions for layout-boundary types.

## No mocks for primitives

Tests use real byte buffers, real caller-owned storage, and real allocators.

Do not mock:

- allocators when allocation behavior is under test;
- collection models when a simple reference container is available;
- atomic operations;
- barrier APIs.

## Diagnostics and panic-safe structures

Diagnostics and panic-safe structures must cover:

- no-allocation error paths;
- fixed-capacity truncation behavior;
- wraparound behavior for rings/logs;
- reentrancy assumptions where documented;
- behavior after partial writes where documented.

## Benchmark discipline

Benchmarks are evidence for optimization, not correctness gates.

A benchmark must state:

- workload;
- input sizes;
- allocator behavior;
- target and optimization mode;
- comparison baseline.

Do not accept a clever implementation solely because it benchmarks well on one workload.
