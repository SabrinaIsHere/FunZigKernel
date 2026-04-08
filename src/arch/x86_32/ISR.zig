//! https://hv.smallkirby.com/en/kernel/interrupt
//! Regrettably smallkirby implmeneted this kind of just the best way so I borrowed lots of code

const arch = @import("arch.zig");
const Idt = @import("IDT.zig");
const Gdt = @import("GDT.zig");
const Console = arch.Console;
const interrupts = @import("interrupts.zig");
export const isrSelect = interrupts.isrSelect;

pub const ErrorCode = packed struct {
    reserved: u12,
    index: u16,
    ti: u2,
    idt: u1,
    ext: u1,

    pub fn print(self: *ErrorCode) void {
        Console.print(
            \\Error code: {any}, {any}, {any}, {any}
            \\
        , .{ self.ext, self.idt, self.ti, self.index });
    }
};
/// Context of the processor when an interrupt is handled
/// This stuff is pretty specific to interrupts which is why it's here and not in arch
pub const CTX = packed struct {
    // General purpose registers
    registers: arch.Registers,
    // Interrupt vector
    vector: u32,
    /// Error code for exceptions. Set to 0 when handling an interrupt
    error_code: ErrorCode,
    /// EIP register at time of exception/interrupt
    eip: u32,
    // CS register at time of exception/interrupt, padded to a double word
    cs: u32,
    /// Eflags register at time of exception/interrupt
    eflags: u32,
    /// Utility function
    pub fn print(self: *CTX) void {
        self.registers.print();
        self.error_code.print();
        Console.print(
            \\Vector: 0x{X}
            \\EIP: 0x{X}
            \\CS: 0x{X}
            \\EFLAGS: 0x{X}
            \\
        ,
            .{
                self.vector,
                self.eip,
                self.cs,
                self.eflags,
            },
        );
    }
};

/// Common ISR function; abstracts hardware weirdness away to make writing handlers easier
export fn isrCommon() callconv(.naked) void {
    // Save registers
    asm volatile (
        \\pushl %%edi
        \\pushl %%esi
        \\pushl %%ebp
        \\pushl %%esp
        \\pushl %%edx
        \\pushl %%ecx
        \\pushl %%ebx
        \\pushl %%eax
    );
    asm volatile (
        \\pushl %%esp
        \\popl %%edi
        // Align stack to 16 bytes.
        \\pushl %%esp
        \\pushl (%%esp)
        \\andl $-0x8, %%esp
        // Call the dispatcher.
        \\call isrSelect
        // Restore the stack.
        \\movl 4(%%esp), %%esp
    );
    // Restore registers; return from interrupt
    asm volatile (
        \\popl %%eax
        \\popl %%ebx
        \\popl %%ecx
        \\popl %%edx
        \\popl %%esp
        \\popl %%ebp
        \\popl %%esi
        \\popl %%edi
        \\add $8, %%esp
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
    defer Console.print("Interrupts Enabled\n", .{});
    // Define defaults
    // Define the 32 exceptions
    // 22-31 are reserved
    inline for (0..32) |i| {
        Idt.IDT[i].defineTrapGate(genISR(i), Gdt.K_CODE_SEGMENT * 8, 1, Idt.PRIV_K);
    }
    // Define interrupts
    //inline for (32..Idt.IDTLength) |i| {
    //    Idt.IDT[i].defineInterruptGate(genISR(i), Gdt.K_CODE_SEGMENT * 8, 1, Idt.PRIV_K);
    //}
    interrupts.init();
    arch.enableInterrupts();
    //runtimeTests();
}

pub fn runtimeTests() void {
    Console.print("Interrupt Test: \n", .{});
    asm volatile ("int $6");
}
