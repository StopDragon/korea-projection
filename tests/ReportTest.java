package korea.projection.app;

/**
 * PC에서 상태 화면의 판단(Report)과 QR 크기를 시험한다. tests/stub-test.sh가 javac로 컴파일해 돌린다.
 * 실패하면 "FAIL ..."을 찍고 종료 코드 1.
 */
public class ReportTest {
    static int fails = 0;

    static void check(String name, boolean ok) {
        System.out.println((ok ? "ok   " : "FAIL ") + name);
        if (!ok) fails++;
    }

    static final String GOOD =
        "product=DEPEHEV.KOR.0000.V039.001.260902\n" +
        "targetdir=/system/onebin/depehev_kr\n" +
        "pkgver=1.4\ntested=yes\nhmgapi=version 1.0.2 build 180185d 2026-11-04\nnemesis=1.16.7\n" +
        "wp=no\nmod=yes\nmod_on=yes\nbridge=on\nhooks=on\nfeat_carplay=yes\nfeat_aa=yes\nfeat_wifi=no\nwlan0=yes\n" +
        "softap_strings=4\nssid_len=8\npass_len=12\nour_ap=yes\nour_dhcp=yes\nother_ap=no\nwpa=no\n" +
        "cp_conn=0\nmade=2026-11-06 06:00\n";

    static String row(Report r, String title) {
        for (String[] x : r.rows()) if (x[0].equals(title)) return x[1];
        return null;
    }

