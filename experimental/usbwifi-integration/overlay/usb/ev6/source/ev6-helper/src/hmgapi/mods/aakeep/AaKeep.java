package hmgapi.mods.aakeep;

import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;
import java.util.Locale;

import hmgapi.hook.LoadedApp;
import hmgapi.hook.ModContext;
import hmgapi.hook.ModEntry;

/**
 * EV6 KR: keep wireless Android Auto connecting (CVEV.KOR 260902, stock HKMC_GPM).
 *
 * Stock GPM (WirelessExplorer.sendStartRequestMessage) asks the phone to join the
 * head unit's Wi-Fi only if the access point is on at that moment. With the USB
 * dongle the access point comes up some seconds after start, so when the phone's
 * Bluetooth connects first the request is dropped (log "isWifiApEnable = false !!!")
 * and never retried; the same happens to stock's own reconnect (MSG_WIFI_RECONNECT)
 * when the dongle daemon is restarting the access point.
 *
 * 1.3.0: every drop of a connected Android Auto is logged and the dongle daemon saves the logs of that moment
 * (askDump, drop.req). 1.2.0 also hides the two dongle plug-in notices (PlugQuiet.java, two hooks). The keep-connected part hooks nothing (1.1.0: decisions in Ladder.java, see there). In GPM's process it watches sys.kp.aa_ap (set to 1 by the
 * dongle daemon when the access point is up) and, when it turns on while a phone's
 * Bluetooth (SPP) link is there and Android Auto hasn't started, calls stock GPM's
 * own GalReceiverService.connectWirelessSession(address) on GPM's main thread, the
 * same call stock makes for a reconnect. At most 3 tries per access-point start,
 * 15 s apart. Never while Android Auto or CarPlay runs or is starting, never with a
 * cable connection, never for an iPhone (stock never makes an SPP thread for those).
 * Anything unexpected in GPM (a missing class, field or method): it logs and stops.
 *
 * Log: logcat tag HMG-API "[ev6-kr-aa-keep]" and /data/local/tmp/usbwifi_hotspot/aakeep.log
 * (the dongle daemon copies that folder's *.log to the USB stick).
 */
public final class AaKeep extends ModEntry {
    static final String GPM = "com.google.android.projection.sink";

    /** 1.2.0: in zygote, before system_server starts: the "unsupported USB" notice hook (PlugQuiet) */
    @Override
    public void zygoteInit(ModContext mod) {
        try {
            PlugQuiet.zygote(mod);
        } catch (Throwable t) {
            mod.error("plug notice 2", t);
        }
    }

    @Override
    public void appLoaded(ModContext mod, LoadedApp app) {
        if (!GPM.equals(app.packageName)) return;
        if (app.processName != null && !GPM.equals(app.processName)) return;   // main process only
        try {
            PlugQuiet.gpm(mod, app.classLoader);                  // 1.2.0: the "charging only" notice
        } catch (Throwable t) {
            mod.error("plug notice 1", t);
        }
        Keeper k = new Keeper(mod, app.classLoader);
        if (!mod.settingBoolean("enabled", true)) {
            k.log("off in the settings: doing nothing");
            return;
        }
        k.start();
    }

    static final class Keeper extends Thread implements Ladder.Gpm {
        static final String PROP = "sys.kp.aa_ap";
        static final String LOG_DIR = "/data/local/tmp/usbwifi_hotspot";
        static final long LOG_MAX = 256 * 1024;

        final ModContext mod;
        final ClassLoader cl;
        final Handler main = new Handler(Looper.getMainLooper());
        final Ladder ladder = new Ladder(this);
        // reflection, resolved once (stock GPM: required)
        Field fExplorer, fService, fThreads, fHandler, fDipo;
        Method mStatus, mConnMode, mConnect, mDipoStat;
        Method mGetProp;
        // optional: stock's AA phone, call state, Broadcom BTCM (the car's Bluetooth manager)
        Method mAaAddr, mBtCalling;
        Field fBtExplorer;
        Method mBtcmGet, mHfp, mSppConn, mSppDisc, mSppStat, mBtConn, mBtDisc;
        volatile boolean busy;
        Object we, svc;              // set on the main thread for each tick

        Keeper(ModContext mod, ClassLoader cl) {
            super("ev6-aakeep");
            this.mod = mod;
            this.cl = cl;
            setDaemon(true);
        }

