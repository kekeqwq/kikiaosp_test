# 0.3 Alpha audio fix candidate

This is a system-only change. Keep the tested KikiEmu 0.2 setup and its 0.2
five-patch QEMU. No host volume/default-device/driver or global ADB changes.
Create a NEW instance from the candidate ZIP; existing disks do not upgrade
in place. No user data or development disks are imported into this package.

## Cause and policy

The pinned Android 17 primary HAL has two lossy emulator mechanisms:

1. `StreamPrimary::transfer` can skip entire buffers to repay its independent
   uptime-based pacing debt while still reporting the frames consumed.
2. `StreamAlsaMonoPipe` uses a non-blocking writer and drops a whole/partial
   burst when its ring is full, also reporting the full frame count consumed.

Independent generated short-clip tests showed both messages, including many
4096-frame drops. App completion, advancing playback heads and zero app
underruns did not prove host output. Windows process-only loopback and packet
QPC evidence were collected separately from the Android logs.

The device enables `ro.vendor.audio.kiki.synchronous_pcm=true`. For this
product's primary OUTPUT only, actual ALSA writes pace the stream; no fake
clock-debt skip or non-blocking MonoPipe drop. Other/stub/input paths retain
the upstream behavior. This is not a change to volumes or buffer tuning.

## Transient error recovery

The pinned tinyalsa `pcm_write` returns `-1` (not `-errno`) for ioctl errors.
An initial-write XRUN can leave its cached `prepared` bit true. Retrying
`proxy_write_with_retries` alone is insufficient: that wrapper only retries
`-EIO`/`-EAGAIN`. Immediately propagating such a transient error can poison the
persistent AIDL stream as ERROR, after which it rejects further bursts.

The Kiki path snapshots errno and the PCM diagnostic. EPIPE/EIO/EAGAIN/ESTRPIPE
can close/reopen this one PCM and retry the current burst, at most twice. It
never restarts Android, audioserver or the HAL as a shipping recovery policy.
Unrecoverable failures still report an error, not fabricated success.

A preliminary private prototype without this recovery became stuck in ERROR
in a long test and was REJECTED. Its passing playback callbacks are not an
acceptance claim. Only the complete patched system ZIP and subsequent clean
boot/reboot regression qualify as delivery evidence.

## Verification boundaries

Test app source is in the KikiEmu audio-stress tools: MediaPlayer, six-rate
mono/stereo static AudioTrack, preloaded SoundPool and continuous streaming
AudioTrack, short bursts, repeated standby boundaries and a final 2-second
reference. The reference also rejects implausibly instantaneous head progress.

- Formal user's instance is read-only throughout this investigation.
- Runtime bind-mounted HAL experiments were confined to an owned fixture;
  they are not package-validation or physical speaker audibility proof.
- Calibrate known successful clips before/after a long run in ONE process
  loopback capture. Account for QPC packet gaps; a concatenated WAV's phase-fit
  residual or elapsed length alone is not distortion evidence.
- Do not mistake an app-only completion or one silent capture for reproduction
  of a permanent failure that can only be cleared by a VM restart.
- Final package status, bytes/hashes, source commits and per-run results are
  recorded in the build audit/provenance and independent regression logs.

The kernel stays Linux 7.3.0-rc5-4k. The format-1 contract and user-created
immutable disk capacities are unchanged. Build is an audited incremental
release-only Btrfs clone, not a build from an empty output directory.
