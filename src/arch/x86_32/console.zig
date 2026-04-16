const Serial = @import("serial.zig");
const arch = @import("arch.zig");

// TODO: Set these to the function the wrapper thing is dumb

/// Initializes VGA and Serial
pub fn init() linksection(".boottext") void {
    //VGA.init();
    Serial.init() catch arch.k_panic("Serial unable to initialize.");
}
/// Prints to serial (for now)
pub fn print(comptime fmt: []const u8, args: anytype) linksection(".boottext") void {
    Serial.print(fmt, args);
}
