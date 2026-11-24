package korea.projection.app;

import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

/**
 * 1.8.0 베타 3(B3-12): 순정 Wi-Fi 서비스가 아이폰에 주는 카플레이 AP 값의 <b>길이만</b> 앱 폴더 파일에 남긴다.
 * WifiManager.getWifiApConfiguration()을 리플렉션으로 불러 ConnectivitySSID·ConnectivityPSK의 길이를 읽는다
 * (순정 Iap2Service와 같은 API). 서비스(root)는 동작을 바꾸지 않고 이 기록을 리포트에 비교로만 싣는다.
 * SSID·PSK 값 자체와 예외 메시지는 어디에도 쓰지 않는다(CLAUDE.md 5장). 부팅마다 한 번, 화면을 막지 않게 뒤에서 돈다.
 * 익명 클래스 대신 이름 있는 클래스(JDK 21 + d8 8.2가 익명 클래스에서 멈춤).
 */
final class ApCfg implements Runnable {
    /** 앱 폴더 파일 이름. 패키지(svc)가 /data/data/korea.projection.app/files/apcfg.len으로 읽는다 */
    static final String NAME = "apcfg.len";
    static final String F_SSID = "ConnectivitySSID", F_PSK = "ConnectivityPSK";

    final File dir;
    final Object wifi;
    final String boot;

    ApCfg(File dir, Object wifi, String boot) {
        this.dir = dir; this.wifi = wifi; this.boot = boot;
    }

    /** 이번 부팅에 이미 남겼으면 다시 하지 않는다(파일의 ap_svc_boot가 지금 boot_id와 같음). boot_id를 모르면 하지 않는다 */
    static boolean need(String oldText, String boot) {
        if (boot == null || boot.trim().isEmpty()) return false;
        return !safe(boot).equals(Report.parse(oldText).get("ap_svc_boot").trim());
    }

    /**
     * wifi(WifiManager)에서 길이를 읽는다: {SSID 길이, PSK 길이, 실패 이유}. 길이를 모르면 "", 성공이면 이유 "".
     * 이유: perm(권한 거절), nomethod(메서드·필드 없음), null(설정·값 없음), err(그 밖). 값과 예외 메시지는 돌려주지 않는다.
     */
    static String[] probe(Object wifi) {
        String[] out = { "", "", "" };
        if (wifi == null) { out[2] = "null"; return out; }
        Object cfg;
        try {
            Method m = wifi.getClass().getMethod("getWifiApConfiguration");
            cfg = m.invoke(wifi);
        } catch (NoSuchMethodException e) {
            out[2] = "nomethod"; return out;
        } catch (InvocationTargetException e) {
            out[2] = e.getCause() instanceof SecurityException ? "perm" : "err"; return out;
        } catch (SecurityException e) {
            out[2] = "perm"; return out;
        } catch (Throwable e) {
            out[2] = "err"; return out;
        }
        if (cfg == null) { out[2] = "null"; return out; }
        String[] names = { F_SSID, F_PSK };
        for (int i = 0; i < 2; i++) {
            String why;
            try {
                Object v = field(cfg, names[i]);
                if (v instanceof String) { out[i] = Integer.toString(((String) v).length()); continue; }
                why = v == null ? "null" : "err";
            } catch (NoSuchFieldException e) {
                why = "nomethod";
            } catch (SecurityException e) {
                why = "perm";
            } catch (Throwable e) {
                why = "err";
            }
            if (out[2].isEmpty()) out[2] = why;
        }
        return out;
    }

    /** 공개 필드(Field)를 먼저, 없으면 선언된 필드를 연다(ApCfgReceiver도 씀) */
    static Object field(Object o, String name) throws Exception {
        Field f;
        try {
            f = o.getClass().getField(name);
        } catch (NoSuchFieldException e) {
            f = o.getClass().getDeclaredField(name);
            f.setAccessible(true);
        }
        return f.get(o);
    }

    /** 파일 내용(패키지가 읽는 "키=값" 다섯 줄) */
    static String text(String[] p, String boot, long t) {
        return "ap_ssid_len_svc=" + safe(p[0]) + "\nap_psk_len_svc=" + safe(p[1]) + "\nap_psk_svc_err=" + safe(p[2])
            + "\nap_svc_boot=" + safe(boot) + "\nap_svc_t=" + t + "\n";
    }

    /** 영문·숫자·_·-만, 40자까지(패키지 규칙과 같음). 그 밖의 글자는 뺀다 */
    static String safe(String s) {
        if (s == null) return "";
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length() && b.length() < 40; i++) {
            char c = s.charAt(i);
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-') b.append(c);
        }
        return b.toString();
    }

    /** 파일을 600으로(앱과 root만) */
    static void ownerOnly(File f) {
        try {
            f.setReadable(false, false); f.setReadable(true, true);
            f.setWritable(false, false); f.setWritable(true, true);
            f.setExecutable(false, false);
        } catch (Throwable ignored) { }
    }

    /** 뒤에서 한 번: 이번 부팅에 아직 없으면 읽어서 쓴다. 어떤 실패도 화면에 영향을 주지 않는다 */
    @Override
    public void run() {
        try {
            File f = new File(dir, NAME);
            if (!need(StatusActivity.read(f.getPath()), boot)) return;
            String body = text(probe(wifi), boot.trim(), System.currentTimeMillis() / 1000);
            File tmp = new File(dir, NAME + ".tmp");
            java.io.FileOutputStream out = null;
            try {
                out = new java.io.FileOutputStream(tmp);
                ownerOnly(tmp);
                out.write(body.getBytes("UTF-8"));
                out.close();
                out = null;
                if (!tmp.renameTo(f)) tmp.delete();
                else ownerOnly(f);
            } finally {
                if (out != null) try { out.close(); } catch (Exception ignored) { }
            }
        } catch (Throwable ignored) {
            // 기록일 뿐이라 조용히 넘어간다(값이 섞일 수 있는 예외 메시지는 남기지 않는다)
        }
    }
}
