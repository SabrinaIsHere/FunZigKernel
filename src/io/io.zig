//! Presents hardware agnostic interfaces for IO

const arch = @import("../arch/arch.zig").arch;
const Drivers = arch.Drivers;
const Serial = Drivers.Serial;

/// Standard interface exposing console IO
pub const Console = struct {
    /// Initializes VGA and Serial
    pub fn init() void {
        //VGA.init();
        Serial.init() catch arch.k_panic("Serial unable to initialize.");
    }
    /// Clears VGA framebuffer. Doesn't clear serial because it's the backup debugging output and it
    /// needs to maintain integrity
    /// Prints to VGA and serial
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        //VGA.print(fmt, args);
        Serial.print(fmt, args);
    }
};
