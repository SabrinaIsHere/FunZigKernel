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
    CR2: usize,
    CR3: usize,
    CR4: usize,
    CR8: usize,
    RAX: usize,
    RBX: usize,
    RCX: usize,
    RDX: usize,
    R8: usize,
    R9: usize,
    R10: usize,
    R11: usize,
    R12: usize,
    R13: usize,
    R14: usize,
    R15: usize,
    RSP: usize,
    RBP: usize,
    RSI: usize,
    RDI: usize,

    pub fn print(self: *Registers) void {
        Console.print(
            \\RAX: 0x{X}
            \\RBX: 0x{X}
            \\RCX: 0x{X}
            \\RDX: 0x{X}
            \\R8:  0x{X}
            \\R9:  0x{X}
            \\R10: 0x{X}
            \\R11: 0x{X}
            \\R12: 0x{X}
            \\R13: 0x{X}
            \\R14: 0x{X}
            \\R15: 0x{X}
            \\RSP: 0x{X}
            \\RBP: 0x{X}
            \\RSI: 0x{X}
            \\RDI: 0x{X}
            \\CR2: 0x{X}
            \\CR3: 0x{X}
            \\CR4: 0x{X}
            \\CR8: 0x{X}
            \\
        , .{
            self.RAX,
            self.RBX,
            self.RCX,
            self.RDX,
            self.R8,
            self.R9,
            self.R10,
            self.R11,
            self.R12,
            self.R13,
            self.R14,
            self.R15,
            self.RSP,
            self.RBP,
            self.RSI,
            self.RDI,
            self.CR2,
            self.CR3,
            self.CR4,
            self.CR8,
        });
    }
};

var hhdm_offset: usize = 0;

pub extern fn reloadSegments() void;

/// Initializes architecture specific things like the GDT and IDT
pub fn init() void {
    disableInterrupts();
    initHhdm();
    GDT.init();
    IDT.init();
    Cpuid.init();
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
pub fn setPML4(pml4: *Paging.PML4E) void {
    Console.print("Loading page tables...\n", .{});
    defer Console.print("New page tables loaded\n", .{});
    const phys_addr: usize = virtualToPhysical(@intFromPtr(pml4));
    const cr3_val = (phys_addr << 12);
    Console.print("Physical address (set cr3): 0x{X}\n", .{phys_addr});
    // BUG: Throwing a #GP, no idea why
    // Or the page table is invalid because it unmaps the kernel
    // bits 0-11 of cr3 should be 0
    // My best guess is that a reserved bit is being written to somewhere but idfk
    asm volatile (
        \\ mov %[pml4], %%cr3 
        :
        : [pml4] "{rax}" (cr3_val),
    );
}

/// Get the current PML4 from cr3
pub fn getPML4() *Paging.PML4E {
    var cr3: u64 = 0;
    asm volatile ("mov %%cr3, %[out]"
        : [out] "={rax}" (cr3),
    );
    const addr = physicalToVirtual(cr3 >> 12) & 0xFFFFFFFFFFFFFFF0;
    Console.print("cr3: 0x{X}, {any}\nAddr: 0x{X}\n", .{ cr3 >> 12, (cr3 >> 12) % 16, addr });
    // BUG: The address I'm getting here doesn't seem to be valid
    return @ptrFromInt((addr));
}

/// Initialize hhdm related data
fn initHhdm() void {
    defer Console.print("HHDM offset: 0x{X}\n", .{hhdm_offset});
    const response = main.hhdm_request.response orelse @panic("No hhdm provided\n");
    hhdm_offset = response.offset;
}

/// Translates a virtual address to a physical via hhdm
/// TODO: Anyopaque? Would be more annoying for some stuff but make more sense. Maybe usize to *anyopaque
pub inline fn virtualToPhysical(addr: usize) usize {
    return addr - hhdm_offset;
}

/// Translates a phyiscal address to a virtual via hhdm
/// TODO: Anyopaque
pub inline fn physicalToVirtual(addr: usize) usize {
    return addr + hhdm_offset;
}
