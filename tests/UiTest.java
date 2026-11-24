package korea.projection.app;

import java.util.List;

/**
 * 1.8.0(SC-2·SC-6): 상태 화면의 판단(Ui)과 여섯 크기(계획의 다섯 해상도 + 1920×660)에서의 배치를 PC에서 시험한다. 안드로이드 없이 돈다.
 * 글자 폭은 PC 추정이다(한글 한 글자 = 글자 크기의 0.95배, 영문·숫자 0.55배). 차의 글꼴로 잰 것이 아니다.
 * 실패하면 "FAIL ..."을 찍고 종료 코드 1.
 * 돌리는 법: javac -encoding UTF-8 -d 출력폴더 Report.java QrCode.java Layout.java Ui.java tests/UiTest.java
 *            java -cp 출력폴더 korea.projection.app.UiTest
 */
public class UiTest {
    static int fails = 0;
    static final int QR = 89;
    /** 설계 7장·계획 SC-1의 PC 시험 크기 + 상태 막대 가정(1920×660) */
    static final int[][] SIZES = { { 800, 480 }, { 1024, 600 }, { 1280, 480 }, { 1280, 720 }, { 1920, 720 }, { 1920, 660 } };

    static void check(String name, boolean ok) {
        System.out.println((ok ? "ok   " : "FAIL ") + name);
        if (!ok) fails++;
    }

    static final String BASE =
        "product=DEPEHEV.KOR.0000.V039.001.260902\npkgver=1.8.0\nmodver=2.4.5\nhmgapi=version 1.0.2 build 180185d 2026-11-04\n"
        + "nemesis=1.16.7\nour_ap=yes\nap_mode=ours\nmod_pin=\ndebug=no\ndebug_auto=none\n"
        + "verdict=ready\nverdict_lv=0\nverdict_msg=무선 카플레이·안드로이드 오토 준비됨.\n"
        + "s1=설치: 끝남\ns2=무선 Wi-Fi: 켜짐\ns3=폰 연결: 지금 연결된 폰 없음\n";

    static Report rep(String extra) {
        return Report.parse(BASE + extra);
    }

    static Ui.Row find(List<Ui.Row> rows, String key) {
        for (Ui.Row r : rows) if (key.equals(r.key)) return r;
        return null;
    }

    /** 글 폭 추정(px): 한글 등 넓은 글자 0.95, 그 밖 0.55 */
    static float width(String s, float size) {
        float w = 0;
        for (int i = 0; i < s.length(); i++) w += s.charAt(i) >= 0x1100 ? 0.95f : 0.55f;
        return w * size;
    }

    /** 폭 w에 들어가는 줄 수(추정) */
    static int lines(String s, float size, float w) {
        if (s.isEmpty()) return 0;
        return Math.max(1, (int) Math.ceil(width(s, size) / Math.max(1f, w)));
    }

    /** 바탕이 있는 작은 글 묶음(먼저 할 일·알림)의 높이: 줄 수 × 줄 높이 + 위아래 0.8u */
    static int block(Layout l, String s, int w) {
        float inner = w - 2 * 1.4f * l.u;
        return Math.round(lines(s, l.textSmall, inner) * l.textSmall * Layout.LINE + 1.6f * l.u);
    }

    /**
     * 상태 칸을 Widgets.Column과 같은 규칙으로 쌓아 본다(높이는 추정). 돌려주는 값: {쓴 높이, 쓸 수 있는 높이, 숨긴 판·차 정보 수,
     * 버튼 보임(1/0), 먼저 할 일 보임(1/0)}.
     */
    static int[] column(Layout l, String first, String[] notices, boolean saving) {
        return column(l, first, notices, saving, "", "", "");
    }

    /** pending: 대기 알림, hint: 서비스 안내, save: 저장·재부팅 안내 줄 문구(빈 값이면 저장 중 문구) */
    static int[] column(Layout l, String first, String[] notices, boolean saving, String pending, String hint, String save) {
        boolean wide = l.kind == Layout.WIDE;
        int w = wide ? l.infoWidth : l.settingsWidth;
        int gap = Math.round(0.7f * l.gap);
        java.util.List<Integer> h = new java.util.ArrayList<Integer>(), p = new java.util.ArrayList<Integer>();
        int kvB = Math.round(l.textBody * Layout.LINE), kvS = Math.round(l.textSmall * Layout.LINE);
        for (int i = 0; i < 3; i++) { h.add(kvB + gap); p.add(Ui.P_SUMMARY); }
        int infoStart = h.size();
        if (wide) for (int i = 0; i < 6; i++) { h.add(kvS + gap); p.add(Ui.P_INFO); }
        int firstAt = -1;
        if (!first.isEmpty()) { firstAt = h.size(); h.add(block(l, first, w) + gap); p.add(Ui.P_KEEP); }
        if (!hint.isEmpty()) { h.add(block(l, hint, w) + gap); p.add(Ui.P_HINT); }
        for (String n : notices) { h.add(block(l, n, w) + gap); p.add(Ui.P_NOTICE); }
        if (!pending.isEmpty()) { h.add(block(l, pending, w) + gap); p.add(Ui.P_PENDING); }
        if (saving) {
            h.add(block(l, save.isEmpty() ? "제보 자료 저장 중 40% · 로그 모으기 (USB를 빼지 마세요)" : save, w) + gap); p.add(Ui.P_KEEP);
            h.add(Math.round(1.4f * l.u) + gap); p.add(Ui.P_KEEP);
        }
        boolean vert = wide || l.buttonsStacked;
        int btnAt = h.size();
        h.add((vert ? 2 * l.touch + l.gap : l.touch) + gap); p.add(Ui.P_KEEP);
        int[] hh = new int[h.size()], pp = new int[h.size()];
        for (int i = 0; i < hh.length; i++) { hh[i] = h.get(i); pp[i] = p.get(i); }
        int avail = wide ? l.bodyHeight : Math.max(0, l.bodyHeight - Ui.settingsMin(l) - l.gap);
        boolean[] show = Ui.fit(hh, pp, avail + gap);
        int used = 0, hid = 0;
        for (int i = 0; i < hh.length; i++) {
            if (show[i]) used += hh[i];
            else if (i >= infoStart && i < infoStart + 6 && wide) hid++;
        }
        return new int[] { used - gap, avail, hid, show[btnAt] ? 1 : 0, firstAt < 0 || show[firstAt] ? 1 : 0 };
    }

