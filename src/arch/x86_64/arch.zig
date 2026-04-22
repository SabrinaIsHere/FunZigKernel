//! Got this from https://github.com/ZystemOS/pluto/blob/develop/src/kernel/arch/x86/arch.zig
//! TODO: Translate machine code in memory to assembly for debugging purposes. For now gdb is fine

const limine = @import("limine");
const GDT = @import("GDT.zig");
const IDT = @import("IDT.zig");
const ISR = @import("ISR.zig");
const Cpuid = @import("cpuid.zig");
const Apic = @import("apic.zig");
const IO = @import("../../io/io.zig");
const Paging = @import("paging.zig");
const main = @import("../../main.zig");
pub const Drivers = @import("drivers/drivers.zig");
pub const Console = IO.Console;

/// General purpose registers
pub const Registers = packed struct {
    RAX: usize,
    RBX: usize,
    RCX: usize,
    RDX: usize,
    RSP: usize,
    RBP: usize,
    RSI: usize,
    RDI: usize,
    R8: usize,
    R9: usize,
    R10: usize,
    R11: usize,
    R12: usize,
    R13: usize,
    R14: usize,
    R15: usize,

    pub fn print(self: *Registers) void {
        Console.print(
            \\RAX: 0x{X}
            \\RBX: 0x{X}
            \\RCX: 0x{X}
            \\RDX: 0x{X}
            \\RSP: 0x{X}
            \\RBP: 0x{X}
            \\RSI: 0x{X}
            \\RDI: 0x{X}
            \\R8:  0x{X}
            \\R9:  0x{X}
            \\R10: 0x{X}
            \\R11: 0x{X}
            \\R12: 0x{X}
            \\R13: 0x{X}
            \\R14: 0x{X}
            \\R15: 0x{X}
            \\
        , .{
            self.RAX,
            self.RBX,
            self.RCX,
            self.RDX,
            self.RSP,
            self.RBP,
            self.RSI,
            self.RDI,
            self.R8,
            self.R9,
            self.R10,
            self.R11,
            self.R12,
            self.R13,
            self.R14,
            self.R15,
        });
    }
};

var hhdm_offset: usize = 0;

/// Initializes architecture specific things like the GDT and IDT
pub fn init() void {
    disableInterrupts();
    initHhdm();
    GDT.init();
    IDT.init();
    Cpuid.init();
    //Apic.init(); // NOTE: This probably needs to go with the acpi stuff
    // This reenables interrupts
    ISR.init();
    Paging.init();
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
pub inline fn hlt() void {
    asm volatile ("hlt");
}

/// Halt the cpu but allow interrupts
pub fn wait() noreturn {
    enableInterrupts();
    while (true) hlt();
}

/// Kernel panic; disable interrupts and halt the cpu
/// TODO: Serial only print
pub fn k_panic(comptime msg: []const u8) noreturn {
    disableInterrupts();
    Console.print("kpanic: ", .{});
    Console.print(msg, .{});
    while (true) hlt();
}

/// Loads the pml4 into the processor
/// Expects pml4 to be a virtual address
pub inline fn setPML4(pml4: *Paging.PML4E) void {
    Console.print("Loading page tables...\n", .{});
    defer Console.print("New page tables loaded\n", .{});
    const phys_addr: usize = @truncate(virtualToPhysical(@intFromPtr(pml4)));
    Console.print("Physical address: 0x{X}\n", .{phys_addr});
    // BUG: Throwing a #GP, likely bc of virtualToPhysical()
    // Or the page table is invalid because it unmaps the kernel
    // CR3 is also 32 bit
    asm volatile (
        \\ mov %[pml4], %%cr3 
        :
        : [pml4] "{rax}" (phys_addr),
    );
}

fn initHhdm() void {
    defer Console.print("HHDM offset: 0x{X}\n", .{hhdm_offset});
    const response = main.hhdm_request.response orelse k_panic("No hhdm provided\n");
    hhdm_offset = response.offset;
}

pub inline fn virtualToPhysical(addr: usize) usize {
    return addr - hhdm_offset;
}

pub inline fn physicalToVirtual(addr: usize) usize {
    return addr + hhdm_offset;
}
