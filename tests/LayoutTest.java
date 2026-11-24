package korea.projection.app;

/**
 * 1.8.0(SC-1): 상태 화면 배치 계산(Layout)을 PC에서 시험한다.
 * 기대값은 drafts/1.8.0-launch-screen-design.md 9·10장의 시안 측정값(브라우저 글꼴 기준)이다.
 * 실패하면 "FAIL ..."을 찍고 종료 코드 1.
 * 돌리는 법: javac -encoding UTF-8 -d 출력폴더 Report.java QrCode.java Layout.java tests/LayoutTest.java
 *            java -cp 출력폴더 korea.projection.app.LayoutTest
 */
public class LayoutTest {
    static int fails = 0;
    /** 제보 링크 560자 → QR 버전 18(89칸) */
    static final int QR = 89;

    static void check(String name, boolean ok) {
        System.out.println((ok ? "ok   " : "FAIL ") + name);
        if (!ok) fails++;
    }

    /** 모든 크기에서 지켜야 하는 것 */
    static void invariants(Layout l) {
        String n = l.width + "x" + l.height;
        boolean ok = true;
        StringBuilder why = new StringBuilder();
        // QR은 늘 보인다: 칸 1px 이상, 화면 안, 맨 오른쪽 끝
        if (l.qrCell < 1) { ok = false; why.append(" 칸<1"); }
        if (l.qrX < 0 || l.qrX + l.qrSide > l.width) { ok = false; why.append(" QR 가로 밖"); }
        if (l.bodyTop + l.qrSide > l.height) { ok = false; why.append(" QR 세로 밖"); }
        // 실제로 그리는 크기(여백 + 칸 × (칸 수+8))가 화면 안(리뷰 중간 2: 자리가 아니라 그린 크기로 잰다)
        int drawn = l.qrOffset + l.qrCell * (QR + 8);
        if (l.qrX + drawn > l.width - l.pad) { ok = false; why.append(" 그린 QR 가로 넘침 ").append(l.qrX + drawn); }
        if (l.bodyTop + drawn > l.height) { ok = false; why.append(" 그린 QR 세로 넘침"); }
        if (l.tooSmall()) { ok = false; why.append(" 너무 작음"); }
        if (l.qrX + l.qrSide != l.width - l.pad) { ok = false; why.append(" QR이 오른쪽 끝이 아님"); }
        // 칸 픽셀로 그린 QR이 자리 안에 들어간다
        if (l.qrOffset * 2 + l.qrCell * (QR + 8) > l.qrSide) { ok = false; why.append(" QR이 자리보다 큼"); }
        // QR 먼저 배치: 왼쪽 칸에 버튼 하나는 들어감
        if (l.kind == Layout.QR_FIRST && l.settingsWidth < Math.round(l.textBody * 9.5f)) { ok = false; why.append(" 왼쪽 칸 < 버튼 하나"); }
        // 왼쪽 칸들의 폭 합이 화면을 넘지 않는다
        int used = l.pad * 2 + l.infoWidth + l.settingsWidth + l.qrSide + (l.kind == Layout.WIDE ? 2 : 1) * l.gap;
        if (used > l.width) { ok = false; why.append(" 폭 합 ").append(used); }
        // 누르는 높이 44px 이상, 글자 크기 순서
        if (l.touch < 44) { ok = false; why.append(" 누르는 높이"); }
        if (!(l.textVerdict >= l.textBody && l.textBody >= l.textSmall)) { ok = false; why.append(" 글자 순서"); }
        // 넓은 화면은 가로÷세로 2 이상일 때만
        if (l.kind == Layout.WIDE && l.width < 2 * l.height) { ok = false; why.append(" 좁은데 넓은 화면"); }
        check("  불변 " + n + (ok ? "" : why.toString()), ok);
    }

