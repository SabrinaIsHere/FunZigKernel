//! You would not believe what I went through to make this

const std = @import("std");

// TODO: Bootable hd image for usb drive

// Gonna be real, zig build system is worse than makefiles almost purely because of how badly documented it is

/// https://codeberg.org/raddari/zig-nasm-lib/src/branch/main/build.zig
pub fn addNasm(b: *std.Build, compile: *std.Build.Step.Compile, file: std.Build.LazyPath, format: []const u8) void {
    const wf = b.addWriteFiles();
    const nasm = b.addSystemCommand(&.{"nasm"});
    nasm.addArg("-f");
    nasm.addArg(format);
    const out = wf.getDirectory().path(b, "asm.o");
    nasm.addArg("-o");
    nasm.addFileArg(out);
    nasm.addFileArg(file);
    compile.step.dependOn(&nasm.step);
    compile.addObjectFile(out);
}

/// Build the project
pub fn build(b: *std.Build) !void {
    const gdb = b.option(bool, "gdb", "Debug with GDB") orelse false;
    const log = b.option(bool, "log", "Enable Qemu logs") orelse false;
    const graphical = b.option(bool, "graphical", "Enable graphical Qemu output") orelse false;
    const shutdown = b.option(bool, "shutdown", "Allow/disallow qemu to shut down") orelse false;
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
    // Main kernel code
    const kernel_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target_64,
        .optimize = optimize,
        .code_model = .kernel,
    });
    // NOTE: Using a branch that works with zig 0.15.X, doesn't seem like the project is still
    // being maintained. Might fork it myself for stability and so I don't have to think about it
    const limine_zig = b.dependency("limine_zig", .{
        .api_revision = 3,
        .allow_deprecated = false,
        .no_pointers = false,
    });
    const limine_module = limine_zig.module("limine");
    kernel_module.addImport("limine", limine_module);
    kernel_module.red_zone = false;
    // Compile the final executable
    const exe = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = kernel_module,
        .use_llvm = true,
    });
    addNasm(b, exe, b.path("src/arch/x86_64/arch.S"), "elf64");
    exe.root_module.addAnonymousImport("console_font", .{ .root_source_file = b.path("fonts/koi8u_8x8.psfu") });
    b.getInstallStep().dependOn(&exe.step);
    // So I can double check compiler output is what I think it is if I need to
    if (emit_asm) {
        const installAssembly = b.addInstallBinFile(exe.getEmittedAsm(), "kernel.s");
        b.getInstallStep().dependOn(&installAssembly.step);
    }
    // Install the elf
    exe.setLinkerScript(b.path("src/linker.ld"));
    exe.entry = .{ .symbol_name = "kmain" };
    exe.linkage = .static;
    exe.link_z_max_page_size = 4096;
    b.installArtifact(exe);

    // Cache area to generate the kernel.iso
    const wf = b.addNamedWriteFiles("isodir");
    const isodir = wf.addCopyDirectory(b.path("iso-template"), "root", .{});
    _ = wf.addCopyFile(exe.getEmittedBin(), "root/boot/kernel.elf");
    wf.step.dependOn(b.getInstallStep());
    const mk_iso_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        "xorriso", "-as", "mkisofs", "-R", "-r", "-J", "-b", "boot/limine/limine-bios-cd.bin",
        "-no-emul-boot", "-boot-load-size", "4", "-boot-info-table", "-hfsplus",
        "-apm-block-size", "2048", "--efi-boot", "boot/limine/limine-uefi-cd.bin",
        "-efi-boot-part", "--efi-boot-image", "--protective-msdos-label",
        "-o", "kernel.iso"
    });
    // zig fmt: on
    mk_iso_cmd.step.dependOn(&wf.step);
    mk_iso_cmd.addFileArg(isodir);
    // Start qemu
    // TODO: Memory and smp options
    const qemu_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        "qemu-system-x86_64",
        "-m", "1G",
        "-smp", "1",
        "--no-reboot",
        "-net", "none",
        "-serial", "mon:stdio",
        //"-vga", "std",
        "-drive", "if=pflash,format=raw,unit=0,file=./ovmf/OVMF_CODE.fd,readonly=on", // For acpi 2.0+
        "-drive", "if=pflash,format=raw,unit=1,file=./ovmf/OVMF_VARS.fd", // For acpi 2.0+
        "-cdrom", "kernel.iso",
    });
    // Add the actual iso directory with the kernel binary as a drive to qemu
    qemu_cmd.step.dependOn(&mk_iso_cmd.step);
    qemu_cmd.addArg("-drive");
    qemu_cmd.addPrefixedFileArg("format=raw,file=fat:rw:", wf.getDirectory());
    if (gdb) qemu_cmd.addArgs(&[_][]const u8 {"-S", "-s"});
    if (!shutdown) qemu_cmd.addArg("--no-shutdown");
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
        .source_dir = exe.getEmittedDocs(),
    });
    docs_step.dependOn(&docs_install.step);
    b.getInstallStep().dependOn(docs_step);
}
