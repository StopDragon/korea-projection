package korea.projection.app;

import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 상태 파일(bin/status.sh가 root로 쓰는 key=value 줄)을 읽어 화면에 보일 줄과 QR에 담을 제보 링크를 만든다.
 * 안드로이드 클래스를 쓰지 않아 PC에서 시험할 수 있다(tests/ReportTest.java).
 * 상태 파일에는 SSID, 비밀번호, 휴대폰 이름, MAC, IP가 없다. 이 클래스도 그런 값을 만들지 않는다.
 */
final class Report {
    static final String ISSUES = "https://github.com/StopDragon/korea-projection/issues/new?template=car-report.yml";
    /** QR이 내비 화면에서 찍히도록 링크 길이를 제한한다 (QR 버전이 커지면 칸이 작아진다) */
    static final int MAX_URL = 560;

    final Map<String, String> v = new LinkedHashMap<String, String>();

    static Report parse(String text) {
        Report r = new Report();
        if (text == null) return r;
        for (String line : text.split("\n")) {
            int i = line.indexOf('=');
            if (i <= 0) continue;
            r.v.put(line.substring(0, i).trim(), line.substring(i + 1).trim());
        }
        return r;
    }

    String get(String k) { String s = v.get(k); return s == null ? "" : s; }
    boolean yes(String k) { return "yes".equals(v.get(k)); }
    boolean empty() { return v.isEmpty(); }
    /** 한국 차를 지원하지 않는 다른 무선 모드가 있고, 그 모드로 카플레이가 연결돼 있지 않음 */
    boolean foreign() { return yes("mod_foreign") && (get("cp_conn").isEmpty() || "0".equals(get("cp_conn"))); }

    /**
     * busybox가 없는 내비(K3·K8, tcc803x)인가. 1.5.5부터 status.sh가 이런 내비에서는 짧은 상태 파일
     * (support=nobb, product, platform, pkgver, usb, made)만 쓴다. 무선 설정은 하지 않는다.
     */
    boolean nobb() { return "nobb".equals(v.get("support")); }

    /** busybox 없는 내비의 제보 파일 칸: saved(USB에 저장함) / fail(USB에 쓰지 못함) / none(USB 없음) */
    private String usbCell() {
        String u = get("usb");
        if ("saved".equals(u)) return "USB의 KoreaProjection-report 폴더에 저장함";
        if ("fail".equals(u)) return "USB에 쓰지 못함 (다른 USB로 다시 해 보세요)";
        return "USB를 꽂고 Launch를 다시 누르면 만듭니다";
    }

    /** README "필요한 것"과 같은 최소 버전 (바꾸면 README와 설치 가이드도 함께 고친다) */
    static final String MIN_HMGAPI = "1.0.2";
    static final String MIN_NEMESIS = "1.16";

    /**
     * 1.6.2: 순정이 카플레이 AP를 직접 띄운 차(K3 BDPE 등, 상태 파일 ap_mode=stock). 이때 우리 핫스팟·DHCP가 꺼져 있는
     * 것이 정상이다(서비스가 일부러 켜지 않는다). 예전 상태 파일(ap_mode 없음)은 false.
     */
    boolean stockAp() { return "stock".equals(get("ap_mode")); }

    /** 맨 위 한 줄: 무선 카플레이가 될 준비가 됐는지, 아니면 무엇이 빠졌는지 */
    String verdict() {
        if (empty()) return "상태를 읽지 못했습니다. NEMESIS Manager에서 Launch를 다시 눌러 주세요.";
        if (nobb()) return "이 내비에서는 아직 동작하지 않습니다(지원 조사 중). 무선 설정은 하지 않았습니다.";
        // 1.7.3(K-5): 판정은 status.sh(kp_verdict) 한 곳에서 한다. 상태 파일에 결과가 있으면 그대로 보인다(리포트·QR과 같은 값).
        // 옛 상태 파일(1.7.2까지, verdict_msg 없음)이면 아래 예전 판정을 쓴다
        if (!get("verdict_msg").isEmpty()) return get("verdict_msg");
        if (!yes("tested")) return "확인되지 않은 차입니다. 핫스팟은 켜지 않고 대기 중입니다. QR로 제보해 주세요.";
        if (hmgapiVer().isEmpty()) return "HMG-API가 없습니다. HMG-API " + MIN_HMGAPI + " 이상을 설치해 주세요.";
        if (older(hmgapiVer(), MIN_HMGAPI) != 0)
            return "지원하지 않는 HMG-API 버전입니다. " + MIN_HMGAPI + " 이상으로 업데이트해 주세요.";
        // 1.6.1: 차에 있는 무선 모드가 한국 차를 지원하지 않는 다른 판(서비스는 덮어쓰지 않음). 토스트 대신 여기서 알린다.
        // 그 모드로 이미 카플레이가 연결돼 있으면 안내하지 않는다(판단은 mod.json의 region만 보므로).
        if (foreign()) return "차에 있는 HMG-API 무선 모드가 한국 차용이 아닙니다. HMG-API 앱에서 그 모드를 지우고 적용한 뒤 재부팅해 주세요.";
        if ("no".equals(get("mod"))) return "HMG-API 무선 모드가 없습니다. HMG-API 앱에서 설치해 주세요.";
        if ("no".equals(get("mod_on")))
            return "HMG-API 무선 모드가 꺼져 있습니다. HMG-API 앱에서 켜고 Apply changes 후 다시 시작해 주세요.";
        if ("off".equals(get("bridge")))
            return "무선 모드의 'Wireless CarPlay' 설정이 꺼져 있습니다. HMG-API 앱에서 켜고 Apply changes 후 다시 시작해 주세요.";
        if ("off".equals(get("hooks"))) return hooksOffAdvice();
        // 1.7.2: HMG-API가 이 차에서 무선 모드의 훅을 켜지 않음(차에 없는 훅 지점이 있음, 스포티지 NQ5 #46)
        if ("off".equals(get("mod_hooks")))
            return "HMG-API가 이 차에서 무선 모드를 켜지 못했습니다(이 차와 맞지 않는 부분이 있음). 내비를 재부팅해 보시고, 그래도 같으면 USB를 꽂고 [제보 파일 만들기]로 리포트를 보내 주세요.";
        if (!yes("feat_carplay")) return "무선 카플레이 기능이 꺼져 있습니다. HMG-API 무선 모드를 확인해 주세요.";
        // 1.6.2: 순정 카플레이 AP를 쓰는 차인데 지금 순정 Wi-Fi가 꺼져 있음(서비스는 우리 핫스팟을 켜지 않고 기다린다)
        if (!stockAp() && yes("stock_seen") && !yes("our_ap"))
            return "내비 Wi-Fi(무선 카플레이용)가 지금 꺼져 있습니다. 아이폰을 연결해 보고, 안 되면 내비를 재부팅해 주세요.";
        // 1.7.0: Wi-Fi 칩은 있는데 드라이버가 올라오지 않아 wlan0가 없다(그랜저 IG #52·#53). 재부팅으로 풀리는지 보고, 아니면 제보
        if (!stockAp() && yes("nowlan") && !yes("our_ap"))
            return "Wi-Fi 장치가 켜지지 않아 핫스팟을 켜지 못했습니다. 내비를 재부팅해 보시고, 그래도 같으면 USB를 꽂고 [제보 파일 만들기]로 리포트를 보내 주세요.";
        if (!stockAp() && (!yes("our_ap") || !yes("our_dhcp"))) return "핫스팟이 꺼져 있습니다. 내비를 재부팅(RESET 버튼 또는 NEMESIS 재부팅)한 뒤 다시 확인해 주세요.";
        if (older(get("nemesis"), MIN_NEMESIS) != 0)
            return "NEMESIS를 " + MIN_NEMESIS + " 이상으로 업데이트해 주세요.";
        if (!"0".equals(get("cp_conn")) && !get("cp_conn").isEmpty()) return "무선 카플레이 연결됨";
        // 1.7.3(U-4): 안드로이드도 쓰는 법을 알린다. 무선 AA가 꺼진 차(aa=no)·옛 상태 파일·순정 AP 차는 아이폰 문장만
        if (stockAp()) return "무선 카플레이 준비됨(내비 Wi-Fi 사용). 아이폰은 설정 → 일반 → CarPlay에서 연결하세요.";
        if (yes("aa")) return READY_BOTH;
        return "무선 카플레이 준비됨. 아이폰은 설정 → 일반 → CarPlay에서 연결하세요.";
    }

