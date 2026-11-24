package korea.projection.app;

import java.util.ArrayList;
import java.util.List;

/**
 * 1.8.0(SC-2·SC-6): 상태 화면의 판단(색·문구·토글 상태·숨길 줄 고르기)과 직접 그린 위젯의 도형 계산.
 * 안드로이드 없이 PC에서 시험하는 순수 계산이다(tests/UiTest.java). 그리는 쪽은 Widgets.java.
 * 익명 클래스·람다를 쓰지 않는다(JDK 21 + d8 8.2가 익명 클래스에서 멈춘 적이 있음).
 */
final class Ui {
    private Ui() { }

    // --- 색(설계 3장: 지금 값을 잇는다) ---
    static final int BG = 0xFF121212, GOOD = 0xFF2E7D32, WARN = 0xFFF9A825, BAD = 0xFFC62828;
    /** 요약 값 글자색(시안): 좋음·주의·나쁨 */
    static final int INK_GOOD = 0xFF8BC34A, INK_WARN = 0xFFF9A825, INK_BAD = 0xFFEF5350;
    static final int INK = 0xFFFFFFFF, INK_DIM = 0xFF9E9E9E, INK_DESC = 0xFFA0A0A0, INK_FAINT = 0xFF808080;
    /** 토글 줄 바탕(평소·누름), 버튼 바탕(평소·누름)과 테두리 */
    static final int ROW = 0xFF1D1D1D, ROW_PRESS = 0xFF2C2C2C, BTN = 0xFF2B2B2B, BTN_PRESS = 0xFF3D3D3D, BTN_EDGE = 0xFF555555;
    /** 토글 트랙: 꺼짐, 적용 중, 원 색 */
    static final int TRACK_OFF = 0xFF555555, TRACK_BUSY = 0xFF6D5A12, KNOB = 0xFFFFFFFF, KNOB_OFF = 0xFFDDDDDD;
    /** 알림 바탕(노랑 글자를 얹음) */
    static final int NOTE_BG = 0xFF2A2410;
    /** 포커스 테두리(조그 다이얼·방향키로 고른 버튼) */
    static final int FOCUS = 0xFFF9A825;

    /** 판정 수준(0 좋음, 1 주의, 2 나쁨) → 바탕색 */
    static int levelColor(int lv) {
        return lv <= 0 ? GOOD : lv == 1 ? WARN : BAD;
    }

    /** 수준에 맞는 글자색: 노랑 바탕 위에는 검정 */
    static int levelInk(int lv) {
        return lv == 1 ? 0xFF000000 : INK;
    }

    /**
     * 1.8.0: "먼저 할 일" 줄의 수준. 상태 파일 first_lv(1 주의, 2 오류). 빈 값·옛 상태 파일은 지금처럼 주의(노랑).
     * K-5 "내비 업데이트 먼저"는 패키지가 1을 쓴다(소유자 결정 11-18: 잘 될 수도 있으니 노랑).
     */
    static int firstLevel(Report r) {
        return "2".equals(r.get("first_lv").trim()) ? 2 : 1;
    }

    /** 패키지가 변조 검사에 걸렸다고 판정했는가(status.sh kp_verdict: verdict=tampered, 빨강) */
    static boolean tampered(Report r) {
        return "tampered".equals(r.get("verdict").trim());
    }

    /** 요약 줄 "이름: 값"을 {이름, 값}으로. ": "이 없으면 {"", 줄 전체} */
    static String[] kv(String line) {
        int i = line.indexOf(": ");
        return i < 0 ? new String[] { "", line } : new String[] { line.substring(0, i), line.substring(i + 2) };
    }

    /** 요약 값의 색(시안의 tone): 끝남·켜짐·연결됨 초록, 진행 중·필요·대기 노랑, 안 됨 빨강, 그 밖은 흰색 */
    static int tone(String v) {
        if (v.contains("안 됨") || v.contains("없음(") || v.contains("켜지지 않음") || v.contains("안 보임")) return INK_BAD;
        if (v.contains("진행 중") || v.contains("필요") || v.contains("켜는 중") || v.contains("대기") || v.contains("확인 중")
            || v.contains("꺼짐")) return INK_WARN;
        if (v.contains("끝남") || v.contains("켜짐") || v.contains("연결됨")) return INK_GOOD;
        return INK;
    }

    /**
     * 판·차 정보 6줄(상태 파일에 이미 있는 값만, 비밀정보 없음): {이름, 값}. 값이 없으면 "-".
     * 넣지 않는 것: SSID·비밀번호·폰 이름·MAC·IP·VIN(CLAUDE.md 5장).
     */
    static List<String[]> info(Report r) {
        List<String[]> out = new ArrayList<String[]>();
        out.add(new String[] { "Korea Projection", dash(r.get("pkgver")) });
        out.add(new String[] { "무선 모드", dash(r.get("modver")) });
        String h = r.hmgapiVer();
        out.add(new String[] { "HMG-API", dash(h) });
        out.add(new String[] { "NEMESIS", dash(r.get("nemesis")) });
        String p = r.get("product").trim();
        int dot = p.indexOf('.');
        out.add(new String[] { "차종", dash(dot > 0 ? p.substring(0, dot) : p) });
        out.add(new String[] { "핫스팟", hotspot(r) });
        return out;
    }

