//! Driver implementing polling serial for debugging purposes pre-interrupt implementation
//! Thank god for https://wiki.osdev.org/Serial_Ports

const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();
const arch = @import("../../arch/x86/arch.zig");
const in = arch.in;
const out = arch.out;

const SerialError = error{
    Timeout,
    NonfunctionalPort,
};

/// Struct representing a fifo serial port. Use as pointer with serial address
const SyncSerialPort = struct {
    port: u16,
    /// Initializes and tests this serial port using 8N1
    pub fn init(com: u16) !SyncSerialPort {
        // TODO look into the default baud, this is a placeholder
        // TODO hardware handshaking? if I ever need it
        var self = SyncSerialPort{
            .port = com,
        };

        self.setBaud(10);
        // Disable interrupts
        out(com + 1, @as(u8, 0));
        // Character length of 8, 1 stop bit, 0 parity bits
        // Typically for text you use 7 bit length but I don't want the headache in case I wanna send
        // numbers
        out(com + 3, @as(u8, 0b00000011));
        // Enable loopback and test functionality
        out(com + 4, @as(u8, 0b00010000));
        self.write('t') catch return SerialError.NonfunctionalPort;
        if ((self.read() catch return SerialError.NonfunctionalPort) != 't') return SerialError.NonfunctionalPort;
        out(com + 4, @as(u8, 0b0));

        return self;
    }

    /// Uses DLAB bit to set the divisor register and control the transmission rate
    pub fn setBaud(self: SyncSerialPort, divisor: u16) void {
        // TODO Maybe I should save and restore port + 0 and port + 1? idk
        // Set DLAB bit
        out(self.port + 3, @as(u8, 0b10000000));
        // Port + 0 = lsbyte
        const lsbyte: u8 = switch (native_endian) {
            .big => @truncate(divisor >> 8),
            .little => @truncate(divisor),
        };
        out(self.port + 0, lsbyte);
        // Port + 1 = msbyte
        const msbyte: u8 = switch (native_endian) {
            .big => @truncate(divisor),
            .little => @truncate(divisor >> 8),
        };
        out(self.port + 1, msbyte);
        // Clear DLAB bit
        out(self.port + 3, @as(u8, 0b0));
    }

    /// Reads a byte from the serial port. Will time out if it waits longer than .5 seconds
    pub fn read(self: *volatile SyncSerialPort) !u8 {
        // Check the data ready field in line status
        // TODO Proper timeout

        // Basic approximation of delta for now
        var lineStatus = in(u8, self.port + 5);
        var i: u16 = 0;
        while (lineStatus & 0b01000000 == 0) {
            if (i >= 100000000) return SerialError.Timeout;
            lineStatus = in(u8, self.port + 5);
            i += 1;
        }
        return in(u8, self.port + 0);
    }

    /// Writes a byte to the serial port. Will time out if it waits longer than .5 seconds
    pub fn write(self: SyncSerialPort, char: u8) !void {
        // Check the transmitter holding register empty field in line status
        // TODO Proper timeout

        // Basic approximation of delta for now
        var lineStatus = in(u8, self.port + 5);
        var i: u16 = 0;
        while (lineStatus & 0b01000000 == 0) {
            if (i >= 100000000) return SerialError.Timeout;
            lineStatus = in(u8, self.port + 5);
            i += 1;
        }
        out(self.port + 0, char);
    }
};

// Common port locations to check, although it'll almost certainly be the first
const COM1: u16 = 0x3F8;
var port: SyncSerialPort = undefined;

/// Finds and remembers functional serial port
pub fn init() !void {
    port = try SyncSerialPort.init(COM1);
}

/// Loops over input and prints it. Quietly ignores errors since this is largely for logging
pub fn printString(str: []const u8) void {
    for (str) |c| port.write(c) catch return;
}

///// Standard printing with format
//pub fn print(comptime fmt: []const u8, args: anytype) void {
//    var w = writer(&.{});
//}
