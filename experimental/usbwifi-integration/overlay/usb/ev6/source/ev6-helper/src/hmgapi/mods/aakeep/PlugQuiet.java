package hmgapi.mods.aakeep;

import java.io.File;
import java.io.FileOutputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

import hmgapi.hook.Hooks;
import hmgapi.hook.MethodHook;
import hmgapi.hook.ModContext;

/**
 * 1.2.0: the two notices the car shows when the USB Wi-Fi dongle is plugged in, found in the car log
 * (EV6_CONNLOG 3, 2026-11-14 18:15, collector 1.4 "동글 꽂을 때 알림" list) and hidden for the dongle only.
 *
 *  1 "USB 케이블로 연결된 기기는 충전 모드만 지원됩니다."  0.7 s after the plug-in, for about 5 s.
 *    Stock GPM (GalReceiverService.onStartCommand, USB attach, mode 1) reads the device's serial with
 *    getMDUsbSerialNumber(device), finds it isn't an Android Auto phone and calls sendToOsdMessage(1, 32) = this OSD.
 *    Hidden: in GPM's process, sendToOsdMessage(1, 32) is skipped when the device just read on the same thread
 *    (under 3 s) is a dongle. Stock carries on exactly as after the OSD (same branch, same next call).
 *
 *  2 "지원하지 않는 미디어 기기입니다."  30 s after the plug-in, for about 5 s (also over a running AA screen).
 *    system_server's UsbHostManager.postUnsupportedUsb(name, device) skips any device its whitelist
 *    isWhiteListedByDevice(device) accepts; otherwise it posts the 30 s "unsupported USB" timer, whose broadcast
 *    INSERTED_UNSUPPORT_USB makes SystemUI's StorageNotification show this notice.
 *    Hidden: isWhiteListedByDevice answers true for a dongle, so the timer is never posted. services.jar is on this
 *    car's BOOTCLASSPATH, so the hook is put in from zygote (zygoteInit) and is there in system_server.
 *
 * "Dongle" = a USB id the dongle driver (88x2bu, modules/88x2bu.ko) takes: 17 ids, the same table. Every other USB
 * device (phones, sticks, other Wi-Fi) is untouched. Any error: the hook lets the stock call through (the notice
 * shows, nothing else changes). Setting hide_plug_notices (default on).
 * Log: logcat HMG-API "[ev6-kr-aa-keep] plug notice ..." and /data/local/tmp/usbwifi_hotspot/plugquiet.log.
 */
final class PlugQuiet {
    static final String LOG = "/data/local/tmp/usbwifi_hotspot/plugquiet.log";
    /** vendor:product of 88x2bu.ko's alias table (strings modules/88x2bu.ko | grep alias=usb) */
    static final int[] IDS = {
            0x0846, 0x9055, 0x0B05, 0x1841, 0x0B05, 0x184C, 0x0BDA, 0xB812, 0x0BDA, 0xB82C, 0x13B1, 0x0043,
            0x13B1, 0x0045, 0x2001, 0x331C, 0x2001, 0x331E, 0x2001, 0x331F, 0x20F4, 0x808A, 0x2357, 0x0115,
            0x2357, 0x012D, 0x2357, 0x012E, 0x2357, 0x0138, 0x7392, 0xB822, 0x7392, 0xC822 };
    static final int OSD_ON_USB = 1, OSD_CHARGING_ONLY = 32;
    static final long SAME_PLUG_MS = 3000;

    private PlugQuiet() {
    }

    static boolean isDongle(int vid, int pid) {
        for (int i = 0; i + 1 < IDS.length; i += 2) if (IDS[i] == vid && IDS[i + 1] == pid) return true;
        return false;
    }

    static String id(int vid, int pid) {
        return hex4(vid) + ":" + hex4(pid);
    }

    static String hex4(int v) {
        String s = Integer.toHexString(v & 0xffff);
        while (s.length() < 4) s = "0" + s;
        return s;
    }

    // ---- notice 1 (GPM): which device the current USB attach is about, per thread
    static final class Seen {
        long at = -1;
        boolean dongle;
        String id = "";
    }

    static final ThreadLocal<Seen> SEEN = new ThreadLocal<Seen>() {
        @Override
        protected Seen initialValue() {
            return new Seen();
        }
    };

    /** the decision for sendToOsdMessage(type, what), kept free of Android so it is tested on the Mac */
    static boolean hideOsd(int type, int what, Seen s, long now) {
        return type == OSD_ON_USB && what == OSD_CHARGING_ONLY && s != null && s.dongle && s.at >= 0 && now - s.at <= SAME_PLUG_MS;
    }