    static String dash(String s) {
        return s == null || s.trim().isEmpty() ? "-" : s.trim();
    }

    /** 핫스팟 줄: 순정 AP 차는 "내비 순정", 우리 핫스팟이면 켜짐·꺼짐 */
    static String hotspot(Report r) {
        if ("stock".equals(r.get("ap_mode"))) return "내비 순정";
        if (r.get("our_ap").isEmpty()) return "-";
        return r.yes("our_ap") ? "우리 핫스팟 켜짐" : "우리 핫스팟 꺼짐";
    }

    // --- 대기 알림 ---

    /**
     * 재부팅해야 반영되는 바꾼 설정 수(상태 파일 set_pending, 제안 키: drafts/1.8.0-work/app.md). 없거나 0이면 "".
     */
    static String pendingNotice(Report r) {
        int n;
        try { n = Integer.parseInt(r.get("set_pending").trim()); } catch (NumberFormatException e) { n = 0; }
        return n > 0 ? "바꾼 설정 " + n + "개는 재부팅 뒤 적용됩니다." : "";
    }

    /** 소유자 결정(11-18): 옛 내비(확인된 판보다 오래됨)여도 설치·동글은 막지 않고 이 안내만 노랑으로 보인다 */
    static final String NAV_OLD_MSG = "내비 업데이트를 권합니다. 호환되지 않을 수 있습니다.";

    /**
     * 상태 파일 dongle_oldnav=yes이면 옛 내비 안내. 같은 뜻의 "먼저 할 일"(K-5·G-4 내비 업데이트)이 이미 보이면 겹치지 않게 비운다.
     * 키가 없거나 yes가 아니면(no·옛 패키지 포함) 아무것도 보이지 않는다.
     */
    static String navOldNotice(Report r) {
        if (!"yes".equals(r.get("dongle_oldnav").trim())) return "";
        String f = r.firstTodo();
        if (f.contains("내비") && f.contains("업데이트")) return "";
        return NAV_OLD_MSG;
    }

    // --- 토글 줄 ---

    static final int OFF = 0, ON = 1, UNKNOWN = 2;
    /** 토글 줄의 종류: 보통 토글, 기본 기능("항상 켜짐", 누를 수 없음) */
    static final int KIND_TOGGLE = 0, KIND_ALWAYS = 1;

    static final String LOCK_INSTALL = "설치가 끝난 뒤 바꿀 수 있습니다.";
    static final String LOCK_TAMPER = "변조된 버전이라 바꿀 수 없습니다.";
    static final String TAG_SOON = "준비 중";
    /** 1.8.0 정식(소유자 11-25): 무선 모드 기본값으로 켜져 있지만 앱에서 바꿀 수 없는 줄의 딱지("준비 중"이면 꺼진 것으로 오해함) */
    static final String TAG_INUSE = "사용 중";
    /** "사용 중" 줄: 켜짐 모양으로 그리고 누를 수 없다(무선 모드 기본값 tbt_fit·now_playing 켬) */
    static final String[] INUSE_KEYS = new String[] { "tbt", "np" };
    static final String TAG_REBOOT = "재부팅 필요";
    static final String BUSY = "적용 중입니다.";

    /** 화면에 그릴 토글 줄 하나. 그리는 쪽은 이 값만 본다 */
    static final class Row {
        String key, title;
        int kind = KIND_TOGGLE;
        /** 켬·끔·모름 */
        int state = UNKNOWN;
        /** 누를 수 있는가 */
        boolean enabled;
        /** 적용 중(원은 가운데, "…") */
        boolean busy;
        /** 제목 옆 딱지("준비 중"·"사용 중"·"재부팅 필요", 없으면 "") */
        String tag = "";
        /** 설명 줄(한 줄, 넘치면 자름). 실패·잠금·적용 중이면 그 문구로 바뀐다 */
        String desc = "";
        int descColor = INK_DESC;
        /** 고정 안내 줄(빈 값이 아니면 늘 보이고 자르지 않고 줄바꿈한다). 지금은 동글 포트 안내(DG_PORT) */
        String pinned = "";
        /** 상태 줄(예: "자동으로 켜짐, 31시간 뒤 꺼짐"). 없으면 "" */
        String note = "";
        /** 그룹 제목(이 줄 앞에 새 묶음이 시작되면 그 이름, 아니면 "") */
        String group = "";

        /** 다른 줄의 값을 모두 옮긴다(같은 뷰를 새 상태로 다시 그릴 때) */
        void copy(Row o) {
            key = o.key; title = o.title; kind = o.kind; state = o.state; enabled = o.enabled; busy = o.busy;
            tag = o.tag; desc = o.desc; descColor = o.descColor; pinned = o.pinned; note = o.note; group = o.group;
        }

