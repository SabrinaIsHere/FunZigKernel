//! https://wiki.osdev.org/Interrupt_Descriptor_Table
//! https://github.com/ZystemOS/pluto/blob/develop/src/kernel/arch/x86/idt.zig

const IO = @import("../../io/io.zig");
const Console = IO.Console;
const std = @import("std");

pub const InterruptHandler = fn () callconv(.naked) void;

/// Defines an entry in the interrupt descriptor table
/// Always 8 bytes long
/// TODO: Mark this private
pub const IDTEntry = packed struct {
    /// Procedure entry
    offset_lower: u16,
    /// GDT segment
    segment: u16,
    /// Hardware reserved
    reserved: u5,
    /// Reserved in task gate, otherwise all zeroes
    zero: u3,
    /// Gate type field. Also defines if the gate is 32 bit or 16 bit.
    d: u5,
    /// Descriptor privilege level
    dpl: u2,
    /// Segment present
    p: u1,
    // Procedure entry
    offset_higher: u16,

    /// For initializing the IDT
    pub fn defineEmptyGate(self: *IDTEntry) void {
        self.offset_lower = 0;
        self.segment = 0;
        self.zero = 0;
        self.d = 0;
        self.dpl = 0;
        self.p = 0;
        self.offset_higher = 0;
    }
    /// Define this gate as a task gate
    pub fn defineTaskGate(self: *IDTEntry, tss_segment: u16, dpl: u2) void {
        self.segment = tss_segment;
        self.d = 0b00101;
        self.dpl = dpl;
        self.p = 1;
    }
    /// Define this gate as a trap gate
    pub fn defineTrapGate(self: *IDTEntry, handler: InterruptHandler, segment: u16, is32Bit: u1, dpl: u2) void {
        const offset: usize = @intFromPtr(&handler);
        self.offset_lower = @truncate(offset & 0x0000FFFF);
        self.offset_higher = @truncate((offset & 0xFFFF0000) >> 16);
        self.segment = segment;
        self.zero = 0;
        self.d = 0b00111 | (@as(u5, is32Bit) << 3);
        self.dpl = dpl;
        self.p = 1;
    }
    /// Define this gate as an interrupt gate
    pub fn defineInterruptGate(self: *IDTEntry, handler: InterruptHandler, segment: u16, is32Bit: u1, dpl: u2) void {
        const offset: usize = @intFromPtr(&handler);
        self.offset_lower = @truncate(offset & 0x0000FFFF);
        self.offset_higher = @truncate((offset & 0xFFFF0000) >> 16);
        self.segment = segment;
        self.zero = 0;
        self.d = 0b00110 | (@as(u5, is32Bit) << 3);
        self.dpl = dpl;
        self.p = 1;
    }
    pub fn print(self: *IDTEntry) void {
        Console.print("Offset: 0x{X}{X}\n", .{ self.offset_higher, self.offset_lower });
        Console.print("Segment: {any}\n", .{self.segment});
        Console.print("D: {b}, P: {b}, DPL: {any}\n", .{ self.d, self.p, self.dpl });
    }
};

/// Length of the IDT
pub const IDTLength: u16 = 256;
/// IDT itself
pub var IDT: [IDTLength]IDTEntry = undefined;

/// Defines the region of memory loaded into the IDTR
const IDTDescriptor = packed struct {
    /// Size, in bytes, of the IDT
    size: u16,
    /// Linear address of the IDT (paging applies)
    offset: u32,
};
/// Actual memory pointed to by the IDTR
var idtr = IDTDescriptor{
    .size = (IDTLength - 1) * @sizeOf(IDTEntry),
    .offset = undefined,
};

pub const PRIV_K = 0x0;
pub const PRIV_1 = 0x1;
pub const PRIV_2 = 0x2;
pub const PRIV_U = 0x2;

/// Tells the processor where the IDT is and it's length
fn loadIDT() void {
    idtr.offset = @intFromPtr(&IDT[0]);
    asm volatile ("lidt (%[idtr])"
        :
        : [idtr] "{eax}" (&idtr),
    );
}

/// sidt gets the data in the IDTR
fn storeIDT() IDTDescriptor {
    var data = IDTDescriptor{ .size = 0, .offset = 0 };
    asm volatile ("sidt %[data]"
        : [data] "=m" (data),
    );
    return data;
}

/// Initialize the IDT
pub fn init() void {
    Console.print("IDT: 0x{X}\nIDTR: 0x{X}\n", .{ @intFromPtr(&IDT), @intFromPtr(&idtr) });
    // Initialize the IDT with blank gates to avoid undefined behaviour
    for (IDT, 0..) |_, i| IDT[i].defineEmptyGate();
    // Load the IDT into the processor
    loadIDT();
    runtimeTests();
}

/// Make sure everything is as expected
pub fn runtimeTests() void {
    const idt = storeIDT();
    if (idt.offset != @intFromPtr(&IDT[0])) {
        Console.print("IDT offset differs from expected: 0x{X}: 0x{X}\n", .{ @intFromPtr(&IDT[0]), idt.offset });
    }
    if (IDTLength - 1 != idt.size / 8) {
        Console.print("IDT Length differs from expected: {any}: {any}\n", .{ IDTLength - 1, idt.size / 8 });
    }
}
