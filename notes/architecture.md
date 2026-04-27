## Todo
 - [x] VGA driver
 - [ ] Serial driver
    - [x] Blocking IO
    - [ ] Interrupt IO
 - [ ] Interrupts
    - [x] GDT
    - [x] IDT
    - [x] ISRs
    - [ ] Exception handlers
    - [ ] APIC reprogramming
        - [x] cpuid
        - note: Basics handled by limine
 - [ ] Memory
    - [ ] Paging
        - [ ] Load non-limine page tables
        - [ ] Map/unmap pages
    - [ ] Memory map
    - [ ] Mynamic allocation
 - [ ] Command interpreter
 - [ ] Module loading
 - [ ] Processes
    - [ ] Time sharing
 - [ ] Message passing

## Architecture
The kernel leaves room for a future port to ARM or RISC-V, though that isn't likely any time soon

### x86_64
---

#### Interrupts

##### GDT
Mostly only used to make IDT privilege levels work, otherwise the data in the GDT in long mode is ignored.

##### IDT
Pretty typical IDT. Handlers are generated in comptime.

##### APIC
I'm not planning to support PICs since the ultimate goal here is to run on my laptop and supporting ultra legacy systems seems like a waste of effort. Maybe if I were targeting a broader hardware set.

## IO
Namespace presenting a hardware agnostic IO interface

### Console
---
Exposes `init`, `print`, and `clear`. Mirrors everything to serial and the display.

## Drivers
Drivers are in src/drivers and included in drivers.zig, which has a `Drivers` namespace which includes the below namespaces. There are also more hardware level drivers in arch/x86_64/drivers.

### Display
---

#### VGA
No longer supported since the move to uefi.

#### Framebuffer
Lowest level framebuffer driver in arch/x86_64/drivers which only handles pixels and scrolling. Higher level video console driver is in drivers/display, which handles rendering text based on bitmaps from misc/font.zig which has a psf console font embedded.

### Data
---

#### Serial
Allows some automated testing and a much more convenient debugging experience. Currently polls on everything though it won't in the future.

## Limine
Limine was selected as I was having a lot of difficulty getting into 64 bit mode and I finally decided to cut my losses. Limine is also a lot more elegant to use due to the zig bindings, but those bindings aren't being maintained anymore and I should likely fork the project for stability.
