# `stdx.barrier`

`stdx.barrier` provides compiler, MMIO, and DMA ordering operations. The
[MMIO and DMA contract](barrier/dma.md) defines their effects and target support.

## Publication and notification

A publisher writes payload data before a `.release` operation on synchronization
state. An acquirer that observes that publication through an `.acquire`
operation can read the published data. `.monotonic` supplies atomicity without
cross-location ordering; `.acq_rel` combines acquire and release effects.
`.seq_cst` additionally participates in the sequentially consistent total order.

A reservation gives a producer ownership of a future mutation point. Consumers
MUST NOT read reserved data before publication. A published slot holds data made
available to a consumer; a free slot has been published as available for reuse.
The owning container or synchronization primitive defines the publication and
acquisition operations.

A doorbell tells a consumer to recheck state. A wake or signal alone does not
prove payload visibility or completion of the work that caused the notification.
Consumers MUST tolerate redundant and spurious notifications.

A sticky signal retains its set state until cleared. An edge signal, or pulse,
retains no state and can lose a wake that races with waiter enrollment. A reusable
wait protocol MUST prevent lost wakes through enrollment followed by a condition
recheck, generation comparison, or documented atomic-wait semantics.

Waiting can block, sleep, park, yield, or spin. The owning primitive defines its
waiting behavior and any caller-supplied backend requirements.
