//! https://wiki.osdev.org/Interrupt_Descriptor_Table

/// Defines an entry in the interrupt descriptor table
/// Always 8 bytes long
const IDTEntry = packed struct {
    /// Procedure entry
    offset_lower: u16,
    /// GDT segment
    segment: u16,
    /// Hardware reserved
    reserved: u5,
    /// Reserved in task gate, otherwise all zeroes
    zero: u3,
    /// Gate type field. Also defines if the gate is 32 bit or 16 bit.
    d: u5,
    /// Descriptor privilege level
    dpl: u2,
    /// Segment present
    p: u1,
    // Procedure entry
    offset_higher: u16,

    pub fn defineTaskGate(self: *IDTEntry, tss_segment: u16, dpl: u2, p: u1) void {
        self.segment = tss_segment;
        self.d = 0b00101;
        self.dpl = dpl;
        self.p = p;
    }
    pub fn defineTrapGate(self: *IDTEntry, offset: u32, segment: u16, is32Bit: u1, dpl: u2, p: u1) void {
        self.offset_lower = @truncate(offset);
        self.offset_lower = @truncate(offset and 0xFFFF);
        self.segment = segment;
        self.zero = 0;
        self.d = 0b00111 or (is32Bit << 3);
        self.dpl = dpl;
        self.p = p;
    }
    pub fn defineInterruptGate(self: *IDTEntry, offset: u32, segment: u16, is32Bit: u1, dpl: u2, p: u1) void {
        self.offset_lower = @truncate(offset);
        self.offset_lower = @truncate(offset and 0xFFFF);
        self.segment = segment;
        self.zero = 0;
        self.d = 0b00110 or (is32Bit << 3);
        self.dpl = dpl;
        self.p = p;
    }
};

var IDT: [256]IDTEntry = undefined;

/// Memory pointed to by the LIDT instruction that defines the IDT for the processor
const IDTDescriptor = packed struct {
    /// Size, in bytes, of the IDT
    size: u16,
    /// Linear address of the IDT (paging applies)
    offset: u32,
};

fn unhandledException(exception: u8) void {
    _ = exception;
}

pub fn init() void {}
