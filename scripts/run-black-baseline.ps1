param(
    [Parameter(Mandatory = $true)][string]$Qemu,
    [Parameter(Mandatory = $true)][string]$Assets,
    [int]$AdbPort = 5555,
    [int]$MonitorPort = 4444
)

$ErrorActionPreference = 'Stop'
$assetsDir = (Resolve-Path -LiteralPath $Assets).Path
$qemuExe = (Resolve-Path -LiteralPath $Qemu).Path
$required = @(
    'kernel-linux-7.3-rc4-4k',
    'kiki-kernel-ramdisk.img',
    'kiki-kernel-system-black-adb.img',
    'userdata-qemu-fresh.img',
    'misc.img'
)
foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $assetsDir $name))) {
        throw "Missing test asset: $name"
    }
}

$append = 'earlycon=pl011,0x09000000 console=ttyAMA0 loglevel=8 printk.devkmsg=on audit=0 androidboot.hardware=ranchu androidboot.hardwareegl=angle androidboot.hardware.egl=angle androidboot.hardware.gralloc=minigbm androidboot.hardware.hwcomposer=ranchu androidboot.hardware.vulkan=pastel androidboot.hardware.hwcomposer.mode=client androidboot.hardware.hwcomposer.display_finder_mode=drm androidboot.hardware.guest_hwui_renderer=gles androidboot.debug.renderengine.backend=skiaglthreaded androidboot.selinux=permissive enforcing=0 androidboot.force_normal_boot=1 androidboot.verifiedbootstate=orange androidboot.init_fatal_reboot_target=none binder.devices=binder,hwbinder,vndbinder'
$serialLog = Join-Path $assetsDir 'qemu-kikiaosp-black.log'
$stderrLog = Join-Path $assetsDir 'qemu-kikiaosp-black.err'
$args = @(
    '-M','virt','-accel','whpx','-cpu','host','-m','4096','-smp','4',
    '-kernel',(Join-Path $assetsDir 'kernel-linux-7.3-rc4-4k'),
    '-initrd',(Join-Path $assetsDir 'kiki-kernel-ramdisk.img'),
    '-append',('"' + $append + '"'),
    '-drive',("if=none,file=$(Join-Path $assetsDir 'kiki-kernel-system-black-adb.img'),format=raw,readonly=on,id=system"),
    '-device','virtio-blk-pci,drive=system',
    '-drive',("if=none,file=$(Join-Path $assetsDir 'userdata-qemu-fresh.img'),format=raw,id=userdata"),
    '-device','virtio-blk-pci,drive=userdata',
    '-drive',("if=none,file=$(Join-Path $assetsDir 'misc.img'),format=raw,id=misc"),
    '-device','virtio-blk-pci,drive=misc',
    '-netdev',"user,id=net0,hostfwd=tcp:127.0.0.1:${AdbPort}-:5555",
    '-device','virtio-net-pci,netdev=net0',
    '-device','virtio-gpu-pci,hostmem=256M,xres=1080,yres=2400',
    '-display','gtk,gl=off',
    '-monitor',"tcp:127.0.0.1:${MonitorPort},server,nowait",
    '-serial',("file:$serialLog"),'-snapshot'
)
$process = Start-Process -FilePath $qemuExe -ArgumentList $args -WindowStyle Hidden -RedirectStandardError $stderrLog -PassThru
"QEMU PID=$($process.Id)"
"Serial log: $serialLog"
"ADB: adb connect 127.0.0.1:${AdbPort}"
