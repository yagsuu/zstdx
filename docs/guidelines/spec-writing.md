# Spec writing

Approved specs under `docs/specs/` define production contracts for public API,
behavior, ownership, representation, implementation constraints, and required
tests.

## Authority

Value: Essential.

Rules:

- Approved specs under `docs/specs/` define contracts.
- Planning documents under `docs/planning/` do not define landed-code contracts.
- Source module headers cite the owning spec path.
- A public module without an approved owning spec does not land.
- Implementation work lands only from `Approved` specs.

## Status values

Value: Essential.

Each spec starts with exactly one status line after the title:

```text
Status: Draft.
Status: Approved.
Status: Superseded by <path>.
```

Rules:

- `Draft` specs are review material.
- `Approved` specs are implementation contracts.
- `Superseded` specs name the replacement path.

## Language

Value: Essential.

Rules:

- Use normative, testable contract statements.
- Use RFC 2119 terms when a requirement is mandatory.
- Prefer direct statements over explanation.
- State observable behavior, ownership, lifetime, invalidation, ordering,
  allocation, waiting, errors, and concurrency effects.
- Omit rationale, decision history, meeting context, approval context,
  implementation diary, and proposal language.
- Omit references that require knowledge outside the repository.
- Omit speculative future work unless the spec explicitly excludes that scope.
- Omit marketing, tutorials, filler, and narration.
- Do not include phrases such as `as discussed`, `for now`, `future work`,
  `until a consumer appears`, `the approved proposal`, `recommended`, or
  `where practical`.
- Replace vague debug behavior with exact conditions, such as
  `core.debug.checksEnabled(.build_mode)`.
- A reader must be able to implement and test the primitive from the spec text
  and linked repository paths alone.

## Section value model

Use the smallest section set that preserves production contracts.

Value levels:

- Essential: required for every approved spec unless explicitly impossible.
- High: required when the primitive has the corresponding contract surface.
- Conditional: include only when it removes ambiguity or prevents misuse.
- Medium: optional; keep only when it clarifies composition.

## Standard section order

New and substantially revised specs under `docs/specs/` use this order. Omit
irrelevant conditional sections.

1. `# <Spec title>` — Essential.
2. `Status: Draft.`, `Status: Approved.`, or `Status: Superseded by <path>.` — Essential.
3. Short description — Essential.
4. `## What this spec is` — Essential.
5. `## What this spec is not` — Essential.
6. `## Terminology` — Conditional.
7. `## Public namespace and source ownership` — Essential.
8. `## Cross-spec relationships` — High.
9. `## Data structures and representation` — High when state or layout matters.
10. `## Global invariants` — Essential.
11. `## API` — Essential.
12. Per-operation sections — High for non-trivial public operations.
13. `## Implementation constraints` — High.
14. `## Testing` — Essential.
15. `## Usage examples` — Medium.

Existing approved specs do not need format-only rewrites. Apply this order when
creating a spec or making a substantial behavioral revision.

## Section rules

### Short description

Value: Essential.

Rules:

- Use one paragraph.
- State the primitive and its concrete job.
- Do not include rationale, marketing, tutorial text, or consumer history.

### What this spec is

Value: Essential.

Rules:

- List owned public namespace, types, operations, storage, state transitions,
  ordering, invalidation, and required tests.
- Include only scope this spec controls.
- Do not include motivation or proposed implementation strategy.

### What this spec is not

Value: Essential.

Rules:

- Exclude adjacent policy domains explicitly.
- Exclude scheduler, allocation, blocking, callback, ownership, hardware, or
  runtime policy when the primitive does not own them.
- Name sibling specs when they own excluded behavior.
- Do not use this section for rationale.

### Terminology

Value: Conditional.

Include only terms used by later contracts, invariants, APIs, or tests.

Rules:

- Define terms with fixed meanings.
- Do not define common English words.
- Do not include glossary entries that no contract uses.

### Public namespace and source ownership

Value: Essential.

State:

- public import paths;
- root promotions, when the spec adds declarations to `src/stdx.zig`;
- facade exports;
- implementation source files;
- required test files.

Rules:

- Omit root-promotion discussion when the public paths are unambiguous.
- State explicit non-promotion when it prevents ambiguity or root namespace
  collisions.
- Domain facades stay thin. They may import, re-export, and alias approved
  public surfaces. They must not contain implementation logic.

### Cross-spec relationships

Value: High.

Rules:

- List required dependencies.
- List intentional composition points.
- Distinguish `depends on` from `composes with but does not own`.
- Do not use speculative sibling references unless the spec excludes that scope
  or the sibling spec exists.
- Do not duplicate another spec's contract.

### Data structures and representation

Value: High when representation affects behavior. Conditional otherwise.

Rules:

- State the conceptual model when it controls behavior.
- State required representation only when observable behavior, ABI, layout,
  safety, complexity, or tests depend on it.
- State exact layout, ABI, wire format, packing, padding, and field-name
  guarantees when they exist.
- State explicit non-guarantees when callers might otherwise depend on layout or
  encoding.
