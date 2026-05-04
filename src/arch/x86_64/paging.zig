const arch = @import("arch.zig");
const Console = arch.Console;
const print = Console.print;
const kallocator = @import("../../memory/kallocator.zig");
const main = @import("../../main.zig");

// TODO: Parse and copy limine paging structure

const PagingError = error{
    InvalidPhysicalAddress,
};

/// References a PDPT
/// Handles mapping logic
pub const PML4E = packed struct(u64) {
    present: bool = true,
    rw: bool = true,
    us: u1 = 1,
    pwt: u1 = 0,
    pcd: u1 = 0,
    accessed: bool = false,
    reserved1: u6 = 0,
    addr: u40 = 0,
    reserved2: u11 = 0,
    xd: u1 = 0,

    /// Sets present bit and initializes data
    /// If there is no PDPT, set address to 0
    pub fn init(self: *PML4E, addr: usize, rw: bool, pwt: u1, pcd: u1) void {
        self.present = true;
        self.rw = rw;
        self.pwt = pwt;
        self.pcd = pcd;
        self.addr = @truncate(addr);
    }

    /// Gets a PTE, allocating space for it if need be. The runtime overhead on this is... not great
    /// I hate this function
    /// BUG: Running out of memory
    pub fn getPTE(self: *PML4E, virt_addr: usize) kallocator.MemError!*PTE {
        const pdptindex: u9 = @truncate(virt_addr >> 30);
        const pdindex: u9 = @truncate(virt_addr >> 21);
        const ptindex: u9 = @truncate(virt_addr >> 12);
        var pdpt: *[512]PDPTE = undefined;
        if (self.addr == 0) {
            pdpt = @ptrCast(try kallocator.get(PDPTE, 512, 4096));
            pdpt[pdptindex].init(0, 1, 1);
            self.addr = @truncate(arch.virtualToPhysical(@intFromPtr(pdpt)) >> 12);
        } else {
            pdpt = @ptrFromInt(arch.physicalToVirtual(self.addr << 12));
        }
        var pd: *[512]PDE = undefined;
        if (pdpt[pdptindex].addr == 0) {
            pd = @ptrCast(try kallocator.get(PDE, 512, 4096));
            pd[pdindex].init(0, true, 1, 1);
            // NOTE: arch.virtualToPhysical may not work forever
            pdpt[pdptindex].addr = @truncate(arch.virtualToPhysical(@intFromPtr(pd)) >> 12);
        } else {
            pd = @ptrFromInt(arch.physicalToVirtual(pdpt[pdptindex].addr << 12));
        }
        var pt: *[512]PTE = undefined;
        if (pd[pdindex].addr == 0) {
            pt = @ptrCast(try kallocator.get(PTE, 512, 4096));
        } else {
            pt = @ptrFromInt(arch.physicalToVirtual(pd[pdindex].addr << 12));
        }
        return &pt[ptindex];
    }

    /// Get a physical address from a virtual
    pub fn v2p(self: *PML4E, virt_addr: usize) usize {
        const pte = self.getPTE(virt_addr);
        const offset: u12 = virt_addr & 0xFFF;
        return pte.addr + offset;
    }

    /// Translates a physical addres to a virtual
    pub fn p2v(self: *PML4E, phys_addr: usize) usize {
        _ = self;
        _ = phys_addr;
        return 0;
    }

    /// Map a virtual address to a physical address
    pub fn map(self: *PML4E, phys_addr: usize, virt_addr: usize) kallocator.MemError!void {
        // TODO: Flush tlb
        const pte: *PTE = try self.getPTE(virt_addr);
        pte.init(phys_addr, true, 1, 1, true);
    }

    /// Decouple a physical and virtual address
    pub fn unmap(self: *PML4E, virt_addr: usize) void {
        const pte: *PTE = self.getPTE(virt_addr);
        pte.present = false;
    }
};

/// References a page directory
const PDPTE = packed struct(u64) {
    present: bool = false,
    rw: bool = true,
    us: bool = true,
    pwt: u1 = 0,
    pcd: u1 = 0,
    accessed: bool = false,
    reserved: u6 = 0,
    addr: u40 = 0,
    reserved2: u11 = 0,
    xd: bool = false,

    pub fn init(self: *PDPTE, addr: usize, pwt: u1, pcd: u1) void {
        self.present = true;
        self.pwt = pwt;
        self.pcd = pcd;
        self.addr = @truncate(addr);
    }
};

