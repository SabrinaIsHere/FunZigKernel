const arch = @import("arch.zig");
const Console = arch.Console;

/// Registers passed back by cpuid
/// Packed for bitcast reasons
const Regs = packed struct {
    eax: usize,
    ebx: usize,
    ecx: usize,
    edx: usize,
};

pub const Features = struct {};

pub var features: Features = undefined;

/// Thin cpuid wrapper, wrapped in other functions to further abstract this gnarly ass assembly lol
fn cpuid(code: u32) Regs {
    var output = Regs{ .eax = 0, .ebx = 0, .ecx = 0, .edx = 0 };
    var eax: usize = 0;
    var ebx: usize = 0;
    var ecx: usize = 0;
    var edx: usize = 0;
    asm volatile (
        \\ cpuid
        \\ movl %%ebx, %[pt1]
        \\ movl %%ecx, %[pt2]
        \\ movl %%edx, %[pt3]
        : [pt1] "=m" (ebx),
          [pt2] "=m" (ecx),
          [pt3] "=m" (edx),
        : [code] "{eax}" (code),
    );
    output.ebx = ebx;
    output.ecx = ecx;
    output.edx = edx;
    // NOTE: Literally no idea why this fucks everything up it's so irritating. Do anything with eax and suddenly nothing works
    // TODO: Just remove this I don't think I need anything from eax so whatever
    asm volatile (
        \\ movl %[code], %%eax
        \\ cpuid
        \\ movl %%eax, %[pt1]
        : [pt1] "=m" (eax),
        : [code] "{ebx}" (code),
    );
    output.eax = eax;
    return output;
}

pub fn getVendorString() [12]u8 {
    const regs: Regs = cpuid(0);
    const string = [_]u32{ regs.ebx, regs.edx, regs.ecx };
    return @bitCast(string);
}

pub fn getFeatures() void {}
