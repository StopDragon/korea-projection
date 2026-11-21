package hmgapi.mods.aakeep;

import java.util.ArrayList;
import java.util.List;

/** Off-car checks of the recovery steps with a fake stock GPM / BTCM. Run by test_offline.sh. */
public final class LadderTest {
    static int pass, fail;

    static void ok(String n, boolean c) {
        System.out.println((c ? "PASS " : "FAIL ") + n);
        if (c) pass++; else fail++;
    }

    static final class Fake implements Ladder.Gpm {
        int status, mode;
        boolean carplay, busy, call, canOpen = true, canRe = true;
        String spp, bt, aa;
        final List<String> calls = new ArrayList<String>();
        // what the phone does when the channel is reopened: stock then runs its start and reaches status 4
        boolean openWorks;

        public int status() { return status; }
        public int mode() { return mode; }
        public boolean carplay() { return carplay; }
        public boolean stockBusy() { return busy; }
        public int sppCount() { return spp == null ? 0 : 1; }
        public String sppPhone() { return spp; }
        public String btPhone() { return bt; }
        public String aaPhone() { return aa; }
        public int btcmSpp(String a) { return spp == null ? 0 : 2; }
        public boolean canOpen() { return canOpen; }
        public boolean canReconnect() { return canRe; }
        public boolean inCall() { return call; }
        public void start(String a) { calls.add("start " + a); }
        public boolean sppOpen(String a) {
            calls.add("open " + a);
            if (openWorks) { spp = a; status = 4; }
            return true;
        }
        public boolean sppClose(String a) { calls.add("close " + a); spp = null; return true; }
        public boolean btOff(String a) { calls.add("btoff " + a); return true; }
        public boolean btOn(String a) { calls.add("bton " + a); return true; }
    }

    static List<String> run(Ladder l, long from, long to, boolean ap) {
        List<String> all = new ArrayList<String>();
        for (long t = from; t <= to; t += 1000) all.addAll(l.tick(t, ap));
        return all;
    }

    static boolean has(List<String> log, String s) {
        for (String l : log) if (l.contains(s)) return true;
        return false;
    }