- Do not include `typical representation` sketches.
- Do not constrain private implementation strategy without contract value.

### Global invariants

Value: Essential.

Rules:

- List invariants every operation preserves.
- Prefer testable statements.
- Cover capacity, ordering, ownership, lifetime, invalidation, allocation,
  waiting, pointer stability, state-machine restrictions, and
  no-mutation-on-error rules when applicable.
- Do not list implementation details unless representation is normative.

### API

Value: Essential.

Rules:

- Show the approved public surface in Zig snippets.
- Public signatures in this section are normative.
- Include associated public types and constants.
- Exclude private helpers unless their shape is part of the public contract.
- State absent methods when omission prevents misuse.

### Per-operation sections

Value: High for public operations that mutate state, fail, wait, allocate,
perform atomics, affect lifetime, invalidate handles or pointers, or define
ordering/concurrency semantics.

Use these subsections where applicable:

- `Contract` — preconditions, postconditions, caller responsibilities.
- `Invariants` — operation-local invariants not covered globally.
- `State transitions` — before/after state changes.
- `Errors and fault behavior` — returned errors, no-mutation-on-error,
  caller-contract violations, assertions, traps, release-mode behavior.
- `Locking and waiting` — locks, backend calls, spinning, yielding, parking, or
  `never`.
- `Allocation behavior` — allocation, freeing, borrowing, allocator calls, or
  `never`.
- `NMI/interrupt safety` — safe contexts and caller obligations.
- `Memory ordering` — atomic orderings and happens-before edges.
- `Concurrency effects` — legal concurrent callers and external serialization.
- `Invalidation and lifetime` — handles, pointers, borrowed storage, copying,
  moving, deinitialization.
- `Complexity/progress` — cost, boundedness, lock-freedom, wait-freedom,
  blocking, retry behavior.

Rules:

- Group trivial accessors when their contracts are identical.
- Always state no-mutation-on-error for mutating fallible operations.
- Always state invalidation effects for handles, pointers, borrowed storage, and
  returned entries.
- Always state whether the operation allocates, waits, reads clocks, invokes
  callbacks, touches hidden globals, or calls scheduler/backend APIs when those
  effects are plausible.

### Implementation constraints

Value: High.

Rules:

- Include constraints required to preserve public contracts.
- Include no hidden globals, no callbacks, no allocator, no syscalls, no
  scheduler calls, exact field names, cache-line padding, atomic publication, or
  algorithm shape only when contract-relevant.
- Do not include implementation preference, rationale, or examples.

### Testing

Value: Essential.

Rules:

- State required tests.
- Test contracts, invariants, errors, boundaries, transitions, ordering,
  invalidation, concurrency, and representation guarantees.
- Do not test incidental implementation mechanics unless representation is
  normative.
- Split tests by purpose when applicable:
  - construction and capacity;
  - positive behavior;
  - negative/error behavior;
  - edge cases;
  - ordering;
  - invalidation and lifetime;
  - concurrency, model, and stress behavior;
  - memory ordering;
  - layout and representation.

### Usage examples

Value: Medium.

Rules:

- Include examples only when they clarify composition boundaries or prevent
  misuse.
- Keep examples short.
- Examples are illustrative unless they explicitly state a normative
  requirement.
- Do not include tutorials.
- Do not duplicate API contracts already stated above.

## Template

```md
# <Spec title>

Status: Draft.

<One-paragraph short description.>

## What this spec is

<Owned scope.>

## What this spec is not

<Non-goals and excluded policy domains.>

## Terminology

<Only fixed terms used by contracts. Omit if unnecessary.>

## Public namespace and source ownership

<Public paths, root promotion/non-promotion if needed, facade exports, source
files, test files.>

## Cross-spec relationships

<Dependencies and composition points.>

## Data structures and representation

<Conceptual model, required representation/layout, invalid states, guarantees,
and non-guarantees.>

## Global invariants

<Invariants every operation preserves.>

## API

<Approved public surface.>

### `<function/type/member>`

#### Contract

<Preconditions, postconditions, caller responsibilities.>

#### Invariants

<Function-specific invariants. Omit if fully covered globally.>

#### State transitions

<Before/after state. Omit for pure accessors.>

#### Errors and fault behavior

<Returned errors, no-mutation-on-error, caller-contract violations, traps.>

#### Locking and waiting

<Locks taken, backend calls, spin/park/yield behavior, or `never`.>

#### Allocation behavior

<Allocates/frees/borrows/calls allocator, or `never`.>

#### NMI/interrupt safety

<Safe contexts and caller obligations.>

#### Memory ordering

<Atomic orderings and happens-before edges.>

#### Concurrency effects

<Concurrent callers and serialization ownership.>

#### Invalidation and lifetime

<Handles, pointers, borrowed storage, copying/moving, deinit effects.>

#### Complexity/progress

<O(1), O(n), bounded/unbounded retry, lock-free/wait-free/blocking.>

## Implementation constraints

<Contract-relevant implementation constraints.>

## Testing

<Required contract tests.>

## Usage examples

<Short illustrative examples. Omit if unnecessary.>
```
