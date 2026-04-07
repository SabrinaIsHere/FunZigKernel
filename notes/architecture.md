## Todo
 - ~~VGA driver~~
 - Serial driver
    - ~~Blocking IO~~
    - Interrupt IO
 - Interrupts
    - GDT
    - IDT
 - Memory
    - Memory map
    - Dynamic allocation
 - Command interpreter
 - Module loading
 - Processes
    - Time sharing
 - Message passing

## Architecture
The kernel leaves room for a future port to ARM or RISC-V, though that isn't likely any time soon

### x86_32
---
64 bit long mode may be supported in the future but for now it is out of scope.

#### Interrupts

##### GDT
Must have, at minimum, the 8 byte null descriptor, DPL 0 code segment descriptor for the kernel, data segment, task state segment. Room for more is necessary, for things like user level LDTs.

As I plan to use paging, the GDT will be fairly minimal, including just the null descriptor, kernel code segment, kernel data segment, user code segment, user data segment, and task state segment, none of which actually restrict memory.

##### IDT
Pretty typical IDT. Handlers are generated in comptime.

Triple fault flow: Program generated interrupt -> #GP -> #DF -> #GP
I am almost 100% certain that the IDT is not valid, and possibly the GDT as well

## IO
Namespace presenting a hardware agnostic IO interface

### Console
---
Exposes `init`, `print`, and `clear`.

## Drivers
Drivers are in src/drivers and included in drivers.zig, which has a `Drivers` namespace which includes the bottom namespaces.

### Display
---

#### VGA
Standard VGA driver implementing printing, colors, etc.

Scrolling pushes everything up one line and blanks out the very bottom

### Data
---

#### Serial
Allows some automated testing and a much more convenient debugging experience. Currently polls on everything though it won't in the future.
