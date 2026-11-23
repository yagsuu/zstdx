# `stdx.addr.Page`

`Page(Addr, page_size)` provides page counts, aligned bases, inclusive ranges,
and page-bounded byte chunks. `P` denotes an instantiated family.

`Addr` supplies unsigned `Int`, `from(Int) Addr`, and `raw() Int`.
`page_size: Addr.Int` must be a power of two of at least two bytes.
Invalid families are compile errors.

## Counts and bases

`P.Int` is `Addr.Int`. `P.Count` and `P.Base` are distinct non-exhaustive enums
backed by `P.Int`. Counts use page units. Bases use byte addresses.
Different address domains or page sizes produce distinct types.

| Operation | Result or failure |
| --- | --- |
| `P.Count.from(value)` / `P.Count.raw()` | Convert page counts without changing bits. Every backing value is valid |
| `P.Count.fromBytes(value)` | Convert an exact page-multiple byte count. Otherwise `error.Misaligned` |
| `P.Count.fromBytesCeil(value)` | Round bytes up to pages. Infallible for every byte count, including zero and the maximum |
| `P.Count.bytes()` | Byte count, or `error.Overflow` |
| `P.Base.from(address)` / `P.Base.fromInt(value)` | Construct from a typed or raw byte address. Unaligned input returns `error.Misaligned` |
| `P.Base.alignDown(address)` | Base of the containing page |
| `P.Base.alignUp(address)` | First base at or above the address, or `error.Overflow` |
| `P.Base.addr()` / `P.Base.raw()` / `P.Base.index()` | Typed byte address, raw byte address, or page index |
| `P.Base.add(count)` / `P.Base.sub(count)` | Move by pages. Count conversion or address arithmetic failure returns `error.Overflow` before an unaligned result returns `error.Misaligned` |

Direct base construction MUST preserve alignment. `P.Base.isAligned(address)`
tests an address. `P.Base.isValid()` and `P.Base.assertValid()` test and assert
the stored base's alignment.

## Construct ranges

`P.Range.bounds` is an `InclusiveRange(P.Int)` in page-index units.
Valid bounds are non-empty and ordered, with a last index no greater than
`maxInt(P.Int) / page_size`. Direct construction, queries, and combinations
require valid bounds. `P.Range.isValid()` tests validity and
`P.Range.assertValid()` asserts it.

| Constructor | Result | Validation order |
| --- | --- | --- |
| `P.Range.init(first_page, last_page)` | Range including both bases | Unaligned base: `error.Misaligned`. Then reversed bounds: `error.OutOfBounds` |
| `P.Range.fromCount(base, count)` | `null` for zero pages. Otherwise the requested pages from `base` | Check base alignment before handling count. An unrepresentable last included base returns `error.Overflow` |
| `P.Range.fromBytes(base, len)` | Construct from an exact page-multiple byte length | Check base alignment, then byte-length alignment. Either failure returns `error.Misaligned`. Then use the `P.Range.fromCount()` rules |
| `P.Range.containing(start, len)` | Cover every page touched by the extent | Zero bytes return `null` immediately. Otherwise an unrepresentable last byte returns `error.Overflow` |

Inclusive ranges can contain the final page and the full address domain.

## Measure and combine ranges

| Operation | Result |
| --- | --- |
| `P.Range.first()` / `P.Range.last()` | Included endpoint bases |
| `P.Range.count()` | Always-representable page count |
| `P.Range.bytes()` | Byte length, or `error.Overflow`, including for the full address domain |
| `P.Range.contains(address)` | Whether any included page contains the byte address |
| `P.Range.containsRange(other)` | Whether all pages of `other` are included |
| `P.Range.overlaps(other)` | Whether any page is shared |
| `P.Range.adjacent(other)` | Whether disjoint ranges have consecutive page indices |
| `P.Range.intersection(other)` | Shared pages, or `null` |
| `P.Range.span(other)` | Smallest range covering both inputs and intervening pages |

## Split a range

`P.Range.splitAt(at)` requires a valid receiver and returns
`{ left: ?P.Range, right: ?P.Range }`. The split page belongs to `right`.

| Split point | Result |
| --- | --- |
| Unaligned base | `error.Misaligned`, before checking bounds |
| Outside the first page through the base immediately after the last | `error.OutOfBounds` |
| First page | `left = null` |
| Immediately after the last page | `right = null`. Unavailable after the final addressable page |

## Test byte extents and slices

`P.Base.contains(address)` tests membership in one page.
`P.Base.containsExtent(start, len)` and `P.Range.containsExtent(start, len)`
require valid receivers and test whether every byte fits.
Zero bytes return true at any start. Non-empty extents can include the final byte.

`P.Base.containsSlice(slice)` and `P.Range.containsSlice(slice)` use the pointer's
numeric address and `slice.len * @sizeOf(Element)` bytes, excluding any sentinel.
Non-slice arguments are compile errors.

| Slice condition | Result |
| --- | --- |
| Pointer or byte length does not fit `P.Int` | False, including an empty slice with an unrepresentable pointer |
| Byte-length multiplication overflows `usize` | False |
| Representable pointer and byte length | Apply the byte-extent rule |

## Iterate chunks

| Operation | Result or failure |
| --- | --- |
| `P.chunks(start, len)` | Iterator over the extent. Zero length is exhausted at any start. An unrepresentable last byte returns `error.Overflow` |
| `P.chunksSlice(slice)` | Uses the slice extent above. Unrepresentable pointers or lengths return `error.Overflow` before extent validation |
| `P.Chunks.next()` | Next `P.Chunk`, or `null` after exhaustion |

Each chunk contains `page: P.Base`, byte `offset: P.Int`, and positive byte
`len: P.Int`. Chunks cover the extent in address order without gaps, overlap,
or page crossings. Preserve the validated extent when modifying iterator state.

These operations do not dereference addresses or retain storage. Each call takes
O(1) time without allocation for built-in address types. Full iteration takes
time proportional to the number of chunks.

## References

- [Page families](../../../src/addr/pages.zig)
- [Address domains and pointer conversions](address.md)
- [Inclusive range semantics](../core/range.md)