        /** 토글 옆 글자: 켬·끔, 적용 중 "…", 모름 "—" */
        String label() {
            if (kind == KIND_ALWAYS) return "항상 켜짐";
            if (busy) return "…";
            return state == ON ? "켬" : state == OFF ? "끔" : "—";
        }
    }

    /**
     * 디버그 로그 줄의 상태 문구. debug=yes|no, debug_auto=none|on|wait|done|off|user, debug_left=남은 시간(시간 단위).
     * 남은 시간은 root가 정한다(앱은 시계를 믿지 않는다: 부팅 직후 2016년일 수 있음).
     * user(베타 2): 차주가 설치 USB의 korea-projection-debug 파일이나 화면 토글로 켬. 48시간 뒤에도 저절로 꺼지지 않는다.
     */
    static final String DEBUG_USER = "켜짐(직접 켬)";

    static String debugNote(Report r) {
        String d = r.get("debug").trim(), a = r.get("debug_auto").trim();
        if (d.isEmpty()) return "";
        if ("yes".equals(d) && "on".equals(a)) {
            int left;
            try { left = Integer.parseInt(r.get("debug_left").trim()); } catch (NumberFormatException e) { left = -1; }
            // 남은 시간을 모르면(시계가 아직 맞지 않음) "자동으로 켜짐"만(오케스트레이터 확인 11-18)
            return left > 0 ? "자동으로 켜짐, " + left + "시간 뒤 꺼짐" : "자동으로 켜짐";
        }
        if ("yes".equals(d) && "user".equals(a)) return DEBUG_USER;
        if ("wait".equals(a) && !"yes".equals(d)) return "곧 48시간 동안 자동으로 기록합니다."; // 베타 3(L4): 설치 말고도 여러 이유로 켜지므로 "설치 뒤"를 뺐다
        return "";
    }

    /**
     * 설정 칸의 줄들. busyKey: 적용 중인 줄(없으면 null), failKey·failMsg: 바꾸지 못한 줄과 그 문구,
     * live: 앱이 요청을 보낼 수 있는 키(지금은 없음: 요청 형식 확인 뒤 "debug"를 넣는다. SC-3·SC-4).
     * 설치 중·변조된 판이면 모든 토글을 막는다.
     */
    static List<Row> rows(Report r, boolean installing, String busyKey, String failKey, String failMsg, String[] live) {
        List<Row> out = new ArrayList<Row>();
        Row base = new Row();
        base.key = "base"; base.kind = KIND_ALWAYS; base.group = "기본 기능"; base.state = ON;
        base.title = "무선 프로젝션";
        base.desc = "이 패키지의 기본 기능입니다.";
        out.add(base);

        // X-8: 디버그 로그만 기본 끔, 나머지는 켬. 계기판·곡 정보는 무선 모드 기본값으로 켜져 있어 켬으로 그린다(소유자 11-25, 누를 수 없음)
        out.add(row("tbt", "부가 기능", "계기판·HUD (TBT) 안내", "길안내 그림을 계기판과 HUD에 보냅니다.", ON));
        out.add(row("np", "", "음악 정보 보내기", "재생 중인 음악 정보를 계기판·미디어 화면에 보냅니다.", ON));

        String d = r.get("debug").trim();
        // 베타 3(소유자 11-23): 고정 경고를 뺐고 설명을 새 문구로 바꿨다
        Row dbg = row("debug", "고급", "디버그 로그", "정교한 지원을 위해 더 세세하게 정보를 저장합니다.",
            "yes".equals(d) ? ON : "no".equals(d) ? OFF : UNKNOWN);
        dbg.note = debugNote(r);
        out.add(dbg);

        // 자동 업데이트 끔 = mod.pin(고정한 판)이 있음. 옛 상태 파일(키 없음)이면 모름
        int au = r.v.containsKey("mod_pin") ? (r.get("mod_pin").trim().isEmpty() ? ON : OFF) : UNKNOWN;
        out.add(row("autoupd", "", "무선 모드 자동 업데이트", "새 무선 모드로 자동으로 바꿉니다. 끄면 지금 버전에 머뭅니다.", au));
        out.add(dongleRow(r));

        boolean tamper = tampered(r);
        for (Row x : out) {
            if (x.kind == KIND_ALWAYS) continue;
            // 동글은 패키지가 자동 판단 키(dongle_set)를 쓸 때만 누를 수 있다(베타 1 패키지면 그대로 "준비 중")
            boolean inUse = contains(INUSE_KEYS, x.key);
            boolean can = !inUse && contains(live, x.key) && (!"dongle".equals(x.key) || r.v.containsKey(DG_SET));
            if (inUse) x.tag = TAG_INUSE;
            else if (!can) x.tag = TAG_SOON;
            // 잠금 문구는 늘 보통 색(동글 문제의 노랑·빨강을 물려받지 않게, 리뷰 낮음 3)
            if (tamper) { x.desc = LOCK_TAMPER; x.descColor = INK_DESC; can = false; }
            else if (installing) { x.desc = LOCK_INSTALL; x.descColor = INK_DESC; can = false; }
            if (x.key.equals(busyKey)) { x.busy = true; x.desc = BUSY; x.descColor = INK_WARN; can = false; }
            else if (busyKey != null) can = false;
            if (x.key.equals(failKey) && failMsg != null) { x.desc = failMsg; x.descColor = INK_BAD; }
            if (x.state == UNKNOWN && !x.busy) can = false;
            x.enabled = can;
        }
        return out;
    }