    public static void main(String[] a) {
        // ---- 색·문구
        check("수준 색: 0 초록, 1 노랑(검정 글자), 2 빨강",
            Ui.levelColor(0) == Ui.GOOD && Ui.levelColor(1) == Ui.WARN && Ui.levelColor(2) == Ui.BAD && Ui.levelInk(1) == 0xFF000000 && Ui.levelInk(2) == Ui.INK);
        check("K-5 먼저 할 일(first_lv=1) → 주의(노랑)", Ui.firstLevel(rep("first=먼저 할 일: 내비 버전이…\nfirst_lv=1\n")) == 1);
        check("first_lv 없음(옛 상태 파일) → 지금처럼 노랑", Ui.firstLevel(rep("first=먼저 할 일: …\n")) == 1);
        check("first_lv=2 → 빨강", Ui.firstLevel(rep("first_lv=2\n")) == 2);
        // 소유자 결정(11-18): 옛 내비는 막지 않고 노랑 안내만
        check("옛 내비 dongle_oldnav=yes → 안내 문구", Ui.NAV_OLD_MSG.equals(Ui.navOldNotice(rep("dongle_oldnav=yes\n"))));
        check("dongle_oldnav 없음·no·1(옛 패키지·다른 값) → 안내 없음", Ui.navOldNotice(rep("")).isEmpty() && Ui.navOldNotice(rep("dongle_oldnav=no\n")).isEmpty() && Ui.navOldNotice(rep("dongle_oldnav=1\n")).isEmpty());
        check("먼저 할 일이 이미 내비 업데이트면 겹치지 않음",
            Ui.navOldNotice(rep("dongle_oldnav=yes\nfirst=먼저 할 일: 내비 버전이 확인된 차(260902)보다 구버전입니다. 내비를 업데이트한 뒤 다시 설치해 주세요.\nfirst_lv=1\n")).isEmpty());
        check("다른 먼저 할 일(ADB TCP)과는 함께 보임", Ui.NAV_OLD_MSG.equals(Ui.navOldNotice(rep("dongle_oldnav=yes\nfirst=먼저 할 일: ADB TCP가 켜져 있습니다.\n"))));
        check("옛 내비 문구는 두 문장 이하·짧게", Ui.NAV_OLD_MSG.length() <= 40 && Ui.NAV_OLD_MSG.split("\\.").length <= 2);
        Report tam = Report.parse(BASE.replace("verdict=ready", "verdict=tampered").replace("verdict_lv=0", "verdict_lv=2")
            .replace("verdict_msg=무선 카플레이·안드로이드 오토 준비됨.", "verdict_msg=변조된 Korea Projection입니다. 지우고 공식 안내대로 다시 설치해 주세요."));
        check("변조 판정 → 빨강 상태 줄, 문구 그대로", Ui.tampered(tam) && tam.level() == 2 && tam.verdict().startsWith("변조된 Korea Projection입니다"));
        check("요약 값 색: 끝남·켜짐·연결됨 초록", Ui.tone("끝남") == Ui.INK_GOOD && Ui.tone("켜짐") == Ui.INK_GOOD && Ui.tone("카플레이 1대 연결됨") == Ui.INK_GOOD);
        check("요약 값 색: 진행 중·꺼짐 노랑, 안 됨 빨강", Ui.tone("진행 중") == Ui.INK_WARN && Ui.tone("꺼짐") == Ui.INK_WARN
            && Ui.tone("안 됨(위 안내를 보세요)") == Ui.INK_BAD && Ui.tone("장치가 켜지지 않음(확인 중)") == Ui.INK_BAD);
        check("요약 줄 나누기", "설치".equals(Ui.kv("설치: 끝남")[0]) && "끝남".equals(Ui.kv("설치: 끝남")[1]) && "".equals(Ui.kv("이름없음")[0]));

        List<String[]> info = Ui.info(rep(""));
        StringBuilder all = new StringBuilder();
        for (String[] x : info) all.append(x[0]).append('=').append(x[1]).append('\n');
        check("판·차 정보 6줄(Korea Projection·무선 모드·HMG-API·NEMESIS·차종·핫스팟)", info.size() == 6
            && "1.8.0".equals(info.get(0)[1]) && "2.4.5".equals(info.get(1)[1]) && "1.0.2".equals(info.get(2)[1]) && "DEPEHEV".equals(info.get(4)[1]));
        Report sec = rep("ssid=비밀SSID\nphone=내폰이름\nmac=aa:bb:cc:dd:ee:ff\nvin=KNAXXXXXXXX\nip=192.168.0.2\n");
        StringBuilder all2 = new StringBuilder();
        for (String[] x : Ui.info(sec)) all2.append(x[1]);
        check("판·차 정보에 SSID·폰 이름·MAC·VIN·IP가 들어가지 않음", !all2.toString().contains("비밀SSID") && !all2.toString().contains("내폰이름")
            && !all2.toString().contains("aa:bb") && !all2.toString().contains("KNA") && !all2.toString().contains("192.168"));
        check("핫스팟: 순정 AP 차 → 내비 순정", "내비 순정".equals(Ui.hotspot(Report.parse("ap_mode=stock\n"))));
        check("값 없음 → '-'", "-".equals(Ui.info(Report.parse("pkgver=1.8.0\n")).get(1)[1]));

        check("대기 알림: set_pending=2 → 문구, 없으면 빈 값", "바꾼 설정 2개는 재부팅 뒤 적용됩니다.".equals(Ui.pendingNotice(rep("set_pending=2\n")))
            && Ui.pendingNotice(rep("")).isEmpty() && Ui.pendingNotice(rep("set_pending=x\n")).isEmpty());

        // ---- 디버그 로그 줄
        check("자동 켜짐 + 남은 시간 → '자동으로 켜짐, 31시간 뒤 꺼짐'",
            "자동으로 켜짐, 31시간 뒤 꺼짐".equals(Ui.debugNote(rep("debug=yes\ndebug_auto=on\ndebug_left=31\n"))));
        Report auto = Report.parse(BASE.replace("debug=no\ndebug_auto=none", "debug=yes\ndebug_auto=on"));
        check("자동 켜짐인데 남은 시간 모름(debug_left 빈 값) → '자동으로 켜짐'만(앱이 계산하지 않음)", "자동으로 켜짐".equals(Ui.debugNote(auto))
            && "자동으로 켜짐".equals(Ui.debugNote(rep("debug=yes\ndebug_auto=on\ndebug_left=\n"))) && "자동으로 켜짐".equals(Ui.debugNote(rep("debug=yes\ndebug_auto=on\ndebug_left=x\n"))));
        check("직접 켬(debug_auto=user) → '켜짐(직접 켬)', 남은 시간은 보이지 않음",
            "켜짐(직접 켬)".equals(Ui.debugNote(rep("debug=yes\ndebug_auto=user\n")))
            && "켜짐(직접 켬)".equals(Ui.debugNote(rep("debug=yes\ndebug_auto=user\ndebug_left=31\n"))));
        check("베타 3(L4): 자동 켜짐 기다림(wait) → '곧 48시간 동안 자동으로 기록합니다.'(설치 뒤라고 하지 않음), 켜져 있으면 그 문구 아님",
            "곧 48시간 동안 자동으로 기록합니다.".equals(Ui.debugNote(rep("debug=no\ndebug_auto=wait\n"))) && !Ui.debugNote(rep("debug=no\ndebug_auto=wait\n")).contains("설치")
            && "".equals(Ui.debugNote(rep("debug=yes\ndebug_auto=wait\n"))));
        check("user인데 켜기 표시가 없으면(debug=no) 상태 줄 없음", Ui.debugNote(rep("debug=no\ndebug_auto=user\n")).isEmpty());
        check("차주가 끔·끝남·자동 없음 → 상태 줄 없음",
            Ui.debugNote(rep("")).isEmpty() && Ui.debugNote(Report.parse(BASE.replace("debug_auto=none", "debug_auto=off"))).isEmpty());

        String[] none = new String[0];
        List<Ui.Row> rows = Ui.rows(rep(""), false, null, null, null, none);
        Ui.Row dbg = find(rows, "debug");
        check("디버그 로그 줄(베타 3): 고급 묶음, 기본 끔, 고정 경고 없음, 새 설명", dbg != null && dbg.state == Ui.OFF && "고급".equals(dbg.group)
            && "디버그 로그".equals(dbg.title) && dbg.pinned.isEmpty() && "정교한 지원을 위해 더 세세하게 정보를 저장합니다.".equals(dbg.desc)
            && "끔".equals(dbg.label()));
        check("디버그 로그 켜짐 → '켬', 원 오른쪽", find(Ui.rows(auto, false, null, null, null, none), "debug").state == Ui.ON
            && "켬".equals(find(Ui.rows(auto, false, null, null, null, none), "debug").label()));
        check("debug 키 없음(옛 상태 파일) → '끔'이 아니라 모름, 누를 수 없음",
            find(Ui.rows(Report.parse("pkgver=1.7.4\n"), false, null, null, null, new String[] { "debug" }), "debug").state == Ui.UNKNOWN
            && !find(Ui.rows(Report.parse("pkgver=1.7.4\n"), false, null, null, null, new String[] { "debug" }), "debug").enabled
            && "—".equals(find(Ui.rows(Report.parse("pkgver=1.7.4\n"), false, null, null, null, none), "debug").label()));
        // 베타 3: 고정 경고는 적용 중·실패·설치 중·변조·모름 어느 때도 다시 나타나지 않는다
        boolean pinOk = true;
        Report[] rs = { rep(""), auto, tam, Report.parse("pkgver=1.7.4\n") };
        for (Report r : rs) {
            for (int k = 0; k < 4; k++) {
                List<Ui.Row> x = Ui.rows(r, k == 1, k == 2 ? "debug" : null, k == 3 ? "debug" : null, k == 3 ? "바꾸지 못했습니다." : null, new String[] { "debug" });
                Ui.Row d = find(x, "debug");
                if (d == null || !d.pinned.isEmpty() || d.pinned.contains("개인정보")) pinOk = false;
            }
        }
        check("디버그 고정 경고는 모든 상태에서 없음(적용 중·실패·설치 중·변조·옛 상태 파일)", pinOk);

        check("요청을 보낼 수 없는 토글 → 누를 수 없음, 디버그는 '준비 중' 딱지", allLocked(rows) && Ui.TAG_SOON.equals(dbg.tag));
        // 1.8.0 베타 1 문구 점검: 토글 줄 설명은 존댓말 한두 문장
        boolean descOk = true;
        for (Ui.Row x : rows) {
            int n = x.desc.split("[.?!]\\s*").length;
            if (n < 1 || n > 2 || !x.desc.endsWith("니다.")) descOk = false;
        }
        check("토글 줄 설명: 존댓말('~니다.'), 한두 문장", descOk);
        List<Ui.Row> live = Ui.rows(rep(""), false, null, null, null, new String[] { "debug" });
        check("요청 길이 생기면(debug) 디버그 줄만 누를 수 있고 딱지 없음", find(live, "debug").enabled && find(live, "debug").tag.isEmpty()
            && !find(live, "tbt").enabled);
        List<Ui.Row> busy = Ui.rows(rep(""), false, "debug", null, null, new String[] { "debug", "autoupd" });
        check("적용 중 → 그 줄 '…'·'적용 중입니다.', 다른 토글도 막힘", find(busy, "debug").busy && "…".equals(find(busy, "debug").label())
            && Ui.BUSY.equals(find(busy, "debug").desc) && !find(busy, "autoupd").enabled);
        List<Ui.Row> fail = Ui.rows(rep(""), false, null, "debug", "바꾸지 못했습니다. 원래대로 두었습니다.", new String[] { "debug" });
        check("실패 → 설명이 실패 문구(빨강), 토글은 원래 값", "바꾸지 못했습니다. 원래대로 두었습니다.".equals(find(fail, "debug").desc)
            && find(fail, "debug").descColor == Ui.INK_BAD && find(fail, "debug").state == Ui.OFF && find(fail, "debug").enabled);
        List<Ui.Row> inst = Ui.rows(rep(""), true, null, null, null, new String[] { "debug" });
        check("설치 중 → 모든 토글 막힘, '설치가 끝난 뒤 바꿀 수 있습니다.'", allLocked(inst) && Ui.LOCK_INSTALL.equals(find(inst, "debug").desc));
        List<Ui.Row> tr = Ui.rows(tam, false, null, null, null, new String[] { "debug" });
        check("변조된 판 → 모든 토글 막힘", allLocked(tr) && Ui.LOCK_TAMPER.equals(find(tr, "debug").desc));
        check("기본 기능 줄: 항상 켜짐, 누를 수 없음", "항상 켜짐".equals(rows.get(0).label()) && !rows.get(0).enabled && "기본 기능".equals(rows.get(0).group));
        check("자동 업데이트: mod_pin 빈 값 → 켬", find(rows, "autoupd").state == Ui.ON);
        Report pin = Report.parse(BASE.replace("mod_pin=\n", "mod_pin=2.4.5\n"));
        check("자동 업데이트: 고정한 판이 있으면 끔", find(Ui.rows(pin, false, null, null, null, none), "autoupd").state == Ui.OFF
            && find(Ui.rows(Report.parse("pkgver=1.7.4\n"), false, null, null, null, none), "autoupd").state == Ui.UNKNOWN);
        check("계기판·곡 정보: '사용 중' 딱지, 켬(ON) 모양, 누를 수 없음(소유자 11-25), 동글 '준비 중'",
            find(rows, "tbt").state == Ui.ON && find(rows, "np").state == Ui.ON
            && Ui.TAG_INUSE.equals(find(rows, "tbt").tag) && Ui.TAG_INUSE.equals(find(rows, "np").tag)
            && "켬".equals(find(rows, "tbt").label()) && !find(rows, "tbt").enabled && !find(rows, "np").enabled
            && Ui.TAG_SOON.equals(find(rows, "dongle").tag) && "사용 중".equals(Ui.TAG_INUSE));
        // 요청 길이 있다고 해도(live에 tbt·np) 누를 수 없고 '사용 중' 그대로. 자동 업데이트는 '준비 중' 그대로
        List<Ui.Row> inUseLive = Ui.rows(rep(""), false, null, null, null, new String[] { "debug", "tbt", "np" });
        check("계기판·곡 정보: live에 있어도 '사용 중'·누를 수 없음, 자동 업데이트는 '준비 중'",
            !find(inUseLive, "tbt").enabled && !find(inUseLive, "np").enabled
            && Ui.TAG_INUSE.equals(find(inUseLive, "tbt").tag) && Ui.TAG_INUSE.equals(find(inUseLive, "np").tag)
            && Ui.TAG_SOON.equals(find(inUseLive, "autoupd").tag));
        // 변조·설치 중이면 잠금 문구가 설명 자리에 먼저 보인다(딱지는 '사용 중', 켬 모양 그대로)
        List<Ui.Row> inUseTam = Ui.rows(tam, false, null, null, null, none), inUseInst = Ui.rows(rep(""), true, null, null, null, none);
        check("계기판·곡 정보: 변조 → 잠금 문구, 설치 중 → 설치 문구, 누를 수 없음",
            Ui.LOCK_TAMPER.equals(find(inUseTam, "tbt").desc) && Ui.LOCK_TAMPER.equals(find(inUseTam, "np").desc)
            && Ui.LOCK_INSTALL.equals(find(inUseInst, "tbt").desc) && Ui.LOCK_INSTALL.equals(find(inUseInst, "np").desc)
            && !find(inUseTam, "tbt").enabled && !find(inUseInst, "np").enabled
            && Ui.TAG_INUSE.equals(find(inUseTam, "tbt").tag) && find(inUseInst, "np").state == Ui.ON);
        check("묶음: 기본 기능 → 부가 기능(tbt) → 고급(debug)", "부가 기능".equals(find(rows, "tbt").group) && "".equals(find(rows, "np").group)
            && "고급".equals(dbg.group));
        // --- 1.8.0 베타 2 문구 정리(11-23 소유자 규칙) ---
        check("문구 정리 D-4·D-7~D-10: 줄 제목·설명",
            "무선 프로젝션".equals(rows.get(0).title)
            && "계기판·HUD (TBT) 안내".equals(find(rows, "tbt").title) && "길안내 그림을 계기판과 HUD에 보냅니다.".equals(find(rows, "tbt").desc)
            && "음악 정보 보내기".equals(find(rows, "np").title) && "재생 중인 음악 정보를 계기판·미디어 화면에 보냅니다.".equals(find(rows, "np").desc));
        check("문구 정리: 변조·자동 업데이트·저장 실패 문구",
            "재부팅할까요?".equals(Ui.RB_ASK) && "변조된 버전이라 바꿀 수 없습니다.".equals(Ui.LOCK_TAMPER)
            && find(rows, "autoupd").desc.endsWith("끄면 지금 버전에 머뭅니다.")
            && "요청을 저장하지 못해 원래대로 두었습니다(재부팅한 뒤 다시 눌러 주세요).".equals(Ui.SET_WRITE_FAILED));
        check("문구 정리: 패키지의 새 요약 값도 색이 그대로(휴대폰 없음=기본, 연결됨=초록, 켜는 중=노랑)",
            Ui.tone("지금 연결된 휴대폰 없음") == Ui.tone("지금 연결된 폰 없음") && Ui.tone("지금 연결된 휴대폰 없음") != Ui.INK_BAD
            && Ui.tone("카플레이 1대 연결됨") == Ui.INK_GOOD && Ui.tone("안드로이드 오토 연결됨") == Ui.INK_GOOD
            && Ui.tone("켜는 중(재부팅 뒤 확인)") == Ui.INK_WARN);

        // ---- 베타 2 동글 토글(제안 키 dongle_set·dongle_why, 소유자 결정 11-18 밤)
        String[] dl = new String[] { "debug", "dongle" };
        Ui.Row d0 = find(Ui.rows(rep("dongle=off\n"), false, null, null, null, dl), "dongle");
        check("동글: 베타 1 패키지(dongle_set 없음) → 요청 길이 있어도 '준비 중', 누를 수 없음, 이유 줄 없음",
            Ui.TAG_SOON.equals(d0.tag) && !d0.enabled && d0.note.isEmpty() && d0.state == Ui.OFF);
        check("동글: 포트 안내는 늘 고정 줄(준비 중·설치 중·변조에도)", Ui.DG_PORT.equals(d0.pinned)
            && Ui.DG_PORT.equals(find(Ui.rows(rep("dongle=off\n"), true, null, null, null, dl), "dongle").pinned)
            && Ui.DG_PORT.equals(find(Ui.rows(tam, false, null, null, null, dl), "dongle").pinned));
        Ui.Row da = find(Ui.rows(rep("dongle=up\ndongle_set=auto\ndongle_why=nochip\n"), false, null, null, null, dl), "dongle");
        check("동글 자동 켜짐(부품 없음) → 켬, 누를 수 있음, 딱지 없음, 이유 한 줄", da.state == Ui.ON && da.enabled && da.tag.isEmpty()
            && "Wi-Fi 부품이 없어 자동으로 켰습니다.".equals(da.note));
        check("동글 자동 켜짐(내장 안 됨) → 이유", Ui.DG_AUTO_BAD.equals(find(Ui.rows(rep("dongle=ok\ndongle_set=auto\ndongle_why=builtin_bad\n"), false, null, null, null, dl), "dongle").note));
        Ui.Row db = find(Ui.rows(rep("dongle=off\ndongle_set=auto\ndongle_why=builtin_ok\n"), false, null, null, null, dl), "dongle");
        check("동글 자동 꺼짐(내장 잘 됨) → 끔, 이유", db.state == Ui.OFF && db.enabled && Ui.DG_AUTO_OK.equals(db.note));
        check("동글 자동 꺼짐(허용 동글 없음)·모르는 이유 → 이유·일반 문구",
            Ui.DG_AUTO_NODONGLE.equals(find(Ui.rows(rep("dongle=off\ndongle_set=auto\ndongle_why=nodongle\n"), false, null, null, null, dl), "dongle").note)
            && Ui.DG_AUTO_OFF.equals(find(Ui.rows(rep("dongle=off\ndongle_set=auto\ndongle_why=xyz\n"), false, null, null, null, dl), "dongle").note)
            && Ui.DG_AUTO_ON.equals(find(Ui.rows(rep("dongle=wait\ndongle_set=auto\n"), false, null, null, null, dl), "dongle").note));
        Ui.Row dc = find(Ui.rows(rep("dongle=off\ndongle_set=on\ndongle_why=builtin_ok\n"), false, null, null, null, dl), "dongle");
        check("동글 직접 켬(아직 적용 전) → 켬, '재부팅 필요', '직접 켠 설정을 따릅니다.'", dc.state == Ui.ON && Ui.TAG_REBOOT.equals(dc.tag)
            && Ui.DG_USER_ON.equals(dc.note) && dc.enabled);
        Ui.Row dd = find(Ui.rows(rep("dongle=off\ndongle_set=off\n"), false, null, null, null, dl), "dongle");
        check("동글 직접 끔(적용됨) → 끔, 딱지 없음, '직접 끈 설정을 따릅니다.'", dd.state == Ui.OFF && dd.tag.isEmpty() && Ui.DG_USER_OFF.equals(dd.note));
        Ui.Row de = find(Ui.rows(rep("dongle=nodongle\ndongle_lv=1\ndongle_msg=동글이 보이지 않습니다. 다시 꽂아 주세요.\ndongle_set=on\n"), false, null, null, null, dl), "dongle");
        String busyMsg = "내장 Wi-Fi를 비우지 못해 이번 부팅은 동글을 쓰지 않습니다. 기존 카플레이는 그대로입니다.";
        Ui.Row bb = find(Ui.rows(rep("dongle=builtinbusy\ndongle_lv=1\ndongle_msg=" + busyMsg + "\ndongle_set=auto\ndongle_why=nochip\n"), false, null, null, null, dl), "dongle");
        check("builtinbusy(lv=1) → 패키지 문구 그대로 노랑, 토글 켬, 재부팅 딱지 없음", busyMsg.equals(bb.desc)
            && bb.descColor == Ui.INK_WARN && bb.state == Ui.ON && !Ui.TAG_REBOOT.equals(bb.tag) && bb.enabled);
        Ui.Row bb2 = find(Ui.rows(rep("dongle=builtinbusy\ndongle_lv=1\ndongle_msg=" + busyMsg + "\ndongle_set=on\ndongle_why=\n"), false, null, null, null, dl), "dongle");
        check("builtinbusy + 직접 켬 → 같은 문구, 되돌리기 버튼 보임", busyMsg.equals(bb2.desc) && bb2.state == Ui.ON
            && Ui.dongleAutoBtn(rep("dongle=builtinbusy\ndongle_set=on\n"), bb2) == 2);
        check("동글 문제(dongle_lv=1) → 설명 자리에 그 문구(노랑), 토글은 켬", "동글이 보이지 않습니다. 다시 꽂아 주세요.".equals(de.desc)
            && de.descColor == Ui.INK_WARN && de.state == Ui.ON);
        Ui.Row df = find(Ui.rows(rep("dongle=blocked\ndongle_lv=2\ndongle_msg=멈춤\ndongle_set=auto\n"), false, null, null, null, dl), "dongle");
        check("동글 막힘(dongle_lv=2) → 빨강", df.descColor == Ui.INK_BAD && "멈춤".equals(df.desc));
        Ui.Row dl2 = find(Ui.rows(rep("dongle=blocked\ndongle_lv=2\ndongle_msg=멈춤\ndongle_set=auto\n"), true, null, null, null, dl), "dongle");
        check("동글 막힘 + 설치 중 → 잠금 문구는 보통 색(빨강을 물려받지 않음)", Ui.LOCK_INSTALL.equals(dl2.desc) && dl2.descColor == Ui.INK_DESC);
        check("동글 키 없음(옛 상태 파일) → 모름, 누를 수 없음", find(Ui.rows(Report.parse("pkgver=1.7.4\n"), false, null, null, null, dl), "dongle").state == Ui.UNKNOWN
            && !find(Ui.rows(Report.parse("pkgver=1.7.4\n"), false, null, null, null, dl), "dongle").enabled);
        check("동글 이유·포트 문구: 존댓말 한 문장", Ui.DG_PORT.endsWith("니다.") && Ui.DG_AUTO_NOCHIP.endsWith("니다.") && Ui.DG_USER_ON.endsWith("니다.")
            && Ui.DG_PORT.split("\\.").length == 1);
        check("동글 요청 줄: 'dongle=on'(debug와 같은 형식), 읽기도 같음", Ui.settingsLine(5000, "b1", "dongle", true).trim().endsWith(" dongle=on")
            && "dongle".equals(Ui.settingsKv(Ui.settingsLine(5000, "b1", "dongle", false))[0]) && "off".equals(Ui.settingsKv(Ui.settingsLine(5000, "b1", "dongle", false))[1]));
        check("동글 성공 → '재부팅하면 적용됩니다.'(같은 부팅에 적용돼도 틀리지 않게)", Ui.DG_SET_OK.equals(Ui.settingsResult("ok", "dongle", true)[0]) && Ui.DG_SET_OK.endsWith("재부팅하면 적용됩니다."));
        // --- 베타 3(B3-2): 꽂기 기다림 중에 끄면 바로 적용, dongle_note 보이기 ---
        String wait = "dongle=up\ndongle_lv=1\ndongle_msg=지금 동글을 꽂으세요. 동글 사용을 끄면 바로 내비 Wi-Fi로 돌아갑니다.\n"
            + "dongle_note=동글을 기다리는 동안은 유선 프로젝션을 쓸 수 없습니다.\ndongle_set=on\ndongle_why=\ndongle_seen=no\ndongle_wait=yes\n";
        check("B3-2: 기다림 중에 끄기 성공 → '바로 적용됩니다', 켜기·기다림 아님은 그대로 '재부팅하면 적용됩니다'",
            Ui.DG_SET_NOW.equals(Ui.settingsResult("ok", "dongle", false, true)[0]) && Ui.DG_SET_OK.equals(Ui.settingsResult("ok", "dongle", true, true)[0])
            && Ui.DG_SET_OK.equals(Ui.settingsResult("ok", "dongle", false, false)[0]) && "ok".equals(Ui.settingsResult("ok", "dongle", false, true)[1])
            && Ui.SET_FAILED.equals(Ui.settingsResult("fail", "dongle", false, true)[0]));
        check("B3-2: 바로 적용 문구는 짧은 존댓말 두 문장, '재부팅' 없음", "동글 사용을 껐습니다. 바로 적용됩니다.".equals(Ui.DG_SET_NOW) && !Ui.DG_SET_NOW.contains("재부팅"));
        check("B3-2: dongle_wait는 yes일 때만(없음·no는 아님)", Ui.dongleWait(rep(wait)) && !Ui.dongleWait(rep("dongle=up\n")) && !Ui.dongleWait(rep("dongle=up\ndongle_wait=no\n")));
        Report dw = rep(wait);
        Ui.applySetting(dw, "dongle", false, Report.parse("code=ok\nval=off\n"));
        Ui.Row dwr = find(Ui.rows(dw, false, null, null, null, dl), "dongle");
        check("B3-2: 기다림 중에 끈 뒤 → 끔, '재부팅 필요' 딱지 없음", dwr.state == Ui.OFF && !Ui.TAG_REBOOT.equals(dwr.tag));
        Report dw2 = rep(wait.replace("dongle_wait=yes", "dongle_wait=no"));
        Ui.applySetting(dw2, "dongle", false, Report.parse("code=ok\nval=off\n"));
        check("B3-2: 기다림이 아니면(dongle_wait=no) 끈 뒤 '재부팅 필요' 그대로", Ui.TAG_REBOOT.equals(find(Ui.rows(dw2, false, null, null, null, dl), "dongle").tag));
        Report dw3 = rep("dongle=up\ndongle_set=auto\ndongle_why=nochip\n");
        Ui.applySetting(dw3, "dongle", false, Report.parse("code=ok\nval=off\n"));
        check("B3-2: 옛 패키지(dongle_wait 없음) → 끈 뒤 '재부팅 필요' 그대로", Ui.TAG_REBOOT.equals(find(Ui.rows(dw3, false, null, null, null, dl), "dongle").tag));
        check("dongle_note: 기다림 중이면 패키지 안내만(포트 안내와 같은 뜻)", "동글을 기다리는 동안은 유선 프로젝션을 쓸 수 없습니다.".equals(find(Ui.rows(rep(wait), false, null, null, null, dl), "dongle").pinned));
        String inuse = "동글을 빼기 전에 상태 화면에서 동글 사용을 끄고 재부팅하세요.";
        check("dongle_note: 쓰는 중이면 포트 안내 뒤에 패키지 안내", (Ui.DG_PORT + " " + inuse).equals(find(Ui.rows(rep("dongle=ok\ndongle_lv=0\ndongle_note=" + inuse + "\ndongle_set=on\ndongle_wait=no\n"), false, null, null, null, dl), "dongle").pinned));
        check("dongle_note: 없으면(빈 값·옛 상태 파일) 포트 안내만", Ui.DG_PORT.equals(find(Ui.rows(rep("dongle=off\ndongle_note=\ndongle_set=auto\ndongle_why=builtin_ok\n"), false, null, null, null, dl), "dongle").pinned)
            && Ui.DG_PORT.equals(find(Ui.rows(rep("dongle=off\ndongle_set=auto\n"), false, null, null, null, dl), "dongle").pinned));
        Report dgs = rep("dongle=off\ndongle_set=auto\ndongle_why=builtin_ok\n");
        Ui.applySetting(dgs, "dongle", true, Report.parse("code=ok\nval=on\n"));
        Ui.Row dg2 = find(Ui.rows(dgs, false, null, null, null, dl), "dongle");
        check("동글 켜기 성공 반영 → 직접 켬, '재부팅 필요'(지금 쓰는 값은 그대로)", "on".equals(dgs.get("dongle_set")) && "off".equals(dgs.get("dongle"))
            && dg2.state == Ui.ON && Ui.TAG_REBOOT.equals(dg2.tag));
        // ---- 동글 "자동으로 되돌리기"(소유자 결정 11-18 밤)
        Report au1 = rep("dongle=off\ndongle_set=on\n");
        check("되돌리기 버튼: 차주가 고른 값(on·off)이면 보이고 누를 수 있음",
            Ui.dongleAutoBtn(au1, find(Ui.rows(au1, false, null, null, null, dl), "dongle")) == 2
            && Ui.dongleAutoBtn(rep("dongle=up\ndongle_set=off\n"), find(Ui.rows(rep("dongle=up\ndongle_set=off\n"), false, null, null, null, dl), "dongle")) == 2);
        check("되돌리기 버튼: 자동·키 없음(베타 1)·옛 상태 파일이면 숨김",
            Ui.dongleAutoBtn(rep("dongle=off\ndongle_set=auto\n"), find(Ui.rows(rep("dongle=off\ndongle_set=auto\n"), false, null, null, null, dl), "dongle")) == 0
            && Ui.dongleAutoBtn(rep("dongle=off\n"), find(Ui.rows(rep("dongle=off\n"), false, null, null, null, dl), "dongle")) == 0
            && Ui.dongleAutoBtn(Report.parse("pkgver=1.7.4\n"), null) == 0);
        check("되돌리기 버튼: 설치 중·적용 중·변조면 보이되 누를 수 없음",
            Ui.dongleAutoBtn(au1, find(Ui.rows(au1, true, null, null, null, dl), "dongle")) == 1
            && Ui.dongleAutoBtn(au1, find(Ui.rows(au1, false, "debug", null, null, dl), "dongle")) == 1
            && Ui.dongleAutoBtn(au1, find(Ui.rows(Report.parse(BASE.replace("verdict=ready", "verdict=tampered").replace("verdict_lv=0", "verdict_lv=2") + "dongle=off\ndongle_set=on\n"), false, null, null, null, dl), "dongle")) == 1);
        String al = Ui.settingsLine(7000, "b1", "dongle", "auto");
        check("되돌리기 요청 줄: 'dongle=auto', 읽기도 같음", al.trim().endsWith(" dongle=auto")
            && "auto".equals(Ui.settingsKv(al)[1]) && Report.reqParse(al, "b1") != null);
        check("auto는 동글만 받음(debug=auto는 잘못된 요청)", Ui.settingsKv("1 b1 1 debug=auto") == null && Ui.settingsKv("1 b1 1 dongle=xyz") == null);
        check("되돌리기 성공 → '자동으로 되돌렸습니다. 재부팅하면 적용됩니다.', 실패·바쁨 → 원래 문구",
            "자동으로 되돌렸습니다. 재부팅하면 적용됩니다.".equals(Ui.autoResult("ok")[0]) && "ok".equals(Ui.autoResult("ok")[1])
            && Ui.SET_BUSY.equals(Ui.autoResult("busy")[0]) && Ui.SET_FAILED.equals(Ui.autoResult("fail")[0]) && "".equals(Ui.autoResult(null)[1]));
        Report au2 = rep("dongle=off\ndongle_set=on\ndongle_why=builtin_ok\n");
        Ui.applyAuto(au2);
        Ui.Row au2r = find(Ui.rows(au2, false, null, null, null, dl), "dongle");
        check("되돌리기 반영 → 자동, 버튼 숨김, 재부팅 딱지 없음, 자동 이유 줄", "auto".equals(au2.get("dongle_set")) && Ui.dongleAutoBtn(au2, au2r) == 0
            && au2r.tag.isEmpty() && Ui.DG_AUTO_OK.equals(au2r.note));
        Report au3 = rep("dongle=off\ndongle_set=on\n");
        Ui.applySetting(au3, "dongle", true, Report.parse("code=ok\nval=auto\n"));
        check("답의 val이 auto면 그대로 자동으로 기록", "auto".equals(au3.get("dongle_set")));
        check("되돌리기 문구: 존댓말 두 문장, 버튼 글은 짧게", Ui.DG_AUTO_DONE.endsWith("니다.") && Ui.DG_AUTO_DONE.split("\\.").length == 2 && Ui.DG_AUTO_BTN.length() <= 10);
        // 패키지 확정 키(11-18 밤)와 대조: 차주 선택이면 dongle_why 빈 값, 토글이 꺼져 있으면 늘 dongle=off
        Ui.Row pk1 = find(Ui.rows(rep("dongle=off\ndongle_set=off\ndongle_why=\n"), false, null, null, null, dl), "dongle");
        check("패키지 형식: 차주가 끔(why 빈 값, dongle=off) → 끔, 딱지 없음, 직접 끈 문구, 되돌리기 버튼", pk1.state == Ui.OFF && pk1.tag.isEmpty()
            && Ui.DG_USER_OFF.equals(pk1.note) && Ui.dongleAutoBtn(rep("dongle=off\ndongle_set=off\ndongle_why=\n"), pk1) == 2);
        Report pk2 = rep("dongle=blocked\ndongle_lv=2\ndongle_msg=동글 드라이버가 이 차와 맞지 않아 멈췄습니다. 기존 카플레이는 그대로 쓸 수 있습니다. 상태 화면에서 동글 사용을 끄면 내장 Wi-Fi로 돌아갑니다.\ndongle_set=auto\ndongle_why=builtin_bad\n");
        Ui.Row pk2r = find(Ui.rows(pk2, false, null, null, null, dl), "dongle");
        check("패키지 형식: 자동으로 켰는데 막힘 → 켬, 빨강 문구 전체(자르지 않음), 자동 이유, 버튼 없음", pk2r.state == Ui.ON && pk2r.descColor == Ui.INK_BAD
            && pk2r.desc.endsWith("내장 Wi-Fi로 돌아갑니다.") && Ui.DG_AUTO_BAD.equals(pk2r.note) && Ui.dongleAutoBtn(pk2, pk2r) == 0);
        check("동글 적용 중이면 디버그도 막힘", !find(Ui.rows(rep("dongle=off\ndongle_set=auto\n"), false, "dongle", null, null, dl), "debug").enabled);

        // ---- 설정 요청(제안 A)
        String line = Ui.settingsLine(123456, "b00t-id", "debug", false);
        check("요청 한 줄: '<id> <boot> <초> debug=off' + 줄끝", "123456 b00t-id 123 debug=off\n".equals(line));
        long[] rq = Report.reqParse(line, "b00t-id");
        check("요청 앞 세 칸은 report.req와 같아 Report.reqParse로 읽힘", rq != null && rq[0] == 123456);
        String[] kv = Ui.settingsKv(line);
        check("요청 넷째 칸 읽기", kv != null && "debug".equals(kv[0]) && "off".equals(kv[1]));
        check("넷째 칸 없음·값이 on/off 아님 → null", Ui.settingsKv("1 b 0\n") == null && Ui.settingsKv("1 b 0 debug=yes\n") == null
            && Ui.settingsKv("1 b 0 =on\n") == null && Ui.settingsKv(null) == null);
        check("요청 줄에 이름·주소 같은 값 없음(칸 넷뿐)", line.trim().split("\\s+").length == 4);
        Report ans = Report.parse("id=123456\nboot=b00t-id\nkey=debug\ncode=ok\nval=off\n");
        check("답: id·boot·key가 맞으면 code", "ok".equals(Ui.settingsAnswer(ans, "b00t-id", 123456, "debug")));
        check("답: 다른 요청 id·다른 부팅·다른 키·빈 code → null", Ui.settingsAnswer(ans, "b00t-id", 999, "debug") == null
            && Ui.settingsAnswer(ans, "other", 123456, "debug") == null && Ui.settingsAnswer(ans, "b00t-id", 123456, "tbt") == null
            && Ui.settingsAnswer(Report.parse("id=123456\nboot=b00t-id\nkey=debug\n"), "b00t-id", 123456, "debug") == null
            && Ui.settingsAnswer(Report.parse(null), "b00t-id", 123456, "debug") == null);
        check("답: 정해진 code(ok·bad·busy·fail)만, 반쯤 쓰인 값·모르는 값이면 계속 기다림(null)",
            Ui.settingsAnswer(Report.parse("id=123456\nboot=b00t-id\nkey=debug\ncode=o\n"), "b00t-id", 123456, "debug") == null
            && Ui.settingsAnswer(Report.parse("id=123456\nboot=b00t-id\nkey=debug\ncode=done\n"), "b00t-id", 123456, "debug") == null
            && "busy".equals(Ui.settingsAnswer(Report.parse("id=123456\nboot=b00t-id\nkey=debug\ncode=busy\n"), "b00t-id", 123456, "debug")));
        check("결과 값은 답의 val(없으면 보낸 값)", !Ui.settingValue(ans, true) && Ui.settingValue(Report.parse("val=on\n"), false)
            && Ui.settingValue(Report.parse(""), true) && !Ui.settingValue(null, false));
        check("실패·busy·저장 실패·결과 모름 문구는 한 문장", oneSentence(Ui.SET_FAILED) && oneSentence(Ui.SET_BUSY)
            && oneSentence(Ui.SET_WRITE_FAILED) && oneSentence(Ui.SET_UNKNOWN));
        check("끄기 성공 → '디버그 기록을 지웠습니다.'", "디버그 기록을 지웠습니다.".equals(Ui.settingsResult("ok", "debug", false)[0])
            && "ok".equals(Ui.settingsResult("ok", "debug", false)[1]));
        check("켜기 성공 → 다음 재부팅부터 기록(지금 기록 중이라고 말하지 않음)", Ui.settingsResult("ok", "debug", true)[0].contains("다음 재부팅부터"));
        check("busy → '잠시 뒤 다시', bad·fail·답 없음(45초) → 원래대로 두었다는 한 문장",
            Ui.SET_BUSY.equals(Ui.settingsResult("busy", "debug", false)[0]) && Ui.SET_FAILED.equals(Ui.settingsResult("bad", "debug", false)[0])
            && Ui.SET_FAILED.equals(Ui.settingsResult("fail", "debug", true)[0]) && Ui.SET_FAILED.equals(Ui.settingsResult(null, "debug", true)[0])
            && "".equals(Ui.settingsResult(null, "debug", true)[1]));
        check("기다리는 시간 45초", Ui.SET_WAIT == 45);
        Report st = Report.parse(BASE.replace("debug=no\ndebug_auto=none", "debug=yes\ndebug_auto=on\ndebug_left=31"));
        Ui.applySetting(st, "debug", false, ans);
        Ui.Row afterOff = find(Ui.rows(st, false, null, null, null, new String[] { "debug" }), "debug");
        check("끄기 성공 반영: 끔, 자동 켜짐 문구 사라짐, 고정 경고 없음", afterOff.state == Ui.OFF && afterOff.note.isEmpty()
            && afterOff.pinned.isEmpty() && afterOff.enabled);
        Report st2 = rep("");
        Ui.applySetting(st2, "debug", true, Report.parse("val=on\n"));
        Ui.Row afterOn = find(Ui.rows(st2, false, null, null, null, new String[] { "debug" }), "debug");
        check("켜기 성공 반영: 켬, debug_auto=user(패키지 debug_set on과 같음), '켜짐(직접 켬)'", afterOn.state == Ui.ON
            && "user".equals(st2.get("debug_auto")) && "켜짐(직접 켬)".equals(afterOn.note));
        Report st4 = Report.parse(BASE.replace("debug=no\ndebug_auto=none", "debug=yes\ndebug_auto=on\ndebug_left=31"));
        Ui.applySetting(st4, "debug", true, Report.parse("val=on\n"));
        check("자동 켜짐 중 다시 켜기 → user, 남은 시간 지움", "user".equals(st4.get("debug_auto")) && st4.get("debug_left").isEmpty()
            && "켜짐(직접 켬)".equals(Ui.debugNote(st4)));
        Report st3 = rep("");
        Ui.applySetting(st3, "debug", true, Report.parse("val=off\n"));
        check("답의 val을 믿음(root가 끔이라고 하면 끔)", find(Ui.rows(st3, false, null, null, null, new String[] { "debug" }), "debug").state == Ui.OFF);
        List<Ui.Row> failed = Ui.rows(rep(""), false, null, "debug", Ui.SET_FAILED, new String[] { "debug" });
        check("실패 뒤: 토글 원래 값(끔), 이유 한 문장, 다시 누를 수 있음", find(failed, "debug").state == Ui.OFF
            && Ui.SET_FAILED.equals(find(failed, "debug").desc) && find(failed, "debug").enabled);
        Ui.Row cp = new Ui.Row();
        cp.copy(find(failed, "debug"));
        check("Row.copy: 모든 값을 옮김", "debug".equals(cp.key) && cp.enabled && cp.pinned.equals(find(failed, "debug").pinned) && Ui.SET_FAILED.equals(cp.desc));

        // ---- 흐르는 글자
        check("흐르는 글자: 처음 1.5초 멈춤", Ui.marqueeShift(0, 100, 500) == 0 && Ui.marqueeShift(1499, 100, 500) == 0);
        check("흐르는 글자: 그 뒤 초당 speed px", Math.abs(Ui.marqueeShift(2500, 100, 500) - 100) < 0.5f);
        check("흐르는 글자: 한 바퀴(멈춤 + loop/speed) 뒤 다시 0", Ui.marqueeShift(1500 + 5000, 100, 500) == 0);

        // ---- 숨길 줄 고르기
        boolean[] s1 = Ui.fit(new int[] { 10, 10, 10, 10 }, new int[] { 50, 10, 10, Ui.P_KEEP }, 25);
        check("fit: 낮은 순위부터 숨김", s1[0] && !s1[1] && !s1[2] && s1[3]);
        boolean[] s3 = Ui.fit(new int[] { 10, 10, 10, 10 }, new int[] { 10, 10, 10, Ui.P_KEEP }, 35);
        check("fit: 같은 순위면 아래 줄부터 숨김(하나만 숨길 때 맨 아래 같은 순위 줄)", s3[0] && s3[1] && !s3[2] && s3[3]);
        boolean[] s2 = Ui.fit(new int[] { 100, 100 }, new int[] { Ui.P_KEEP, Ui.P_KEEP }, 50);
        check("fit: 숨길 수 없는 줄은 남김", s2[0] && s2[1]);

        // ---- 스크롤 손잡이(소유자 결정 11-18: 설정 부분 스크롤)
        int[] th = new int[2];
        check("스크롤: 내용이 다 보이면 막대 없음", !Ui.scrollThumb(300, 300, 0, 20, th) && !Ui.scrollThumb(300, 200, 0, 20, th) && !Ui.scrollThumb(0, 500, 0, 20, th));
        check("스크롤: 맨 위면 손잡이 위, 길이는 보이는 비율", Ui.scrollThumb(100, 400, 0, 10, th) && th[0] == 0 && th[1] == 25);
        check("스크롤: 맨 아래면 손잡이 끝이 길 끝", Ui.scrollThumb(100, 400, 300, 10, th) && th[0] + th[1] == 100);
        check("스크롤: 아주 긴 내용도 손잡이 최소 길이, 범위 밖 위치는 끝으로", Ui.scrollThumb(100, 100000, 999999, 22, th) && th[1] == 22 && th[0] + th[1] == 100
            && Ui.scrollThumb(100, 400, -50, 10, th) && th[0] == 0);
        check("확인 창: 연 직후 누른 재부팅은 받지 않는 시간이 있음(0.5~1초)", Ui.CONFIRM_ARM_MS >= 500 && Ui.CONFIRM_ARM_MS <= 1000);
        check("확인 창 문구: 제목 한 문장, 본문 두 문장 이하", Ui.RB_ASK.endsWith("?") && Report.RB_CONFIRM.split("\\.").length <= 2);

        // ---- 여섯 해상도: 토글 도형·상태 칸
        String longFirst = "먼저 할 일: 내비 버전이 확인된 차(260902)보다 구버전입니다. 내비를 업데이트한 뒤 NEMESIS·HMG-API·Korea Projection을 다시 설치해 주세요.";
        String[] notes3 = { "알림 12:01  무선 카플레이 설정을 마쳤습니다. 내비를 3분 후 재부팅해 주세요.", "알림 12:00  지도를 확인하는 중입니다.",
            "알림 11:59  HMG-API가 바뀌어 지도를 다시 확인했습니다. 내비를 3분 후 재부팅해 주세요." };
        for (int[] sz : SIZES) {
            Layout l = Layout.of(sz[0], sz[1], QR);
            String n = sz[0] + "x" + sz[1] + "(" + (l.kind == Layout.WIDE ? "넓은 화면" : "QR 먼저") + ")";
            int[] t = Ui.toggleSize(l);
            boolean geo = t[1] < l.touch && t[0] > t[1] && t[2] < t[1];
            int x0 = 100;
            int kOn = Ui.knobX(x0, t[0], t[1], t[2], Ui.ON, false), kOff = Ui.knobX(x0, t[0], t[1], t[2], Ui.OFF, false);
            int kBusy = Ui.knobX(x0, t[0], t[1], t[2], Ui.ON, true);
            geo &= kOff >= x0 && kOn + t[2] <= x0 + t[0] && kOn > kBusy && kBusy > kOff;
            check(n + " 토글: 누르는 높이 안, 원은 트랙 안(켬 오른쪽 > 적용 중 가운데 > 끔 왼쪽)", geo);
            // 재부팅 확인 창(소유자 결정 11-18): 화면 안, 제목·문구가 다 보이고, 두 버튼이 누르는 높이 이상·글이 버튼 안
            {
                int pw = Math.min(l.width - 2 * l.pad, Ui.confirmWidth(l)), cpad = Ui.confirmPad(l);
                float inner = pw - 2 * cpad;
                int titlePx = width(Ui.RB_ASK, l.textVerdict) <= inner ? l.textVerdict : l.textBody;
                int ml = lines(Report.RB_CONFIRM, l.textBody, inner);
                int ph = Ui.confirmHeight(l, ml, titlePx);
                if (ph > l.height - 2 * l.pad) { titlePx = l.textBody; ph = Ui.confirmHeight(l, ml, titlePx); }
                int bw = (int) ((inner - l.gap) / 2), bh = Ui.confirmButton(l);
                float room = bw - 2 * 1.2f * l.u;
                check(n + " 확인 창: 화면 안(" + pw + "x" + ph + "), 문구 " + ml + "줄, 제목 " + titlePx + "px",
                    pw > 0 && pw <= l.width - 2 * l.pad && ph <= l.height - 2 * l.pad && ml <= 3 && width(Ui.RB_ASK, titlePx) <= inner);
                check(n + " 확인 창 버튼: 높이 " + bh + " ≥ 누르는 높이, 폭 " + bw + "에 '취소'·'재부팅'이 들어감",
                    bh >= l.touch && bw >= l.touch && width(Ui.RB_OK, l.textBody) <= room && width(Ui.RB_CANCEL, l.textBody) <= room);
            }
            // 설정 칸 스크롤 막대: 보이는 폭, 내용 폭을 크게 줄이지 않음
            check(n + " 스크롤 막대 폭 " + Ui.scrollBarWidth(l) + "px(8px 이상, 설정 칸의 3% 이하)",
                Ui.scrollBarWidth(l) >= 8 && Ui.scrollBarWidth(l) * 100 <= l.settingsWidth * 3);

            int[] c0 = column(l, "", new String[0], false);
            check(n + " 상태 칸(보통): 다 들어감, 버튼 보임, 숨김 " + c0[2], c0[0] <= c0[1] && c0[3] == 1 && c0[2] == 0);
            int[] c1 = column(l, longFirst, notes3, true);
            check(n + " 상태 칸(K-5 먼저 할 일 + 알림 3 + 저장 중): 먼저 할 일·버튼은 남고 칸 안(" + c1[0] + "/" + c1[1] + ", 판·차 정보 숨김 " + c1[2] + ")",
                c1[3] == 1 && c1[4] == 1 && c1[0] <= c1[1]);
            int[] c2 = column(l, longFirst, notes3, true, "바꾼 설정 2개는 재부팅 뒤 적용됩니다.",
                "폰의 블루투스를 껐다 켠 뒤 다시 연결해 보세요. (12:00)", Report.RB_GUARD);
            check(n + " 상태 칸(가장 무거움: + 대기 알림·서비스 안내·재부팅 거절 문구): 먼저 할 일·버튼은 남음(" + c2[0] + "/" + c2[1] + ")",
                c2[3] == 1 && c2[4] == 1);
            if (l.kind == Layout.QR_FIRST) {
                // 필요한 높이를 여기서 따로 셈: 묶음 제목(1.2u + 작은 글자 줄) + 간격 + 토글 줄(제목 + 설명 한 줄, 누르는 높이 이상)
                int need = Math.round(1.2f * l.u + l.textSmall * 1.35f) + Math.round(0.7f * l.gap)
                    + Math.max(l.touch, Math.round(1.6f * l.u + l.textBody * 1.35f + l.textSmall * 1.35f));
                int worst = Math.min(c2[0], c2[1]);
                int settingsH = l.bodyHeight - worst - l.gap;
                check(n + " QR 먼저: 상태 칸이 가득 차도 설정 칸에 묶음 제목 + 토글 한 줄(" + settingsH + "px ≥ " + need + ")", settingsH >= need);
            }

            // 설정 칸 글 폭(추정). 베타 3에서 디버그 고정 경고는 뺐다
            int sw = l.settingsWidth;
            float textW = sw - 2 * 1.6f * l.u - (width("끔", l.textSmall) + 0.8f * l.u + t[0]) - 1.6f * l.u;
            check(n + " 설정 칸 글 폭이 충분함(설정 칸 " + sw + "px)", textW > l.textSmall * 4);
            // 베타 2 동글: 포트 안내(고정, 줄바꿈) 3줄 이하, 자동 이유(한 줄, 넘치면 잘림)는 한 줄에 들어감
            int pl = lines(Ui.DG_PORT, l.textSmall, textW);
            boolean noteFit = true;
            String[] notes = { Ui.DG_AUTO_NOCHIP, Ui.DG_AUTO_BAD, Ui.DG_AUTO_OK, Ui.DG_AUTO_NODONGLE, Ui.DG_USER_ON, Ui.DG_USER_OFF };
            for (String nt : notes) if (lines(nt, l.textSmall, textW) > 1) noteFit = false;
            check(n + " 동글 포트 안내 " + pl + "줄, 자동·직접 이유는 한 줄", pl >= 1 && pl <= 3 && noteFit);
            // "자동으로 되돌리기" 버튼: 작은 글자 + 양옆 2.4u가 설정 칸 폭의 절반 안(토글과 떨어진 왼쪽에 한 줄로)
            float abw = width(Ui.DG_AUTO_BTN, l.textSmall) + 4.8f * l.u;
            check(n + " 동글 '자동으로 되돌리기' 버튼 " + Math.round(abw) + "px ≤ 설정 칸 절반 " + (sw / 2) + "px", abw <= sw / 2f);

            // 버튼 글자가 버튼 폭에 들어가는가(추정): QR 먼저 가로 두 개면 반 폭
            int bw = l.kind == Layout.WIDE ? l.infoWidth : (l.buttonsStacked ? l.settingsWidth : (l.settingsWidth - l.gap) / 2);
            float need = width("제보 파일 만들기", l.textBody) + 2.4f * l.u;
            check(n + " 버튼 '제보 파일 만들기'가 버튼 폭 안(" + Math.round(need) + "/" + bw + "px)", need <= bw);
        }

        // ---- 베타 2: 상태 파일이 바뀌면 다시 그림(소유자 제보 11-23)
        long g0 = Ui.statSig("dongle_msg=동글을 빼 주세요.\n", "boot=x\n", null);
        long g1 = Ui.statSig("dongle_msg=지금 동글을 꽂으세요.\n", "boot=x\n", null);
        check("지문: 같은 내용이면 같고(다시 써도 그대로), 문구가 바뀌면 다름",
            g0 == Ui.statSig("dongle_msg=동글을 빼 주세요.\n", "boot=x\n", null) && g0 != g1);
        check("지문: 안내·알림만 바뀌어도 다름, 없는 파일과 빈 파일은 다름",
            g0 != Ui.statSig("dongle_msg=동글을 빼 주세요.\n", "boot=y\n", null)
            && g0 != Ui.statSig("dongle_msg=동글을 빼 주세요.\n", "boot=x\n", "")
            && Ui.statSig(null, null, null) != Ui.statSig("", "", ""));
        check("판단: 그린 것과 같으면 그대로", Ui.redrawStep(g0, g0, g0, false) == Ui.REDRAW_NONE
            && Ui.redrawStep(g0, g1, g0, true) == Ui.REDRAW_NONE);
        check("판단: 처음 바뀐 것을 본 틱은 기다림(쓰는 중일 수 있음)", Ui.redrawStep(g0, g0, g1, false) == Ui.REDRAW_WAIT);
        check("판단: 두 틱 같은 새 값이면 다시 그림", Ui.redrawStep(g0, g1, g1, false) == Ui.REDRAW_NOW);
        check("판단: 바쁠 때(확인 창·설정 기다림 등)는 기다리고, 끝나면 바로 그림",
            Ui.redrawStep(g0, g1, g1, true) == Ui.REDRAW_WAIT && Ui.redrawStep(g0, g1, g1, false) == Ui.REDRAW_NOW);
        long g2 = Ui.statSig("dongle_msg=다른 문구\n", "boot=x\n", null);
        check("판단: 연달아 바뀌면 멈출 때까지 기다림", Ui.redrawStep(g0, g1, g2, false) == Ui.REDRAW_WAIT);
        // 틱을 흉내 낸다: 패키지가 문구를 바꾸면 2틱 안에 한 번만 다시 그린다
        long shown = g0, seen = g0;
        int draws = 0, firstDraw = -1;
        long[] file = { g0, g1, g1, g1, g1 };
        for (int t = 0; t < file.length; t++) {
            int gs = Ui.redrawStep(shown, seen, file[t], false);
            seen = file[t];
            if (gs == Ui.REDRAW_NOW) { draws++; shown = file[t]; if (firstDraw < 0) firstDraw = t; }
        }
        check("흉내: 문구가 바뀐 뒤 1초 안팎(다음 틱)에 한 번만 다시 그림", draws == 1 && firstDraw == 2);
        check("간격 1초(1~2초 안에 보임)", Ui.STAT_POLL_MS == 1000);
        // 바쁜 틱이 여럿 이어지다 풀리면 그 틱에 바로 그린다
        shown = g0; seen = g0; draws = 0; firstDraw = -1;
        boolean[] busyT = { false, true, true, true, false, false };
        for (int t = 0; t < busyT.length; t++) {
            int gs = Ui.redrawStep(shown, seen, g1, busyT[t]);
            seen = g1;
            if (gs == Ui.REDRAW_NOW) { draws++; shown = g1; if (firstDraw < 0) firstDraw = t; }
        }
        check("흉내: 바쁜 동안 미뤘다가 풀린 틱에 한 번 그림", draws == 1 && firstDraw == 4);
        check("판단: A→B→A로 돌아오면 그대로(그린 것과 같음)", Ui.redrawStep(g0, g1, g0, false) == Ui.REDRAW_NONE);
        check("판단: 매 틱 바뀌는 파일은 그리지 않음(쓰는 중으로 봄, 우리 파일은 mv로 한 번에 씀)",
            Ui.redrawStep(g0, g1, g2, false) == Ui.REDRAW_WAIT && Ui.redrawStep(g0, g2, g1, false) == Ui.REDRAW_WAIT);
        check("실패 이유 되살리기: 그대로 다시 그릴 때만", Ui.keepFail("dongle", false, null, null));
        check("실패 이유 되살리기 안 함: 늦은 답을 처리함·새 실패 이유가 있음·다시 기다림·이유 없었음",
            !Ui.keepFail("dongle", true, null, null) && !Ui.keepFail("dongle", false, "dongle", null)
            && !Ui.keepFail("dongle", false, null, "dongle") && !Ui.keepFail(null, false, null, null));

        System.out.println(fails == 0 ? "모두 통과" : "실패 " + fails + "개");
        if (fails > 0) System.exit(1);
    }

    /** 마침표가 하나뿐이고 그것으로 끝나는가(한 문장) */
    static boolean oneSentence(String s) {
        return s.indexOf('.') == s.length() - 1;
    }

    static boolean allLocked(List<Ui.Row> rows) {
        for (Ui.Row r : rows) if (r.enabled) return false;
        return true;
    }
}
