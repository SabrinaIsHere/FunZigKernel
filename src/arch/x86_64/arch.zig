//! Got this from https://github.com/ZystemOS/pluto/blob/develop/src/kernel/arch/x86/arch.zig

const GDT = @import("GDT.zig");
const IDT = @import("IDT.zig");
const ISR = @import("ISR.zig");
const Cpuid = @import("cpuid.zig");
const Apic = @import("apic.zig");
const IO = @import("../../io/io.zig");
pub const Console = IO.Console;

// General purpose registers
pub const Registers = packed struct {
    EAX: usize,
    EBX: usize,
    ECX: usize,
    EDX: usize,
    ESP: usize,
    EBP: usize,
    ESI: usize,
    EDI: usize,

    pub fn print(self: *Registers) void {
        Console.print(
            \\EAX: 0x{X}
            \\EBX: 0x{X}
            \\ECX: 0x{X}
            \\EDX: 0x{X}
            \\ESI: 0x{X}
            \\EDI: 0x{X}
            \\ESP: 0x{X}
            \\EBP: 0x{X}
            \\
        , .{
            self.EAX,
            self.EBX,
            self.ECX,
            self.EDX,
            self.ESI,
            self.EDI,
            self.ESP,
            self.EBP,
        });
    }
};

/// Initializes architecture specific things like the GDT and IDT
pub fn init() void {
    disableInterrupts();
    GDT.init();
    IDT.init();
    Cpuid.init();
    //Apic.init(); // NOTE: This probably needs to go with the acpi stuff
    // This reenables interrupts
    ISR.init();
}

/// Wrapper for the x86 assembly instruction 'inb'
pub fn in(comptime Type: type, port: u16) Type {
    return switch (Type) {
        u8 => asm volatile ("inb %[port], %[result]"
            : [result] "={al}" (-> Type),
            : [port] "{dx}" (port),
        ),
        u16 => asm volatile ("inw %[port], %[result]"
            : [result] "={ax}" (-> Type),
            : [port] "{dx}" (port),
        ),
        u32 => asm volatile ("inl %[port], %[result]"
            : [result] "={eax}" (-> Type),
            : [port] "{dx}" (port),
        ),
        else => @compileError("in: Valid types are u8, u16, and u32. Found " ++ @typeName(Type)),
    };
}

/// Wrapper for the x86 assembly instruction 'outb'
pub fn out(port: u16, val: anytype) void {
    switch (@TypeOf(val)) {
        u8 => asm volatile ("outb %[val], %[port]"
            :
            : [port] "{dx}" (port),
              [val] "{al}" (val),
        ),
        u16 => asm volatile ("outw %[val], %[port]"
            :
            : [port] "{dx}" (port),
              [val] "{ax}" (val),
        ),
        u32 => asm volatile ("outl %[val], %[port]"
            :
            : [port] "{dx}" (port),
              [val] "{eax}" (val),
        ),
        else => @compileError("out: Valid types are u8, u16, and u32. Found " ++ @typeName(@TypeOf(val))),
    }
}

// Enable interrupts
pub fn enableInterrupts() void {
    asm volatile ("sti");
}

// Disable interrupts
pub fn disableInterrupts() void {
    asm volatile ("cli");
}

/// Halt the processor
pub fn hlt() void {
    asm volatile ("hlt");
}

/// Halt the cpu but allow interrupts
pub fn wait() noreturn {
    enableInterrupts();
    while (true) hlt();
}

/// Kernel panic; disable interrupts and halt the cpu
pub fn k_panic(comptime msg: []const u8) noreturn {
    disableInterrupts();
    Console.print("kpanic: ", .{});
    Console.print(msg, .{});
    while (true) hlt();
}
