//! https://wiki.osdev.org/Interrupt_Descriptor_Table
//! https://github.com/ZystemOS/pluto/blob/develop/src/kernel/arch/x86/idt.zig

const IO = @import("../../io/io.zig");
const Console = IO.Console;
const std = @import("std");

pub const InterruptHandler = fn () callconv(.naked) void;

pub const GateType = enum(u4) {
    Null = 0,
    Interrupt = 0xE,
    Trap = 0xF,
};

/// Defines an entry in the interrupt descriptor table
/// Always 16 bytes long. 0 defaults for every field for initializing blank IDT
const IDTEntry = packed struct(u128) {
    /// Procedure entry
    offset_low: u16 = 0,
    /// GDT segment
    segment: u16 = 0,
    /// Offset int othe interrupt stack table. Not used if IST = 0
    ist: u3 = 0,
    /// Reserved by hardware
    reserved1: u5 = 0,
    /// 0xE for interrupt gate, 0xF for trap gate
    gate_type: GateType = .Null,
    /// Reserved by hardware
    reserved2: u1 = 0,
    /// CPU privilege level allowed to access this interrupt
    dpl: u2 = 0,
    /// If this is present or not
    p: bool = false,
    /// Highed 48 bits of the offset
    offset_high: u48 = 0,
    /// Reserved by hardware
    reserved3: u32 = 0,

    /// Define this gate as a trap or interrupt gate
    pub fn defineGate(self: *IDTEntry, handler: InterruptHandler, segment: u16, dpl: u2, gate_type: GateType) void {
        const offset: usize = @intFromPtr(&handler);
        self.offset_low = @truncate(offset & 0x000000000000FFFF);
        self.offset_high = @truncate((offset & 0xFFFFFFFFFFFF0000) >> 16);
        self.segment = segment;
        self.gate_type = gate_type;
        self.dpl = dpl;
        self.p = true;
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
pub var IDT: [IDTLength]IDTEntry = [_]IDTEntry{.{}} ** IDTLength;

/// Defines the region of memory loaded into the IDTR
const IDTDescriptor = packed struct {
    /// Size, in bytes, of the IDT
    size: u16,
    /// Linear address of the IDT (paging applies)
    offset: u64,
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
    if (IDTLength - 1 != idt.size / 16) {
        Console.print("IDT Length differs from expected: {any}: {any}\n", .{ IDTLength - 1, idt.size / 16 });
    }
}
