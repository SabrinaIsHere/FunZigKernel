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
Allows some automated testing and a much more convenient debugging experience

Notes
 - Needs initialization
 - Polls on everything for now but that'll get a touchup when I get around to interrupts
