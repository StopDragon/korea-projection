package hmgapi.mods.aakeep;

import java.util.ArrayList;
import java.util.List;

/**
 * The decision part of aa-keep, plain Java (tested on the Mac, test/LadderTest.java). Called once a second on GPM's main
 * thread with the time and the access point state; it reads stock GPM and Bluetooth through {@link Gpm} and returns log
 * lines. Nothing here touches Android directly.
 *
 * Car log 2026-11-14 15:24: after an AA session ended (dongle pulled), stock GPM kept status 3 ("starting") with the
 * phone's Bluetooth AA channel (SPP) closed by its own rfcommDisconnect, and nothing ever reopened it: AA stayed off until
 * the phone's Bluetooth was reconnected by hand. aa-keep 1.0 read status 3 as "starting" and stopped.
 *
 * Now: while the access point is up and Android Auto is not connected (status below 4), and either stock has not started
 * (status below 3) 3 s after the access point came up, or stock has sat at status 3 for 12 s, the steps below are tried in
 * order, one at a time, each followed by a wait to see if stock carries on (any time status reaches 4 = done):
 *   1 START  stock's own connectWirelessSession(phone)               - the phone's AA channel is open
 *   2 OPEN   reopen the phone's AA channel (BTCM IbtcmSppConnect)     - channel closed; the same thing BTCM does after the
 *            phone's Bluetooth connects; stock then runs its normal start (startRfcommNego, even at status 3)
 *   3 RENEW  close and reopen the AA channel
 *   4 BT     disconnect and reconnect the phone's Bluetooth (music/calls pause for a few seconds) - setting, never in a
 *            call, at most once per 10 minutes
 * then it stops until the access point goes off and on, or AA connects and drops again.
 * Only the phone stock knows as its wireless AA phone (getGpmBtAddress(2)) is touched; never with a cable (mode 1) or
 * CarPlay. Every change of state and every step is logged.
 */
final class Ladder {
    interface Gpm {
        int status();                // stock getGpmStatus(false): 3 starting, 4+ connected; -1 unknown
        int mode();                  // getGpmConnectMode(): 0 none, 1 cable, 2 wireless
        boolean carplay();
        boolean stockBusy();         // stock has a phone message queued (WirelessHandler 0/1)
        int sppCount();              // phones in stock's AA channel table (mALConnectedThread)
        String sppPhone();           // the one phone there, or null
        String btPhone();            // the phone on Bluetooth hands-free (BTCM), or null
        String aaPhone();            // stock's wireless AA phone (getGpmBtAddress(2)), or null/""
        int btcmSpp(String a);       // BTCM's AA channel state for a phone, -1 unknown
        boolean canOpen();           // BTCM channel calls available
        boolean canReconnect();      // BTCM Bluetooth connect/disconnect available
        boolean inCall();            // a phone call (fail safe: true when it can't tell)
        void start(String a) throws Exception;
        boolean sppOpen(String a) throws Exception;
        boolean sppClose(String a) throws Exception;
        boolean btOff(String a) throws Exception;
        boolean btOn(String a) throws Exception;
    }

    static final long FIRST_DELAY = 3000, STUCK_AT_3 = 12000, WAIT = 15000, WAIT_BT = 30000, BUSY_WAIT = 2000;
    static final long BT_SETTLE = 10000, RENEW_GAP = 2000, BT_GAP = 5000, BT_EVERY = 10 * 60 * 1000L;

    final Gpm g;
    boolean btAllowed = true;

    // state
    boolean apUp;
    long apSince = -1, s3Since = -1, btSince = -1, nextAt, stepAt, lastBtReconnect = -BT_EVERY;
    String lastBt, lastAa;
    int step;                    // last step done in this episode (0 none)
    int phase;                   // 2-phase steps: 1 = second half pending
    boolean gaveUp, episode;
    long gaveUpAt;
    static final long AGAIN = 10 * 60 * 1000L;
    String lastState = "";
    // 1.3.0: a drop = Android Auto was connected (status 4+) and now is not. Ladder.drop is read and cleared by the caller,
    // which asks the dongle daemon to save the car's logs of that moment (2026-11-15 15:24: a drop while driving, cause
    // not in any log because nothing was recording).
    int prevSt = -1;
    long connSince = -1;
    String drop;