    // --- 동글 토글(베타 2, 소유자 결정 11-18 밤: 자동으로 정하고 차주가 바꾸면 그 선택이 먼저) ---
    // 상태 키(제안, 패키지 세션이 확정): dongle=<상태>(off면 지금 동글을 쓰지 않음, 이미 있음),
    // dongle_set=auto|on|off(자동 판단 또는 차주 선택), dongle_why=nochip|builtin_bad|builtin_ok|nodongle(자동 판단 이유),
    // dongle_lv·dongle_msg(문제 문구, 이미 있음)

    static final String DG_SET = "dongle_set", DG_WHY = "dongle_why";
    static final String DG_PORT = "USB 포트가 하나인 차는 동글을 쓰는 동안 유선 연결을 함께 쓸 수 없습니다.";
    static final String DG_AUTO_NOCHIP = "Wi-Fi 부품이 없어 자동으로 켰습니다.";
    static final String DG_AUTO_BAD = "내장 Wi-Fi가 안 되어 자동으로 켰습니다.";
    static final String DG_AUTO_ON = "자동으로 켰습니다.";
    static final String DG_AUTO_OK = "내장 Wi-Fi가 잘 되어 자동으로 껐습니다.";
    static final String DG_AUTO_NODONGLE = "허용 동글이 없어 자동으로 껐습니다.";
    static final String DG_AUTO_OFF = "자동으로 껐습니다.";
    static final String DG_USER_ON = "직접 켠 설정을 따릅니다.";
    static final String DG_USER_OFF = "직접 끈 설정을 따릅니다.";
    static final String DG_SET_OK = "동글 설정을 바꿨습니다. 재부팅하면 적용됩니다.";
    /** 베타 3(B3-2): 꽂기를 기다리는 중에 끄면 패키지가 그 부팅에 바로 돌린다(dongle_wait=yes). 부품 없는 차도 맞게 "어디로"는 말하지 않는다 */
    static final String DG_SET_NOW = "동글 사용을 껐습니다. 바로 적용됩니다.";
    // 문구는 "재부팅하면 적용됩니다": 부팅 뒤 약 120초 안에 바꾸면 패키지가 같은 부팅에서 정리하므로 "뒤"라고 못 박지 않는다(11-18 밤)
    /** 차주가 고른 값을 지우고 자동 판단으로 돌아가는 버튼(dongle=auto, 소유자 결정 11-18 밤) */
    static final String DG_AUTO_BTN = "자동으로 되돌리기";
    static final String DG_AUTO_DONE = "자동으로 되돌렸습니다. 재부팅하면 적용됩니다.";

    /**
     * "자동으로 되돌리기" 버튼: 0 숨김, 1 보이되 누를 수 없음, 2 누를 수 있음.
     * 차주가 고른 값(dongle_set=on|off)일 때만 보이고(자동이면 숨김), 누를 수 있는 때는 동글 줄과 같다(적용 중·설치 중·변조면 막힘).
     */
    static int dongleAutoBtn(Report r, Row dongle) {
        String set = r.get(DG_SET).trim();
        if (!"on".equals(set) && !"off".equals(set)) return 0;
        return dongle != null && dongle.enabled ? 2 : 1;
    }

    /** 되돌리기 성공을 상태 값에 반영한다(재부팅 전에도 버튼이 숨고 "직접" 표시가 사라지게) */
    static void applyAuto(Report r) {
        r.v.put(DG_SET, "auto");
    }

    /** 되돌리기 결과 문구 {문구, "ok" 또는 ""} */
    static String[] autoResult(String code) {
        if ("ok".equals(code)) return new String[] { DG_AUTO_DONE, "ok" };
        if ("busy".equals(code)) return new String[] { SET_BUSY, "" };
        return new String[] { SET_FAILED, "" };
    }

    /** 지금 동글을 쓰는가: dongle 키가 off면 끔, 다른 값이면 켬, 없으면(옛 상태 파일) 모름 */
    static int dongleNow(Report r) {
        String s = r.get("dongle").trim();
        if (s.isEmpty()) return UNKNOWN;
        return "off".equals(s) ? OFF : ON;
    }