    static void gpm(final ModContext mod, ClassLoader cl) {
        if (!mod.settingBoolean("hide_plug_notices", true)) {
            note(mod, "plug notice 1 (charging only): off in the settings");
            return;
        }
        Class<?> sc, ud;
        try {
            sc = Class.forName("com.google.android.projection.service.GalReceiverService", false, cl);
            ud = Class.forName("android.hardware.usb.UsbDevice");
        } catch (Throwable t) {
            note(mod, "plug notice 1: stock GPM class missing (" + t + "): not hidden");
            return;
        }
        try {
            Hooks.findAndHookMethod(sc, "getMDUsbSerialNumber", ud, new MethodHook() {
                @Override
                protected void beforeHookedMethod(Param p) {
                    try {
                        Seen s = SEEN.get();
                        s.at = now();
                        s.dongle = false;
                        s.id = "";
                        Object d = p.args[0];
                        if (d == null) return;
                        int vid = (Integer) d.getClass().getMethod("getVendorId").invoke(d);
                        int pid = (Integer) d.getClass().getMethod("getProductId").invoke(d);
                        s.id = id(vid, pid);
                        s.dongle = isDongle(vid, pid);
                    } catch (Throwable ignored) {
                        // fail open
                    }
                }
            });
            Hooks.findAndHookMethod(sc, "sendToOsdMessage", int.class, int.class, new MethodHook() {
                @Override
                protected void beforeHookedMethod(Param p) {
                    try {
                        Seen s = SEEN.get();
                        if (hideOsd((Integer) p.args[0], (Integer) p.args[1], s, now())) {
                            p.setResult(null);
                            s.dongle = false;          // once per attach
                            note(mod, "plug notice 1 hidden: \"charging only\" OSD for the dongle " + s.id);
                        }
                    } catch (Throwable ignored) {
                        // fail open: the stock OSD shows
                    }
                }
            });
            note(mod, "plug notice 1 (charging only): hooked in GPM");
        } catch (Throwable t) {
            mod.error("plug notice 1: hook failed, not hidden", t);
            note(mod, "plug notice 1: hook failed (" + t + "): not hidden");
        }
    }

    // ---- notice 2 (system_server, put in from zygote)
    static void zygote(final ModContext mod) {
        if (!mod.settingBoolean("hide_plug_notices", true)) return;
        try {
            Class<?> hm = Class.forName("com.android.server.usb.UsbHostManager");
            Class<?> ud = Class.forName("android.hardware.usb.UsbDevice");
            Hooks.findAndHookMethod(hm, "isWhiteListedByDevice", ud, new MethodHook() {
                @Override
                protected void afterHookedMethod(Param p) {
                    try {
                        if (Boolean.TRUE.equals(p.getResult())) return;
                        Object d = p.args[0];
                        if (d == null) return;
                        int vid = (Integer) d.getClass().getMethod("getVendorId").invoke(d);
                        int pid = (Integer) d.getClass().getMethod("getProductId").invoke(d);
                        if (!isDongle(vid, pid)) return;
                        p.setResult(Boolean.TRUE);
                        note(mod, "plug notice 2 hidden: no \"unsupported USB\" timer for the dongle " + id(vid, pid));
                    } catch (Throwable ignored) {
                        // fail open: stock answer kept, the notice shows
                    }
                }
            });
            mod.log("plug notice 2 (unsupported USB): hooked UsbHostManager.isWhiteListedByDevice (zygote, for system_server)");
        } catch (Throwable t) {
            mod.error("plug notice 2: hook failed, not hidden", t);
        }
    }

    static long now() {
        try {
            return (Long) Class.forName("android.os.SystemClock").getMethod("elapsedRealtime").invoke(null);
        } catch (Throwable t) {
            return System.nanoTime() / 1000000L;
        }
    }

    /** logcat (HMG-API) and the plug-in log file, which the dongle daemon copies to the USB stick */
    static void note(ModContext mod, String s) {
        try {
            mod.log(s);
        } catch (Throwable ignored) {
        }
        File f = new File(LOG);
        if (!f.getParentFile().isDirectory()) return;
        try {
            if (f.length() > 64 * 1024) f.renameTo(new File(LOG + ".old"));
            FileOutputStream o = new FileOutputStream(f, true);
            try {
                String t = new SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(new Date());
                o.write((t + " pid " + android_pid() + " " + s + "\n").getBytes("UTF-8"));
            } finally {
                o.close();
            }
            f.setReadable(true, false);
            f.setWritable(true, false);                // GPM and system_server both append
        } catch (Throwable ignored) {
        }
    }

    static int android_pid() {
        try {
            return (Integer) Class.forName("android.os.Process").getMethod("myPid").invoke(null);
        } catch (Throwable t) {
            return -1;
        }
    }
}