    Ladder(Gpm g) {
        this.g = g;
    }

    static String mask(String a) {
        return a == null || a.length() < 5 ? "none" : "..:" + a.substring(a.length() - 5);
    }

    void reset() {
        step = 0;
        phase = 0;
        gaveUp = false;
        episode = false;
    }

    List<String> tick(long now, boolean ap) {
        List<String> out = new ArrayList<String>();
        if (ap && !apUp) {
            out.add("access point up: check in " + FIRST_DELAY / 1000 + " s");
            apSince = now;
            nextAt = now + FIRST_DELAY;
            reset();
        } else if (!ap && apUp) {
            out.add("access point down");
            reset();
        }
        apUp = ap;
        int st = g.status();
        int mode = g.mode();
        // while Android Auto runs (status 4+) the Bluetooth manager is not asked every second (cached values)
        boolean quiet = st >= 4;
        String spp = g.sppPhone();
        String bt = quiet ? lastBt : g.btPhone();
        String aa = quiet ? lastAa : g.aaPhone();
        lastAa = aa;
        if (bt == null) btSince = -1;
        else if (!bt.equals(lastBt) || btSince < 0) btSince = now;
        lastBt = bt;
        if (st == 3) {
            if (s3Since < 0) s3Since = now;
        } else {
            s3Since = -1;
        }
        String phone = phone(spp, bt, aa);
        String state = "GPM status " + st + ", mode " + mode + ", AA channel " + (g.sppCount() == 0 ? "closed" : mask(spp) + (g.sppCount() > 1 ? " +" + (g.sppCount() - 1) : ""))
                + " (BTCM " + (phone == null || quiet ? "-" : String.valueOf(g.btcmSpp(phone))) + "), phone on Bluetooth " + mask(bt) + ", AA phone " + mask(aa)
                + ", access point " + (ap ? "up" : "down");
        if (!state.equals(lastState)) {
            out.add("state: " + state);
            lastState = state;
        }
        if (st >= 4) {
            if (connSince < 0) connSince = now;
        } else if (st >= 0 && prevSt >= 4) {
            drop = "DROP: Android Auto ended while connected (status " + prevSt + " -> " + st + ", mode " + mode + ") after "
                    + (connSince < 0 ? "?" : String.valueOf((now - connSince) / 1000)) + " s; AA channel "
                    + (g.sppCount() == 0 ? "closed" : "open") + ", access point " + (ap ? "up" : "down (dongle unplugged or hotspot off)")
                    + ", phone on Bluetooth " + (g.btPhone() == null ? "none" : "yes");
            out.add(drop);
            connSince = -1;
        }
        if (st >= 0) prevSt = st;
        if (!ap) return out;
        if (st >= 4) {
            if (episode) out.add("Android Auto connected (status " + st + ") " + ((now - apSince) / 1000) + " s after the access point came up"
                    + (step > 0 ? ", after step " + step + " " + name(step) : ""));
            reset();
            return out;
        }
        if (gaveUp && now - gaveUpAt >= AGAIN) {
            out.add("again: " + AGAIN / 60000 + " min since giving up, trying the steps once more");
            reset();
        }
        if (now < nextAt || gaveUp) return out;
        if (mode == 1) return out;                       // cable Android Auto: not ours
        if (g.carplay()) return out;
        boolean stuck = st < 3 ? now - apSince >= FIRST_DELAY : s3Since >= 0 && now - s3Since >= STUCK_AT_3;
        if (phase == 1) stuck = true;                    // second half of a step is due
        if (!stuck) return out;
        if (phone == null) {
            if (!"no AA phone".equals(lastNote)) out.add("wait: no wireless AA phone on Bluetooth (phone on Bluetooth " + mask(bt) + ", AA phone " + mask(aa) + ")");
            lastNote = "no AA phone";
            nextAt = now + BUSY_WAIT;
            return out;
        }
        lastNote = "";
        if (g.stockBusy()) {
            nextAt = now + BUSY_WAIT;
            return out;
        }
        episode = true;
        try {
            doNext(now, st, spp, phone, out);
        } catch (Throwable t) {
            out.add("step " + step + " " + name(step) + " failed: " + t + " (stop)");
            gaveUp = true;
            gaveUpAt = now;
        }
        return out;
    }

