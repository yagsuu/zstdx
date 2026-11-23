# API contracts

`docs/api/` records settled caller-visible API contracts. Organize one page per
primitive family, with all variants together. State shared behavior once and
place variant differences beside the applicable contract.

Review test: **Can a caller quickly find what to call, what must hold,
what happens, and what can fail?**

## Publication and ownership

- Review and approve contract changes before implementation. Published pages
  describe settled behavior; proposals and unresolved decisions stay in planning.
  Published pages need no approval-status header.
- Public primitive behavior MUST have an owning contract. One family page can
  cover several modules and all variants. Re-export-only facades need no separate
  contract page or export inventory.
- Implementation work MUST follow published contracts, not planning documents.
  Resolve unclear behavior through contract review before implementation.
- Source boundaries and facade rules follow [conventions](conventions.md).

## Content

- Identify the public primitive and its responsibility in a short introduction.
- State caller requirements, validated inputs, results, and observable effects.
  Distinguish returned errors from caller-contract violations.
- Preserve applicable bounds, units, sentinels, ownership, lifetime, invalidation,
  allocation, waiting, concurrency, memory ordering, and progress guarantees.
- State the resulting state on failure: unchanged, partially changed, restored,
  or cleanup incomplete. Do not imply atomicity or rollback.
- State debug configuration when it changes the caller-visible contract.
  Private assertion predicates belong in source.
- Describe guarantees, not private algorithms. Include representation, ABI,
  layout, or implementation restrictions only when they constrain the contract.
- Define shared rules once and link related contracts.
  Distinguish dependencies from caller-controlled composition.
- Link owning source declarations instead of reproducing signatures, error
  unions, accessor inventories, export wiring, or source ownership trees.
  Include a signature or short example only when it resolves an ambiguity.
- Keep test cases and fixture mechanics in tests, and shared verification policy
  in the testing guidelines. Observable requirements remain testable.
- Usage examples are optional and illustrative unless explicitly normative.
- External standards may supply hardware or protocol references. State usable
  behavior locally and cite the applicable revision and clauses.

## Language and presentation

- Organize by caller tasks, not implementation structure.
- Retain a paragraph only when it answers a caller question about API selection,
  valid use, results, failures, or resource management.
- State each fact once beside the relevant operation or shared preconditions.
  Omit commentary that repeats or derives table contents.
- Remove obvious declaration, metadata, and accessor descriptions. Keep units,
  limits, unusual behavior, failures, and lifetime requirements.
- Use short table cells for comparison and lookup. Split independent conditions
  into rows or bullets instead of packing them into one cell.
- Use numbered steps for required sequencing. Use prose for relationships that
  need explanation.
- Avoid semicolons in prose and table cells. Use separate sentences, bullets,
  or rows. Preserve semicolons required by code syntax.
- State caller obligations directly. Omit defensive-check walkthroughs and use
  contrasts such as "X, not Y" only to resolve a plausible API ambiguity.
- Preserve exact boundaries, exceptions, error precedence, and partial-failure
  behavior. Do not weaken `MUST`, `MUST NOT`, or other existing obligations.
- Qualify operations with their owning type, such as `Entry.range()` or
  `List.len()`. Use exact variant names for variant-specific behavior and define
  shared family notation once.
- Use natural, professional software prose and consistent terms.
- Omit approval narration, unrelated rationale, speculative features, tutorials,
  `Value:` labels, empty sections, and lists of absent effects.
- Keep examples only when they replace a longer explanation.
- Use no word-count target or mandatory section order.

## Template

Headings are prompts, not required sections. Omit or combine them as useful.

```markdown
# `<public namespace or primitive family>`

<One sentence defining the responsibility.>

## Variants

<Only differences in construction, storage, capacity, ownership, or behavior.>

## Values and shared rules

<Non-obvious meanings, bounds, invariants, and common guarantees.>

## `<operation or related group>`

<Caller requirements, results, observable effects, and failure state.>

## References

<Owning declarations, related contracts, and applicable external clauses.>
```

Use dedicated lifetime, concurrency, representation, or sequencing sections when
they improve readability.

## Maintenance

- Concise rewrites of existing contract pages are permitted. Preserve obligations,
  conditions, bounds, ordering, error precedence, and failure guarantees.
- For implementation-alignment rewrites, current source defines existing behavior.
  Remove stale APIs and guarantees; record implementation bugs separately.
- Update contracts when observable behavior changes, not when private code moves.
- Consolidate variant pages into their family contract. Remove replaced pages and
  update inbound links; do not leave forwarding pages.
- Review each statement against the previous contract, owning declarations, and
  relevant tests. Account for removed obligations separately from duplicate prose,
  declaration inventories, private implementation details, and test procedures.
