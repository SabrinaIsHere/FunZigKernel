//! Driver implementing polling serial for debugging purposes pre-interrupt implementation
//! Thank god for https://wiki.osdev.org/Serial_Ports

const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();

const SerialError = error{
    Timeout,
    NonfunctionalPort,
};

/// Struct representing a fifo serial port. Use as pointer with serial address
const SyncSerialPort = packed struct {
    /// Read/write buffer
    buffer: u8,
    /// Whether or not to enable interrupts, as opposed to FIFO
    /// +------------------------------------------------------------------------------------------------------+
    /// | 7 - 4    | 3            | 2                    | 1                         | 0                       |
    /// | Reserved | Modem status | Receiver line status | Trans. holding reg. empty | Received data available |
    /// +------------------------------------------------------------------------------------------------------+
    interruptEnable: u8,
    /// Controls fifo buffers
    /// +--------------------------------------------------------------------------------------------+
    /// | 7 - 6               | 5 - 4    | 3               | 2              | 1             | 0      |
    /// | Input trigger level | Reserved | DMA mode select | Clear transmit | Clear receive | Enable |
    /// +--------------------------------------------------------------------------------------------+
    fifoControl: u8,
    /// Sets general connection parameters
    /// +------------------------------------------------------------+
    /// | 7                    | 6            | 5 - 3  | 2    | 1 - 0|
    /// | Divisor latch access | Break enable | Parity | Stop | Data |
    /// +------------------------------------------------------------+
    lineControl: u8,
    /// Hardware handshake register. Largely unused except for the loop bit
    /// +-----------------------------------------------------------------------+
    /// | 7 - 5  | 4    | 3     | 2     | 1               | 0                   |
    /// | Unused | Loop | Out 1 | Out 2 | Request to send | Data terminal ready |
    /// +-----------------------------------------------------------------------+
    modemControl: u8,
    /// Checks for errors and enables polling
    /// +---------------------------------------------------------------------------------------------+
    /// | 7               | 6            | 5                         | 4  | 3  | 2  | 1  | 0          |
    /// | Impending error | Trans. empty | Trans. holding reg. empty | BI | FE | PE | OE | Data ready |
    /// +---------------------------------------------------------------------------------------------+
    lineStatus: u8,
    /// Current state of control lines and change information. If the loop bit is set the upper
    /// 4 bits mirror the 4 status output lines in the mcr
    /// +--------------------------------------------------+
    /// | 7   | 6  | 5   | 4   | 3    | 2    | 1    | 0    |
    /// | DCD | RI | DSR | CTS | DDCD | TERI | DDSR | DCTS |
    /// +--------------------------------------------------+
    modemStatus: u8,
    scratch: u8,

    /// Initializes and tests this serial port using 8N1
    pub fn init(self: *volatile SyncSerialPort) !void {
        // TODO look into the default baud, this is a placeholder
        // TODO hardware handshaking? if I ever need it
        self.setBaud(10);
        // Disable interrupts
        self.interruptEnable = 0;
        // Character length of 8, 1 stop bit, 0 parity bits
        // Typically for text you use 7 bit length but I don't want the headache in case I wanna send
        // numbers
        self.lineControl = 0b00000011;
        // Enable loopback and test functionality
        self.modemControl = 0b00010000;
        self.write('t') catch return SerialError.NonfunctionalPort;
        if ((self.read() catch return SerialError.NonfunctionalPort) != 't') return SerialError.NonfunctionalPort;
        self.modemControl = 0b0;
    }

    /// Uses DLAB bit to set the divisor register and control the transmission rate
    pub fn setBaud(self: *volatile SyncSerialPort, divisor: u16) void {
        // Save values
        const savedBuffer = self.buffer;
        const savedInterruptEnable = self.interruptEnable;
        // Set DLAB bit
        self.lineControl |= 0b10000000;
        // Port + 0 = lsbyte
        self.buffer = switch (native_endian) {
            .big => @truncate(divisor >> 8),
            .little => @truncate(divisor),
        };
        // Port + 1 = msbyte
        self.interruptEnable = switch (native_endian) {
            .big => @truncate(divisor),
            .little => @truncate(divisor >> 8),
        };
        // Clear DLAB bit
        self.lineControl &= 0b01111111;
        // Restore values
        self.buffer = savedBuffer;
        self.interruptEnable = savedInterruptEnable;
    }

    /// Reads a byte from the serial port. Will time out if it waits longer than .5 seconds
    pub fn read(self: *volatile SyncSerialPort) !u8 {
        // Check the data ready field in line status
        // TODO Timeout

        // Basic approximation of delta for now
        var i: u16 = 0;
        while (self.lineStatus & 0b1 == 0) {
            if (i >= 1000000000) return SerialError.Timeout;
            i += 1;
        }
        return self.buffer;
    }

    /// Writes a byte to the serial port. Will time out if it waits longer than .5 seconds
    pub fn write(self: *volatile SyncSerialPort, char: u8) !void {
        // Check the transmitter holding register empty field in line status
        // TODO Timeout

        // Basic approximation of delta for now
        var i: u16 = 0;
        while (self.lineStatus & 0b01000000 == 0) {
            if (i >= 1000000000) return SerialError.Timeout;
            i += 1;
        }
        self.buffer = char;
    }
};

// Common port locations to check, although it'll almost certainly be the first
const PORTS = [_]usize{ 0x3F8, 0x2F8, 0x3E8, 0x2E8, 0x5F8, 0x4F8, 0x5E8, 0x4E8 };
var port: *volatile SyncSerialPort = undefined;

/// Finds and remembers functional serial port
pub fn init() !void {
    // Loop through potential ports until a working one is found
    for (PORTS) |candidate| {
        port = @ptrFromInt(candidate);
        port.init() catch continue;
        return;
    }
    return SerialError.NonfunctionalPort;
}

/// Loops over input and prints it. Quietly ignores errors since this is largely for logging
pub fn printString(str: []const u8) void {
    for (str) |c| port.write(c) catch return;
}

///// Standard printing with format
//pub fn print(comptime fmt: []const u8, args: anytype) void {
//    var w = writer(&.{});
//}