/// References a page table
const PDE = packed struct(u64) {
    present: bool = false,
    rw: bool = false,
    us: u1 = 0,
    pwt: u1 = 0,
    pcd: u1 = 0,
    accessed: bool = false,
    ignored1: u1 = 0,
    ps: u1 = 0,
    ignored2: u4 = 0,
    addr: u40 = 0,
    reserved: u11 = 0,
    xd: bool = false,

    pub fn init(
        self: *PDE,
        addr: usize,
        rw: bool,
        pwt: u1,
        pcd: u1,
    ) void {
        self.present = true;
        self.addr = @truncate(addr);
        self.rw = rw;
        self.pwt = pwt;
        self.pcd = pcd;
    }
};

/// Defines a 4 KiB page
const PTE = packed struct(u64) {
    present: bool = false,
    rw: bool = false,
    us: u1 = 0,
    pwt: u1 = 0,
    pcd: u1 = 0,
    accessed: bool = false,
    dirty: bool = false,
    pat: u1 = 0,
    global: bool = false,
    ignored1: u3 = 0,
    addr: u40 = 0,
    reserved: u11 = 0,
    xd: bool = false,

    pub fn init(
        self: *PTE,
        addr: usize,
        rw: bool,
        pwt: u1,
        pcd: u1,
        global: bool,
    ) void {
        self.present = true;
        self.rw = rw;
        self.pwt = pwt;
        self.pcd = pcd;
        self.global = global;
        self.addr = @truncate(addr);
    }
};

/// Pointer to paging structures setup by limine. Virtual address
var pml4: *PML4E = undefined;

// TODO: When there's a functional allocator this should stop being static

/// Initialize and enable paging
/// Maps the first 2 MiB
pub fn init() void {
    defer Console.print("Paging enabled\n", .{});
    pml4 = allocatePageTable() catch |err| {
        print("Page table allocation error: {any}\n", .{err});
        arch.wait();
        unreachable;
    };
    // Identity map system memory with hhdm offset (excepting first 1MB)
    const attempted_allocations = (kallocator.total_phys_memory / 4096) - (1000000 / 4096);
    Console.print("Attempted page allocations: {any}\n", .{attempted_allocations});
    Console.print("Total memory - Page memory: {any}\n", .{kallocator.total_phys_memory - attempted_allocations * 64});
    for (1000000 / 4096..kallocator.total_phys_memory / 4096) |i| {
        map(i * 4096, arch.hhdm_offset + (i * 4096));
    }
    arch.setPML4(pml4);
}

/// Runs a couple tests to make sure everything is in order before we attempt to load cr4
/// Only for use when debugging
fn runtimeTests() PagingError!void {
    // Check that the physical address is translating
    // NOTE: This isn't doing anything, figure out how to verify a physical address
    const pml4_physical: usize = arch.virtualToPhysical(@intFromPtr(&pml4[0]));
    Console.print("PML4 Physical: 0x{X}\n", .{pml4_physical});
    const pml4_virtual: usize = arch.physicalToVirtual(pml4_physical);
    Console.print("PML4 Virtual: 0x{X}\n", .{pml4_virtual});
    if (pml4_virtual != @intFromPtr(&pml4[0])) return PagingError.InvalidPhysicalAddress;
}

/// Allocates a new pml4 which will allocate space for page structures as needed
pub fn allocatePageTable() kallocator.MemError!*PML4E {
    const retval: *PML4E = @ptrCast(try kallocator.get(PML4E, 1, 4096));
    retval.init(0, true, 1, 1);
    return retval;
}

pub fn map(phys: usize, virt: usize) void {
    pml4.map(phys, virt) catch |err| {
        Console.print("{any}\n", .{err});
        Console.print("Attempted allocations: {any}\n", .{kallocator.allocation_attempts});
        kallocator.printMmap();
        @panic("Page allocation error");
    };
}

pub fn unmap(virt: usize) void {
    pml4.unmap(virt);
}
