# Intel VT-d

`arch.x86_64.vtd` implements legacy-mode DMA translation and remapped interrupts. The source is [Intel VT-d Architecture Specification, revision 5.20](https://cdrdv2-public.intel.com/919688/D51397-019-vt-directed-io-spec.pdf), sections 6.5–6.9, 9.1, 9.3, 9.8, 9.9, and 11.4. Scalable-mode contexts, PASID tables, posted interrupts, page requests, and enhanced commands are separate formats and are not implemented here.

The facade exports `DomainId`, `SourceId`, `Capabilities`, `registers`, `translation`, `invalidation`, `interrupt`, `fault`, `Unit`, and `publishTables`. Each namespace owns its wire formats and errors. `Unit` owns register programming. Its private, fieldless `Impl` shares the programming sequence between MMIO and a compile-time recording backend. There is no runtime backend interface.

## Ownership and memory

`Unit.init(window, host_width)` reads version and capabilities. Initialization does not change hardware state. The caller supplies the actual platform host physical address width, a live MMIO mapping, and exclusive access to command submission. Map registers with the platform-required device memory type. The caller must serialize all register and enhanced commands. Do not submit another command until the previous command completes.

The caller owns all DMA memory and physical addresses. Root tables, context tables, second-level tables, and the queue need 4096-byte physical alignment. The translation table types are aligned extern wrappers with an `entries` array and enforce 4096-byte virtual alignment. Their virtual allocations also need the alignment required by the platform. Interrupt tables have a 4096-byte-aligned base and a power-of-two count from 2 through 65536. Physical addresses must refer to memory, not MMIO, peer memory, or the interrupt aperture. The library checks width, alignment, count, and capability constraints. The library cannot check physical routing or virtual-to-physical correspondence.

Use coherent write-back DMA memory for queue descriptors and completion words. These structures are always snooped by VT-d. For translation and interrupt tables, check `caps.coherent()`. If this returns false, the caller must supply uncached memory or complete the platform-required cache writeback before publication. An `sfence` does not flush cache lines. The library does not perform cache maintenance.

Programming operations execute an x86 store fence with a compiler memory barrier before hardware publication. `invalidation.Completion.complete()` reads a volatile DWORD and executes a load fence with a compiler memory barrier after a matching value. Volatile access alone is not the publication mechanism.

Use `publishTables()` to order coherent table writes before a publication operation outside this API. This function does not invalidate translation caches or complete device DMA.

## Translation bring-up

1. Quiesce devices and stop DMA generation. Preserve firmware-required mappings and reserved-memory regions.
2. Read capabilities. Select a supported `translation.AddressWidth` and valid `DomainId`. Domain zero is reserved when caching mode is set. Contexts with the same domain must reference the same translation tables.
3. Initialize second-level tables with `translation.SecondLevelEntry.table` and `translation.SecondLevelEntry.page`. Initialize context and root entries. Keep entries absent until their child structures are ready. These types are VT-d formats, not CPU page-table formats.
4. Complete cache maintenance when required.
5. Call `installRoot`. Wait for `rootInstalled()` to return true.
6. Perform a global context-cache invalidation followed by a global IOTLB invalidation. Complete both operations. Root installation does not replace these invalidations unless the enhanced root-pointer capability explicitly permits that omission.
7. If the hardware requires write-buffer flushing, call `requestWriteBufferFlush()`. Wait for `writeBufferFlushComplete()` to return true.
8. Call `requestTranslation(true)`. Wait for `translationEnabled()` to return true.
9. Permit device DMA.

`translation.ContextEntry.init` supports translated, device-TLB, and pass-through contexts. Device-TLB and pass-through modes require their capability bits. Pass-through contexts must use the largest supported address width. ATS configuration in the PCI function remains the caller's responsibility.

## Queued invalidation

`invalidation.Queue.init` accepts caller-backed, 4096-byte-aligned storage containing 256 through 32768 `invalidation.Descriptor` values. Initialization clears that storage. Never initialize or reuse storage that hardware can still access. The queue uses 128-bit descriptors and retains one empty slot.

Call `configureQueue` only after register invalidations have completed and the previous queue is disabled. Its head, software tail, and published tail must be zero. Call `enableQueue()` and wait for `queueEnabled()` to return true. Hardware resets its head when the previous queue disable completes.

Use `invalidation.ContextInvalidation.descriptor`, `invalidation.IotlbInvalidation.descriptor`, `invalidation.Descriptor.deviceTlb`, `invalidation.Descriptor.interruptCache`, and `invalidation.Descriptor.waitStatus` to construct descriptors. Read `queueHead()` and supply that snapshot to `invalidation.Queue.enqueue`. The head must come from this queue and must not be fabricated. A stale head is safe only if it does not precede a full wrap of queue reuse. Serialize queue producers. Do not mutate published descriptors.

`registers` contains typed byte offsets and `bits.BitField` schemas. `Offset(T).Value` specifies the access width. `registers.read(window, offset)` and `registers.write(window, offset)` return register references whose width comes from the offset. Call `load()` or `store(value)` on these references. Dynamic IOTLB and fault offsets use the same typed representation. Each schema provides `Args`, `AssignArgs`, packed `Word`, masks, and policy-aware encoding. Read-only, trigger, and W1C fields retain their access policies. Reserved-preserve writes require the explicit preservation used by `Unit`; do not replace these writes with zero-default encoding.

`invalidation.Queue.enqueue` validates the head offset, checks the empty slot, and wraps the tail. `Unit.publishQueue(&queue)` orders descriptor writes and writes the tail register. `queue.publish(unit)` delegates to that operation. Publication does not mean completion. A hardware head advance releases descriptor storage, but does not prove completion of invalidations or DMA draining. Programming operations acquire all register references before the first write. Rejected operations do not change registers or the published software tail.

For completion, initialize a dedicated DWORD to a value different from the expected value. Construct a status-write wait descriptor with its physical address and the expected value. Enqueue that descriptor after the invalidations. Publish the queue. Use `invalidation.Completion` with the corresponding virtual pointer and expected value. Keep the word allocated until completion. Do not reuse the expected value while an earlier matching write can remain outstanding. The wait descriptor can set its fence flag to prevent following descriptors from executing before completion.

For device-TLB invalidations, `address` and `size` are the PCIe ATS encoded range, not a byte count. `size=false` selects one aligned 4 KiB page. For larger ranges, supply the ATS address encoding and set `size=true`; the size is encoded by the low address bits. `pending=0` encodes 32 pending requests. Supply the PF source ID only when invalidation throttling is supported. With throttling enabled, use the source ID for a PF, or its owning PF source ID for a VF. Invalidate the IOTLB before the corresponding device-TLB invalidation.

Descriptor constructors use named arguments. Use `deviceTlb(caps, .{ .source = source, .address = address, .size = false, .pending = 0, .physical_function = null })`, `interruptCache(caps, .{ .index = null, .mask = 0 })`, and `waitStatus(.{ .address = physical, .host_width = width, .value = expected, .fence = false })`. A null interrupt-cache index selects global invalidation. Context and IOTLB requests are structs with a `descriptor(caps)` method. Named word schemas encode the queue, translation, and interrupt formats.

For shutdown, stop producers. Append and publish a final wait descriptor. Wait for its completion. Call `disableQueue` with that completion and queue. This method also requires equal hardware head and published tail, no unpublished descriptors, and disabled interrupt remapping. Wait for `queueEnabled()` to return false. Only then release queue storage. The caller must establish that the supplied completion belongs to the final wait descriptor.

## Register invalidation

Register invalidation is available only for major versions through 5, legacy translation mode, and disabled queued invalidation. `invalidateContext` and `invalidateIotlb` reject a pending register invalidation. `contextInvalidationComplete()` and `iotlbInvalidationComplete()` return null while busy, the actual granularity on success, or `InvalidRequest` when hardware reports zero actual granularity.

Follow each context invalidation with a domain-selective or global IOTLB invalidation. For page invalidation, select a supported address mask and a size-aligned input address. Use mask 0 for 4 KiB, 9 for 2 MiB, or 18 for 1 GiB. `leaf_only` is valid only when the update does not require invalidation of intermediate paging structures. The implementation preserves the IOTLB register's reserved-preserve low DWORD.

## Interrupt remapping

`interrupt.InterruptEntry.init` constructs remapped fixed or lowest-priority entries with source-ID validation. It supports edge and level trigger modes, physical and logical destinations, and phantom-function qualifiers. The caller must use destination and trigger settings that match the APIC and interrupt source. xAPIC encodes the destination in destination-field bits 15:8; x2APIC uses all 32 bits.

1. Mask and quiesce interrupt sources.
2. Enable queued invalidation and wait for completion.
3. Prepare entries and complete required cache maintenance.
4. Call `installInterruptTable` while interrupt remapping is disabled. Wait for `interruptTableInstalled()` to return true.
5. Submit a global interrupt-cache invalidation followed by a wait descriptor. Wait for completion. The enhanced interrupt-table-pointer capability can make this invalidation unnecessary; do not assume that capability.
6. Call `requestInterruptRemapping(true)`. Wait for `interruptRemappingEnabled()` to return true.
7. Configure source remappable MSI/MSI-X or I/O APIC messages, then unmask the sources.

For updates, mask affected sources, publish complete entry changes, invalidate the affected interrupt-cache indexes, and wait for completion before release or reuse. Do not assume two 64-bit CPU stores form an atomic 128-bit entry replacement. Use source quiescence for replacement. For shutdown, mask sources, drain the interrupt cache with a wait completion, call `requestInterruptRemapping(false)`, and wait for `interruptRemappingEnabled()` to return false before queue disable or memory release. Compatibility-format interrupts remain blocked unless the caller explicitly enables their bypass with `requestCompatibilityInterrupts(true)`.

## Faults and recovery

`faultStatus` returns the raw fault status. `readFault(index)` reads the highest DWORD first and checks its fault flag before reading the source ID and remaining payload. A present record remains owned by software until acknowledgement. `fault.Fault` decodes reason, source, page address, request direction, address type, and optional PASID. Interpret reason codes with the specification's DMA and interrupt fault tables.

Call `acknowledgeFault` only after consuming a present record. The write contains only the W1C fault bit. `acknowledgeFaultStatus` accepts only the W1C overflow, queue-error, completion-error, and timeout bits. Neither method reads and replays W1C fields. Clear overflow only after processing recorded faults. Queue errors require recovery under section 6.5.2.11; acknowledgement alone does not repair a malformed descriptor or a timed-out device.

`maskFaultEvent` changes the interrupt mask and preserves reserved-preserve fields. `configureFaultEvent` requires a masked event and programs a fixed-delivery fault MSI. x2APIC requires the extended-interrupt capability. `acknowledgeCompletion` clears only the invalidation-wait completion status bit. Completion-event message registers and queue-error registers are exposed through `registers` and `Mmio.Window` for explicit platform event handling.

## Updates and disable

Before a translation update, stop affected device activity when the update can remove access or replace a live entry. Publish the entry changes. Perform context, IOTLB, and device-TLB invalidations in that order when applicable. Append a wait descriptor and wait for completion before releasing tables or mapped memory. A head advance alone is insufficient. Handle caching mode even for previously absent entries.

To disable translation, quiesce devices, complete required invalidations and drains, call `requestTranslation(false)`, and wait for `translationEnabled()` to return false. Re-enabling requires a new root-pointer operation. The request methods do not establish device quiescence, check enhanced-command activity, or infer completion ownership. Those are explicit caller preconditions.

## Tests

The `unit` namespace contains permanent tests for domain-width rejection, large-page alignment, entry encodings, queue capacity and wrap, malformed queue heads, command one-shot masking, fault W1C payloads, and wait completion encoding. The private recording fixture also checks access widths and order, read-only state, multiwrite rejection without mutation, queue publication rejection, and hardware completion states. These tests do not certify platform cache behavior or device DMA completion.
