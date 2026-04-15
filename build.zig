//! You would not believe what I went through to make this

const std = @import("std");

// Gonna be real, zig build system is worse than makefiles almost purely because of how badly documented it is

/// Build the project
pub fn build(b: *std.Build) !void {
    const gdb = b.option(bool, "gdb", "Debug with GDB") orelse false;
    const log = b.option(bool, "log", "Enable Qemu logs") orelse false;
    const graphical = b.option(bool, "graphical", "Enable graphical Qemu output") orelse false;
    const emit_asm = b.option(bool, "asm", "Emit kernel.s") orelse false;
    //const mem = b.option(u32, "mem", "Define the number megabytes of memory available") orelse 1024;
    //const smp = b.option(u8, "smp", "Define the number of processors available") orelse 1;

    const optimize = b.standardOptimizeOption(.{});

    const Target = std.Target.x86;
    // 64 bit target used for the kernel
    const target_64 = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
        // We use software float because we are disabling all SIMD stuff
        .cpu_features_add = Target.featureSet(&.{.soft_float}),
        // Disable all SIMD related stuff because SIMD are problematic in kernel
        .cpu_features_sub = Target.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx }),
    });
    // 32 bit target used to the bootstrapping code
    const target_32 = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        // We use software float because we are disabling all SIMD stuff
        .cpu_features_add = Target.featureSet(&.{.soft_float}),
        // Disable all SIMD related stuff because SIMD are problematic in kernel
        .cpu_features_sub = Target.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx }),
    });

    // Main kernel code
    const kernel_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target_64,
        .optimize = optimize,
        .code_model = .kernel,
    });
    // Code I wrote when I wasn't planning for the kernel to be 64 bit. Still useful for the bootstrap
    const arch32 = b.createModule(.{
        .root_source_file = b.path("src/arch/x86_32/arch.zig"),
        .target = target_32,
        .optimize = optimize,
        .code_model = .kernel,
    });
    const multiboot_module = b.createModule(.{
        .root_source_file = b.path("src/multiboot.zig"),
        .target = target_32,
        .optimize = optimize,
        .code_model = .kernel,
    });
    // Bootstrap module itself, loaded by grub, enters 64 bit
    const bootstrap_module = b.createModule(.{
        .root_source_file = b.path("src/entry.zig"),
        .target = target_32,
        .optimize = optimize,
        .code_model = .kernel,
        .imports = &.{
            .{
                .name = "arch",
                .module = arch32,
            },
            .{
                .name = "multiboot",
                .module = multiboot_module,
            },
        },
    });
    // Final executable loaded by grub
    const exe_module = b.createModule(.{
        .target = target_64,
        .optimize = optimize,
        .code_model = .kernel,
    });
    // The bootstrap object needs to be converted to a 64 bit elf before the linker will allow 64 and 32
    // bit code. Idk why it doesn't like linking compiler generated stuff, it does assemly just fine
    const bootstrap = b.addObject(.{
        .name = "bs",
        .root_module = bootstrap_module,
    });
    // Cursed. bs_wf is an area in the zig cache for me to operate on the bin file
    const bs_wf = b.addNamedWriteFiles("bs");
    bs_wf.step.dependOn(&bootstrap.step);
    const bs_bin32 = bs_wf.addCopyFile(bootstrap.getEmittedBin(), "bs32.o");
    const bs_bin64 = bs_wf.getDirectory().path(b, "bs64.o");
    const bootstrap_64_cmd = b.addSystemCommand(&[_][]const u8{
        "objcopy", "-O", "elf64-x86-64",
    });
    bootstrap_64_cmd.addFileArg(bs_bin32);
    bootstrap_64_cmd.addFileArg(bs_bin64);
    bootstrap_64_cmd.step.dependOn(&bootstrap.step);
    const kernel = b.addObject(.{
        .name = "kernel",
        .root_module = kernel_module,
    });
    kernel.step.dependOn(&bootstrap_64_cmd.step);
    exe_module.addObjectFile(bs_bin64);
    exe_module.addObject(kernel);
    // Compile the final executable
    const exe = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = exe_module,
    });
    exe.step.dependOn(&kernel.step);
    // So I can double check compiler output is what I think it is if I need to
    // NOTE: Not working
    if (emit_asm) {
        const installAssembly = b.addInstallBinFile(exe.getEmittedAsm(), "kernel.s");
        b.getInstallStep().dependOn(&installAssembly.step);
    }
    // Install the elf
    exe.setLinkerScript(b.path("src/linker.ld"));
    b.installArtifact(exe);

    // Cache area to generate the kernel.iso. Qemu directly launches from here so the iso creation
    // is kind of vestigial
    const wf = b.addNamedWriteFiles("isodir");
    _ = wf.addCopyFile(kernel.getEmittedBin(), "boot/kernel.elf");
    _ = wf.addCopyFile(b.path("grub.cfg"), "boot/grub/grub.cfg");
    wf.step.dependOn(b.getInstallStep());
    const mk_iso_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        "grub-mkrescue", "-o", "kernel.iso", 
    });
    // zig fmt: on
    mk_iso_cmd.step.dependOn(&wf.step);
    mk_iso_cmd.addFileArg(wf.getDirectory());
    // Start qemu
    // TODO: Memory and smp options
    const qemu_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        "qemu-system-x86_64",
        "-m", "1G",
        "-smp", "1",
        "--no-reboot",
        "--no-shutdown",
        "-net", "none",
        "-drive", "if=pflash,format=raw,unit=0,file=./ovmf/OVMF_CODE.fd,readonly=on", // For acpi 2.0+
        "-drive", "if=pflash,format=raw,unit=1,file=./ovmf/OVMF_VARS.fd", // For acpi 2.0+
        "-cdrom", "kernel.iso",
    });
    // Add the actual iso directory with the kernel binary as a drive to qemu
    qemu_cmd.step.dependOn(&mk_iso_cmd.step);
    qemu_cmd.addArg("-drive");
    qemu_cmd.addPrefixedFileArg("format=raw,file=fat:rw:", wf.getDirectory());
    if (gdb) qemu_cmd.addArgs(&[_][]const u8 {"-S", "-s"});
    if (log) {
        qemu_cmd.addArgs(&[_][]const u8 {"-D", "./qemu.log", "-d", "int"});
    } else {
        qemu_cmd.addArgs(&[_][]const u8 {"--enable-kvm", "-cpu", "host"});
    }
    if (!graphical) qemu_cmd.addArgs(&[_][]const u8 {"-nographic"});
    // zig fmt: on
    //qemu_cmd.addArg("-kernel");
    //qemu_cmd.addFileArg(kernel_path);

    // How the user tells zig to run qem
    const run_step = b.step("run", "Run kernel with qemu");
    run_step.dependOn(&qemu_cmd.step);

    // Clean out the cache and output directories
    const rm_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        "rm",  "-rf", "kernel.iso", "zig-out", "*.log", ".zig-cache"
    });
    // zig fmt: on
    const clean_step = b.step("clean", "Remove artifacts");
    clean_step.dependOn(&rm_cmd.step);

    // Make sure everything is formatted well
    const fmt_step = b.step("fmt", "Check formatting");

    const fmt = b.addFmt(.{
        .paths = &.{
            "src/",
            "build.zig",
        },
        .check = true,
    });

    fmt_step.dependOn(&fmt.step);
    b.getInstallStep().dependOn(fmt_step);

    // Generate documentation
    const docs_step = b.step("docs", "Emit documentation");
    const docs_install = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .install_subdir = "docs",
        .source_dir = kernel.getEmittedDocs(),
    });
    docs_step.dependOn(&docs_install.step);
    b.getInstallStep().dependOn(docs_step);
}
