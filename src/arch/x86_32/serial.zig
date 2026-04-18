//! Driver implementing polling serial for debugging purposes pre-interrupt implementation
//! This does not work. Leaving it here in case I need to use it for something

const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();
const arch = @import("arch.zig");
const In = arch.In;
const Out = arch.Out;

const SerialError = error{
    Timeout,
    NonfunctionalPort,
};

/// Struct representing a fifo serial port. Use as pointer with serial address
const SyncSerialPort = struct {
    port: u16,
    /// Initializes and tests this serial port using 8N1
    pub fn init(self: *SyncSerialPort, com: u16) linksection(".boottext") !void {
        // TODO: look into the default baud, this is a placeholder
        // TODO: hardware handshaking? if I ever need it

        self.port = com;

        // NOTE: Error in here somewhere

        self.setBaud(10); // This is fine
        // Disable interrupts
        Out(com + 1, @as(u8, 0));
        // Character length of 8, 1 stop bit, 0 parity bits
        // Typically for text you use 7 bit length but I don't want the headache in case I wanna send
        // numbers
        Out(com + 3, @as(u8, 0b00000011));
        // Enable loopback and test functionality
        Out(com + 4, @as(u8, 0b00010000));
        self.write('t') catch return SerialError.NonfunctionalPort;
        if ((self.read() catch return SerialError.NonfunctionalPort) != 't') return SerialError.NonfunctionalPort;
        Out(com + 4, @as(u8, 0b0));
    }

    /// Uses DLAB bit to set the divisor register and control the transmission rate
    pub fn setBaud(self: SyncSerialPort, divisor: u16) linksection(".boottext") void {
        // TODO: Maybe I should save and restore port + 0 and port + 1? idk
        // Set DLAB bit
        Out(self.port + 3, @as(u8, 0b10000000));
        // Port + 0 = lsbyte
        const lsbyte: u8 = switch (native_endian) {
            .big => @truncate(divisor >> 8),
            .little => @truncate(divisor),
        };
        Out(self.port + 0, lsbyte);
        // Port + 1 = msbyte
        const msbyte: u8 = switch (native_endian) {
            .big => @truncate(divisor),
            .little => @truncate(divisor >> 8),
        };
        Out(self.port + 1, msbyte);
        // Clear DLAB bit
        Out(self.port + 3, @as(u8, 0b0));
    }

    /// Reads a byte from the serial port. Will time out if it waits longer than .5 seconds
    pub fn read(self: *volatile SyncSerialPort) linksection(".boottext") !u8 {
        // Check the data ready field in line status
        // TODO: Proper timeout

        // Basic approximation of delta for now
        var lineStatus = In(u8, self.port + 5);
        var i: u16 = 0;
        while (lineStatus & 0b01000000 == 0) {
            if (i >= 100000000) return SerialError.Timeout;
            lineStatus = In(u8, self.port + 5);
            i += 1;
        }
        return In(u8, self.port + 0);
    }

    /// Writes a byte to the serial port. Will time out if it waits longer than .5 seconds
    pub fn write(self: SyncSerialPort, char: u8) linksection(".boottext") !void {
        // Check the transmitter holding register empty field in line status
        // TODO: Proper timeout

        // Basic approximation of delta for now
        var lineStatus = In(u8, self.port + 5);
        var i: u16 = 0;
        while (lineStatus & 0b01000000 == 0) {
            if (i >= 100000000) asm volatile ("hlt");
            lineStatus = In(u8, self.port + 5);
            i += 1;
        }
        Out(self.port + 0, char);
    }
};

// TODO: Logic for multiple ports
const PORTS: [8]u16 linksection(".bootrodata") = [_]u16{
    0x3F8,
    0x2F8,
    0x3E8,
    0x2E8,
    0x5F8,
    0x4F8,
    0x5E8,
    0x4E8,
};
var port: SyncSerialPort linksection(".bootdata") = SyncSerialPort{ .port = 0 };

/// Finds and remembers functional serial port
pub fn init() linksection(".boottext") !void {
    //for (PORTS) |p| {
    //    port.init(p) catch continue;
    //    return;
    //}

    //return SerialError.NonfunctionalPort;
    port.init(0x3F8) catch asm volatile ("hlt");
}

/// Loops over input and prints it. Quietly ignores errors since this is largely for logging
pub fn printString(str: []const u8) linksection(".boottext") void {
    for (str) |c| port.write(c) catch continue;
}

/// Drains buffer
fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) linksection(".boottext") !usize {
    // the length of data must not be zero
    //std.debug.assert(data.len != 0);
    if (data.len != 0) asm volatile ("hlt");

    var consumed: usize = 0;
    const pattern = data[data.len - 1];
    const splat_len = pattern.len * splat;

    // If buffer is not empty write it first
    if (w.end != 0) {
        printString(w.buffered());
        w.end = 0;
    }

    // Now write all data except last element
    for (data[0 .. data.len - 1]) |bytes| {
        printString(bytes);
        consumed += bytes.len;
    }

    // If out patter (i.e. last element of data) is non zero len then write splat times
    switch (pattern.len) {
        0 => {},
        else => {
            for (0..splat) |_| {
                printString(pattern);
            }
        },
    }
    // Now we have to return how many bytes we consumed from data
    consumed += splat_len;
    return consumed;
}

/// Returns std.Io.Writer implementation for this console
/// NOTE: This likely tries to reference stdio code linked into the 64 bit area
pub fn writer(buffer: []u8) linksection(".boottext") std.Io.Writer {
    return .{
        .buffer = buffer,
        .end = 0,
        .vtable = &.{
            .drain = drain,
        },
    };
}

/// Standard printing with format
pub fn print(comptime fmt: []const u8, args: anytype) linksection(".boottext") void {
    var w = writer(&.{});
    w.print(fmt, args) catch return;
}