    /**
     * 동글 줄. 토글은 차가 따를 값: 차주가 고른 값(dongle_set=on|off)이 있으면 그것, 자동이면 지금 쓰는지(dongle).
     * 고른 값이 아직 적용되지 않았으면 "재부팅 필요" 딱지. 문제(dongle_lv 1·2)는 설명 자리에 노랑·빨강으로.
     */
    static Row dongleRow(Report r) {
        String set = r.get(DG_SET).trim();
        int now = dongleNow(r);
        int want = "on".equals(set) ? ON : "off".equals(set) ? OFF : now;
        Row dg = row("dongle", "", "USB Wi-Fi 동글 사용", "켜면 내비 Wi-Fi 대신 지원 목록의 동글만 씁니다.", want);
        dg.pinned = donglePinned(r);
        dg.note = dongleNote(set, want, r.get(DG_WHY).trim());
        // 베타 3(B3-2): 꽂기 기다림 중에 끈 것은 그 부팅에 바로 적용되므로 "재부팅 필요"를 달지 않는다
        boolean nowOff = want == OFF && dongleWait(r);
        if (now != UNKNOWN && want != UNKNOWN && want != now && !nowOff) dg.tag = TAG_REBOOT;
        String msg = r.get("dongle_msg").trim();
        String lv = r.get("dongle_lv").trim();
        if (!msg.isEmpty() && ("1".equals(lv) || "2".equals(lv))) {
            dg.desc = msg;
            dg.descColor = "2".equals(lv) ? INK_BAD : INK_WARN;
        }
        return dg;
    }

    /** 베타 3(B3-2): 지금 끄면 그 부팅에 바로 적용되는가(패키지 dongle_wait=yes, 꽂기 기다림 중). 키가 없으면(옛 패키지) 아니라고 본다 */
    static boolean dongleWait(Report r) {
        return "yes".equals(r.get("dongle_wait").trim());
    }

    /**
     * 동글 줄의 고정 안내(자르지 않고 줄바꿈). 패키지 안내(dongle_note, 쓰는 중·기다리는 중)가 있으면 함께 보인다.
     * 꽂기 기다림 중(dongle_wait=yes)의 안내는 포트 안내와 같은 뜻(유선을 못 씀)이라 그것만 보인다.
     */
    static String donglePinned(Report r) {
        String n = r.get("dongle_note").trim();
        if (n.isEmpty()) return DG_PORT;
        return dongleWait(r) ? n : DG_PORT + " " + n;
    }

    /** 자동·직접 표시와 이유 한 줄(한 문장). 자동 판단 키가 없으면(옛 패키지) "" */
    static String dongleNote(String set, int want, String why) {
        if ("on".equals(set)) return DG_USER_ON;
        if ("off".equals(set)) return DG_USER_OFF;
        if (!"auto".equals(set) || want == UNKNOWN) return "";
        if (want == ON) return "nochip".equals(why) ? DG_AUTO_NOCHIP : "builtin_bad".equals(why) ? DG_AUTO_BAD : DG_AUTO_ON;
        return "builtin_ok".equals(why) ? DG_AUTO_OK : "nodongle".equals(why) ? DG_AUTO_NODONGLE : DG_AUTO_OFF;
    }

    static Row row(String key, String group, String title, String desc, int state) {
        Row x = new Row();
        x.key = key; x.group = group; x.title = title; x.desc = desc; x.state = state;
        return x;
    }

    static boolean contains(String[] a, String k) {
        if (a == null) return false;
        for (String s : a) if (s.equals(k)) return true;
        return false;
    }

    // --- 설정 요청(SC-3, drafts/1.8.0-work/app.md 제안 A, 오케스트레이터 승인 2026-11-18) ---

    /** 앱 개인 폴더의 요청 파일 이름. root 쪽(status.sh 감시자·hotspot.sh req_tick)과 같아야 한다 */
    static final String SET_NAME = "settings.req";
    /** root가 쓰는 답(644, 비밀 없음): id·boot·key·code·val */
    static final String SET_RES = "/data/local/tmp/korea-projection-settings-result.txt";
    /** 답을 기다리는 최대 시간(초): 서비스 점검 30초 + 여유. 그동안 다른 요청은 막는다 */
    static final int SET_WAIT = 45;
    /** 앱이 보낸 요청을 따로 기억하는 파일(요청 파일과 같은 한 줄). root가 요청 파일을 가져가도 늦은 답을 다음에 열 때 맞춰 본다 */
    static final String SET_LAST = "settings.last";
    /** 늦은 답을 다음에 화면을 열 때 보여 주는 최대 시간(초). 그보다 오래된 기억은 지운다 */
    static final int SET_LATE = 600;
    // 실패 이유는 한 문장(오케스트레이터 승인 조건, 리뷰 2 중간 3)
    static final String SET_FAILED = "바꾸지 못해 원래대로 두었습니다(3분 후 재부팅한 뒤 다시 해 주세요).";
    static final String SET_BUSY = "지금은 바꿀 수 없어 원래대로 두었습니다(잠시 뒤 다시 눌러 주세요).";
    static final String SET_WRITE_FAILED = "요청을 저장하지 못해 원래대로 두었습니다(재부팅한 뒤 다시 눌러 주세요).";
    /** 45초 안에 답이 없지만 root가 요청을 이미 가져간 때: 바뀌었는지 모른다(리뷰 2 높음 1) */
    static final String SET_UNKNOWN = "결과를 아직 받지 못했습니다(Launch를 다시 누르면 확인됩니다).";
    static final String DEBUG_CLEARED = "디버그 기록을 지웠습니다.";
    static final String DEBUG_ON = "디버그 로그를 켰습니다. 다음 재부팅부터 기록합니다.";

