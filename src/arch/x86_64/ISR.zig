//! https://hv.smallkirby.com/en/kernel/interrupt
//! Regrettably smallkirby implmeneted this kind of just the best way so I borrowed lots of code

const arch = @import("arch.zig");
const Idt = @import("IDT.zig");
const Console = arch.Console;
const interrupts = @import("interrupts.zig");
const Gdt = @import("GDT.zig");
export const isrSelect = interrupts.isrSelect;

/// Context of the processor when an interrupt is handled
/// This stuff is pretty specific to interrupts which is why it's here and not in arch
pub const CTX = packed struct {
    // General purpose registers
    registers: arch.Registers,
    // Interrupt vector
    vector: u64,
    /// Error code for exceptions. Set to 0 when handling an interrupt
    error_code: u64,
    /// EIP register at time of exception/interrupt
    rip: u64,
    // CS register at time of exception/interrupt, padded to a double word
    cs: u64,
    /// Eflags register at time of exception/interrupt
    rflags: u64,
    /// Utility function
    pub fn print(self: *CTX) void {
        self.registers.print();
        Console.print(
            \\Vector: 0x{X}
            \\Error Code: 0x{X}
            \\RIP: 0x{X}
            \\CS: 0x{X}
            \\EFLAGS: 0x{X}
            \\
        ,
            .{
                self.vector,
                self.error_code,
                self.rip,
                self.cs,
                self.rflags,
            },
        );
    }
};

/// Common ISR function; abstracts hardware weirdness away to make writing handlers easier
export fn isrCommon() callconv(.naked) void {
    // Save registers
    asm volatile (
        \\pushq %%rdi
        \\pushq %%rsi
        \\pushq %%rbp
        \\pushq %%rsp
        \\pushq %%r15
        \\pushq %%r14
        \\pushq %%r13
        \\pushq %%r12
        \\pushq %%r11
        \\pushq %%r10
        \\pushq %%r9
        \\pushq %%r8
        \\pushq %%rdx
        \\pushq %%rcx
        \\pushq %%rbx
        \\pushq %%rax
        \\movq %%cr2, %%rax
        \\pushq %%rax
        \\movq %%cr3, %%rax
        \\pushq %%rax
        \\movq %%cr4, %%rax
        \\pushq %%rax
        \\movq %%cr8, %%rax
        \\pushq %%rax
    );
    asm volatile (
        \\pushq %%rsp
        \\popq %%rdi
        // Align stack to 16 bytes.
        \\pushq %%rsp
        \\pushq (%%rsp)
        \\andq $-0x10, %%rsp
        // Call the dispatcher.
        \\call isrSelect
        // Restore the stack.
        \\movq 8(%%rsp), %%rsp
    );
    // Restore registers; return from interrupt
    asm volatile (
        \\popq %%rax
        \\movq %%rax, %%cr8
        \\popq %%rax
        \\movq %%rax, %%cr4
        \\popq %%rax
        \\movq %%rax, %%cr3
        \\popq %%rax
        \\movq %%rax, %%cr2
        \\popq %%rax
        \\popq %%rbx
        \\popq %%rcx
        \\popq %%rdx
        \\popq %%r8
        \\popq %%r9
        \\popq %%r10
        \\popq %%r11
        \\popq %%r12
        \\popq %%r13
        \\popq %%r14
        \\popq %%r15
        \\popq %%rsp
        \\popq %%rbp
        \\popq %%rsi
        \\popq %%rdi
        \\add $0x10, %%rsp
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
                asm volatile ("pushq $0");
            }
            // Push the vector
            asm volatile (
                \\pushq %[vector]
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
    // Define the 32 exceptions
    inline for (0..32) |i| {
        //Idt.IDT[i].defineTrapGate(genISR(i), Gdt.K_CODE_SEGMENT * 8, 1, Idt.PRIV_K);
        Idt.IDT[i].defineGate(genISR(i), Gdt.K_CODE_SEGMENT * 8, Idt.PRIV_K, .Trap);
    }
    // Define interrupts
    inline for (32..Idt.IDTLength) |i| {
        Idt.IDT[i].defineGate(genISR(i), Gdt.K_CODE_SEGMENT * 8, Idt.PRIV_K, .Interrupt);
    }
    interrupts.init();
    arch.enableInterrupts();
    //runtimeTests();
}

pub fn runtimeTests() void {
    Console.print("Interrupt Test: \n", .{});
    asm volatile ("int $6");
}
