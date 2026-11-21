package hmgapi.mods.aakeep;

/** Off-car checks of the plug-in notice decisions (PlugQuiet). Run by ../test_offline.sh. */
public final class PlugQuietTest {
    static int pass, fail;

    static void ok(String n, boolean c) {
        System.out.println((c ? "PASS " : "FAIL ") + n);
        if (c) pass++; else fail++;
    }

    static PlugQuiet.Seen seen(boolean dongle, long at) {
        PlugQuiet.Seen s = new PlugQuiet.Seen();
        s.dongle = dongle;
        s.at = at;
        return s;
    }

    public static void main(String[] a) {
        ok("our T3U Nano 2357:012e is a dongle", PlugQuiet.isDongle(0x2357, 0x012e));
        ok("all 17 driver ids", PlugQuiet.IDS.length == 34);
        ok("Realtek 0bda:b812 (same chip) is a dongle", PlugQuiet.isDongle(0x0bda, 0xb812));
        ok("the car's USB stick 058f:6387 is not", !PlugQuiet.isDongle(0x058f, 0x6387));
        ok("a Realtek card reader 0bda:0129 is not", !PlugQuiet.isDongle(0x0bda, 0x0129));
        ok("a Samsung phone 04e8:6860 is not", !PlugQuiet.isDongle(0x04e8, 0x6860));
        ok("id text", "2357:012e".equals(PlugQuiet.id(0x2357, 0x12e)));
        ok("charging-only OSD right after reading the dongle: hidden", PlugQuiet.hideOsd(1, 32, seen(true, 1000), 1500));
        ok("same OSD for a phone cable: shown", !PlugQuiet.hideOsd(1, 32, seen(false, 1000), 1500));
        ok("dongle read 4 s ago (another attach): shown", !PlugQuiet.hideOsd(1, 32, seen(true, 1000), 5000));
        ok("never read on this thread: shown", !PlugQuiet.hideOsd(1, 32, new PlugQuiet.Seen(), 1500));
        ok("another OSD (type 2): shown", !PlugQuiet.hideOsd(2, 32, seen(true, 1000), 1500));
        ok("another OSD number: shown", !PlugQuiet.hideOsd(1, 31, seen(true, 1000), 1500));
        System.out.println("passed " + pass + ", failed " + fail);
        System.exit(fail == 0 ? 0 : 1);
    }
}