    /**
     * 요청 한 줄: "<요청 id> <boot_id> <부팅 뒤 초> <키>=<on|off>". 앞 세 칸은 report.req와 같다(Report.reqLine).
     * 이름·주소·SSID 같은 값은 넣지 않는다.
     */
    static String settingsLine(long elapsedMs, String boot, String key, boolean on) {
        return settingsLine(elapsedMs, boot, key, on ? "on" : "off");
    }

    /** 값 글자 그대로(on·off, 동글만 auto: "자동으로 되돌리기", 소유자 결정 11-18 밤) */
    static String settingsLine(long elapsedMs, String boot, String key, String val) {
        String base = Report.reqLine(elapsedMs, boot).trim();
        return base + " " + key + "=" + val + "\n";
    }

    /** 요청 파일에서 {키, 값}. 넷째 칸이 없거나 꼴이 다르면 null(앞 세 칸은 Report.reqParse로 본다) */
    static String[] settingsKv(String text) {
        if (text == null) return null;
        String[] f = text.trim().split("\\s+");
        if (f.length < 4) return null;
        int i = f[3].indexOf('=');
        if (i <= 0) return null;
        String v = f[3].substring(i + 1), k = f[3].substring(0, i);
        boolean auto = "auto".equals(v) && "dongle".equals(k);
        if (!"on".equals(v) && !"off".equals(v) && !auto) return null;
        return new String[] { k, v };
    }

    /** 답 파일이 이 요청(id·boot·key)의 것이면 code(ok·bad·busy·fail), 아니면 null */
    static String settingsAnswer(Report res, String boot, long id, String key) {
        if (res == null || res.empty() || boot == null) return null;
        if (!boot.trim().equals(res.get("boot").trim())) return null;
        if (!String.valueOf(id).equals(res.get("id").trim())) return null;
        if (!key.equals(res.get("key").trim())) return null;
        String c = res.get("code").trim();
        // 리뷰 2 높음 2: 정해진 값만 답으로 본다(반쯤 쓰인 파일·모르는 값이면 계속 기다림)
        return "ok".equals(c) || "bad".equals(c) || "busy".equals(c) || "fail".equals(c) ? c : null;
    }

    /** 답의 val(on·off)이 있으면 그것, 없으면 보낸 값(리뷰 2 낮음 8: 문구와 토글이 같은 값을 말하게) */
    static boolean settingValue(Report res, boolean sent) {
        String val = res == null ? "" : res.get("val").trim();
        return "on".equals(val) ? true : "off".equals(val) ? false : sent;
    }

    /**
     * 답(또는 시간 지남: code null)에 따라 보일 문구. ok면 바꾼 뒤 값, 아니면 원래대로 둔 이유 한 문장.
     * 돌려주는 값 {문구, "ok" 또는 ""}.
     */
    static String[] settingsResult(String code, String key, boolean on) {
        return settingsResult(code, key, on, false);
    }

    /** dgWait: 요청을 보낼 때 꽂기 기다림 중이었는가(dongleWait). 그때 끈 것은 "바로 적용됩니다" */
    static String[] settingsResult(String code, String key, boolean on, boolean dgWait) {
        if ("ok".equals(code)) {
            if ("debug".equals(key)) return new String[] { on ? DEBUG_ON : DEBUG_CLEARED, "ok" };
            if ("dongle".equals(key)) return new String[] { !on && dgWait ? DG_SET_NOW : DG_SET_OK, "ok" };
            return new String[] { "", "ok" };
        }
        if ("busy".equals(code)) return new String[] { SET_BUSY, "" };
        return new String[] { SET_FAILED, "" };
    }

    /**
     * 성공한 바꾸기를 상태 값에 반영한다(root가 상태 파일을 다시 쓰기 전에도 줄이 맞게). 답의 val이 있으면 그것을 믿는다.
     * 디버그를 끄면 자동 켜짐도 끝난 것으로(debug_auto=off) 본다(패키지 debug_set off와 같음).
     */
    static void applySetting(Report r, String key, boolean on, Report res) {
        boolean v = settingValue(res, on);
        if ("debug".equals(key)) {
            r.v.put("debug", v ? "yes" : "no");
            if (!v) { r.v.put("debug_auto", "off"); r.v.put("debug_left", ""); }
            // 패키지 debug_set on은 자동 표시를 지우므로 상태가 user(직접 켬)가 된다. 앱도 같게 맞춘다
            else { r.v.put("debug_auto", "user"); r.v.put("debug_left", ""); }
        }
        // 동글: 차주의 선택으로 기록(재부팅 전까지 dongle은 그대로라 줄에 "재부팅 필요"가 붙는다)
        if ("dongle".equals(key)) r.v.put(DG_SET, "auto".equals(res == null ? "" : res.get("val").trim()) ? "auto" : v ? "on" : "off");
    }

    // --- 토글 도형(Layout의 u 기준, 시안 .tg) ---

