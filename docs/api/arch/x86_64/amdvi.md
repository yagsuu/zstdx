# AMD IOMMU baseline primitives

`arch.x86_64.amdvi` implements host translation, basic interrupt remapping, the command buffer, and the event log. The source is [AMD IOMMU Specification 48882, revision 3.11](https://docs.amd.com/api/khub/documents/2oKZlc87KNCKiT3B~xJjHg/content): sections 2.2.1–2.2.5, 2.3–2.5, 3.2, and 3.4.1/3.4.15/3.4.16; tables 7, 14–20, and 34–38. Guest translation, PASID, PPR, guest virtual APIC, segmented device tables, and SEV-SNP formats are separate interfaces and are not enabled by this API.

## Ownership and memory

The caller owns the MMIO mapping, the device topology, all DMA memory, and all physical addresses. `Unit.init` reads registers but does not write registers. It accepts the PCI IOMMU capability header because this header is not an MMIO register. The caller must obtain ownership from firmware before any configuration operation. The caller must not use this API to take over an active unit.

Use an uncached device mapping for MMIO. Use coherent, write-back DMA memory for tables, rings, logs, and completion markers. The physical mapping must remain stable while hardware can access the memory. Physical addresses must fit both the implementation's physical address width and the architectural 52-bit fields. The caller must check platform address-width limits. The caller must also check IVRS device coverage and aliases. These primitives do not discover PCI or ACPI resources.

DTE page walks use snooping (`SD=0`). `configureDeviceTable` establishes `Coherent=1` while translation is disabled, preserving other control fields. Translation enable checks this invariant. The library issues x86 store fences before command-tail publication, table-base publication, and enable operations. Event-head publication uses a full fence. Event reads and completion-marker reads use load fences. Volatile MMIO alone does not provide this contract. These operations use the existing target-checked x86 fence functions.

Noncoherent DMA memory is not supported by this contract. A platform that cannot provide coherent memory needs explicit cache clean/invalidate operations and platform-specific ordering before it can use these primitives safely. A fence does not clean a cache.

There is no allocation, lock, timeout loop, or hidden polling. The caller must serialize each unit and each ring. A configured `Unit` owns software configuration state; do not copy it into independent owners. The caller must supply a timeout and error policy for every wait.

## Public ownership

`Unit`, `Capabilities`, `DeviceId`, and `DomainId` remain at the root. The `registers`, `translation`, `command`, `interrupt`, and `event` namespaces own their related formats and operations. Register schemas use `bits.BitField` and expose typed `Args`, `AssignArgs`, access masks, assignment operations, and supported trigger or W1C operations. Unknown register bits survive raw snapshot updates. `Unit.acknowledge` takes a compile-time selection of observed status fields and writes the schema-generated W1C payload.

## Translation tables

`DeviceId` and `DomainId` are distinct 16-bit enum types. Construct a DTE with `translation.DeviceTableEntry.init`. The constructor checks the host level limit (`HATS`), ATS support, root alignment, and identity-mode constraints. It sets translation-valid and device-valid. It blocks interrupts by default. All devices in a domain must use the same root and mode. A device table must cover every requester that can reach the unit. Initialize unused DTEs to zero before enable.

`translation.PageEntry.table` validates a strictly decreasing next level. `translation.PageEntry.page` creates a natural-size leaf at levels 1–5: 4 KiB, 2 MiB, 1 GiB, 512 GiB, or 256 TiB. Level 6 has no natural leaf. The constructor checks leaf alignment. These are IOMMU entries, not CPU page entries. Access and dirty updates remain disabled in the baseline DTE. Enlarged, replicated `NextLevel=7` leaves are not required for baseline translation and are not produced.

Prepare a new table while the affected device is quiescent. Call `translation.publish()` after coherent DTE/page-table writes and before command invalidation publication. A multiword DTE update is not atomic. Do not write a live DTE with an ordinary struct assignment while hardware can read the entry. Follow section 2.2.1 and the DTE update procedures in section 2.2.2 for live changes. The primitives do not claim that a fence makes a multiword update atomic.

## Initial enable

1. Quiesce all affected devices and acquire exclusive unit ownership.
2. Read `control`, `status`, and `capabilities`.
3. Confirm that translation is disabled and that command/event processing is stopped.
4. Allocate and initialize the device table and page tables in coherent memory.
5. Call `configureDeviceTable` with its physical address and byte length.
6. Construct `command.CommandRing` and `event.EventLog` over caller-owned storage.
7. Call `configureCommands` and `configureEvents`.
8. Call `requestCommands(.{ .enabled = true, .completion_interrupt = false })` and `requestEvents(.{ .enabled = true, .notify = false })` as required.
9. Call `requestTranslation(true)`.
10. Read `translationEnabled` and the running status bits under a caller-defined timeout.
11. Submit the required cache invalidations and a completion command before allowing device traffic.

The ring/log constructors validate 256–32768 power-of-two entries and a 4 KiB-aligned physical base. Configuration resets the software and hardware cursors to zero. Configuration rejects an enabled or running engine. `requestCommands` and `requestEvents` require successful configuration through the same `Unit` before enable; architectural reset length fields do not establish configuration. Do not configure the same hardware ring through two software owners. Software storage alignment must permit normal accesses to its element type; physical alignment is checked separately.

Translation enable is a control request and readback, not proof that earlier DMA has drained. The baseline enable operation refuses active guest translation, guest APIC, and x2APIC formats. Preserve firmware routing controls only when the platform contract permits them.

## Commands, publication, and completion

`command.Command` provides DTE invalidation, domain-page invalidation, device-IOTLB invalidation, interrupt-table invalidation, and completion-wait encoding. `command.InvalidationRange.page`, `range`, and `all` provide the size/address encoding from table 14. The range must cover the largest affected page. Device-IOTLB commands require `IotlbSup`. Supply the device's advertised maximum pending count and shared invalidation queue ID.

1. Sample `Unit.commandHead`.
2. Pass the byte offset to `command.CommandRing.enqueue` for each command.
3. If enqueue returns `Full`, publish pending commands and retry only after the hardware head advances.
4. Call `command.CommandRing.publish` after writing descriptors.

The ring reserves one slot. It never publishes a tail equal to the sampled head after an enqueue. A hardware head is a validated byte offset, not a completion indication. A stale head can conservatively report `Full`; it must never be fabricated or advanced by software. Only one producer may enqueue. Do not modify a descriptor after publication until hardware has fetched the descriptor. `publish` checks the configured physical base and length before the tail write.

`command.Command.completion` stores an exact 64-bit value at an eight-byte-aligned physical address. Keep a corresponding `command.Completion` marker live in coherent memory. Initialize the marker to a different value before submitting the command. Use a unique expected value while an earlier completion can still arrive. `command.Completion.reached` performs one observation, not a wait. Do not reclaim an invalidated mapping until the completion is observed and the required device-quiescence conditions hold. A command-head advance does not replace this marker.

For a mapping update, publish table writes first. Enqueue `invalidatePages(.{ .domain = domain, .range = range, .directories = true })` for the domain. Enqueue `invalidateIotlb(.{ .device = device, .queue = queue, .max_pending = max_pending, .range = range }, caps)` for each ATS-enabled device in that domain. Enqueue `completion(.{ .physical = marker_address, .value = expected })`. Publish the ring. Wait for the completion marker with a caller-defined timeout. DTE changes also need `invalidateDevice`; domain removal also needs domain-page invalidation. Quiesce the device before removing mappings so that new requests cannot use the old mapping during the sequence.

## Interrupt remapping

`interrupt.InterruptEntry` encodes the basic 32-bit IRTE. `init` checks the vector and the `ForcePhyDestSup` logical-destination restriction. The caller must keep `guest_mode` and reserved bits zero. Basic tables have at most 512 entries in the baseline interrupt mode. `linkInterruptTable` checks a 128-byte-aligned physical base and a power-of-two entry count. It sets IV and remap control. Legacy NMI, INIT, ExtINT, LINT0, and LINT1 remain blocked in generated DTEs.

Quiesce interrupt sources before changing a DTE link. Use `blockInterrupts` and the vendor DTE update procedure before changing a live link. Publish the new IRTE/link. Invalidate the interrupt table and DTE as required by section 2.2.2. Wait for command completion before releasing the old table or enabling interrupt sources. Configure the IOMMU's own MSI capability through the platform PCI interface before enabling event or completion interrupts; these flags do not program an interrupt destination.

## Event consumption and overflow

`event.EventLog.peek(Unit.eventTail())` returns an event only when the sampled tail differs from the software head. `consume` advances by one record and rejects an empty log. `publish` publishes the consumed head after the read-ordering fence. Do not advance beyond the sampled tail. The caller must copy an event before consuming it. Hardware can reuse the entry after head publication.

`event.Event.code`, `device`, `address`, `operand`, and `domain` decode the baseline record envelope. `event.Event.fault` decodes the IO_PAGE_FAULT flags. The write flag is meaningful only for a present memory transaction that is not a translation request. The permission and reserved-bit flags are meaningful only when present is set. `operand` preserves all event-specific operand bits, including unknown event codes. Interpret other code-dependent flags according to section 2.5. `domain` is absent when the event uses a guest PASID instead of a host domain.

`status` reports overflow independently from a nonempty log. Overflow means that event information was lost. `acknowledge` writes only selected baseline W1C bits; it does not read-modify-write status. To service an event interrupt, consume available entries, publish the head, clear `event_interrupt`, and read the tail/status again. This recheck closes the interrupt-clear race.

After overflow:

1. Wait for `status.event_running` to clear under a caller-defined timeout.
2. Call `requestEvents(.{ .enabled = false, .notify = false })`.
3. Consume and publish any remaining complete records, or configure a replacement log while stopped.
4. Clear `event_overflow` with `acknowledge`.
5. Call `requestEvents(.{ .enabled = true, .notify = interrupt_policy })`.
6. Recheck status and the tail.

Do not clear overflow and assume that logging restarted. The enable transition is required. Lost records cannot be recovered by these primitives.

## Disable and reclamation

Quiesce DMA, ATS, and interrupt sources first. Submit the required invalidations and a completion command. Wait for the marker. Disable command and event processing. Wait for both running bits to clear. Request translation disable. Read back the control state. Only then release queue/log/table storage according to the platform's fabric-drain and device-reset rules. Translation disable is not a general DMA barrier. Disabling translation removes protection and must not expose active devices to unrestricted DMA.

`configureExclusion(.{ .base = base, .last_page = last_page, .allow_all = false })` takes an inclusive final page address. Exclusion bypasses translation and access checks. Use it only with explicit platform policy, with DMA and ATS quiescent, and with translation disabled. Invalidate affected remote IOTLBs before resuming traffic. The caller must establish that SEV-SNP is not enabled: SNP repurposes these registers and forbids exclusion. `SNPSup` alone does not establish current SNP state.

## Tests

The public `unit` namespace contains encoding, mode/alignment, unsupported-capability, ring-full/wrap, event-empty/wrap, invalid-pointer, running-hardware, and W1C-payload tests. The architecture facade imports this namespace. Hardware completion, cache coherency, PCI MSI delivery, and fabric drain require platform tests.

The private fieldless programming implementation is shared by MMIO and a compile-time recording fixture. The fixture checks access widths, ordered writes, preflight failures, W1C payloads, running-state preservation, and cursor nonmutation after failed publication. It does not model hardware fences or completion timing.
