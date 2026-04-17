const Serial = @import("serial.zig");
const arch = @import("arch.zig");

/// Initializes VGA and Serial
pub fn init() linksection(".boottext") void {
    Serial.init() catch asm volatile ("hlt");
}
/// Prints to serial (for now)
pub fn print(comptime fmt: []const u8, args: anytype) linksection(".boottext") void {
    Serial.print(fmt, args);
}

pub fn printString(s: []const u8) linksection(".boottext") void {
    Serial.printString(s);
}