    static final String READY_BOTH = "무선 연결 준비됨. 아이폰은 설정 → 일반 → CarPlay, 안드로이드는 블루투스 연결 뒤 '무선 Android Auto 사용'을 누르세요.";

    /** 1.7.3(U-6): "이 차는 안 됨"으로 끝나는 판정(verdict_end=yes) 아래 회색 한 줄 */
    static final String UNINSTALL_HINT = "지우려면 NEMESIS Manager → Korea Projection → Uninstall 뒤 재부팅하세요. 유선 카플레이는 그대로입니다.";

    /** 판정 아래 회색 한 줄(없으면 "") */
    String endHint() {
        return yes("verdict_end") ? UNINSTALL_HINT : "";
    }

    /** 1.7.3(G-4): "먼저 할 일" 한 줄(README ✅ 차종인데 문제가 있을 때, 없으면 "") */
    String firstTodo() {
        return get("first");
    }

    /** 1.7.3(U-9): 차주용 요약 3줄(설치·무선 Wi-Fi·폰 연결). 옛 상태 파일이면 빈 목록 */
    List<String> summary() {
        List<String> out = new ArrayList<String>();
        for (String k : new String[] { "s1", "s2", "s3" }) if (!get(k).isEmpty()) out.add(get(k));
        return out;
    }

    /** 0: 좋음, 1: 확인 필요, 2: 문제 (화면 색) */
    int level() {
        if (empty()) return 2;
        if (nobb()) return 1;
        if (!get("verdict_msg").isEmpty()) {
            try {
                int lv = Integer.parseInt(get("verdict_lv"));
                return lv < 0 ? 0 : lv > 2 ? 2 : lv;
            } catch (NumberFormatException e) {
                return 1;
            }
        }
        if (!yes("tested")) return 1;
        if (!yes("feat_carplay")) return 2;
        if (hmgapiVer().isEmpty() || older(hmgapiVer(), MIN_HMGAPI) != 0) return 2;
        if (foreign()) return 2;
        if ("no".equals(get("mod")) || "no".equals(get("mod_on")) || "off".equals(get("bridge"))) return 2;
        if ("off".equals(get("mod_hooks"))) return 2;
        // 훅 기록은 지난 부팅 것일 수 있어 노랑
        if ("off".equals(get("hooks"))) return 1;
        if (!stockAp() && (!yes("our_ap") || !yes("our_dhcp"))) return 1;
        if (older(get("nemesis"), MIN_NEMESIS) != 0) return 1;
        return 0;
    }

    // --- 설치 진행 기록(1.5.5, 서비스가 쓰는 /data/local/tmp/korea-projection-progress.txt) ---
    // 이 Report를 진행 기록 파일로 만들었을 때 쓴다. boot는 지금 부팅 id(/proc/sys/kernel/random/boot_id):
    // 지난 부팅의 기록은 무시한다(재부팅 전 "진행 중"이 남아 있어도 막대를 보이지 않게).

    /** 이번 부팅의 기록인가 */
    boolean progThisBoot(String boot) {
        return !empty() && boot != null && boot.trim().equals(get("boot"));
    }

    /** 진행 기록이 이만큼(초) 새로 쓰이지 않으면 멈춘 것으로 본다(status.sh --wait의 15분과 같다) */
    static final long STALE = 900;

