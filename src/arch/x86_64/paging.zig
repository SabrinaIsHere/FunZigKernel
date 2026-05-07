//! Deals with paging
//! When I'm less sick of looking at this file I should circle back and clean it up a little it's pretty gnarly
//! I should really reevalute the ****.addr = 0 thing

const arch = @import("arch.zig");
const Console = arch.Console;
const print = Console.print;
const kallocator = @import("../../memory/kallocator.zig");
const main = @import("../../main.zig");

const PagingError = error{
    UnmappedAddress,
    InvalidPhysicalAddress,
    InvalidAddressTranslation,
};

/// References a PDPT
/// Handles mapping logic
pub const PML4E = packed struct(u64) {
    present: bool = false,
    rw: bool = false,
    us: u1 = 0,
    pwt: u1 = 0,
    pcd: u1 = 0,
    accessed: bool = false,
    reserved1: u6 = 0,
    addr: u40 = 0,
    reserved2: u11 = 0,
    xd: bool = false,

    /// Sets present bit and initializes data
    /// If there is no PDPT, set address to 0
    pub fn init(self: *PML4E, addr: usize, rw: bool, pwt: u1, pcd: u1) void {
        self.present = true;
        self.rw = rw;
        self.pwt = pwt;
        self.pcd = pcd;
        self.addr = @truncate(addr);
        self.xd = true;
    }

    /// Copy the mappings from another pml4e. Quiet fails
    /// I really hate this function lol
    pub fn copyMappings(self: *PML4E, copied: *PML4E) !void {
        // It'd be nice to do this with @memcpy but then I'd have to handle allocation logic here and I had
        // a hard enough time with getPTE
        if (!copied.present) return;
        // Get pdpt
        const pdpt: *[512]PDPTE = @ptrFromInt(arch.physicalToVirtual(copied.addr << 12));
        // Iterate through it
        for (0..512) |i| {
            // Skip if not present
            if (!pdpt[i].present) continue;
            // Get page directory
            const pd: *[512]PDE = @ptrFromInt(arch.physicalToVirtual(pdpt[i].addr << 12));
            // Iterate page directory
            for (0..512) |j| {
                // Skip if not present
                if (!pd[j].present) continue;
                // Handle 2 MB pages
                if (pd[j].ps == 1) {
                    for (0..512) |k| {
                        const pte = try self.getPTE(i << 30 | j << 21 | k << 12);
                        pte.init(pd[j].addr + (k * 4096), pd[j].rw, pd[j].pwt, pd[j].pcd, false);
                        pte.us = pd[j].us;
                        pte.xd = pd[j].xd;
                    }
                    continue;
                }
                // Handle page tables
                const pt: *[512]PTE = @ptrFromInt(arch.physicalToVirtual(pd[j].addr << 12));
                for (0..512) |k| {
                    if (!pt[k].present) continue;
                    const pte = try self.getPTE(i << 30 | j << 21 | k << 12);
                    pte.init(pt[k].addr, pt[k].rw, pt[k].pwt, pt[k].pcd, pt[k].global);
                    pte.us = pt[k].us;
                    pte.xd = pt[k].xd;
                }
            }
        }
    }

    /// Gets a PTE, allocating space for it if need be. The runtime overhead on this is... not great
    /// I hate this function
    pub fn getPTE(self: *PML4E, virt_addr: usize) kallocator.MemError!*PTE {
        const pdptindex: u9 = @truncate(virt_addr >> 30);
        const pdindex: u9 = @truncate(virt_addr >> 21);
        const ptindex: u9 = @truncate(virt_addr >> 12);
        var pdpt: *[512]PDPTE = undefined;
        if (!self.present) {
            pdpt = @ptrCast(try kallocator.get(PDPTE, 512, 4096));
            self.init(arch.virtualToPhysical(@intFromPtr(pdpt)) >> 12, true, 0, 0);
        } else {
            pdpt = @ptrFromInt(arch.physicalToVirtual(self.addr << 12));
        }
        var pd: *[512]PDE = undefined;
        if (!pdpt[pdptindex].present) {
            pd = @ptrCast(try kallocator.get(PDE, 512, 4096));
            pdpt[pdptindex].init(arch.virtualToPhysical(@intFromPtr(pd)) >> 12, 0, 0);
        } else {
            pd = @ptrFromInt(arch.physicalToVirtual(pdpt[pdptindex].addr << 12));
        }
        var pt: *[512]PTE = undefined;
        if (!pd[pdindex].present) {
            pt = @ptrCast(try kallocator.get(PTE, 512, 4096));
            pd[pdindex].init(arch.virtualToPhysical(@intFromPtr(pt)) >> 12, true, 0, 0);
        } else {
            pt = @ptrFromInt(arch.physicalToVirtual(pd[pdindex].addr << 12));
        }
        return &pt[ptindex];
    }

    /// Get a physical address from a virtual
    pub fn v2p(self: *PML4E, virt_addr: usize) PagingError!usize {
        const pte = self.getPTE(virt_addr) catch return PagingError.UnmappedAddress;
        const offset: u12 = @truncate(virt_addr);
        return (pte.addr << 12) + offset;
    }

    /// Translates a physical addres to a virtual
    pub fn p2v(self: *PML4E, phys_addr: usize) usize {
        _ = self;
        _ = phys_addr;
        print("Don't call p2v!\n", .{});
        return 0;
    }

    /// Map a virtual address to a physical address
    pub fn map(self: *PML4E, phys_addr: usize, virt_addr: usize) kallocator.MemError!void {
        // TODO: Flush tlb
        const pte: *PTE = try self.getPTE(virt_addr);
        pte.init(phys_addr >> 12, true, 0, 0, false);
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
        self.xd = true;
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
        self.xd = true;
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
        self.xd = true;
    }
};