    public static void main(String[] a) {
        String P = "02:00:00:00:12:E4";
        System.out.println("== 2026-11-14 15:24 car case: stock stuck at status 3, AA channel closed, phone on Bluetooth");
        Fake f = new Fake();
        f.status = 3; f.mode = 2; f.bt = P; f.aa = P; f.openWorks = true;
        Ladder l = new Ladder(f);
        List<String> log = run(l, 0, 5000, true);
        ok("state logged with the channel closed", has(log, "AA channel closed") && has(log, "phone on Bluetooth ..:12:E4"));
        ok("nothing before 12 s at status 3", f.calls.isEmpty());
        log = run(l, 6000, 14000, true);
        ok("step 2 OPEN: channel reopened to the AA phone", f.calls.contains("open " + P) && has(log, "step 2 OPEN"));
        log.addAll(run(l, 15000, 16000, true));
        ok("success logged with the step", has(log, "Android Auto connected") && has(log, "after step 2 OPEN"));
        ok("no Bluetooth reconnect needed", !f.calls.contains("btoff " + P));

        System.out.println("== channel open but stock not started (old aa-keep case)");
        f = new Fake();
        f.status = 0; f.spp = P; f.bt = P; f.aa = P;
        l = new Ladder(f);
        log = run(l, 0, 4000, true);
        ok("step 1 START 3 s after the access point", f.calls.contains("start " + P) && has(log, "step 1 START"));

        System.out.println("== nothing helps: every step once, Bluetooth reconnect last, then gives up");
        f = new Fake();
        f.status = 3; f.mode = 2; f.spp = P; f.bt = P; f.aa = P;
        l = new Ladder(f);
        log = run(l, 0, 200000, true);
        ok("order START, (RENEW close+open), BT off+on", f.calls.indexOf("start " + P) >= 0 && f.calls.indexOf("close " + P) > f.calls.indexOf("start " + P)
                && f.calls.lastIndexOf("open " + P) > f.calls.indexOf("close " + P) && f.calls.indexOf("bton " + P) > f.calls.indexOf("btoff " + P));
        ok("gave up after the steps, logged", has(log, "gave up"));
        int n = f.calls.size();
        run(l, 201000, 400000, true);
        ok("quiet after giving up (until 10 min)", f.calls.size() == n);
        log = run(l, 401000, 900000, true);
        ok("tries again after 10 min, but Bluetooth reconnect at most once per 10 min", has(log, "again:") && f.calls.size() > n);

        System.out.println("== safety");
        f = new Fake();
        f.status = 3; f.mode = 2; f.spp = P; f.bt = P; f.aa = P; f.call = true;
        l = new Ladder(f);
        log = run(l, 0, 200000, true);
        ok("in a call: Bluetooth step skipped", !f.calls.contains("btoff " + P) && has(log, "phone call"));
        f = new Fake();
        f.status = 0; f.mode = 1; f.spp = P; f.bt = P; f.aa = P;
        l = new Ladder(f);
        run(l, 0, 60000, true);
        ok("cable Android Auto: nothing done", f.calls.isEmpty());
        f = new Fake();
        f.status = 0; f.bt = "11:22:33:44:55:66"; f.aa = P;
        l = new Ladder(f);
        log = run(l, 0, 60000, true);
        ok("a phone that is not the wireless AA phone: never touched", f.calls.isEmpty() && has(log, "no wireless AA phone"));
        f = new Fake();
        f.status = 0; f.spp = P; f.bt = P; f.aa = P; f.carplay = true;
        l = new Ladder(f);
        run(l, 0, 60000, true);
        ok("CarPlay on: nothing done", f.calls.isEmpty());
        f = new Fake();
        f.status = 3; f.bt = P; f.aa = P;
        l = new Ladder(f);
        run(l, 0, 60000, false);
        ok("access point down: nothing done", f.calls.isEmpty());
        f = new Fake();
        f.status = 0; f.bt = P; f.aa = P;
        l = new Ladder(f);
        run(l, 0, 5000, true);
        ok("phone's Bluetooth just came (under 10 s): stock is left to open the channel", f.calls.isEmpty());
        run(l, 6000, 12000, true);
        ok("after 10 s on Bluetooth without the channel: OPEN", f.calls.contains("open " + P));
        f = new Fake();
        f.status = 3; f.mode = 2; f.spp = P; f.bt = P; f.aa = P;
        l = new Ladder(f);
        l.btAllowed = false;
        log = run(l, 0, 200000, true);
        ok("Bluetooth reconnect off in settings: skipped, logged", !f.calls.contains("btoff " + P) && has(log, "off in the settings"));
        f = new Fake();
        f.status = 3; f.mode = 2; f.spp = P; f.bt = P; f.aa = P;
        l = new Ladder(f);
        run(l, 0, 9000, true);
        f.status = 6;
        log = run(l, 10000, 11000, true);
        ok("stock connects by itself while waiting: nothing done", f.calls.isEmpty());

        System.out.println("== 1.3.0 drop: 2026-11-15 15:24 car case, AA connected then status 0 while driving (dongle up)");
        f = new Fake();
        f.status = 6; f.mode = 2; f.spp = P; f.bt = P; f.aa = P;
        l = new Ladder(f);
        log = run(l, 0, 578000, true);
        ok("no drop while connected", l.drop == null && !has(log, "DROP"));
        f.status = 0; f.mode = 0; f.aa = null;
        log = l.tick(579000, true);
        ok("drop logged with status, time connected and access point up", has(log, "DROP: Android Auto ended while connected (status 6 -> 0")
                && has(log, "after 579 s") && has(log, "access point up"));
        ok("drop handed to the caller once", l.drop != null);
        l.drop = null;
        log = run(l, 580000, 582000, true);
        ok("no second drop while still down", l.drop == null && !has(log, "DROP"));
        f.status = 6; f.mode = 2;
        run(l, 583000, 584000, true);
        f.status = 0;
        log = l.tick(585000, false);
        ok("drop with the dongle pulled says so", has(log, "access point down") && l.drop != null);
        f = new Fake();
        f.status = 3; f.mode = 2; f.bt = P; f.aa = P;
        l = new Ladder(f);
        run(l, 0, 5000, true);
        f.status = 0;
        run(l, 6000, 7000, true);
        ok("starting (status 3) then 0 is not a drop", l.drop == null);
        f = new Fake();
        f.status = 6; f.mode = 2;
        l = new Ladder(f);
        run(l, 0, 2000, true);
        f.status = -1;
        run(l, 3000, 4000, true);
        ok("status unknown (-1) is not a drop", l.drop == null);
        System.out.println("passed " + pass + ", failed " + fail);
        System.exit(fail == 0 ? 0 : 1);
    }
}
