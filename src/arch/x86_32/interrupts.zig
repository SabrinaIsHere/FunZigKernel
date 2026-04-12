const arch = @import("arch.zig");
const Console = arch.Console;
const Isr = @import("ISR.zig");
const CTX = Isr.CTX;

pub const ErrorVectors = enum(u16) {
    DivideError,
    DebugException,
    NMI,
    Breakpoint,
    Overflow,
    BoundRangeExceeded,
    InvalidOpcode,
    DeviceNotAvailable,
    DoubleFault,
    CoprocessorSegmentOverrun,
    InvalidTSS,
    SegmentNotPresent,
    StackSegmentFault,
    GeneralProtection,
    PageFault,
    Reserved1,
    FloatingPointError,
    AlignmentCheck,
    MachineCheck,
    SIMDFloatingPointException,
    VirtualizationException,
    ControlProtectionException,
    Reserved2,
    Reserved3,
    Reserved4,
    Reserved5,
    Reserved6,
    Reserved7,
    Reserved8,
    Reserved9,
    Reserved10,
};

/// Higher level interrupt handler type
pub const Handler = *const fn (ctx: *CTX) void;

/// All high level handler functions
pub var handlers: [256]Handler = [_]Handler{isrStub} ** 256;

/// TODO: remove this, just to keep the handlers from vomiting all over my screen while debugging
var interrupts: u16 = 0;

/// Stub function for unhandled exceptions
fn isrStub(ctx: *CTX) void {
    interrupts += 1;
    Console.print("========== UNHANDLED INTERRUPT ==========\n", .{});
    ctx.print();
    if (interrupts >= 2) arch.k_panic("Interrupts exceeded.\n");
    arch.wait();
}

/// Selects ISR function to call into
pub fn isrSelect(ctx: *CTX) callconv(.c) void {
    // Sometimes the stack can be screwy and vector can be off
    if (ctx.vector >= 256) isrStub(ctx);
    handlers[ctx.vector](ctx);
}

pub fn init() void {
    handlers[@intFromEnum(ErrorVectors.GeneralProtection)] = handleGP;
    handlers[@intFromEnum(ErrorVectors.InvalidOpcode)] = handleUD;
}

// Some basic error handling. These will likely be moved at some point when the codebase is more fleshed out
/// Handle invalid opcode faults
fn handleUD(ctx: *CTX) void {
    Console.print("Invalid opcode fault\n", .{});
    ctx.print();
    ctx.eip += 4;
    //arch.wait();
}

/// Handle general protection faults
fn handleGP(ctx: *CTX) void {
    Console.print("General protection fault\n", .{});
    ctx.print();
    arch.wait();
}