    /** 트랙 폭·높이와 원 지름(px). 트랙 9u×5u, 원 4u. 누르는 높이 안에 들어가게 자른다 */
    static int[] toggleSize(Layout l) {
        int th = Math.max(16, Math.min(Math.round(5f * l.u), l.touch - 8));
        int tw = Math.round(th * 1.8f);
        int knob = Math.max(10, Math.round(th * 0.8f));
        return new int[] { tw, th, knob };
    }

    /**
     * 원의 왼쪽 x(트랙 안). 켜짐은 오른쪽 끝, 꺼짐은 왼쪽 끝, 적용 중·모름은 가운데.
     * 켜짐·꺼짐을 색만으로 가르지 않는다(설계 3장): 원 위치 + "켬"·"끔" 글자.
     */
    static int knobX(int trackX, int tw, int th, int knob, int state, boolean busy) {
        int m = (th - knob) / 2;
        if (busy || state == UNKNOWN) return trackX + (tw - knob) / 2;
        return state == ON ? trackX + tw - m - knob : trackX + m;
    }

    // --- 상태 칸의 줄 고르기 ---

    /**
     * 위에서부터 쌓는 칸에서 넘치면 낮은 순위부터 숨긴다. heights: 각 줄의 높이(간격 포함), prio: 클수록 남김
     * (Integer.MAX_VALUE는 숨기지 않음), avail: 쓸 수 있는 높이. 같은 순위면 아래 줄부터 숨긴다.
     * 돌려주는 값: 보일 줄 표시.
     */
    static boolean[] fit(int[] heights, int[] prio, int avail) {
        int n = heights.length;
        boolean[] show = new boolean[n];
        int total = 0;
        for (int i = 0; i < n; i++) { show[i] = true; total += heights[i]; }
        while (total > avail) {
            int pick = -1;
            for (int i = n - 1; i >= 0; i--) {
                if (!show[i] || prio[i] == Integer.MAX_VALUE) continue;
                if (pick < 0 || prio[i] < prio[pick]) pick = i;
            }
            if (pick < 0) break;
            show[pick] = false;
            total -= heights[pick];
        }
        return show;
    }

    /** 상태 칸 줄의 순위(fit의 prio). 판·차 정보가 가장 먼저 숨고, 먼저 할 일·버튼·저장 표시는 숨기지 않는다 */
    static final int P_INFO = 10, P_ENDHINT = 20, P_NOTICE = 30, P_HINT = 40, P_PENDING = 45, P_SUMMARY = 50, P_KEEP = Integer.MAX_VALUE;

    /** 묶음 제목 높이(Widgets.Group과 같은 식): 위 여백 1.2u + 작은 글자 한 줄 */
    static int groupHeight(Layout l) {
        return Math.round(1.2f * l.u + l.textSmall * Layout.LINE);
    }

    /** 설명 한 줄짜리 토글 줄 높이(Widgets.ToggleRow와 같은 식): 위아래 0.8u + 제목 + 설명, 누르는 높이 이상 */
    static int rowHeight(Layout l) {
        return Math.max(l.touch, Math.round(1.6f * l.u + l.textBody * Layout.LINE + l.textSmall * Layout.LINE));
    }

    /**
     * QR 먼저 배치에서 설정 칸에 남겨 둘 높이: 첫 묶음 제목 + 토글 줄 하나(리뷰 중간 3: 누르는 높이만 남기면 묶음 제목에 밀려
     * 첫 줄도 다 보이지 않았음). 상태 칸은 아래 칸 높이에서 이것과 간격을 뺀 만큼만 쓴다.
     */
    static int settingsMin(Layout l) {
        return groupHeight(l) + Math.round(0.7f * l.gap) + rowHeight(l);
    }

    // --- 설정 칸 스크롤 막대(소유자 결정 11-18: 800×480에서 설정 부분을 스크롤로) ---

    /** 스크롤 막대 색: 길(어두운 회색)과 손잡이(밝은 회색). 기본 Holo 막대는 가늘어 차에서 보이지 않아 직접 그린다 */
    static final int SCROLL_TRACK = 0xFF2B2B2B, SCROLL_THUMB = 0xFF9E9E9E;

    /** 스크롤 막대 폭(px): 1.2u, 최소 8px(차 화면에서 보이게) */
    static int scrollBarWidth(Layout l) {
        return Math.max(8, Math.round(1.2f * l.u));
    }

    /**
     * 손잡이 위치를 out = {위, 길이}(px)에 쓴다. view: 보이는 높이, content: 내용 높이, y: 스크롤 위치. 내용이 다 보이면 false(막대 없음).
     * 손잡이는 minLen보다 짧아지지 않는다(긴 목록에서도 보이게). 그리기 중에 불리므로 새 배열을 만들지 않는다.
     */
    static boolean scrollThumb(int view, int content, int y, int minLen, int[] out) {
        if (view <= 0 || content <= view) return false;
        int len = Math.max(Math.min(view, minLen), (int) ((long) view * view / content));
        int range = content - view;
        int yy = Math.max(0, Math.min(range, y));
        int top = (int) ((long) (view - len) * yy / range);
        out[0] = top;
        out[1] = len;
        return true;
    }

