const Serial = @import("serial.zig");
const arch = @import("arch.zig");

/// Initializes VGA and Serial
pub fn init() void {
    //VGA.init();
    Serial.init() catch arch.k_panic("Serial unable to initialize.");
}
/// Prints to serial
pub fn print(comptime fmt: []const u8, args: anytype) void {
    Serial.print(fmt, args);
}
