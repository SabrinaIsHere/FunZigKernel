const std = @import("std");
const builtin = std.builtin;
const Serial = @import("arch/x86_64/drivers/data/serial.zig");

var panicked = false;

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    panicked = true;
    // TODO: Print to screen as well
    Serial.printString(msg);
    Serial.printString("\n");
    // Wait forever
    while (true) asm volatile ("hlt");
}