    /** 이번 부팅에 설치가 진행 중인가(진행 막대를 보일지) */
    boolean progRunning(String boot) {
        return progThisBoot(boot) && "run".equals(get("state"));
    }

    /** progRunning이면서 최근(STALE초 안)에 쓰인 기록인가. now: 지금 시각(초) */
    boolean progRunning(String boot, long now) {
        if (!progRunning(boot)) return false;
        try {
            // 1.7.3(리뷰 중간 2): 시계가 뒤로 바뀌어 기록 시각이 한참 미래면 멈춘 기록으로 본다(버튼이 계속 막히지 않게)
            long d = now - Long.parseLong(get("t"));
            return d <= STALE && d >= -STALE;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    /** 진행률 0~100 (읽지 못하면 0) */
    int progPct() {
        try {
            int p = Integer.parseInt(get("pct"));
            return p < 0 ? 0 : p > 100 ? 100 : p;
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    /** 시작한 지 몇 초 (now: 지금 시각 초). 읽지 못하면 -1 */
    long progElapsed(long now) {
        try {
            long s = Long.parseLong(get("start"));
            return now >= s ? now - s : -1;
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    /** "3분 05초" */
    static String mmss(long sec) {
        if (sec < 0) return "-";
        long m = sec / 60, ss = sec % 60;
        return (m > 0 ? m + "분 " : "") + (ss < 10 && m > 0 ? "0" : "") + ss + "초";
    }

    /**
     * 설치가 끝난 결과가 맨 위 판정을 대신할 때의 문구. 재부팅 필요·실패만(이번 부팅 기록일 때). 아니면 null.
     * 재부팅이 필요한데 상태표만 보면 "무선 모드가 없습니다"처럼 보여 사용자가 오해하기 쉽다.
     */
    String progVerdict(String boot) {
        if (!progThisBoot(boot)) return null;
        String st = get("state");
        if ("reboot".equals(st) || "fail".equals(st)) return get("stage").isEmpty() ? null : get("stage");
        return null;
    }

    /** 1.7.3(U-3): 이번 부팅에 "재부팅 필요"(state=reboot)인가. 베타 1부터 [지금 재부팅] 버튼은 늘 보이므로 화면은 이것을 쓰지 않는다(시험용으로 둠) */
    boolean progReboot(String boot) {
        return progThisBoot(boot) && "reboot".equals(get("state"));
    }

    /**
     * 1.7.3(U-2): QR 제보를 막는가. 이번 부팅에 설치 중(run)이거나 재부팅 전(reboot)이면 리포트 판정이 틀리므로(#114·#115·#122)
     * QR 자리에 QR_BLOCKED 문구를 보인다.
     */
    boolean qrBlocked(String boot) {
        return progThisBoot(boot) && ("run".equals(get("state")) || "reboot".equals(get("state")));
    }

    // 베타 1: 재부팅 안내는 판정 줄에서 한 번만 한다(이 문구와 겹치지 않게)
    static final String QR_BLOCKED = "제보 QR은 설정이 끝난 뒤 Launch를 다시 누르면 나옵니다.";

    /** 1.7.3(U-7): 진행 기록의 단계(step=N/M)를 "단계 N/M"으로. 옛 형식(줄 없음)이나 깨진 값이면 "" */
    String progStep() {
        String st = get("step");
        int i = st.indexOf('/');
        if (i <= 0 || i == st.length() - 1) return "";
        try {
            int n = Integer.parseInt(st.substring(0, i)), m = Integer.parseInt(st.substring(i + 1));
            return n >= 1 && n <= m && m <= 20 ? "단계 " + n + "/" + m : "";
        } catch (NumberFormatException e) {
            return "";
        }
    }

    /** 1.7.3(U-7): 이만큼(초) 넘게 걸리면 "평소보다 오래" 안내(STALE 900초 = 15분과 맞춤) */
    static final long SLOW = 600;
    static final String SLOW_MSG = "평소보다 오래 걸립니다. 15분이 지나도 그대로면 내비를 재부팅해 주세요.";
    static final String PROGRESS_HINT = "보통 5분 안에 끝납니다. 끝날 때까지 내비를 끄지 마세요.";

    /** 진행이 오래 걸리면 SLOW_MSG, 아니면 "" (now: 지금 시각 초) */
    String progSlow(long now) {
        return progSlow(now, -1);
    }

    /**
     * 리뷰 L6: nowUp(지금 부팅 뒤 초, /proc/uptime)을 주고 진행 기록에 시작한 부팅 뒤 초(ust)가 있으면 그것으로 잰다(시계가 앞당겨져도
     * 설치 초반에 "재부팅해 주세요"가 나오지 않게). 없거나 잴 수 없으면 예전처럼 시각(start)으로 잰다.
     */
    String progSlow(long now, long nowUp) {
        long ust = num("ust");
        if (nowUp >= 0 && !get("ust").isEmpty() && nowUp >= ust) return nowUp - ust >= SLOW ? SLOW_MSG : "";
        return progElapsed(now) >= SLOW ? SLOW_MSG : "";
    }

    /** /proc/uptime 내용 → 부팅 뒤 초. 읽지 못하면 -1 */
    static long upSec(String uptime) {
        if (uptime == null) return -1;
        String t = uptime.trim();
        int i = t.indexOf('.');
        if (i < 0) i = t.indexOf(' ');
        try { return Long.parseLong(i < 0 ? t : t.substring(0, i)); } catch (NumberFormatException e) { return -1; }
    }

    /** 1.7.3(U-5): 이번 부팅 진행이 끝난(run이 아닌) 시각(초). 이보다 앞선 알림은 지난 단계의 것이라 숨긴다. 없으면 0 */
    long progEndedAt(String boot) {
        // 리뷰 L7: 끝난 차(done)는 서비스가 부팅마다 "준비됨"을 다시 쓴다. 그 시각으로 숨기면 그 앞의 다른 안내(기능 파일 복구 뒤
        // 재부팅 안내 등)가 가려지므로, 진행이 재부팅 필요·실패로 끝났을 때만 숨긴다
        if (!progThisBoot(boot) || !("reboot".equals(get("state")) || "fail".equals(get("state")))) return 0;
        return num("t");
    }

    // --- 1.7.3(U-3): [지금 재부팅] ---
    static final String RB_CONFIRM = "차를 세운 상태에서만 누르세요. 화면이 1~2분 꺼졌다 켜집니다.";
    static final String RB_SENT = "재부팅합니다…";
    static final String RB_FAILED = "재부팅하지 못했습니다. RESET 버튼이나 NEMESIS 재부팅을 써 주세요.";
    /** 리뷰 M2: 설치 중·설치 마무리 중(root가 일부러 막음): RESET으로 막으려던 일을 하지 않게. 베타 1: 정말 마무리 중일 때만 */
    static final String RB_FINISHING = "설정을 마무리하는 중입니다. 잠시 뒤 다시 눌러 주세요.";
    /** 리뷰 M2: 요청이 늦게 닿았거나 이번 부팅의 새 요청으로 받지 못함(감시자는 있음) */
    static final String RB_RETRY = "재부팅 요청을 받지 못했습니다. 다시 눌러 주세요.";
    /** 베타 1 리뷰 3: 요청을 받을 감시자(Launch 뒤 10분)가 이미 끝났을 때. 요청을 보내지 않고 바로 보인다 */
    static final String RB_NOWATCH = "NEMESIS에서 Launch를 다시 누른 뒤 눌러 주세요.";

    /**
     * 베타 1 리뷰 3: 감시자가 끝났는가. text: root가 쓰는 감시자 파일(boot=…, until=부팅 뒤 초), upSec: 지금 부팅 뒤 초
     * (SystemClock.elapsedRealtime, 요청 파일과 같은 기준). 이번 부팅 것이 아니거나 읽지 못하면 끝난 것으로 본다(보내도 받을 쪽이 없음).
     * 끝나기 3초 전부터도 끝난 것으로 본다(요청을 받는 데 1초쯤 걸림)
     */
    static boolean watchGone(String text, String boot, long upSec) {
        Report w = parse(text);
        if (boot == null || boot.trim().isEmpty() || !boot.trim().equals(w.get("boot").trim())) return true;
        long until;
        try { until = Long.parseLong(w.get("until").trim()); } catch (NumberFormatException e) { return true; }
        return upSec + 3 >= until;
    }

    /**
     * 1.7.3(리뷰 M2): root 감시자가 남긴 재부팅 결과(res: id·boot·code)에서 내 요청(reqId)에 대한 안내. 이번 부팅의 내 요청이
     * 아니거나 아직 답이 없으면 null(계속 기다림). install·fix·sysw → RB_FINISHING, collect → RB_BUSY, old·bad → RB_RETRY,
     * guard(HMG-API 부팅 보호, 2분 전) → RB_GUARD,
     * cmd(재부팅 명령이 돌아옴)와 모르는 값 → RB_FAILED.
     * 베타 1(니로 차 확인 2026-11-11): root가 /system 쓰기 모드(rw)·"재부팅 필요가 아님"(state)으로 거절하던 조건을 뺐다.
     * 업데이트 직후 늘 rw라 "마무리하는 중"이 계속 나왔다. 이어진 거절 세기는 재리뷰 M2에서 install·sysw로 다시 두었다(아래 4인자)
     */
    static String rbAnswer(Report res, String boot, long reqId) {
        if (boot == null || boot.trim().isEmpty() || reqId <= 0) return null;
        if (!boot.trim().equals(res.get("boot").trim()) || !String.valueOf(reqId).equals(res.get("id").trim())) return null;
        String c = res.get("code").trim();
        if (c.isEmpty()) return null;
        if ("install".equals(c) || "fix".equals(c) || "sysw".equals(c)) return RB_FINISHING;
        if ("collect".equals(c)) return RB_BUSY;
        if ("old".equals(c) || "bad".equals(c)) return RB_RETRY;
        if ("guard".equals(c)) return RB_GUARD;
        return RB_FAILED;
    }

    /**
     * 베타 2 #64: root가 HMG-API 부팅 보호를 부추기지 않으려고 거절함(부팅 뒤 2분 전이고 HMG-API 시작 횟수가 2·3).
     * 시간이 지나면 풀리므로 이어진 거절 세기(rbStuckCode)에 넣지 않는다
     */
    // 10장 확인 리뷰 3: root 거절은 zygote 시각 + 135초(커널 줄 없으면 부팅 뒤 300초)까지라 "2~5분"
    static final String RB_GUARD = "2분 안에 재부팅을 반복하면 HMG-API가 무선 기능을 끕니다. 내비가 켜지고 2~5분 뒤에 다시 눌러 주세요.";

    /** 재리뷰 M2: 같은 이유(설치 중·바깥 /system 작업)로 이만큼 이어서 거절되면 그다음부터 RESET 안내로 넘긴다 */
    static final int RB_STUCK_MAX = 3;

    /** 오래 풀리지 않을 수 있는 거절(install 설치 중, sysw 바깥 /system 작업)인가. 우리 설치 마무리(fix)는 끝나면 풀리므로 넣지 않는다 */
    static boolean rbStuckCode(Report res) {
        String c = res.get("code").trim();
        return "install".equals(c) || "sysw".equals(c);
    }

    /**
     * 재리뷰 M2: stuckBefore는 바로 앞까지 이어진 install·sysw 거절 수. 이번도 그렇고 앞서 RB_STUCK_MAX번 넘게 이어졌으면
     * "잠시 뒤 다시" 대신 RESET 안내(RB_FAILED)를 준다(root 판단이 틀려 영영 막혀도 빠져나갈 길). 그 밖에는 rbAnswer와 같다
     */
    static String rbAnswer(Report res, String boot, long reqId, int stuckBefore) {
        String a = rbAnswer(res, boot, reqId);
        if (a != null && rbStuckCode(res) && stuckBefore >= RB_STUCK_MAX) return RB_FAILED;
        return a;
    }
    /**
     * 재리뷰 중간 2: [지금 재부팅]을 막는가. 진행 기록이 "만드는 중"(이번 부팅, run)이거나 내 제보 요청이 아직 기다리는 중
     * (myReqWaiting: REQ_FAIL초 안, 실패를 보이기 전)일 때만. 실패를 보인 뒤 늦은 진행을 기다리는 동안은 막지 않는다.
     */
    static boolean rbBusy(boolean myReqWaiting, Report rprog, String boot, long now) {
        return myReqWaiting || rprog.progRunning(boot, now);
    }

    /** 리뷰 M1: 제보 파일을 만드는 동안에는 재부팅을 막는다(root도 막지만, 앱에서 먼저 알린다) */
    static final String RB_BUSY = "제보 파일을 다 만든 뒤 눌러 주세요.";
    /** 요청 뒤 이만큼(초) 지나도 화면이 살아 있으면 재부팅하지 못한 것으로 본다(리뷰 L4: USB가 꽂혀 sync가 길 수 있어 넉넉히) */
    // 재리뷰 L2: root 쪽 최악(요청 나이 40초 + sync + 재부팅 명령 기다림 30초)보다 길게. 45초면 "못 했습니다" 뒤에 재부팅될 수 있었다
    static final long RB_WAIT = 80;

    /** progVerdict의 색: 재부팅 필요는 노랑(1), 실패는 빨강(2) */
    int progLevel() {
        return "fail".equals(get("state")) ? 2 : 1;
    }

    /** 훅이 꺼진 이유(HMG-API CarMap 상태)별 안내 */
    String hooksOffAdvice() {
        String m = get("hookmap");
        if ("mapped".equals(m))
            return "HMG-API 훅이 꺼져 있습니다. HMG-API 앱 Settings에서 'Check the map on this car'를 누른 뒤 내비를 재부팅해 주세요.";
        if ("none".equals(m))
            return "HMG-API에 이 차의 지도가 없어 훅이 꺼져 있습니다. QR로 제보해 주세요.";
        if ("mismatch".equals(m))
            return "HMG-API 지도가 이 차의 소프트웨어와 맞지 않아 훅이 꺼져 있습니다. QR로 제보해 주세요.";
        return "HMG-API 훅이 꺼져 있습니다(마지막 부팅 기록). 내비를 재부팅(RESET 버튼 또는 NEMESIS 재부팅)한 뒤 다시 확인해 주세요.";
    }

    /** status.sh의 hmgapi 값("version 1.0.2 build 180185d 2026-11-04")에서 버전만. 없으면 "" */
    String hmgapiVer() {
        String s = get("hmgapi");
        int i = s.indexOf("version ");
        if (i < 0) return "";
        String rest = s.substring(i + 8).trim();
        int sp = rest.indexOf(' ');
        return sp < 0 ? rest : rest.substring(0, sp);
    }

    /**
     * have가 need보다 낮은가: 0 아니요(같거나 높음), 1 낮음, 2 숫자로 읽지 못함.
     * 앞의 숫자 부분만 본다("1.0.0-beta.5"는 1.0.0). 빈 값도 2.
     */
    static int older(String have, String need) {
        int[] a = nums(have), b = nums(need);
        if (a == null || b == null) return 2;
        for (int i = 0; i < Math.max(a.length, b.length); i++) {
            int x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
            if (x != y) return x < y ? 1 : 0;
        }
        return 0;
    }

    private static int[] nums(String s) {
        if (s == null) return null;
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("^\\s*(\\d+(?:\\.\\d+)*)").matcher(s);
        if (!m.find()) return null;
        String[] p = m.group(1).split("\\.");
        int[] r = new int[p.length];
        try {
            for (int i = 0; i < p.length; i++) r[i] = Integer.parseInt(p[i]);
        } catch (NumberFormatException e) {
            return null;
        }
        return r;
    }

    /** 무선 모드 칸: 없음 / 꺼짐 / 켜짐(무선 카플레이 설정 꺼짐) / 켜짐. 예전 상태 파일(mod만 있음)도 읽는다 */
    private String modCell() {
        if (yes("mod_foreign")) return "한국 차용 아님 (지워야 함)";
        if ("no".equals(get("mod"))) return "없음 (필요)";
        if ("no".equals(get("mod_on"))) return "꺼짐 (켜야 함)";
        if ("off".equals(get("bridge"))) return "켜짐, Wireless CarPlay 설정 꺼짐";
        if ("off".equals(get("mod_hooks"))) return "켜짐, 훅이 안 켜짐 (리포트 참고)";
        if (yes("mod_on")) return "켜짐" + pendingNote();
        return yn("mod");
    }

    /** 1.7.1: 우리가 넣은 모드가 패키지의 새 판으로 바뀌기를 기다리는 중(부팅 약 2분 뒤 자동). 차의 판을 함께 보인다 */
    private String pendingNote() {
        if (!yes("mod_pending")) return get("modver").isEmpty() ? "" : " (" + get("modver") + ")";
        return " (" + (get("modver").isEmpty() ? "이전 판" : get("modver")) + ", 새 판으로 바꾸기 대기 중)";
    }

    /**
     * 1.7.1: 알림 기록(svc/hotspot.sh notice, 토스트 대신). 한 줄에 "<시각(초)> <부팅 id> <문구>".
     * 이번 부팅의 줄만, 새것부터 최대 max개. 돌려주는 값은 {시각(초), 문구}.
     * now·maxAge(초)를 주면 그보다 오래된 줄은 뺀다(지난 단계의 안내가 계속 남아 오해하지 않게, 리뷰 M3).
     */
    static List<String[]> notices(String text, String boot, int max) {
        return notices(text, boot, max, 0, 0);
    }

    static List<String[]> notices(String text, String boot, int max, long now, long maxAge) {
        return notices(text, boot, max, now, maxAge, 0);
    }

    /** 앞의 "Korea Projection: "을 뗀다(화면 위에 이미 이름이 있다, U-5) */
    static String plain(String msg) {
        String p = "Korea Projection: ";
        return msg.startsWith(p) ? msg.substring(p.length()).trim() : msg;
    }

    /**
     * 1.7.3(U-5): minT(초)를 주면 그보다 앞선 알림은 뺀다. 진행이 끝난 시각(progEndedAt)을 주면 "재부팅하지 마세요"(설치 중)와
     * "재부팅해 주세요"(설치 끝)가 함께 보이지 않는다.
     */
    static List<String[]> notices(String text, String boot, int max, long now, long maxAge, long minT) {
        List<String[]> out = new ArrayList<String[]>();
        if (text == null || boot == null || boot.isEmpty()) return out;
        String[] lines = text.split("\n");
        for (int i = lines.length - 1; i >= 0 && out.size() < max; i--) {
            String l = lines[i].trim();
            int a = l.indexOf(' ');
            int b = a < 0 ? -1 : l.indexOf(' ', a + 1);
            if (b < 0) continue;
            if (!boot.equals(l.substring(a + 1, b))) continue;
            String msg = plain(l.substring(b + 1).trim());
            if (msg.isEmpty()) continue;
            if (maxAge > 0 || minT > 0) {
                long t;
                try { t = Long.parseLong(l.substring(0, a)); } catch (NumberFormatException e) { continue; }
                if (maxAge > 0 && now - t > maxAge) continue;
                if (minT > 0 && t < minT) continue;
            }
            out.add(new String[] { l.substring(0, a), msg });
        }
        return out;
    }

    /** 1.7.2: 안내가 이만큼(초) 지나면 보이지 않는다(서비스도 10분 뒤 지운다. 서비스가 멈춰 남은 안내를 가리려고) */
    static final long HINT_SHOW = 600;

    /**
     * 1.7.2: 서비스(svc/hotspot.sh hint_write)가 30초마다 정하는 상태 안내(/data/local/tmp/korea-projection-hint.txt, key=value).
     * 이번 부팅의 것만 보인다. 돌려주는 값은 {수준(0 좋음·1 확인 필요), 문구, 시각(초, 문구 옆에 HH:MM로 붙일 때만, 아니면 "")}.
     * 확인이 필요한 것(설정 바뀜·아이폰·AA 안내)을 먼저, "준비됨·연결됨"은 뒤에 둔다. 문구는 내비 화면에서 읽기 좋게 한두 문장.
     */
    static List<String[]> hints(String text, String boot, long now) {
        List<String[]> out = new ArrayList<String[]>();
        Report h = parse(text);
        if (boot == null || boot.isEmpty() || !boot.trim().equals(h.get("boot"))) return out;
        if ("wait".equals(h.get("conf")))
            out.add(new String[] { "1", "Wi-Fi 설정이 바뀌었습니다. 카플레이 연결이 끝나면 핫스팟을 다시 시작합니다.", "" });
        if ("wifi".equals(h.get("iph")) && h.fresh("iph_t", now))
            out.add(new String[] { "1", "아이폰이 차 Wi-Fi에 오지 않습니다. 아이폰 설정 → Wi-Fi에서 차 네트워크를 지우고 다시 연결하세요.", "" });
        // 베타 1 리뷰 A: 우리 Wi-Fi에 기기는 붙었는데 카플레이가 60초 동안 안 열림. 아이폰인지 가릴 수 없어 "폰"이라고 쓴다
        if ("nocp".equals(h.get("iph")) && h.fresh("iph_t", now))
            out.add(new String[] { "1", "폰이 차 Wi-Fi에 연결됐지만 카플레이가 시작되지 않았습니다. 내비를 재부팅해 주세요.", "" });
        String aa = h.get("aa");
        boolean aaNow = h.fresh("aa_t", now);
        if ("bt".equals(aa) && aaNow)
            out.add(new String[] { "1", "안드로이드 폰의 블루투스를 껐다 켜 주세요(또는 내비 블루투스 화면에서 폰을 다시 연결).", "" });
        if ("cpwait".equals(aa) && aaNow)
            out.add(new String[] { "1", "카플레이가 연결되어 있어 안드로이드 오토는 기다립니다.", "" });
        // 베타 1(소유자 요청): 무선 안드로이드 오토 준비됨·연결됨은 따로 줄을 두지 않는다. 판정 줄(status.sh kp_verdict)이
        // 카플레이와 함께 한 줄로 말한다(예: "무선 카플레이·안드로이드 오토 준비됨"). 리포트·QR 요약과 같은 문구
        return out;
    }

    /** 숫자 값(초). 없거나 숫자가 아니면 0 */
    long num(String k) {
        try { return Long.parseLong(get(k)); } catch (NumberFormatException e) { return 0; }
    }

    /** 시각 k가 있고 HINT_SHOW초 안인가 */
    boolean fresh(String k, long now) {
        long t = num(k);
        return t > 0 && now - t <= HINT_SHOW;
    }

    // --- 1.7.3(R-2·R-5): [제보 파일 만들기] 버튼 ---
    // 앱은 일반 앱 권한이라 로그·USB를 직접 다루지 못한다. 그래서 요청 파일만 쓰고, root 쪽(status.sh 감시자 또는 서비스 점검)이
    // 받아 만든다. 진행은 지금처럼 RPROG(제보 저장 기록)로 보되, 자기 요청은 RPROG의 req·req2(요청 id)로 찾는다.
    // 시간은 부팅 뒤 경과(SystemClock.elapsedRealtime)로 잰다: 시계가 바뀌어도 "만드는 중"에 멈추지 않게(리뷰 중간 2).

    /** 요청 뒤 이만큼(초) 자기 진행이 안 보이면 "기다리는 중"으로 바꾼다 */
    static final long REQ_WAIT = 3;
    /** 요청 뒤 이만큼(초) 지나도 자기 진행이 안 보이면 실패로 본다(서비스 점검은 30초마다, status.sh 시작에 몇 초) */
    static final long REQ_FAIL = 120;
    /** 실패를 보인 뒤에도 이만큼(초)까지는 늦게 시작한 진행을 이어 보인다(감시자 10분과 같다) */
    static final long REQ_LATE = 600;
    static final String REQ_SENT = "제보 파일을 만드는 중입니다. USB를 빼지 마세요.";
    static final String REQ_WAITING = "요청을 기다리는 중입니다(길면 1분쯤).";
    static final String REQ_FAILED = "제보 파일을 만들지 못했습니다. NEMESIS에서 Launch를 다시 눌러 주세요.";
    static final String REQ_WRITE_FAILED = "요청을 저장하지 못했습니다. 내비를 재부팅한 뒤 다시 눌러 주세요.";

    /**
     * /proc/mounts 내용에서 USB(/storage/usb0·usb1)가 마운트돼 있는가. 읽지 못했으면(null) 모름(null)을 돌려준다:
     * 그때는 막지 않고 root 쪽(make_report가 USB를 다시 본다)에 맡긴다(리뷰 중간 5). 마운트 지점 폴더는 USB가 없어도 있을 수 있다.
     */
    static Boolean usbMounted(String mounts) {
        if (mounts == null) return null;
        for (String l : mounts.split("\n")) {
            String[] f = l.trim().split("\\s+");
            if (f.length > 1 && ("/storage/usb0".equals(f[1]) || "/storage/usb1".equals(f[1]))) return Boolean.TRUE;
        }
        return Boolean.FALSE;
    }

    /**
     * 요청 파일 내용: "<요청 id> <boot_id> <부팅 뒤 초>" 한 줄. id는 부팅 뒤 밀리초(숫자만), 부팅 뒤 초는 root가 오래된 요청을
     * 버리는 데 쓴다. 다른 값(이름·주소)은 넣지 않는다.
     */
    static String reqLine(long elapsedMs, String boot) {
        return elapsedMs + " " + (boot == null ? "" : boot.trim()) + " " + (elapsedMs / 1000) + "\n";
    }

    /** 요청 파일에서 {요청 id, 부팅 뒤 밀리초}. 이번 부팅의 요청이 아니거나 읽지 못하면 null */
    static long[] reqParse(String text, String boot) {
        if (text == null || boot == null || boot.trim().isEmpty()) return null;
        String[] f = text.trim().split("\\s+");
        if (f.length < 3 || !boot.trim().equals(f[1])) return null;
        try {
            long id = Long.parseLong(f[0]);
            Long.parseLong(f[2]);
            return id < 0 ? null : new long[] { id, id };
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /**
     * 버튼을 지금 누를 수 없는 이유(누를 수 있으면 null). prog: 설치 진행 기록, rprog: 제보 저장 기록,
     * usb: USB가 꽂혀 있는가(null이면 모름: 막지 않음). 설치 중에 만든 리포트는 판정이 틀린다(#114·#115).
     */
    static String reqBlock(Report prog, Report rprog, String boot, long now, Boolean usb) {
        if (boot == null || boot.trim().isEmpty()) return "내비 상태를 읽지 못했습니다. NEMESIS에서 Launch를 다시 눌러 주세요.";
        if (prog.progRunning(boot, now)) return "설치가 끝난 뒤 눌러 주세요.";
        if (rprog.progRunning(boot, now)) return "제보 파일을 만드는 중입니다. 끝날 때까지 기다려 주세요.";
        if (Boolean.FALSE.equals(usb)) return "USB를 꽂은 뒤 다시 눌러 주세요.";
        return null;
    }

    /** 이 진행 기록이 그 요청의 것인가(이번 부팅, req 또는 req2가 요청 id) */
    boolean forReq(String boot, String reqId) {
        return reqId != null && !reqId.isEmpty() && progThisBoot(boot) && (reqId.equals(get("req")) || reqId.equals(get("req2")));
    }

    /**
     * 요청 뒤 화면 단계. rprog: 제보 저장 기록, reqId: 요청 id, waited: 요청 뒤 지난 초(부팅 뒤 경과로 잼).
     * 0: 자기 요청의 진행이 보임(진행 막대를 따라간다), 1: 막 보냄(REQ_WAIT초 안), 2: 기다리는 중, 3: 실패(REQ_FAIL초 지남).
     * waited가 음수면(잴 수 없음) 1로 본다(부르는 쪽이 시작 시각을 다시 잡는다).
     */
    static int reqPhase(Report rprog, String boot, String reqId, long waited) {
        if (rprog.forReq(boot, reqId)) return 0;
        if (waited < 0) return 1;
        if (waited >= REQ_FAIL) return 3;
        if (waited >= REQ_WAIT) return 2;
        return 1;
    }

    /** 버전 칸: 값 옆에 필요 조건을 붙인다 */
    private static String ver(String have, String need) {
        if (have == null || have.isEmpty()) return "없음 (" + need + " 이상 필요)";
        int o = older(have, need);
        if (o == 1) return have + " (지원 안 함, " + need + " 이상 필요)";
        if (o == 2) return have + " (버전 확인 안 됨, " + need + " 이상 필요)";
        return have;
    }

    /** 화면 왼쪽 표: {제목, 값}. 필요한 것(버전·모드·훅)을 위에 둔다 */
    List<String[]> rows() {
        List<String[]> out = new ArrayList<String[]>();
        if (nobb()) {
            out.add(new String[] { "내비 소프트웨어", get("product") });
            out.add(new String[] { "내비 종류(플랫폼)", get("platform") });
            out.add(new String[] { "Korea Projection", get("pkgver") });
            out.add(new String[] { "지원", "아직 안 됨 (이 내비 종류는 조사 중)" });
            out.add(new String[] { "무선 설정", "하지 않았습니다 (차의 파일을 바꾸지 않음)" });
            out.add(new String[] { "제보 파일", usbCell() });
            return out;
        }
        out.add(new String[] { "내비 소프트웨어", get("product") });
        out.add(new String[] { "확인된 차", yn("tested") });
        out.add(new String[] { "Korea Projection", get("pkgver") });
        out.add(new String[] { "HMG-API", ver(hmgapiVer(), MIN_HMGAPI) });
        out.add(new String[] { "HMG-API 무선 모드", modCell() });
        String h = get("hooks");
        out.add(new String[] { "HMG-API 훅", "on".equals(h) ? "켜짐" : "off".equals(h) ? "꺼짐 (" + (get("hookmap").isEmpty() ? "?" : get("hookmap")) + ", 마지막 부팅 기록)" : "-" });
        out.add(new String[] { "NEMESIS", ver(get("nemesis"), MIN_NEMESIS) });
        out.add(new String[] { "무선 카플레이 기능", yn("feat_carplay") });
        // 1.7.0: 우리 무선 AA 설정(aa=yes 기본, no면 USB kp-aa-off로 끔). 줄 수는 그대로 둔다
        String aa = get("aa");
        out.add(new String[] { "무선 안드로이드 오토 기능", yn("feat_aa") + ("yes".equals(aa) ? " · 켜짐" : "no".equals(aa) ? " · 꺼짐(kp-aa-off)" : "") });
        out.add(new String[] { "Wi-Fi 장치", yn("wlan0") });
        String am = get("ap_mode");
        if (!am.isEmpty())
            out.add(new String[] { "무선 카플레이 Wi-Fi", "stock".equals(am) ? "내비 순정 Wi-Fi" : "ours".equals(am) ? "Korea Projection 핫스팟" : "없음" });
        out.add(new String[] { "핫스팟 (hostapd)", yn("our_ap") + (stockAp() ? " (순정 Wi-Fi를 쓰므로 꺼 둠)" : "") });
        out.add(new String[] { "IP 나눠 주기 (DHCP)", yn("our_dhcp") });
        out.add(new String[] { "순정 핫스팟", yn("other_ap") });
        out.add(new String[] { "카플레이 연결", get("cp_conn") + "개" });
        out.add(new String[] { "wireless.projection", yn("wp") + " (필요 없음)" });
        return out;
    }

    private String yn(String k) {
        String s = v.get(k);
        if ("yes".equals(s)) return "예";
        if ("no".equals(s)) return "아니요";
        return s == null ? "-" : s;
    }

    /**
     * QR에 담을 제보 링크. GitHub 이슈 양식은 항목 id로 미리 채울 수 있다(title, product, report).
     * report는 영문 key: value로 짧게 쓴다(한글은 링크에서 9배로 길어진다). 링크가 MAX_URL을 넘으면
     * 뒤쪽 줄부터 뺀다.
     */
    String issueUrl() {
        // 중요한 것부터: 링크가 길면 뒤에서부터 뺀다 (product는 제목·항목에 따로 들어간다)
        String[] keys = { "support", "state", "platform", "targetdir", "pkgver", "tested", "feat_carplay", "ap_mode", "our_ap", "our_dhcp", "other_ap", "stock_ssid", "stock_seen",
            "cp_conn", "aa", "nowlan", "wlan0", "softap_strings", "ssid_len", "pass_len", "wp", "mod", "mod_on", "bridge", "hooks", "hookmap", "feat_aa", "feat_wifi",
            "wpa", "hmgapi", "nemesis", "made", "modver" };
        List<String> lines = new ArrayList<String>();
        lines.add("(QR summary)");
        for (String k : keys) if (v.containsKey(k)) lines.add(k + ": " + v.get(k));
        // mod_foreign은 yes일 때만(링크 길이를 아낀다), 앞쪽에 넣는다
        if (yes("mod_foreign")) lines.add(1, "mod_foreign: yes");
        // 1.7.1: 모드 업데이트 대기도 yes일 때만 앞쪽에(리포트를 새 판 전에 만들었다는 표시)
        if (yes("mod_pending")) lines.add(1, "mod_pending: yes (" + get("modver") + ")");
        // 1.7.2: 무선 모드 훅이 안 켜졌으면 앞쪽에
        if ("off".equals(get("mod_hooks"))) lines.add(1, "mod_hooks: off");
        // 1.7.3(K-5): 판정 결과(상태 화면·리포트와 같은 값)를 앞쪽에. U-10: 확인 안 된 차가 연결됐으면 맨 앞에 result: connected
        if (!get("verdict").isEmpty()) lines.add(1, "verdict: " + get("verdict"));
        if ("newconnected".equals(get("verdict")) || "connected".equals(get("verdict"))) lines.add(1, "result: connected");
        String url = build(lines);
        while (url.length() > MAX_URL && lines.size() > 2) {
            lines.remove(lines.size() - 1);
            url = build(lines);
        }
        return url;
    }

    private String build(List<String> lines) {
        StringBuilder body = new StringBuilder();
        for (String l : lines) body.append(l).append('\n');
        String product = get("product");
        return ISSUES + "&title=" + enc("차량 제보: " + product) + "&product=" + enc(product)
            + "&report=" + enc(body.toString());
    }

    /**
     * 한 변 side 픽셀 안에 QR(칸 qrSize개 + 양쪽 여백 4칸)을 정수 픽셀 칸으로 넣는 크기: {칸 픽셀, 가장자리 여백}.
     * 칸이 1px보다 작아지면 1px로 둔다(그 화면에서는 어차피 찍기 어렵다).
     */
    static int[] fit(int side, int qrSize) {
        int n = qrSize + 8;
        int scale = Math.max(1, side / n);
        int off = Math.max(0, (side - scale * n) / 2);
        return new int[] { scale, off };
    }

    static String enc(String s) {
        try {
            return URLEncoder.encode(s, "UTF-8").replace("+", "%20");
        } catch (UnsupportedEncodingException e) {
            throw new IllegalStateException(e);
        }
    }
}
