//! Presents hardware agnostic interfaces for IO

const Drivers = @import("../drivers/drivers.zig");
const VGA = Drivers.VGA;
const Serial = Drivers.Serial;

/// Standard interface exposing console IO
pub const Console = struct {
    /// Initializes VGA and Serial
    pub fn init() void {
        VGA.init();
        Serial.init() catch VGA.print("Serial uninitialized.", .{});
    }
    /// Clears VGA framebuffer. Doesn't clear serial because it's the backup debugging output and it
    /// needs to maintain integrity
    pub const clear = VGA.clear;
    /// Prints to VGA and serial
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        VGA.print(fmt, args);
        Serial.print(fmt, args);
    }
};
