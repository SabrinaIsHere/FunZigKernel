#mkdir -p isodir/boot/grub
#cp zig-out/bin/kernel.elf isodir/boot/kernel.elf
#cp grub.cfg isodir/boot/grub/grub.cfg
#grub-mkrescue -o kernel.iso isodir

dd if=/dev/zero of=disk.img bs=1M count=128