    String lastNote = "";

    /** the phone to work on: the one in stock's channel table, else the Bluetooth phone if it is stock's AA phone */
    String phone(String spp, String bt, String aa) {
        if (spp != null) return spp;
        if (bt != null && aa != null && aa.length() > 0 && bt.equalsIgnoreCase(aa)) return bt;
        return null;
    }

    static String name(int s) {
        return s == 1 ? "START" : s == 2 ? "OPEN" : s == 3 ? "RENEW" : s == 4 ? "BT" : "-";
    }

    void doNext(long now, int st, String spp, String phone, List<String> out) throws Exception {
        String why = st == 3 ? "stock at status 3 for " + ((now - s3Since) / 1000) + " s" : "stock not started (status " + st + ") " + ((now - apSince) / 1000) + " s after the access point";
        if (phase == 1) {                                  // second halves
            phase = 0;
            if (step == 3) {
                boolean r = g.sppOpen(phone);
                out.add("step 3 RENEW: reopened the AA channel to " + mask(phone) + " (BTCM answered " + r + ")");
                nextAt = now + WAIT;
            } else if (step == 4) {
                boolean r = g.btOn(phone);
                lastBtReconnect = now;
                out.add("step 4 BT: Bluetooth reconnect to " + mask(phone) + " asked (BTCM answered " + r + ")");
                nextAt = now + WAIT_BT;
            }
            return;
        }
        if (step < 1 && spp != null) {
            step = 1;
            g.start(phone);
            out.add("step 1 START: " + why + ", AA channel open: called stock connectWirelessSession(" + mask(phone) + ")");
            nextAt = now + WAIT;
            return;
        }
        if (step < 2 && spp == null && g.canOpen()) {
            if (btSince >= 0 && now - btSince < BT_SETTLE) {   // the phone's Bluetooth just came: stock opens the channel itself
                nextAt = btSince + BT_SETTLE;
                return;
            }
            step = 2;
            boolean r = g.sppOpen(phone);
            out.add("step 2 OPEN: " + why + ", AA channel closed: asked BTCM to reopen it to " + mask(phone) + " (answered " + r + ")");
            nextAt = now + WAIT;
            return;
        }
        if (step < 3 && g.canOpen()) {
            step = 3;
            boolean r = g.sppClose(phone);
            out.add("step 3 RENEW: " + why + ": closed the AA channel to " + mask(phone) + " (answered " + r + "), reopening in " + RENEW_GAP / 1000 + " s");
            phase = 1;
            nextAt = now + RENEW_GAP;
            return;
        }
        if (step < 4) {
            step = 4;
            if (!btAllowed) {
                out.add("step 4 BT skipped: Bluetooth reconnect is off in the settings");
            } else if (!g.canReconnect()) {
                out.add("step 4 BT skipped: BTCM connect/disconnect not available");
            } else if (g.inCall()) {
                out.add("step 4 BT skipped: a phone call is on (or can't tell)");
            } else if (now - lastBtReconnect < BT_EVERY) {
                out.add("step 4 BT skipped: already done " + ((now - lastBtReconnect) / 1000) + " s ago (at most once per " + BT_EVERY / 60000 + " min)");
            } else {
                boolean r = g.btOff(phone);
                out.add("step 4 BT: " + why + ": Bluetooth of " + mask(phone) + " disconnected (answered " + r + "), connecting again in " + BT_GAP / 1000 + " s");
                phase = 1;
                nextAt = now + BT_GAP;
                return;
            }
        }
        gaveUp = true;
        gaveUpAt = now;
        out.add("gave up: Android Auto did not start after every step (status " + st + "); next try in " + AGAIN / 60000 + " min, or when the access point comes up again");
    }
}
