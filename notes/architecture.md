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