    // --- 재부팅 확인 창(소유자 결정 11-18: AlertDialog 대신 이 화면 모양으로 직접 그림, "취소"가 기본) ---

    static final String RB_ASK = "재부팅할까요?";
    static final String RB_CANCEL = "취소", RB_OK = "재부팅";
    /** 창 뒤를 어둡게 */
    static final int CONFIRM_DIM = 0xCC000000;
    /** 창을 연 뒤 이 시간(ms) 안에 누른 "재부팅"은 받지 않는다("지금 재부팅"을 두 번 눌러 바로 재부팅되지 않게) */
    static final long CONFIRM_ARM_MS = 700;

    /** 창 안쪽 여백 */
    static int confirmPad(Layout l) {
        return Math.max(l.gap, Math.round(2f * l.u));
    }

    /** 창 폭: 화면 폭의 55%와 본문 글자 20자 중 큰 것, 화면 안 */
    static int confirmWidth(Layout l) {
        return Math.max(0, Math.min(l.width - 2 * l.pad, Math.max(Math.round(l.textBody * 20f), l.width * 11 / 20)));
    }

    /** 버튼 높이: 누르는 높이의 1.2배(차에서 누르기 쉽게) */
    static int confirmButton(Layout l) {
        return Math.round(l.touch * 1.2f);
    }

    /** 창 높이: 여백 + 제목 한 줄 + 문구 lines줄 + 버튼 */
    static int confirmHeight(Layout l, int lines, int titlePx) {
        int p = confirmPad(l);
        return 2 * p + Math.round(titlePx * Layout.LINE) + l.gap + Math.round(lines * l.textBody * Layout.LINE) + 2 * l.gap + confirmButton(l);
    }

    // --- 흐르는 글자(상태 줄, 소유자 결정 2026-11-16) ---

    /** 처음 멈춤(ms) */
    static final long MARQUEE_HOLD = 1500;

    /**
     * 흐르는 글자의 왼쪽 이동량(px). t: 시작 뒤 ms, speed: px/s(높이의 14%), loop: 문구 폭 + 간격.
     * 처음 MARQUEE_HOLD 동안 0, 그 뒤 loop만큼 흐르고 다시 멈춤부터 되풀이한다.
     */
    static float marqueeShift(long t, float speed, float loop) {
        if (t < 0 || speed <= 0 || loop <= 0) return 0;
        long run = (long) (loop * 1000f / speed);
        long cycle = MARQUEE_HOLD + run;
        long p = t % cycle;
        return p < MARQUEE_HOLD ? 0 : (p - MARQUEE_HOLD) * speed / 1000f;
    }

    // ---- 1.8.0 베타 2: 결과 화면이 앞에 있는 동안 상태 파일이 바뀌면 다시 그린다(소유자 제보 11-23: Launch를 다시 눌러야 문구가 바뀜)
    /** 다시 그릴지 보는 간격(밀리초). 한 번 바뀐 것을 본 뒤 다음 틱에도 같으면 그린다(쓰는 중인 파일을 읽지 않게, 몰아 쓰기를 한 번에) */
    static final int STAT_POLL_MS = 1000;
    static final int REDRAW_NONE = 0, REDRAW_WAIT = 1, REDRAW_NOW = 2;

    /**
     * 상태·안내·알림 파일 내용의 지문. 내용이 같으면(다시 썼어도) 같은 값이다. 수정 시각은 옛 내비에서 초 단위라 내용으로 본다.
     * 없는 파일(null)과 빈 파일은 다르게 친다.
     */
    static long statSig(String status, String hint, String notice) {
        long h = 17;
        h = h * 1000003L + (status == null ? -1 : status.hashCode());
        h = h * 1000003L + (hint == null ? -1 : hint.hashCode());
        h = h * 1000003L + (notice == null ? -1 : notice.hashCode());
        return h;
    }

    /**
     * 한 틱의 판단. shown: 화면을 그린 때의 지문, seen: 지난 틱에 본 지문, cur: 지금 지문,
     * busy: 지금 다시 그리면 안 되는 때(확인 창·설정 기다림·재부팅 기다림·제보 저장·손가락으로 끄는 중).
     * 같으면 NONE, 이번에 처음 바뀐 것을 보면 WAIT(seen만 고침), 두 틱 같은 새 값이면 NOW. busy면 바뀐 것을 기억만 하고 기다린다.
     */
    /**
     * 다시 그린 뒤 그 전의 "바꾸지 못함" 이유를 되살릴까. old: 그 전 이유의 키, lateDone: 다시 그리며 늦은 답을 처리함,
     * nowFail·pending: 다시 그린 뒤의 실패 키·기다리는 요청 키. 새 화면이 스스로 정한 것(늦은 답의 결과, 이어 기다림)이 먼저다.
     */
    static boolean keepFail(String old, boolean lateDone, String nowFail, String pending) {
        return old != null && !lateDone && nowFail == null && pending == null;
    }

    static int redrawStep(long shown, long seen, long cur, boolean busy) {
        if (cur == shown) return REDRAW_NONE;
        if (cur != seen || busy) return REDRAW_WAIT;
        return REDRAW_NOW;
    }
}
