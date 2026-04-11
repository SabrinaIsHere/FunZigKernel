//! Since at some point I'd like to target an architecture beyond IA-32, this provides a unified interface to call into
//! architecture stuff and which code is actually compiled can be controlled at compile time depending on the target

pub const arch = @import("x86_32/arch.zig");

/// Initialize the target architecture
pub fn init() void {
    arch.init();
}
