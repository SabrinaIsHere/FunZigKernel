const arch = @import("arch.zig");
const Console = arch.Console;
const Isr = @import("ISR.zig");
const CTX = Isr.CTX;

/// Higher level interrupt handler type
const Handler = *const fn (ctx: *CTX) void;

/// All high level handler functions
var handlers: [256]Handler = [_]Handler{isrStub} ** 256;

/// TODO: remove this, just to keep the handlers from vomiting all over my screen while debugging
var interrupts: u16 = 0;

/// Stub function for unhandled exceptions
fn isrStub(ctx: *CTX) void {
    interrupts += 1;
    Console.print("========== UNHANDLED INTERRUPT ==========\n", .{});
    ctx.print();
    if (interrupts >= 4) arch.k_panic("Interrupts exceeded.\n");
    arch.wait();
}

/// Selects ISR function to call into
pub fn isrSelect(ctx: *CTX) callconv(.c) void {
    // Sometimes the stack can be screwy and vector can be off
    if (ctx.vector >= 256) isrStub(ctx);
    handlers[ctx.vector](ctx);
}
