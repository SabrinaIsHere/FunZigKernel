//! https://hv.smallkirby.com/en/kernel/interrupt
//! Regrettably smallkirby implmeneted this kind of just the best way so I borrowed lots of code

const arch = @import("arch.zig");
const Idt = @import("IDT.zig");
const Gdt = @import("GDT.zig");
const Console = arch.Console;

// General purpose registers
const Registers = packed struct {
    EAX: usize,
    EBX: usize,
    ECX: usize,
    EDX: usize,
    ESI: usize,
    EDI: usize,
    ESP: usize,
    EBP: usize,
};
/// Context of the processor when an interrupt is handled
const CTX = packed struct {
    // General purpose registers
    registers: Registers,
    /// Error code for exceptions. Set to 0 when handling an interrupt
    error_code: u32,
    // Interrupt vector
    vector: u32,
    /// EIP register at time of exception/interrupt
    eip: u32,
    // CS register at time of exception/interrupt, padded to a double word
    cs: u32,
    /// Eflags register at time of exception/interrupt
    eflags: u32,
    /// Utility function
    pub fn print(self: *CTX) void {
        _ = self;
        Console.print("ISR Called!", .{});
    }
};

/// Stub function for unhandled exceptions
/// TODO: Move this out to interrupts.zig when everything is tested and working
fn isrStub(ctx: *CTX) void {
    ctx.print();
}

/// Selects ISR function to call into
export fn isrSelect(ctx: *CTX) callconv(.c) void {
    isrStub(ctx);
}

/// Common ISR function; abstracts hardware weirdness away to make writing handlers easier
export fn isrCommon() callconv(.naked) void {
    // Save registers
    asm volatile (
        \\pusha
    );
    asm volatile (
        \\call isrSelect
    );
    // Restore registers; return from interrupt
    asm volatile (
        \\popa
        \\iret
    );
}

fn genISR(comptime vector: usize) Idt.InterruptHandler {
    return struct {
        fn handler() callconv(.naked) void {
            // Disable interrupts
            asm volatile ("cli");
            // If an error code is not provided, push one
            if (vector != 8 and !(vector >= 10 and vector <= 14) and vector != 17) {
                asm volatile ("pushl $0");
            }
            // Push the vector
            asm volatile (
                \\movl $16, %%edx
                \\pushl %[vector]
                :
                : [vector] "n" (vector),
            );
            // Jump to the ISR common
            asm volatile ("jmp isrCommon");
        }
    }.handler;
}

/// Initialize the ISRs and load them into the IDT
pub fn init() void {
    // Define defaults
    // Define the 32 exceptions
    // 22-31 are reserved
    inline for (0..32) |i| {
        Idt.IDT[i].defineTrapGate(genISR(i), Gdt.K_CODE_SEGMENT, 1, Idt.PRIV_K);
    }
    // Define interrupts
    inline for (32..Idt.IDTLength) |i| {
        Idt.IDT[i].defineInterruptGate(genISR(i), Gdt.K_CODE_SEGMENT, 1, Idt.PRIV_K);
    }
    Console.print("Size: {any}\n", .{@sizeOf(Idt.IDTEntry)});
    for (0..Idt.IDTLength) |i| {
        Console.print("IDT Offset: 0x{X}\n", .{@intFromPtr(&Idt.IDT[i])});
    }
    Console.print("Interrupts Enabled\n", .{});
    asm volatile ("sti");
}

pub fn runtimeTests() void {
    Console.print("Interrupt Test: \n", .{});
    asm volatile ("int $5");
    Console.print("Post Interrupt Test: \n", .{});
}