/// Pointer to PML4 loaded by cpu
var pml4: *[512]PML4E = undefined;

/// Initialize and enable paging
/// Identity maps first 1 MB, then the rest of system memory is identity mapped with the hhdm offset
pub fn init() void {
    defer Console.print("Paging enabled\n", .{});
    pml4 = @ptrCast(arch.getPML4());
    pml4 = allocatePageTable() catch @panic("Insufficient memory to allocate page tables");

    const num_pages = kallocator.total_phys_memory >> 12;
    print("Pages: {any}\n", .{num_pages});

    //for (0..num_pages) |i| {
    //    map(i << 12, arch.physicalToVirtual(i << 12));
    //}

    print("pml4: 0x{X}\n", .{@intFromPtr(pml4)});

    runtimeTests() catch |err| {
        print("{any}\n", .{err});
        @panic("paging: Runtime tests failed");
    };
    arch.setPML4(&pml4[0]);
}

/// Runs a couple tests to make sure everything is in order before we attempt to load cr4
/// Only for use when debugging
fn runtimeTests() PagingError!void {
    const test_addr: usize = arch.physicalToVirtual(try v2p(@intFromPtr(pml4)));
    if (@intFromPtr(pml4) != test_addr) {
        print("Actual vs. Translated: 0x{X}, 0x{X}\n", .{ @intFromPtr(pml4), test_addr });
        return PagingError.InvalidAddressTranslation;
    }
}

/// Allocates a new pml4 table which will allocate space for page structures as needed
fn allocatePageTable() kallocator.MemError!*[512]PML4E {
    const retval: *[512]PML4E = @ptrCast(try kallocator.get(PML4E, 512, 4096));
    for (0..512) |i| try retval[i].copyMappings(&pml4[i]);
    return retval;
}

/// Allocates a new pml4 table meant for userspace which will allocate space for page structures as needed
fn allocateUserPageTable() kallocator.MemError!*[512]PML4E {
    const retval: *[512]PML4E = @ptrCast(try kallocator.get(PML4E, 512, 4096));
    for (256..512) |i| try retval[i].copyMappings(&pml4[i]);
    return retval;
}

fn getPML4Index(virt: usize) u9 {
    return @truncate(virt >> 39);
}

// This is kind of screwy because I'm dumb and misunderstood something early on, I don't love how the logic
// splits across functions like this

pub fn map(phys: usize, virt: usize) void {
    const pml4e = &pml4[getPML4Index(virt)];
    pml4e.map(phys, virt) catch |err| {
        Console.print("{any}\n", .{err});
        kallocator.printMmap();
        @panic("Page allocation error");
    };
}

pub fn unmap(virt: usize) void {
    const pml4e = &pml4[getPML4Index(virt)];
    pml4e.unmap(virt);
}

pub fn v2p(virt: usize) PagingError!usize {
    const pml4e = &pml4[getPML4Index(virt)];
    if (!pml4e.present) return PagingError.UnmappedAddress;
    return pml4e.v2p(virt);
}
