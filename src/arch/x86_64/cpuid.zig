const arch = @import("arch.zig");
const Console = arch.Console;

// CPUID wrapper return value
pub const Regs = packed struct(u128) {
    eax: usize,
    ebx: usize,
    ecx: usize,
    edx: usize,
};

/// Higher level interface for the features given by the processor.
/// Packed for bit cast reasons
pub const CPUInfo = packed struct(u128) {
    // EAX
    stepping_id: u4,
    model_id: u4,
    family_id: u4,
    processor_type: u2,
    reserved1: u2,
    extended_model_id: u4,
    extended_family_id: u8,
    reserved2: u4,
    // EBX
    brand_index: u8,
    cl_flush_line_size: u8,
    apic_io_space: u8,
    initial_apic_io: u8,
    // ECX
    sse3: bool,
    pclmulqdq: bool,
    dtes64: bool,
    monitor: bool,
    ds_cpl: bool,
    vmx: bool,
    smx: bool,
    eist: bool,
    tm2: bool,
    ssse3: bool,
    l1_context_id: bool,
    debug_interface: bool,
    fma: bool,
    cmpxchg16b: bool,
    xptr_update_control: bool,
    perf_capabilities: bool,
    reserved3: bool,
    pcid: bool,
    dca: bool,
    sse4_1: bool,
    sse4_2: bool,
    x2apic: bool,
    movbe: bool,
    popcnt: bool,
    tsc_deadline: bool,
    aesni: bool,
    xsave: bool,
    osxsave: bool,
    avx: bool,
    f16c: bool,
    rdbrand: bool,
    unused: bool,
    // EDX
    fpu: bool,
    vme: bool,
    de: bool,
    pse: bool,
    tsc: bool,
    msr: bool,
    pae: bool,
    mce: bool,
    cmpxchg8b: bool,
    apic: bool,
    reserved4: bool,
    sep: bool,
    mtrr: bool,
    pge: bool,
    mca: bool,
    cmov: bool,
    pat: bool,
    pse_36: bool,
    psn: bool,
    clflush: bool,
    reserved5: bool,
    ds: bool,
    acpi: bool,
    mmx: bool,
    fxsr: bool,
    sse: bool,
    sse2: bool,
    self_snoop: bool,
    htt: bool,
    tm: bool,
    reserved6: bool,
    pbe: bool,
};

/// Actual object initialized to describe the processor
pub var cpu_info: CPUInfo = undefined;

/// Maximum code value that can be passed to cpuid. Found when the vendor string is set
var max_leaf: usize = 0;
/// Tells us what vendor made the processor
pub var vendor_string: [12]u8 = [_]u8{ 'n', 'o', 't', ' ', 'k', 'n', 'o', 'w', 'n', '.', ' ', ' ' };

/// Thin cpuid wrapper, wrapped in other functions to further abstract this gnarly ass assembly lol
fn cpuid(code: u32) Regs {
    // Handle invalid codes
    if (!(max_leaf == 0 and code == 0) and code > max_leaf) {
        Console.print("cpuid: Code '{any}' is out of bounds for this processor\n", .{code});
        return Regs{ .eax = 0, .ebx = 0, .ecx = 0, .edx = 0 };
    }
    var eax: usize = 0;
    var ebx: usize = 0;
    var ecx: usize = 0;
    var edx: usize = 0;
    asm volatile (
        \\ cpuid
        \\ movl %%eax, %[eax]
        \\ movl %%ebx, %[ebx]
        \\ movl %%ecx, %[ecx]
        \\ movl %%edx, %[edx]
        : [eax] "=m" (eax),
          [ebx] "=m" (ebx),
          [ecx] "=m" (ecx),
          [edx] "=m" (edx),
        : [code] "{eax}" (code),
    );
    // NOTE: I need to look at the assmebly don't I
    Console.print("", .{}); // This is the only way to make this work. I have no idea why, probably compiler fuckery
    return Regs{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

/// Initialize the data structures in this file
pub fn init() void {
    vendor_string = getVendorString();
    cpu_info = getCpuInfo();
}

/// Get the vendor string and set the max leaf value
fn getVendorString() [12]u8 {
    const regs = cpuid(0);
    max_leaf = regs.eax;
    const string = [_]u32{ regs.ebx, regs.edx, regs.ecx };
    return @bitCast(string);
}

/// Leaf 01h. CPU version, family, model, feature info, etc.
fn getCpuInfo() CPUInfo {
    return @bitCast(cpuid(1));
}