        @Override
        public void run() {
            try {
                resolve();
            } catch (Throwable t) {
                log("stock GPM isn't the one this mod was made for (" + t + "): doing nothing");
                return;
            }
            ladder.btAllowed = mod.settingBoolean("bt_reconnect", true);
            log("1.3.0 watching " + PROP + ": steps START, OPEN" + (mSppConn == null ? "(n/a)" : "") + ", RENEW" + (mSppDisc == null ? "(n/a)" : "")
                    + ", BT" + (mBtConn == null ? "(n/a)" : ladder.btAllowed ? "" : "(off in settings)") + "; AA phone " + (mAaAddr == null ? "(n/a)" : "ok")
                    + ", call check " + (mBtCalling == null ? "(n/a: BT step never runs)" : "ok"));
            while (true) {
                try {
                    Thread.sleep(1000);
                    if (!mod.enabled()) continue;
                    if (busy) continue;
                    busy = true;
                    final boolean ap = "1".equals(prop());
                    final long now = SystemClock.elapsedRealtime();
                    main.post(new Runnable() {
                        @Override
                        public void run() {
                            try {
                                we = fExplorer.get(null);
                                svc = we == null ? null : fService.get(we);
                                if (svc != null) for (String l : ladder.tick(now, ap)) log(l);
                                if (ladder.drop != null) {
                                    askDump(ladder.drop);
                                    ladder.drop = null;
                                }
                            } catch (Throwable t) {
                                log("error " + t);
                            } finally {
                                busy = false;
                            }
                        }
                    });
                } catch (InterruptedException e) {
                    return;
                } catch (Throwable t) {
                    busy = false;
                    log("error " + t);
                }
            }
        }

        void resolve() throws Exception {
            Class<?> wec = Class.forName("com.google.android.projection.protocol.WirelessExplorer", false, cl);
            Class<?> sc = Class.forName("com.google.android.projection.service.GalReceiverService", false, cl);
            fExplorer = field(wec, "mWirelessExplorer");
            fService = field(wec, "mService");
            fThreads = field(wec, "mALConnectedThread");
            fHandler = field(wec, "mWirelessHandler");
            fDipo = field(wec, "mDipoManager");
            mStatus = sc.getDeclaredMethod("getGpmStatus", boolean.class);
            mConnMode = sc.getDeclaredMethod("getGpmConnectMode");
            mConnect = sc.getDeclaredMethod("connectWirelessSession", String.class);
            mConnect.setAccessible(true);
            mStatus.setAccessible(true);
            mConnMode.setAccessible(true);
            if (!HashMap.class.isAssignableFrom(fThreads.getType())) throw new NoSuchFieldException("mALConnectedThread type " + fThreads.getType());
            if (!Handler.class.isAssignableFrom(fHandler.getType())) throw new NoSuchFieldException("mWirelessHandler type " + fHandler.getType());
            try {
                mDipoStat = fDipo.getType().getMethod("getCurrentDiPOStat");
            } catch (Throwable t) {
                mDipoStat = null;
            }
            mGetProp = Class.forName("android.os.SystemProperties").getMethod("get", String.class);
            // optional parts: each missing one only turns its step off (logged at start)
            try {
                mAaAddr = sc.getDeclaredMethod("getGpmBtAddress", int.class);
                mAaAddr.setAccessible(true);
            } catch (Throwable t) {
                mAaAddr = null;
            }
            try {
                fBtExplorer = field(sc, "mBluetoothExplorer");
                mBtCalling = fBtExplorer.getType().getDeclaredMethod("isBtCalling");
                mBtCalling.setAccessible(true);
            } catch (Throwable t) {
                mBtCalling = null;
            }
            try {
                Class<?> bm = Class.forName("com.broadcom.bt.hfdevice.hfbtcm.HfDeviceBTCMManager", false, cl);
                mBtcmGet = bm.getMethod("getLocalBTCMManager", android.content.Context.class);
                mHfp = bm.getMethod("IbtcmGetHfpConnectedDevice");
                mSppStat = bm.getMethod("IbtcmGetSppConnectStatus", String.class);
                try { mSppConn = bm.getMethod("IbtcmSppConnect", String.class); } catch (Throwable t) { mSppConn = null; }
                try { mSppDisc = bm.getMethod("IbtcmSppDisconnect", String.class); } catch (Throwable t) { mSppDisc = null; }
                try {
                    mBtConn = bm.getMethod("IbtcmConnect", String.class);
                    mBtDisc = bm.getMethod("IbtcmDisconnect", String.class);
                } catch (Throwable t) {
                    mBtConn = null;
                    mBtDisc = null;
                }
            } catch (Throwable t) {
                mBtcmGet = null;
            }
        }

        static Field field(Class<?> c, String name) throws Exception {
            Field f = c.getDeclaredField(name);
            f.setAccessible(true);
            return f;
        }

        String prop() {
            try {
                return (String) mGetProp.invoke(null, PROP);
            } catch (Throwable t) {
                return "";
            }
        }