    public static void main(String[] a) {
        System.out.println("== 확정 시안의 세 크기(설계 10장)");
        Layout l = Layout.of(1920, 720, QR);
        System.out.println("  " + l);
        check("1920x720(10.25·12.3인치): 넓은 화면", l.kind == Layout.WIDE);
        check("  QR 칸 6px(시안과 같음)", l.qrCell == 6);
        check("  상태 칸 = 본문 글자 27px × 20 = 540px", l.textBody == 27 && l.infoWidth == 540);
        check("  설정 칸이 본문 글자 16개분 이상", l.settingsWidth >= l.textBody * Layout.SETTINGS_MIN_CHARS);
        check("  누르는 높이 86px", l.touch == 86);

        l = Layout.of(1920, 660, QR);
        System.out.println("  " + l);
        check("1920x660(상태 막대 가정): 넓은 화면, QR 칸 5px", l.kind == Layout.WIDE && l.qrCell == 5);
        check("  상태 칸 500px", l.infoWidth == 500);

        l = Layout.of(800, 480, QR);
        System.out.println("  " + l);
        check("800x480(8인치 추정): QR 먼저, QR 칸 4px", l.kind == Layout.QR_FIRST && l.qrCell == 4 && !l.qrSmall());
        check("  왼쪽 칸에 버튼 두 개(가로)가 들어감", l.settingsWidth >= Math.round(l.textBody * 9.5f) * 2 + l.gap);

        System.out.println("== 배치 고르기");
        check("1280x720(가로÷세로 1.78): QR 먼저", Layout.of(1280, 720, QR).kind == Layout.QR_FIRST);
        Layout w1280 = Layout.of(1280, 480, QR);
        check("1280x480(2.67): 넓은 화면, QR 칸 4px, 설정 칸 본문 글자 16개분 이상",
            w1280.kind == Layout.WIDE && w1280.qrCell == 4 && w1280.settingsWidth >= w1280.textBody * Layout.SETTINGS_MIN_CHARS);
        Layout l640 = Layout.of(640, 480, QR);
        check("640x480: QR이 아래 칸 높이 전체(칸 4px), 버튼은 세로로", l640.qrSide == l640.bodyHeight && l640.qrCell == 4 && l640.buttonsStacked);
        check("800x480: 버튼은 가로 한 줄", !Layout.of(800, 480, QR).buttonsStacked);
        check("960x480(딱 2): 설정 칸이 모자라 QR 먼저", Layout.of(960, 480, QR).kind == Layout.QR_FIRST);
        check("2560x720: 넓은 화면, QR 칸 6px", Layout.of(2560, 720, QR).kind == Layout.WIDE && Layout.of(2560, 720, QR).qrCell == 6);

        System.out.println("== QR은 늘 보인다");
        Layout tiny = Layout.of(400, 240, QR);
        System.out.println("  " + tiny);
        check("400x240: 칸 4px 미만이어도 QR을 그림(qrSmall), 그린 크기가 자리 안",
            tiny.qrCell >= 1 && tiny.qrSmall() && tiny.qrCell * (QR + 8) <= tiny.qrSide);
        Layout port = Layout.of(480, 800, QR);
        System.out.println("  " + port);
        check("480x800(세로 화면): QR이 자리 안에 칸 1px 이상(97px 이상 자리)", port.qrSide >= QR + 8 && port.qrX + port.qrSide <= 480);
        check("링크를 줄이면(버전 13, 69칸) 800x480 칸이 커짐", Layout.of(800, 480, 69).qrCell > Layout.of(800, 480, QR).qrCell);

        System.out.println("== 상태 줄 글자(늘 한 줄)");
        l = Layout.of(1920, 720, QR);
        check("들어가면 판정 글자 그대로(33px)", l.verdictSize(1000f, 1500f) == l.textVerdict);
        int s = l.verdictSize(1800f, 1500f);
        check("조금 넘치면 줄임: 33 × 1500/1800 = 27.5 → 27px(본문 글자 하한)", s == 27);
        check("본문 글자에서도 넘치면 -1(흐르는 글자)", l.verdictSize(3000f, 1500f) == -1);
        check("폭이 0이면 -1", l.verdictSize(1000f, 0f) == -1);

        System.out.println("== 여러 크기에서 불변(480~1080 높이, 가로 1.2~4배)");
        int[][] sizes = { { 800, 480 }, { 1024, 600 }, { 1280, 480 }, { 1280, 720 }, { 1920, 660 }, { 1920, 720 },
                          { 1920, 1080 }, { 2560, 720 }, { 2880, 720 }, { 960, 480 }, { 640, 480 }, { 400, 240 },
                          { 320, 240 }, { 480, 800 }, { 600, 1024 }, { 720, 1280 }, { 1920, 360 } };
        for (int[] z : sizes) invariants(Layout.of(z[0], z[1], QR));

        // 뷰가 아직 크기를 못 받았을 때(0·1px)도 예외 없이 값을 낸다. 앱은 이때 그리지 않는다
        boolean noThrow = true;
        try { Layout.of(0, 0, QR); Layout.of(1, 1, QR); Layout.of(-5, 10, QR); } catch (RuntimeException e) { noThrow = false; }
        check("0x0·1x1·음수 크기에서 예외 없음, 너무 작음으로 알림", noThrow && Layout.of(0, 0, QR).qrCell >= 1 && Layout.of(1920, 40, QR).tooSmall());

        System.out.println(fails == 0 ? "모두 통과" : "실패 " + fails);
        System.exit(fails == 0 ? 0 : 1);
    }
}
