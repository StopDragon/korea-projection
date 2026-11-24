package korea.projection.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import java.io.File;

/**
 * 1.8.0 정식(C4, 11-24 소유자 승인): 순정 Wi-Fi 서비스의 카플레이 AP 값(SSID·PSK)을 root 서비스에 건넨다.
 * 화면이 없는 receiver이고 exported=false다. root 서비스가 아래처럼 명시적으로 부를 때만 동작한다.
 *   am broadcast -a korea.projection.app.action.APCFG -n korea.projection.app/.ApCfgReceiver -f 32
 *   (-f 32 = FLAG_INCLUDE_STOPPED_PACKAGES: 설치 뒤 앱을 한 번도 열지 않은 부팅에서도 받게 한다)
 * files/apcfg.val(0600, 임시 파일에 쓴 뒤 이름 바꾸기)에 세 줄을 쓴다:
 *   boot=<boot_id>, ssid_hex=<UTF-8 바이트 16진>, psk_hex=<UTF-8 바이트 16진>
 * 값은 로그·리포트·화면·예외 메시지 어디에도 남기지 않는다(CLAUDE.md 5장). 로그 호출 자체가 없다.
 * 읽기에 실패하면 값 대신 boot·err=noval 두 줄을 같은 방식으로 쓴다(서비스가 기다리지 않고 바로 파일 값을 씀, 리뷰 L2).
 * boot_id도 모르거나 쓰기에 실패하면 파일을 남기지 않는다(서비스는 timeout 뒤 파일 값).
 * 토스트 없음. 익명 클래스 없음(d8 8.2가 익명 클래스에서 멈춤).
 */
public final class ApCfgReceiver extends BroadcastReceiver {
    /** root 서비스와 정한 액션 이름. 다른 액션이면 아무것도 하지 않는다 */
    static final String ACTION = "korea.projection.app.action.APCFG";
    /** 앱 폴더 파일 이름. 서비스가 /data/data/korea.projection.app/files/apcfg.val로 읽고 바로 지운다 */
    static final String NAME = "apcfg.val";
    static final String BOOT_ID = "/proc/sys/kernel/random/boot_id";

    @Override
    public void onReceive(Context ctx, Intent intent) {
        try {
            if (intent == null || !ACTION.equals(intent.getAction())) return;
            // 파일 하나 읽고 binder 한 번 부르는 짧은 일이라 receiver 안에서 바로 끝낸다
            save(ctx.getFilesDir(), ctx.getApplicationContext().getSystemService(Context.WIFI_SERVICE),
                StatusActivity.read(BOOT_ID));
        } catch (Throwable ignored) {
            // 조용히 넘어간다(값이 섞일 수 있는 예외 메시지는 남기지 않는다)
        }
    }

    /** 바이트를 소문자 16진으로(2자리씩). 서비스의 busybox awk가 되돌린다 */
    static String hex(byte[] b) {
        StringBuilder s = new StringBuilder(b.length * 2);
        for (int i = 0; i < b.length; i++) {
            int v = b[i] & 0xff;
            s.append(Character.forDigit(v >> 4, 16)).append(Character.forDigit(v & 15, 16));
        }
        return s.toString();
    }

    /**
     * 파일 내용(세 줄). 하나라도 못 읽으면 null: boot_id 모름, WifiManager·설정 없음, 권한 거절,
     * 필드 없음, 값이 문자열이 아니거나 비어 있음. 값 검사(글자 범위·길이)는 서비스가 한다.
     */
    static String body(Object wifi, String boot) {
        String b = ApCfg.safe(boot == null ? null : boot.trim());
        if (b.isEmpty() || wifi == null) return null;
        try {
            Object cfg = wifi.getClass().getMethod("getWifiApConfiguration").invoke(wifi);
            if (cfg == null) return null;
            Object ssid = ApCfg.field(cfg, ApCfg.F_SSID), psk = ApCfg.field(cfg, ApCfg.F_PSK);
            if (!(ssid instanceof String) || !(psk instanceof String)) return null;
            if (((String) ssid).isEmpty() || ((String) psk).isEmpty()) return null;
            return "boot=" + b + "\nssid_hex=" + hex(((String) ssid).getBytes("UTF-8"))
                + "\npsk_hex=" + hex(((String) psk).getBytes("UTF-8")) + "\n";
        } catch (Throwable e) {
            return null;
        }
    }

    /** 값을 못 읽었을 때 쓰는 두 줄(리뷰 L2): 서비스가 10초를 다 기다리지 않고 바로 파일 값으로 간다. 값·예외 메시지는 없다 */
    static String errBody(String boot) {
        String b = ApCfg.safe(boot == null ? null : boot.trim());
        return b.isEmpty() ? null : "boot=" + b + "\nerr=noval\n";
    }

    /**
     * 읽어서 쓴다. 값을 쓰면 true. 값을 못 읽으면 boot·err=noval 두 줄을 쓰고 false
     * (boot_id도 모르면 아무것도 쓰지 않음). 쓰기에 실패하면 파일(임시 파일 포함)을 남기지 않는다. 예외는 밖으로 내지 않는다
     */
    static boolean save(File dir, Object wifi, String boot) {
        String text = body(wifi, boot);
        if (text != null) return write(dir, text);
        File f = new File(dir, NAME);
        String err = errBody(boot);
        if (err == null || !write(dir, err)) f.delete();
        return false;
    }

    /** 0600 임시 파일에 쓴 뒤 이름을 바꾼다. 실패하면 apcfg.val·임시 파일을 지우고 false */
    static boolean write(File dir, String text) {
        File f = new File(dir, NAME), tmp = new File(dir, NAME + ".tmp");
        java.io.FileOutputStream out = null;
        try {
            out = new java.io.FileOutputStream(tmp);
            ApCfg.ownerOnly(tmp);
            out.write(text.getBytes("UTF-8"));
            out.close();
            out = null;
            if (!tmp.renameTo(f)) { tmp.delete(); f.delete(); return false; }
            ApCfg.ownerOnly(f);
            return true;
        } catch (Throwable e) {
            try { tmp.delete(); f.delete(); } catch (Throwable ignored) { }
            return false;
        } finally {
            if (out != null) try { out.close(); } catch (Throwable ignored) { }
            if (tmp.exists()) tmp.delete();
        }
    }
}
