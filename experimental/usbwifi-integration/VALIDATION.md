# Validation of the integration candidate

The default upstream package is unchanged. The optional overlay is applied only
by prepare.py to the SHA-256 pinned official v1.7.4 package. The full installer
also requires the original user-supplied NX4 signed-mode input; that file and the
unused GRT reference binaries are not committed.

Local public-input host validation on 2026-11-21:

- 76 existing integration/regression tests passed (324.654 seconds), prepared
  only from the public official package and this overlay.
- Two additional build-input tests passed: an unpinned base is rejected, and a
  full installer cannot be generated when the NX4 signed mode is absent.
- 90 syntax checks passed: 30 active runtime shell files under bash/dash/ksh.
- The four lifecycle/log export tests were repeated after removing unreachable
  legacy controller branches; all four passed (10.173 seconds).
- GPL driver corresponding-source archives, patch/config/build files and module
  hashes in SOURCE.txt were checked, together with helper source/license notices.

The newly source-built ARM AX module has six compiled ff/ff/ff aliases, including
0bda:b831. Its 203 required global symbols exist in the collected G70 exports.
See AX-MODULE.json. This check does not establish full ABI compatibility. The
module was built from pinned source/config using AOSP gcc 4.7 with the original
EV6 kernel/USB patches and the six-ID source patch. Source files were compared
with the original archive plus all five patches after the build. Existing vendor
macro/initializer and old-compiler-option warnings remain; no warning-free build
is claimed. No private signing key was used or published.

The AP capability parser was checked under Linux/UBSan in the preceding private
build, and that test is part of this candidate's Linux CI. The ARM static helper
also returned an explicit unknown status under QEMU without an eligible radio.
These are parser/execution tests, not a vehicle AP capability measurement.

The complete integration, all AX adapters, G70 AX900mini, and the effect of RX
checksum changes on G70 screen freezes still need actual vehicle tests. The
G70 owner reported a responsive initial display with the earlier 0.4.0 bridge,
followed by frozen video/unresponsive controls while music continued. The owner
forced the disconnect to exit that screen. The later session termination is not
classified as spontaneous link loss. Neither the dongle's performance nor a
video/decoder/driver failure has been established as the cause.

CI for this candidate validates only public-input host behavior. It does not
sign or publish an installer, access a vehicle, or silently replace the missing
NX4 mode. A fork CI result and any upstream approval requirement are recorded
in the PR description separately.