        // ---- Ladder.Gpm, on GPM's main thread
        Object btcm() {
            try {
                return mBtcmGet == null || svc == null ? null : mBtcmGet.invoke(null, svc);
            } catch (Throwable t) {
                return null;
            }
        }

        public int status() {
            try {
                return (Integer) mStatus.invoke(svc, false);
            } catch (Throwable t) {
                return -1;
            }
        }

        public int mode() {
            try {
                return (Integer) mConnMode.invoke(svc);
            } catch (Throwable t) {
                return -1;
            }
        }

        public boolean carplay() {
            try {
                Object d = mDipoStat == null ? null : fDipo.get(we);
                return d != null && (Integer) mDipoStat.invoke(d) > 0;
            } catch (Throwable t) {
                return false;
            }
        }

        public boolean stockBusy() {
            try {
                Handler h = (Handler) fHandler.get(we);
                return h != null && (h.hasMessages(0) || h.hasMessages(1));
            } catch (Throwable t) {
                return false;
            }
        }

        HashMap<?, ?> threads() {
            try {
                return (HashMap<?, ?>) fThreads.get(we);
            } catch (Throwable t) {
                return null;
            }
        }

        public int sppCount() {
            HashMap<?, ?> m = threads();
            return m == null ? 0 : m.size();
        }

        public String sppPhone() {
            HashMap<?, ?> m = threads();
            if (m == null || m.size() != 1) return null;
            Object k = m.keySet().iterator().next();
            return k instanceof String ? (String) k : null;
        }

        public String btPhone() {
            try {
                Object b = btcm();
                Object d = b == null ? null : mHfp.invoke(b);
                return d == null ? null : ((android.bluetooth.BluetoothDevice) d).getAddress();
            } catch (Throwable t) {
                return null;
            }
        }

        public String aaPhone() {
            try {
                return mAaAddr == null ? null : (String) mAaAddr.invoke(svc, 2);
            } catch (Throwable t) {
                return null;
            }
        }

        public int btcmSpp(String a) {
            try {
                Object b = btcm();
                return b == null ? -1 : (Integer) mSppStat.invoke(b, a);
            } catch (Throwable t) {
                return -1;
            }
        }

        public boolean canOpen() {
            return mBtcmGet != null && mSppConn != null && mSppDisc != null;
        }

        public boolean canReconnect() {
            return mBtcmGet != null && mBtConn != null && mBtDisc != null;
        }

        public boolean inCall() {
            try {
                if (mBtCalling == null) return true;
                if ((Boolean) mBtCalling.invoke(fBtExplorer.get(svc))) return true;
                android.media.AudioManager am = (android.media.AudioManager) ((android.content.Context) svc).getSystemService("audio");
                int m = am == null ? 0 : am.getMode();
                return m == 2 || m == 3;
            } catch (Throwable t) {
                return true;
            }
        }

        public void start(String a) throws Exception {
            mConnect.invoke(svc, a);
        }

        boolean call(Method m, String a) throws Exception {
            Object b = btcm();
            if (b == null || m == null) throw new IllegalStateException("BTCM not available");
            return (Boolean) m.invoke(b, a);
        }

        public boolean sppOpen(String a) throws Exception {
            return call(mSppConn, a);
        }

        public boolean sppClose(String a) throws Exception {
            return call(mSppDisc, a);
        }

        public boolean btOff(String a) throws Exception {
            return call(mBtDisc, a);
        }

        public boolean btOn(String a) throws Exception {
            return call(mBtConn, a);
        }

        /** 1.3.0: the dongle daemon (root) sees this file within a second and saves logcat, dmesg and Wi-Fi state */
        void askDump(String why) {
            try {
                File f = new File(LOG_DIR, "drop.req");
                FileOutputStream o = new FileOutputStream(f, false);
                try {
                    String t = new SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(new Date());
                    o.write((t + " " + why + "\n").getBytes("UTF-8"));
                } finally {
                    o.close();
                }
                f.setReadable(true, false);
                f.setWritable(true, false);
            } catch (Throwable t) {
                log("drop: could not ask the daemon for the logs (" + t + ")");
            }
        }

        void log(String s) {
            mod.log(s);
            File d = new File(LOG_DIR);
            if (!d.isDirectory()) return;
            try {
                File f = new File(d, "aakeep.log");
                if (f.length() > LOG_MAX) f.renameTo(new File(d, "aakeep.old.log"));
                FileOutputStream o = new FileOutputStream(f, true);
                try {
                    String t = new SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(new Date());
                    o.write((t + " " + s + "\n").getBytes("UTF-8"));
                } finally {
                    o.close();
                }
            } catch (Throwable ignored) {
                // the logcat line is still there
            }
        }
    }
}
