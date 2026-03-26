## Todo
 - ~~VGA driver~~
 - Serial driver
    - ~~Blocking IO~~
    - Interrupt IO
 - Interrupts
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

### x86_64
---
#### Interrupts

## IO
Namespace presenting a hardware agnostic IO interface

### Console
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