    public static void main(String[] a) throws Exception {
        Report r = Report.parse(GOOD);
        check("상태 파일 해석", "DEPEHEV.KOR.0000.V039.001.260902".equals(r.get("product")) && r.yes("our_ap"));
        check("모두 정상 → '준비됨', 초록", r.verdict().startsWith("무선 카플레이 준비됨") && r.level() == 0);
        check("연결 수가 있으면 → '연결됨'", Report.parse(GOOD.replace("cp_conn=0", "cp_conn=1")).verdict().equals("무선 카플레이 연결됨"));
        check("확인 안 된 차 → 대기 안내, 노랑", Report.parse(GOOD.replace("tested=yes", "tested=no")).verdict().startsWith("확인되지 않은 차") &&
            Report.parse(GOOD.replace("tested=yes", "tested=no")).level() == 1);
        check("무선 기능 꺼짐 → 빨강", Report.parse(GOOD.replace("feat_carplay=yes", "feat_carplay=no")).level() == 2);
        check("핫스팟 꺼짐 → 안내", Report.parse(GOOD.replace("our_ap=yes", "our_ap=no")).verdict().startsWith("핫스팟이 꺼져"));
        check("파일 없음 → 다시 눌러 달라는 안내", Report.parse(null).verdict().startsWith("상태를 읽지 못했습니다") && Report.parse(null).level() == 2);
        check("표는 15줄, 예/아니요로 표시", r.rows().size() == 15 && "예".equals(r.rows().get(1)[1]));
        check("정상이면 버전 칸은 버전만 (HMG-API 1.0.2, NEMESIS 1.16.7)", "1.0.2".equals(row(r, "HMG-API")) && "1.16.7".equals(row(r, "NEMESIS")));

        // 필요 조건: README "필요한 것"과 같은 최소 버전
        Report old = Report.parse(GOOD.replace("version 1.0.2 build", "version 1.0.1 build"));
        check("HMG-API 1.0.1 → '지원하지 않는 버전', 빨강", old.verdict().startsWith("지원하지 않는 HMG-API 버전") && old.level() == 2);
        check("  버전 칸에 '지원 안 함, 1.0.2 이상 필요'", "1.0.1 (지원 안 함, 1.0.2 이상 필요)".equals(row(old, "HMG-API")));
        Report beta = Report.parse(GOOD.replace("version 1.0.2 build", "version 1.0.0-beta.5 build"));
        check("  1.0.0-beta.5도 낮은 버전", beta.level() == 2 && row(beta, "HMG-API").contains("지원 안 함"));
        Report newer = Report.parse(GOOD.replace("version 1.0.2 build", "version 1.1.0 build"));
        check("  1.1.0은 통과 (1.0.10 > 1.0.2 같은 숫자 비교)", newer.level() == 0 && Report.older("1.0.10", "1.0.2") == 0 && Report.older("1.0.1", "1.0.10") == 1);
        Report none = Report.parse(GOOD.replace("hmgapi=version 1.0.2 build 180185d 2026-11-04\n", ""));
        check("HMG-API 없음 → 설치 안내, 빨강, '없음 (1.0.2 이상 필요)'", none.verdict().startsWith("HMG-API가 없습니다") && none.level() == 2 && "없음 (1.0.2 이상 필요)".equals(row(none, "HMG-API")));
        Report odd = Report.parse(GOOD.replace("version 1.0.2 build", "version dev build"));
        check("숫자가 아닌 버전 → '버전 확인 안 됨', 빨강 (멈추지 않음)", odd.level() == 2 && row(odd, "HMG-API").contains("버전 확인 안 됨"));
        Report nomod = Report.parse(GOOD.replace("mod=yes\nmod_on=yes", "mod=no\nmod_on=no"));
        // 1.6.1: 차에 맞지 않는 다른 무선 모드(HMG-API 기본판) → 토스트 대신 Launch 화면 맨 위에서 지우라고 안내
        Report fm = Report.parse(GOOD.replace("mod=yes", "mod=yes\nmod_foreign=yes"));
        check("다른 판 무선 모드 → 지우고 재부팅 안내, 빨강, 칸 '한국 차용 아님'", fm.verdict().startsWith("차에 있는 HMG-API 무선 모드가 한국 차용이 아닙니다")
            && fm.level() == 2 && row(fm, "HMG-API 무선 모드").startsWith("한국 차용 아님") && fm.verdict().length() <= 80);
        Report fmc = Report.parse(GOOD.replace("mod=yes", "mod=yes\nmod_foreign=yes").replace("cp_conn=0", "cp_conn=1"));
        check("다른 판이어도 카플레이가 연결돼 있으면 빨강 안내 안 함", fmc.verdict().equals("무선 카플레이 연결됨") && fmc.level() == 0);
        check("확인 안 된 차는 그 안내가 먼저", Report.parse(GOOD.replace("mod=yes", "mod=yes\nmod_foreign=yes").replace("tested=yes", "tested=no")).verdict().startsWith("확인되지 않은 차"));
        check("QR 요약: mod_foreign은 yes일 때만", fm.issueUrl().contains("mod_foreign") && !Report.parse(GOOD.replace("mod=yes", "mod=yes\nmod_foreign=no")).issueUrl().contains("mod_foreign"));
        check("mod_foreign=no면 그대로 '준비됨'", Report.parse(GOOD.replace("mod=yes", "mod=yes\nmod_foreign=no")).verdict().startsWith("무선 카플레이 준비됨"));
        check("무선 모드 없음 → 설치 안내, 빨강, '없음 (필요)'", nomod.verdict().startsWith("HMG-API 무선 모드가 없습니다") && nomod.level() == 2 && "없음 (필요)".equals(row(nomod, "HMG-API 무선 모드")));
        Report modoff = Report.parse(GOOD.replace("mod_on=yes", "mod_on=no"));
        check("무선 모드 꺼짐(11-06 시험 상태) → 켜기 안내, 빨강, '꺼짐 (켜야 함)'", modoff.verdict().startsWith("HMG-API 무선 모드가 꺼져") && modoff.level() == 2 && "꺼짐 (켜야 함)".equals(row(modoff, "HMG-API 무선 모드")));
        Report broff = Report.parse(GOOD.replace("bridge=on", "bridge=off"));
        check("Wireless CarPlay 설정 꺼짐 → 켜기 안내, 빨강", broff.verdict().contains("'Wireless CarPlay' 설정이 꺼져") && broff.level() == 2 && row(broff, "HMG-API 무선 모드").contains("설정 꺼짐"));
        check("정상이면 무선 모드 칸 '켜짐'", "켜짐".equals(row(r, "HMG-API 무선 모드")));
        Report oldfile = Report.parse(GOOD.replace("mod_on=yes\nbridge=on\n", ""));
        check("예전 상태 파일(mod_on·bridge 없음)도 초록, 칸은 '예'", oldfile.level() == 0 && "예".equals(row(oldfile, "HMG-API 무선 모드")));
        Report hoff = Report.parse(GOOD.replace("hooks=on", "hooks=off\nhookmap=mapped"));
        check("훅 꺼짐(mapped) → 'Check the map on this car' 안내, 노랑(지난 기록일 수 있음)", hoff.verdict().contains("Check the map on this car") && hoff.level() == 1 && row(hoff, "HMG-API 훅").startsWith("꺼짐 (mapped"));
        check("  none → 지도 없음 제보 안내", Report.parse(GOOD.replace("hooks=on", "hooks=off\nhookmap=none")).verdict().contains("지도가 없어"));
        check("  mismatch → 소프트웨어 불일치 안내", Report.parse(GOOD.replace("hooks=on", "hooks=off\nhookmap=mismatch")).verdict().contains("맞지 않아"));
        check("  상태 모름 → 재부팅 안내", Report.parse(GOOD.replace("hooks=on", "hooks=off")).verdict().contains("마지막 부팅 기록"));
        check("확인 안 된 차는 HMG-API가 없어도 노랑(문구와 색이 맞음)", Report.parse(GOOD.replace("tested=yes", "tested=no").replace("hmgapi=version 1.0.2 build 180185d 2026-11-04\n", "")).level() == 1);
        Report hunk = Report.parse(GOOD.replace("hooks=on\n", "hooks=\n"));
        check("훅 기록 없음 → 판정에 쓰지 않고 '-'", hunk.level() == 0 && "-".equals(row(hunk, "HMG-API 훅")));
        Report nold = Report.parse(GOOD.replace("nemesis=1.16.7", "nemesis=1.15.2"));
        check("NEMESIS 1.15 → 업데이트 안내, 노랑", nold.verdict().startsWith("NEMESIS를 1.16 이상") && nold.level() == 1 && row(nold, "NEMESIS").contains("1.16 이상 필요"));
        check("wireless.projection 칸에 '필요 없음'", "아니요 (필요 없음)".equals(row(r, "wireless.projection")));

        String url = r.issueUrl();
        check("제보 링크: 우리 저장소의 양식", url.startsWith("https://github.com/StopDragon/korea-projection/issues/new?template=car-report.yml&title="));
        check("  양식 항목 product·report를 미리 채움", url.contains("&product=DEPEHEV.KOR.0000.V039.001.260902") && url.contains("&report="));
        check("  길이 " + url.length() + " <= " + Report.MAX_URL, url.length() <= Report.MAX_URL);
        check("  공백은 %20 (+ 아님)", !url.contains("+") && url.contains("%20"));
        String dec = java.net.URLDecoder.decode(url, "UTF-8");
        check("  요약에 길이만 있고 값은 없음", dec.contains("ssid_len: 8") && dec.contains("pass_len: 12"));
        check("  중요한 항목은 링크에 남음", dec.contains("feat_carplay: yes") && dec.contains("our_ap: yes") && dec.contains("targetdir: "));

        // 아주 긴 값이 와도 링크가 늘어나지 않는다
        StringBuilder big = new StringBuilder(GOOD);
        big.append("made=").append(new String(new char[2000]).replace('\0', 'x')).append('\n');
        String u2 = Report.parse(big.toString()).issueUrl();
        check("긴 값이 와도 링크 <= " + Report.MAX_URL + " (뒤 줄부터 뺌)", u2.length() <= Report.MAX_URL);

        QrCode q = QrCode.encode(url.getBytes("UTF-8"));
        QrCode q2 = QrCode.encode(u2.getBytes("UTF-8"));
        check("QR 버전 " + q.version + " (최대 길이 " + q2.version + ")", q2.version <= 18);
        // 화면 높이를 다 쓰는 정사각형(여백 12dp씩 뺌): 흔한 내비 화면 높이 480, 600, 720 px에서
        for (int h : new int[] { 480, 600, 720 }) {
            int side = h - 24;
            int[] f = Report.fit(side, q2.size);
            boolean inside = f[1] >= 0 && f[1] + f[0] * (q2.size + 8) <= side;
            check("화면 높이 " + h + "px: 칸 " + f[0] + "px (>= 4), QR이 화면 안에 다 들어감", f[0] >= 4 && inside);
        }
        int[] tiny = Report.fit(50, q2.size);
        check("아주 작은 자리도 칸 1px 이상, 음수 여백 없음", tiny[0] >= 1 && tiny[1] >= 0);

        // 1.5.5 설치 진행 기록
        String PR = "pct=40\nstate=run\nstage=이 차의 지도를 만드는 중입니다(1~2분)\nstart=1000\nt=1100\nboot=abc-123\n";
        Report pr = Report.parse(PR);
        check("진행 기록: 이번 부팅이면 진행 중, 40%, 경과 2분 05초", pr.progRunning("abc-123\n") && pr.progPct() == 40
            && "2분 05초".equals(Report.mmss(pr.progElapsed(1125))));
        check("  지난 부팅의 기록이면 진행 막대를 보이지 않음", !pr.progRunning("other") && !pr.progRunning(null));
        check("  15분 넘게 새로 쓰이지 않은 기록은 멈춘 것으로 봄", pr.progRunning("abc-123", 1100 + 900) && !pr.progRunning("abc-123", 1100 + 901));
        check("  진행 중이면 맨 위 판정을 바꾸지 않음", pr.progVerdict("abc-123") == null);
        Report rb = Report.parse(PR.replace("state=run", "state=reboot").replace("stage=이 차의 지도를 만드는 중입니다(1~2분)", "stage=무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요."));
        check("  재부팅 필요 → 그 문구가 판정, 노랑", "무선 카플레이 설정을 마쳤습니다. 내비를 재부팅해 주세요.".equals(rb.progVerdict("abc-123")) && rb.progLevel() == 1);
        Report rf = Report.parse(PR.replace("state=run", "state=fail").replace("stage=이 차의 지도를 만드는 중입니다(1~2분)", "stage=HMG-API가 없습니다."));
        check("  실패 → 그 문구가 판정, 빨강", "HMG-API가 없습니다.".equals(rf.progVerdict("abc-123")) && rf.progLevel() == 2);
        check("  준비됨(done)은 판정을 바꾸지 않음(상태표 판정 그대로)", Report.parse(PR.replace("state=run", "state=done")).progVerdict("abc-123") == null);
        check("  진행률이 이상하면 0~100으로", Report.parse("pct=250").progPct() == 100 && Report.parse("pct=x").progPct() == 0 && Report.parse("pct=-5").progPct() == 0);
        check("  시간: 59초, 1분 00초, 시작 기록 없으면 -", "59초".equals(Report.mmss(59)) && "1분 00초".equals(Report.mmss(60)) && "-".equals(Report.mmss(Report.parse("").progElapsed(5))));

        // 1.5.5 busybox 없는 내비(K3·K8): status.sh가 짧은 상태 파일만 쓴다
        String NB = "support=nobb\nproduct=BDPE.KOR.0000.V039.001.260902\nplatform=tcc803x\npkgver=1.5.5\nusb=saved\nmade=11-07 03:00\n";
        Report nb = Report.parse(NB);
        check("busybox 없는 내비 → '아직 동작하지 않습니다(지원 조사 중)', 노랑", nb.nobb()
            && nb.verdict().startsWith("이 내비에서는 아직 동작하지 않습니다") && nb.level() == 1);
        check("  표는 6줄: 플랫폼, 지원 안 됨, 무선 설정 안 함, 제보 파일 저장함", nb.rows().size() == 6
            && "tcc803x".equals(row(nb, "내비 종류(플랫폼)")) && row(nb, "제보 파일").startsWith("USB의 KoreaProjection-report")
            && row(nb, "무선 설정").startsWith("하지 않았습니다"));
        check("  USB가 없으면 Launch를 다시 누르라고, 쓰지 못했으면 다른 USB", row(Report.parse(NB.replace("usb=saved", "usb=none")), "제보 파일").startsWith("USB를 꽂고")
            && row(Report.parse(NB.replace("usb=saved", "usb=fail")), "제보 파일").startsWith("USB에 쓰지 못함"));
        check("  QR 링크에 support·platform이 들어감", nb.issueUrl().contains("support%3A%20nobb") && nb.issueUrl().contains("platform%3A%20tcc803x"));
        check("  보통 상태 파일은 busybox 없는 내비가 아님(표 15줄 그대로)", !r.nobb() && r.rows().size() == 15);

        // 1.6.2: 순정 카플레이 AP(K3 #15: our_ap=no, our_dhcp는 오판이 고쳐져 no, other_ap=yes)
        String STOCK = GOOD.replace("our_ap=yes", "our_ap=no").replace("our_dhcp=yes", "our_dhcp=no").replace("other_ap=no", "other_ap=yes")
            + "stock_ssid=carplay\nap_mode=stock\n";
        Report st = Report.parse(STOCK);
        check("1.6.2: 순정 카플레이 AP → '준비됨(내비 Wi-Fi 사용)', 초록, 재부팅 안내 없음",
            st.verdict().equals("무선 카플레이 준비됨(내비 Wi-Fi 사용). 아이폰은 설정 → 일반 → CarPlay에서 연결하세요.") && st.level() == 0 && !st.verdict().contains("재부팅"));
        check("  순정 AP + 연결 수 있음 → '연결됨'", Report.parse(STOCK.replace("cp_conn=0", "cp_conn=1")).verdict().equals("무선 카플레이 연결됨"));
        check("  순정 AP여도 무선 모드가 꺼져 있으면 그 안내(빨강)", Report.parse(STOCK.replace("mod_on=yes", "mod_on=no")).verdict().contains("꺼져 있습니다") &&
            Report.parse(STOCK.replace("mod_on=yes", "mod_on=no")).level() == 2);
        check("  순정 AP여도 bridge가 꺼져 있으면 그 안내", Report.parse(STOCK.replace("bridge=on", "bridge=off")).verdict().contains("'Wireless CarPlay' 설정이 꺼져"));
        check("  표에 '무선 카플레이 Wi-Fi: 내비 순정 Wi-Fi'와 핫스팟 칸 설명", "내비 순정 Wi-Fi".equals(row(st, "무선 카플레이 Wi-Fi")) &&
            row(st, "핫스팟 (hostapd)").startsWith("아니요 (순정 Wi-Fi를 쓰므로"));
        Report hs = Report.parse(GOOD.replace("our_ap=yes", "our_ap=no").replace("other_ap=no", "other_ap=yes") + "stock_ssid=hotspot\nap_mode=none\n");
        check("  순정 일반 핫스팟(ap_mode=none)은 예전처럼 '핫스팟이 꺼져' 안내, 노랑", hs.verdict().startsWith("핫스팟이 꺼져") && hs.level() == 1 &&
            "없음".equals(row(hs, "무선 카플레이 Wi-Fi")));
        check("  ap_mode=ours는 예전과 같은 '준비됨'(1.7.3 U-4 문구)", Report.parse(GOOD + "stock_ssid=none\nap_mode=ours\n").verdict().equals("무선 카플레이 준비됨. 아이폰은 설정 → 일반 → CarPlay에서 연결하세요."));
        check("  예전 상태 파일(ap_mode 없음)은 표 15줄 그대로", r.rows().size() == 15 && row(r, "무선 카플레이 Wi-Fi") == null);
        String sd = java.net.URLDecoder.decode(st.issueUrl(), "UTF-8");
        check("  QR 요약에 ap_mode·stock_ssid", sd.contains("ap_mode: stock") && sd.contains("stock_ssid: carplay"));
        Report off = Report.parse(GOOD.replace("our_ap=yes", "our_ap=no").replace("our_dhcp=yes", "our_dhcp=no") + "stock_ssid=none\nap_mode=none\nstock_seen=yes\n");
        check("  순정 AP를 쓰는 차인데 지금 꺼져 있으면 '내비 Wi-Fi가 꺼져' 안내(우리 핫스팟 재부팅 안내 아님), 노랑",
            off.verdict().startsWith("내비 Wi-Fi(무선 카플레이용)가 지금 꺼져 있습니다") && off.level() == 1);
        // 1.7.0: Wi-Fi 장치(wlan0)가 생기지 않아 핫스팟을 못 켬(그랜저 IG #52·#53)
        Report nw = Report.parse(GOOD.replace("our_ap=yes", "our_ap=no") + "nowlan=yes\nap_mode=none\n");
        check("1.7.0 wlan0 없음 → 'Wi-Fi 장치가 켜지지 않아' 안내(재부팅·리포트)", nw.verdict().startsWith("Wi-Fi 장치가 켜지지 않아 핫스팟을 켜지 못했습니다"));
        check("  nowlan=no면 예전 '핫스팟이 꺼져' 안내", Report.parse(GOOD.replace("our_ap=yes", "our_ap=no") + "nowlan=no\n").verdict().startsWith("핫스팟이 꺼져"));
        check("  무선 AA 칸: aa=yes '켜짐', aa=no '꺼짐(kp-aa-off)', 표 줄 수는 그대로", row(Report.parse(GOOD + "aa=yes\n"), "무선 안드로이드 오토 기능").endsWith("· 켜짐")
            && row(Report.parse(GOOD + "aa=no\n"), "무선 안드로이드 오토 기능").endsWith("· 꺼짐(kp-aa-off)") && Report.parse(GOOD + "aa=yes\n").rows().size() == 15);
        String nq = java.net.URLDecoder.decode(Report.parse(GOOD + "state=reboot\naa=yes\nnowlan=yes\n").issueUrl(), "UTF-8");
        check("  QR 요약에 state·aa·nowlan", nq.contains("state: reboot") && nq.contains("aa: yes") && nq.contains("nowlan: yes"));
        // 1.7.1: 알림 기록(토스트 대신), 모드 업데이트 대기
        String nt = "1700000000 boot-A 첫 안내\n1700000100 boot-B 지난 부팅 안내\n1700000200 boot-A 두 번째 안내\n1700000300 boot-A 세 번째\n1700000400 boot-A 네 번째\nbroken\n1700000500 boot-A \n";
        java.util.List<String[]> ns = Report.notices(nt, "boot-A", 3);
        check("1.7.1 알림: 이번 부팅 줄만, 새것부터 최대 3개, 빈 문구·깨진 줄은 건너뜀", ns.size() == 3 && "네 번째".equals(ns.get(0)[1]) && "1700000400".equals(ns.get(0)[0])
            && "두 번째 안내".equals(ns.get(2)[1]));
        check("  부팅 id를 모르거나 기록이 없으면 없음", Report.notices(nt, null, 3).isEmpty() && Report.notices(null, "boot-A", 3).isEmpty() && Report.notices(nt, "boot-C", 3).isEmpty());
        java.util.List<String[]> fresh = Report.notices(nt, "boot-A", 3, 1700000500L, 250);
        check("  보여 주는 시간이 지난 줄(리뷰 M3)은 뺌", fresh.size() == 2 && "네 번째".equals(fresh.get(0)[1]) && "세 번째".equals(fresh.get(1)[1]));
        check("  문구 안의 띄어쓰기는 그대로", "지난 부팅 안내".equals(Report.notices(nt, "boot-B", 1).get(0)[1]));
        check("1.7.1 모드 칸: 새 판 대기 중이면 차의 판과 '대기 중', 아니면 판만, 예전 파일은 '켜짐' 그대로",
            "켜짐 (2.2.0, 새 판으로 바꾸기 대기 중)".equals(row(Report.parse(GOOD + "modver=2.2.0\nmod_pending=yes\n"), "HMG-API 무선 모드"))
            && "켜짐 (2.3.0)".equals(row(Report.parse(GOOD + "modver=2.3.0\nmod_pending=no\n"), "HMG-API 무선 모드"))
            && "켜짐".equals(row(r, "HMG-API 무선 모드")));
        String mq = java.net.URLDecoder.decode(Report.parse(GOOD + "modver=2.2.0\nmod_pending=yes\n").issueUrl(), "UTF-8");
        check("  QR 요약 앞쪽에 mod_pending과 차의 판", mq.contains("mod_pending: yes (2.2.0)"));
        // 1.7.2: 무선 모드 훅이 안 켜짐(스포티지 NQ5 #46)
        Report mh = Report.parse(GOOD + "mod_hooks=off\n");
        check("1.7.2 무선 모드 훅 안 켜짐 → 'HMG-API가 이 차에서 무선 모드를 켜지 못했습니다', 빨강, 모드 칸 표시",
            mh.verdict().startsWith("HMG-API가 이 차에서 무선 모드를 켜지 못했습니다") && mh.level() == 2 && row(mh, "HMG-API 무선 모드").contains("훅이 안 켜짐"));
        check("  mod_hooks=on·없음이면 예전 판정 그대로", Report.parse(GOOD + "mod_hooks=on\n").verdict().equals(r.verdict()) && Report.parse(GOOD + "mod_hooks=on\n").level() == r.level());
        check("  QR 요약 앞쪽에 mod_hooks: off", java.net.URLDecoder.decode(mh.issueUrl(), "UTF-8").contains("mod_hooks: off"));
        // 1.7.2: 상태 안내 파일(hint_write)
        long now = 1700001000L;
        String hb = "boot=boot-A\naa_ready=1700000900\naa=\naa_t=\niph=\niph_t=\nconf=\nconf_t=\n";
        java.util.List<String[]> h0 = Report.hints(hb, "boot-A", now);
        check("베타 1 안내: 신호가 켜져도 '무선 안드로이드 오토 준비됨' 줄을 따로 두지 않음(판정 줄이 카플레이와 한 줄로 말함)", h0.isEmpty());
        check("  지난 부팅·부팅 id 모름·파일 없음이면 없음", Report.hints(hb, "boot-B", now).isEmpty() && Report.hints(hb, null, now).isEmpty()
            && Report.hints(null, "boot-A", now).isEmpty());
        java.util.List<String[]> h1 = Report.hints(hb.replace("aa=\naa_t=", "aa=bt\naa_t=1700000950"), "boot-A", now);
        check("  aa=bt → '안드로이드 폰의 블루투스를 껐다 켜 주세요(…다시 연결)' 노랑 한 줄(준비됨 줄 없음)", h1.size() == 1 && "1".equals(h1.get(0)[0])
            && h1.get(0)[1].startsWith("안드로이드 폰의 블루투스를 껐다 켜 주세요") && h1.get(0)[1].contains("내비 블루투스 화면에서 폰을 다시 연결"));
        check("  aa=cpwait → '카플레이가 연결되어 있어 안드로이드 오토는 기다립니다'",
            Report.hints(hb.replace("aa=\naa_t=", "aa=cpwait\naa_t=1700000950"), "boot-A", now).get(0)[1].equals("카플레이가 연결되어 있어 안드로이드 오토는 기다립니다."));
        java.util.List<String[]> h2 = Report.hints(hb.replace("aa=\naa_t=", "aa=ok\naa_t=1700000980"), "boot-A", now);
        check("  베타 1: aa=ok여도 '무선 안드로이드 오토 연결됨' 줄을 따로 두지 않음(판정 줄이 말함)", h2.isEmpty());
        check("  10분 지난 AA·아이폰 안내는 보이지 않음(서비스가 멈춰 남은 것)",
            Report.hints(hb.replace("aa=\naa_t=", "aa=bt\naa_t=1700000000").replace("iph=\niph_t=", "iph=wifi\niph_t=1700000000"), "boot-A", now).isEmpty());
        java.util.List<String[]> h3 = Report.hints(hb.replace("iph=\niph_t=", "iph=wifi\niph_t=1700000990").replace("conf=\nconf_t=", "conf=wait\nconf_t=1700000990"), "boot-A", now);
        check("  conf=wait·iph=wifi 문구(설정 바뀜이 맨 위, 아이폰 Wi-Fi 지우고 다시 연결)", h3.size() == 2
            && h3.get(0)[1].startsWith("Wi-Fi 설정이 바뀌었습니다") && h3.get(1)[1].contains("아이폰 설정 → Wi-Fi에서 차 네트워크를 지우고 다시 연결하세요"));
        check("  안내 문구에 SSID·비밀번호 같은 값이 들어갈 자리가 없음(코드만 읽음)",
            Report.hints(hb.replace("aa=\n", "aa=MyNet secret\n"), "boot-A", now).isEmpty());
        // 1.7.3(R-2·R-5): [제보 파일 만들기] 버튼
        String mnt = "rootfs / rootfs ro 0 0\n/dev/block/sda1 /storage/usb0 vfat rw 0 0\n";
        check("1.7.3 버튼: /proc/mounts에 /storage/usb0·usb1이 있어야 USB로 봄(폴더 이름이 다른 줄에 섞여도 아님)", Boolean.TRUE.equals(Report.usbMounted(mnt))
            && Boolean.TRUE.equals(Report.usbMounted(mnt.replace("usb0", "usb1")))
            && Boolean.FALSE.equals(Report.usbMounted("rootfs / rootfs ro 0 0\n/dev/x /storage/usb0x vfat rw 0 0\n"))
            && Boolean.FALSE.equals(Report.usbMounted("")));
        check("  리뷰 중간 5: /proc/mounts를 읽지 못하면 '모름'(null)이고 막지 않음(root가 USB를 다시 봄)", Report.usbMounted(null) == null
            && Report.reqBlock(Report.parse(null), Report.parse(null), "boot-A", now, null) == null);
        check("  요청 파일 내용은 '요청 id(부팅 뒤 밀리초) boot_id 부팅 뒤 초' 한 줄뿐", "123456789 boot-A 123456\n".equals(Report.reqLine(123456789L, " boot-A\n")));
        long[] rq = Report.reqParse("123456789 boot-A 123456\n", "boot-A\n");
        check("  요청 파일 읽기: 이번 부팅만, 다른 부팅·깨진 값·옛 꼴(두 칸)이면 null", rq != null && rq[0] == 123456789L && rq[1] == 123456789L
            && Report.reqParse("123456789 boot-B 123456", "boot-A") == null && Report.reqParse("x boot-A 1", "boot-A") == null
            && Report.reqParse("1 boot-A x", "boot-A") == null && Report.reqParse(null, "boot-A") == null
            && Report.reqParse("1700001000 boot-A", "boot-A") == null);
        Report noProg = Report.parse(null);
        Report instRun = Report.parse("pct=40\nstate=run\nstage=x\nt=1700000990\nboot=boot-A\n");
        Report instOld = Report.parse("pct=40\nstate=run\nstage=x\nt=1700000990\nboot=boot-B\n");
        check("  누를 수 있음: 설치 끝남·만드는 중 아님·USB 있음 → null", Report.reqBlock(noProg, noProg, "boot-A", now, true) == null
            && Report.reqBlock(Report.parse("state=done\nboot=boot-A\nt=1700000990\n"), Report.parse("pct=100\nstate=done\nt=1700000990\nboot=boot-A\n"), "boot-A", now, true) == null);
        check("  USB 없음 → 'USB를 꽂은 뒤 다시 눌러 주세요.'", "USB를 꽂은 뒤 다시 눌러 주세요.".equals(Report.reqBlock(noProg, noProg, "boot-A", now, false)));
        check("  설치 중(이번 부팅 state=run) → '설치가 끝난 뒤 눌러 주세요.'(USB가 있어도), 지난 부팅 기록은 막지 않음",
            "설치가 끝난 뒤 눌러 주세요.".equals(Report.reqBlock(instRun, noProg, "boot-A", now, true)) && Report.reqBlock(instOld, noProg, "boot-A", now, true) == null);
        check("  만드는 중(RPROG state=run) → 막음", Report.reqBlock(noProg, instRun, "boot-A", now, true).startsWith("제보 파일을 만드는 중입니다"));
        check("  리뷰 중간 2: 시계가 뒤로 바뀌어 진행 기록 시각이 한참 미래면 '만드는 중'으로 막지 않음",
            Report.reqBlock(noProg, instRun, "boot-A", now - 86400, true) == null && Report.reqBlock(instRun, noProg, "boot-A", now - 86400, true) == null);
        check("  부팅 id를 못 읽으면 막음(요청을 쓸 수 없음)", Report.reqBlock(noProg, noProg, null, now, true) != null);
        Report rpMine = Report.parse("pct=5\nstate=run\nstage=x\nt=1\nboot=boot-A\nreq=777\nreq2=\n");
        Report rpJoin = Report.parse("pct=50\nstate=run\nstage=x\nt=1\nboot=boot-A\nreq=555\nreq2=777\n");
        Report rpOther = Report.parse("pct=100\nstate=done\nstage=x\nt=1700000900\nboot=boot-A\nreq=555\nreq2=\n");
        check("1.7.3 R-5: 진행 기록의 req(또는 만드는 중에 들어온 req2)가 내 요청 id면 0(진행을 따라감), 이전 부팅·다른 id는 아님",
            Report.reqPhase(rpMine, "boot-A", "777", 1) == 0 && Report.reqPhase(rpJoin, "boot-A", "777", 1) == 0
            && Report.reqPhase(rpMine, "boot-B", "777", 1) != 0 && Report.reqPhase(rpOther, "boot-A", "777", 1) != 0
            && Report.reqPhase(Report.parse("state=run\nboot=boot-A\nreq=\n"), "boot-A", "", 1) != 0);
        check("  리뷰 중간 2: 시각(t)이 아니라 id로 짝지음(시계가 뒤로 바뀌어 t가 작아도 내 진행을 따라감)",
            Report.reqPhase(Report.parse("pct=5\nstate=run\nt=5\nboot=boot-A\nreq=777\n"), "boot-A", "777", 1) == 0);
        check("  내 진행이 없으면 3초 안은 1(보냄), 3초부터 2(기다림), 리뷰 중간 4: 120초부터 3(실패), 잴 수 없으면(음수) 1",
            Report.reqPhase(rpOther, "boot-A", "777", 2) == 1 && Report.reqPhase(rpOther, "boot-A", "777", 3) == 2
            && Report.reqPhase(rpOther, "boot-A", "777", 119) == 2 && Report.reqPhase(rpOther, "boot-A", "777", 120) == 3
            && Report.reqPhase(noProg, "boot-A", "777", 120) == 3 && Report.reqPhase(noProg, "boot-A", "777", -5) == 1);
        check("  문구: 기다림(30초 점검과 맞게 '길면 1분쯤'), 실패(Launch를 다시 눌러 달라고), 요청 저장 실패(재부팅), 두 문장 이하",
            Report.REQ_WAITING.equals("요청을 기다리는 중입니다(길면 1분쯤).")
            && Report.REQ_FAILED.equals("제보 파일을 만들지 못했습니다. NEMESIS에서 Launch를 다시 눌러 주세요.")
            && !Report.REQ_WRITE_FAILED.contains("Launch") && Report.REQ_SENT.split("\\. ").length <= 2
            && Report.REQ_LATE >= Report.REQ_FAIL);
        check("  판정 안내에 'Launch로 리포트'가 남지 않음(버튼 안내로 바뀜)",
            Report.parse(GOOD.replace("hooks=on", "hooks=on\nmod_hooks=off")).verdict().contains("[제보 파일 만들기]로 리포트를")
            && !Report.parse(GOOD.replace("our_ap=yes", "our_ap=no\nnowlan=yes")).verdict().contains("Launch로"));
        // --- 1.7.3 2b: U-2·U-3·U-4·U-5·U-7 ---
        Report pRun = Report.parse("pct=40\nstate=run\nstage=무선 모드를 설치하는 중입니다\nstart=1700000000\nt=1700000990\nboot=boot-A\nstep=5/5\n");
        Report pRb = Report.parse("pct=100\nstate=reboot\nstage=x\nt=1700000990\nboot=boot-A\nstep=\n");
        Report pDone = Report.parse("pct=100\nstate=done\nstage=x\nt=1700000990\nboot=boot-A\n");
        check("2b U-2: 이번 부팅 설치 중(run)·재부팅 전(reboot)이면 QR을 막음, 끝남·지난 부팅·기록 없음은 막지 않음",
            pRun.qrBlocked("boot-A") && pRb.qrBlocked("boot-A") && !pDone.qrBlocked("boot-A") && !pRb.qrBlocked("boot-B")
            && !Report.parse(null).qrBlocked("boot-A") && Report.QR_BLOCKED.equals("제보 QR은 설정이 끝난 뒤 Launch를 다시 누르면 나옵니다.")
            && !Report.QR_BLOCKED.contains("재부팅"));
        check("2b U-3: [지금 재부팅]은 이번 부팅 state=reboot일 때만(설치 중 run·끝남·지난 부팅은 아님)",
            pRb.progReboot("boot-A") && !pRun.progReboot("boot-A") && !pDone.progReboot("boot-A") && !pRb.progReboot("boot-B"));
        check("  재부팅 문구: 확인 창·보냄·20초 뒤 실패, 두 문장 이하", Report.RB_CONFIRM.equals("차를 세운 상태에서만 누르세요. 화면이 1~2분 꺼졌다 켜집니다.")
            && Report.RB_SENT.equals("재부팅합니다…") && Report.RB_FAILED.equals("재부팅하지 못했습니다. RESET 버튼이나 NEMESIS 재부팅을 써 주세요.")
            && Report.RB_WAIT == 80 && Report.RB_BUSY.equals("제보 파일을 다 만든 뒤 눌러 주세요."));
        // 1.7.3(리뷰 M2): root가 남긴 재부팅 결과로 이유에 맞는 안내(이번 부팅의 내 요청만)
        Report rr = Report.parse("id=12345\nboot=boot-A\ncode=fix\n");
        check("리뷰 M2·베타 1: 설치 중(install)·설치 마무리 중(fix)만 '마무리하는 중' 안내(RESET 아님)",
            Report.RB_FINISHING.equals(Report.rbAnswer(rr, "boot-A", 12345))
            && Report.RB_FINISHING.equals(Report.rbAnswer(Report.parse("id=12345\nboot=boot-A\ncode=install\n"), "boot-A", 12345))
            && Report.RB_FINISHING.equals("설정을 마무리하는 중입니다. 잠시 뒤 다시 눌러 주세요."));
        // 베타 2 #64: HMG-API 부팅 보호를 부추기지 않으려는 거절(guard) → "2분 뒤에", 이어진 거절로 세지 않음
        Report gd = Report.parse("id=6\nboot=boot-A\ncode=guard\n");
        check("베타 2 #64: guard → '2분 안에 재부팅을 반복하면 … 2~5분 뒤에 다시 눌러 주세요.', 몇 번 이어져도 RESET 안내로 넘기지 않음",
            Report.RB_GUARD.equals(Report.rbAnswer(gd, "boot-A", 6)) && Report.RB_GUARD.equals(Report.rbAnswer(gd, "boot-A", 6, 9)) && !Report.rbStuckCode(gd)
            && Report.RB_GUARD.equals("2분 안에 재부팅을 반복하면 HMG-API가 무선 기능을 끕니다. 내비가 켜지고 2~5분 뒤에 다시 눌러 주세요."));
        // 재리뷰 M2: 바깥 /system 작업(sysw)도 '마무리하는 중', install·sysw가 RB_STUCK_MAX번 넘게 이어지면 RESET 안내
        Report m2s = Report.parse("id=5\nboot=boot-A\ncode=sysw\n"), m2i = Report.parse("id=5\nboot=boot-A\ncode=install\n"),
            m2f = Report.parse("id=5\nboot=boot-A\ncode=fix\n");
        check("재리뷰 M2: sysw → '마무리하는 중', install·sysw가 3번 이어진 뒤(4번째부터)는 RESET 안내, fix는 이어져도 '마무리하는 중'",
            Report.RB_FINISHING.equals(Report.rbAnswer(m2s, "boot-A", 5)) && Report.RB_STUCK_MAX == 3
            && Report.RB_FINISHING.equals(Report.rbAnswer(m2s, "boot-A", 5, 0)) && Report.RB_FINISHING.equals(Report.rbAnswer(m2i, "boot-A", 5, 2))
            && Report.RB_FAILED.equals(Report.rbAnswer(m2s, "boot-A", 5, 3)) && Report.RB_FAILED.equals(Report.rbAnswer(m2i, "boot-A", 5, 7))
            && Report.RB_FINISHING.equals(Report.rbAnswer(m2f, "boot-A", 5, 9)) && Report.rbAnswer(m2s, "boot-B", 5, 9) == null);
        check("  베타 1: root가 더는 내지 않는 rw·state 코드는 '마무리하는 중'이 아님(모르는 값 → RESET 안내)",
            Report.RB_FAILED.equals(Report.rbAnswer(Report.parse("id=12345\nboot=boot-A\ncode=rw\n"), "boot-A", 12345))
            && Report.RB_FAILED.equals(Report.rbAnswer(Report.parse("id=12345\nboot=boot-A\ncode=state\n"), "boot-A", 12345)));
        check("  리뷰 M2: 제보 만드는 중 → RB_BUSY, 늦은·받지 못한 요청 → 다시 누르기, 명령이 돌아옴·모르는 값 → RESET 안내",
            Report.RB_BUSY.equals(Report.rbAnswer(Report.parse("id=7\nboot=boot-A\ncode=collect\n"), "boot-A", 7))
            && Report.RB_RETRY.equals(Report.rbAnswer(Report.parse("id=7\nboot=boot-A\ncode=old\n"), "boot-A", 7))
            && Report.RB_RETRY.equals(Report.rbAnswer(Report.parse("id=7\nboot=boot-A\ncode=bad\n"), "boot-A", 7))
            && Report.RB_FAILED.equals(Report.rbAnswer(Report.parse("id=7\nboot=boot-A\ncode=cmd\n"), "boot-A", 7))
            && Report.RB_FAILED.equals(Report.rbAnswer(Report.parse("id=7\nboot=boot-A\ncode=zzz\n"), "boot-A", 7)));
        check("  리뷰 M2: 다른 요청 id·다른 부팅·코드 없음·결과 없음이면 답 없음(계속 기다림, 45초 뒤에만 RESET 안내)",
            Report.rbAnswer(rr, "boot-A", 12346) == null && Report.rbAnswer(rr, "boot-B", 12345) == null
            && Report.rbAnswer(Report.parse("id=12345\nboot=boot-A\n"), "boot-A", 12345) == null
            && Report.rbAnswer(Report.parse(null), "boot-A", 12345) == null && Report.rbAnswer(rr, null, 12345) == null);
        check("  리뷰 M2: 새 안내 두 문장 이하", Report.RB_RETRY.equals("재부팅 요청을 받지 못했습니다. 다시 눌러 주세요."));
        // 베타 1 리뷰 3: 감시자가 끝났으면 요청을 보내지 않고 바로 "Launch를 다시"
        String wf = "boot=boot-A\nuntil=700\n";
        check("베타 1 리뷰 3: 감시자 끝 시각 전이면 보냄, 끝났거나(3초 여유) 다른 부팅·파일 없음·깨진 값이면 '끝남'",
            !Report.watchGone(wf, "boot-A", 600) && Report.watchGone(wf, "boot-A", 697) && Report.watchGone(wf, "boot-A", 800)
            && Report.watchGone(wf, "boot-B", 600) && Report.watchGone(null, "boot-A", 600) && Report.watchGone("boot=boot-A\nuntil=x\n", "boot-A", 600)
            && Report.watchGone(wf, null, 600));
        check("  베타 1 리뷰 3: 안내 문구(한 문장)", Report.RB_NOWATCH.equals("NEMESIS에서 Launch를 다시 누른 뒤 눌러 주세요."));
        // 베타 1 리뷰 A: 기기는 Wi-Fi에 붙었는데 카플레이가 안 열림
        java.util.List<String[]> hn = Report.hints("boot=boot-A\naa_ready=\naa=\naa_t=\niph=nocp\niph_t=1700000990\nconf=\nconf_t=\n", "boot-A", 1700001000L);
        check("베타 1 리뷰 A: iph=nocp → '폰이 차 Wi-Fi에 연결됐지만 카플레이가 시작되지 않았습니다. 내비를 재부팅해 주세요.' 노랑",
            hn.size() == 1 && "1".equals(hn.get(0)[0]) && "폰이 차 Wi-Fi에 연결됐지만 카플레이가 시작되지 않았습니다. 내비를 재부팅해 주세요.".equals(hn.get(0)[1]));
        check("2b U-4: 준비됨 문구: 무선 AA 켜진 차는 아이폰·안드로이드 둘 다, 꺼진 차·옛 상태 파일은 아이폰만, 순정 AP 차는 아이폰만",
            Report.parse(GOOD + "aa=yes\n").verdict().equals(Report.READY_BOTH) && Report.READY_BOTH.contains("무선 Android Auto 사용")
            && Report.parse(GOOD + "aa=no\n").verdict().startsWith("무선 카플레이 준비됨. 아이폰은 설정 → 일반 → CarPlay")
            && !Report.parse(GOOD + "aa=no\n").verdict().contains("안드로이드") && r.verdict().startsWith("무선 카플레이 준비됨")
            && Report.parse(GOOD.replace("our_ap=yes", "our_ap=no").replace("our_dhcp=yes", "our_dhcp=no") + "ap_mode=stock\naa=yes\n").verdict().startsWith("무선 카플레이 준비됨(내비 Wi-Fi 사용). 아이폰은"));
        String nt2b = "1700000100 boot-A Korea Projection: 무선 카플레이를 설정하는 중입니다. 약 5분 동안 내비를 재부팅하거나 끄지 마세요.\n"
            + "1700000995 boot-A 무선 모드 적용에 실패했습니다.\n";
        java.util.List<String[]> n0 = Report.notices(nt2b, "boot-A", 3, now, 1800, pRb.progEndedAt("boot-A"));
        check("2b U-5: 진행이 끝난 시각보다 앞선 알림은 숨김('재부팅하지 마세요'가 '재부팅해 주세요'와 함께 안 보임), 뒤의 알림은 보임",
            n0.size() == 1 && n0.get(0)[1].equals("무선 모드 적용에 실패했습니다.") && pRun.progEndedAt("boot-A") == 0 && pRb.progEndedAt("boot-B") == 0);
        java.util.List<String[]> n1 = Report.notices(nt2b, "boot-A", 3, now, 1800);
        check("  알림 앞의 'Korea Projection: '은 뗌(진행이 안 끝났으면 둘 다 보임)", n1.size() == 2 && n1.get(1)[1].startsWith("무선 카플레이를 설정하는 중입니다"));
        check("2b U-7: 단계 표시 'step=5/5' → '단계 5/5', 옛 형식(줄 없음)·빈 값·깨진 값은 ''", "단계 5/5".equals(pRun.progStep())
            && "".equals(pRb.progStep()) && "".equals(pDone.progStep()) && "".equals(Report.parse("step=6/5\n").progStep())
            && "".equals(Report.parse("step=x/5\n").progStep()) && "".equals(Report.parse("step=3/\n").progStep()));
        check("  10분(600초) 넘으면 '평소보다 오래 걸립니다. 15분이 지나도 그대로면 내비를 재부팅해 주세요.', 그 전은 ''",
            "".equals(pRun.progSlow(1700000599L)) && Report.SLOW_MSG.equals(pRun.progSlow(1700000600L))
            && Report.SLOW_MSG.equals("평소보다 오래 걸립니다. 15분이 지나도 그대로면 내비를 재부팅해 주세요.")
            && Report.PROGRESS_HINT.equals("보통 5분 안에 끝납니다. 끝날 때까지 내비를 끄지 마세요.") && Report.SLOW < Report.STALE);
        // --- 1.7.3 3단계: 판정은 status.sh 한 곳(K-5), 앱은 결과를 그대로 보임 ---
        String V3 = GOOD + "verdict=nochip\nverdict_lv=2\nverdict_msg=이 차는 Wi-Fi 칩이 켜지지 않아 지원하기 어렵습니다. USB Wi-Fi 동글로 쓰는 방법을 준비하고 있습니다.\nverdict_end=yes\nfirst=\ns1=설치: 안 됨(위 안내를 보세요)\ns2=무선 Wi-Fi: 칩이 켜지지 않음\ns3=폰 연결: 지금 연결된 카플레이 없음\n";
        Report v3 = Report.parse(V3);
        check("3단계 K-5: 상태 파일에 판정 결과가 있으면 그 문구·수준을 그대로(앱이 따로 판정하지 않음)", v3.verdict().startsWith("이 차는 Wi-Fi 칩이 켜지지 않아") && v3.level() == 2);
        check("  옛 상태 파일(판정 결과 없음)은 예전 판정 그대로", r.verdict().startsWith("무선 카플레이 준비됨") && r.level() == 0
            && Report.parse(GOOD.replace("our_ap=yes", "our_ap=no")).verdict().startsWith("핫스팟이 꺼져"));
        check("  수준 값이 깨졌으면 1(확인 필요), 범위 밖은 0~2로", Report.parse(V3.replace("verdict_lv=2", "verdict_lv=x")).level() == 1
            && Report.parse(V3.replace("verdict_lv=2", "verdict_lv=9")).level() == 2);
        check("3단계 U-6: '안 됨'으로 끝나면(verdict_end=yes) 지우는 법 한 줄, 아니면 없음", Report.UNINSTALL_HINT.equals(v3.endHint())
            && Report.UNINSTALL_HINT.equals("지우려면 NEMESIS Manager → Korea Projection → Uninstall 뒤 재부팅하세요. 유선 카플레이는 그대로입니다.")
            && "".equals(Report.parse(V3.replace("verdict_end=yes", "verdict_end=no")).endHint()) && "".equals(r.endHint()));
        check("3단계 U-9: 요약 3줄(설치·무선 Wi-Fi·폰 연결), 옛 상태 파일은 없음", v3.summary().size() == 3 && v3.summary().get(1).equals("무선 Wi-Fi: 칩이 켜지지 않음") && r.summary().isEmpty());
        check("3단계 G-4: 먼저 할 일 줄은 상태 파일 값 그대로", "먼저 할 일: x".equals(Report.parse(V3.replace("first=\n", "first=먼저 할 일: x\n")).firstTodo()) && "".equals(v3.firstTodo()));
        String q3 = java.net.URLDecoder.decode(v3.issueUrl(), "UTF-8");
        check("3단계 K-5: QR 요약 앞쪽에 verdict(상태 화면·리포트와 같은 값)", q3.contains("(QR summary)\nverdict: nochip\n"));
        String qc = java.net.URLDecoder.decode(Report.parse(V3.replace("verdict=nochip", "verdict=newconnected")).issueUrl(), "UTF-8");
        check("3단계 U-10: 확인 안 된 차가 연결되면 QR 요약 맨 앞에 result: connected", qc.contains("(QR summary)\nresult: connected\nverdict: newconnected\n"));
        // --- 2b 재리뷰 ---
        check("2b 재리뷰 중간 2: 재부팅을 막는 것은 진행 기록 '만드는 중'(이번 부팅)이나 내 요청이 아직 기다리는 중일 때뿐(실패한 요청은 막지 않음)",
            Report.rbBusy(true, noProg, "boot-A", now) && Report.rbBusy(false, instRun, "boot-A", now)
            && !Report.rbBusy(false, noProg, "boot-A", now) && !Report.rbBusy(false, rpOther, "boot-A", now)
            && !Report.rbBusy(false, instOld, "boot-A", now));
        // --- 2b 리뷰 반영 ---
        Report pUp = Report.parse("pct=40\nstate=run\nstage=x\nstart=1700000000\nt=1700000990\nboot=boot-A\nust=100\nut=150\n");
        check("2b 리뷰 L6: 진행 기록에 부팅 뒤 초(ust)가 있으면 경과를 그것으로(시계가 앞당겨져 시각으로는 11분이어도 부팅 뒤 5분이면 안내 없음)",
            "".equals(pUp.progSlow(1700000660L, 400)) && Report.SLOW_MSG.equals(pUp.progSlow(1700000000L, 700))
            && Report.SLOW_MSG.equals(pUp.progSlow(1700000660L, -1)) && Report.SLOW_MSG.equals(pUp.progSlow(1700000660L, 50)));
        check("  /proc/uptime 읽기('123.45 67.8' → 123), 못 읽으면 -1", Report.upSec("123.45 67.8\n") == 123 && Report.upSec(null) == -1 && Report.upSec("x") == -1);
        check("2b 리뷰 L7: 끝난(done) 기록은 알림 숨기기 기준이 아님(부팅마다 다시 써서 다른 안내를 가리지 않게), 실패(fail)는 기준",
            pDone.progEndedAt("boot-A") == 0 && Report.parse("pct=100\nstate=fail\nt=1700000990\nboot=boot-A\n").progEndedAt("boot-A") == 1700000990L);
        System.out.println(fails == 0 ? "Java 모두 통과" : "Java 실패 " + fails + "개");
        System.exit(fails == 0 ? 0 : 1);
    }
}
