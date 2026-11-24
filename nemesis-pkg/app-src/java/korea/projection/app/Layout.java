package korea.projection.app;

/**
 * 1.8.0(SC-1): 상태 화면(Launch) 배치 계산. 안드로이드 없이 PC에서 시험하는 순수 계산이다(tests/LayoutTest.java).
 *
 * 근거: drafts/1.8.0-launch-screen-design.md 10장(확정 시안 2026-11-16), drafts/1.8.0-launch-mockup.html의 layout().
 * 입력은 뷰가 실제로 받은 가로·세로 픽셀(onSizeChanged)과 QR 한 변의 칸 수다. DisplayMetrics·dp는 쓰지 않는다.
 *
 * 화면 짜임(모든 크기):
 *   맨 위 줄  [상태 줄][닫기]
 *   아래 칸   넓은 화면(가로÷세로 2 이상, 설정 칸이 충분할 때)  [상태 칸 | 설정 칸 | QR]
 *             그 밖                                             [지금 상태·버튼 + 설정 | QR]  (QR 먼저)
 * QR은 늘 보인다(소유자 결정 2026-11-16): 아래 칸 높이 전체의 정사각형을 맨 오른쪽에 두고, 칸 크기는 Report.fit으로 정한다.
 * 칸이 4px에 못 미쳐도 문구로 바꾸지 않고 받은 크기대로 그린다(qrSmall()로 알 수만 있다).
 */
final class Layout {
    /** 넓은 화면: [상태 칸 | 설정 칸 | QR] */
    static final int WIDE = 0;
    /** QR 먼저: [지금 상태·버튼 + 설정 | QR] */
    static final int QR_FIRST = 1;

    /**
     * QR 칸이 이보다 작으면 찍기 어려울 수 있다(경계 4px, 시안 기준). qrSmall()로 알리기만 한다.
     * 배치를 바꾸는 데는 쓰지 않는다: 두 배치 모두 QR 한 변이 아래 칸 높이라 바꿔도 칸이 커지지 않는다.
     */
    static final int QR_CELL_MIN = 4;
    /** 넓은 화면의 상태 칸 너비 = 본문 글자 × 이 값(시안에서 22부터 설정 설명 줄이 잘려 20) */
    static final int INFO_CHARS = 20;
    /** 넓은 화면을 쓰려면 설정 칸이 본문 글자 몇 개분 이상이어야 하는가(토글 줄 제목·설명이 읽힐 너비) */
    static final int SETTINGS_MIN_CHARS = 16;
    /** 줄 높이 배수(글자 크기 × 이 값). 안드로이드 기본 줄 간격과 시안의 line-height 1.35를 맞춘다 */
    static final float LINE = 1.35f;

    final int width, height, kind;
    /** 기준 단위: 높이의 1/100 */
    final float u;
    /** 글자 크기(px): 판정, 본문, 작은 글자. 상태 줄이 넘칠 때 판정 글자는 본문 크기까지 줄인다 */
    final int textVerdict, textBody, textSmall;
    /** 바깥 여백, 칸 사이 간격, 누르는 영역 높이(토글 줄·버튼) */
    final int pad, gap, touch;
    /** 맨 위 줄 높이(상태 줄 한 줄과 닫기 단추 중 큰 쪽) */
    final int topHeight;
    /** 아래 칸의 위치와 크기 */
    final int bodyTop, bodyHeight;
    /** 넓은 화면의 상태 칸 너비(QR 먼저면 0) */
    final int infoWidth;
    /** 설정 칸 너비. QR 먼저면 지금 상태·버튼·설정이 함께 쓰는 왼쪽 칸 너비 */
    final int settingsWidth;
    /** QR 자리: 왼쪽 위 x, 한 변(정사각형, y는 bodyTop) */
    final int qrX, qrSide;
    /** QR 칸 픽셀과 자리 안 여백(Report.fit과 같음) */
    final int qrCell, qrOffset;
    /** QR 먼저 배치에서 왼쪽 칸이 좁아 버튼 두 개를 세로로 쌓아야 하는가 */
    final boolean buttonsStacked;

    private Layout(int width, int height, int kind, float u, int textVerdict, int textBody, int textSmall,
                   int pad, int gap, int touch, int topHeight, int bodyTop, int bodyHeight,
                   int infoWidth, int settingsWidth, int qrX, int qrSide, int qrCell, int qrOffset, boolean buttonsStacked) {
        this.width = width; this.height = height; this.kind = kind; this.u = u;
        this.textVerdict = textVerdict; this.textBody = textBody; this.textSmall = textSmall;
        this.pad = pad; this.gap = gap; this.touch = touch;
        this.topHeight = topHeight; this.bodyTop = bodyTop; this.bodyHeight = bodyHeight;
        this.infoWidth = infoWidth; this.settingsWidth = settingsWidth;
        this.qrX = qrX; this.qrSide = qrSide; this.qrCell = qrCell; this.qrOffset = qrOffset;
        this.buttonsStacked = buttonsStacked;
    }

    static int clamp(float v, int lo, int hi) {
        int r = Math.round(v);
        return r < lo ? lo : r > hi ? hi : r;
    }

    /**
     * 배치를 계산한다.
     * @param width  뷰가 받은 가로 픽셀
     * @param height 뷰가 받은 세로 픽셀
     * @param qrSize QR 한 변의 칸 수(여백 빼고, 예: 버전 18이면 89)
     */
    static Layout of(int width, int height, int qrSize) {
        int w = Math.max(1, width), h = Math.max(1, height);
        float u = h / 100f;
        int textVerdict = clamp(4.6f * u, 16, 36);
        int textBody = clamp(3.8f * u, 14, 30);
        int textSmall = clamp(3.0f * u, 12, 24);
        int pad = clamp(2.4f * u, 8, 24);
        int gap = clamp(1.8f * u, 6, 18);
        int touch = clamp(12f * u, 44, 96);

        // 맨 위 줄: 상태 줄은 늘 한 줄(판정 글자 + 위아래 여백 1.6u씩). 닫기 단추는 누르는 높이의 0.8 이상
        int statusLine = Math.round(textVerdict * LINE + 3.2f * u);
        int closeMin = Math.round(touch * 0.8f);
        int topHeight = Math.max(statusLine, closeMin);
        int bodyTop = pad + topHeight + gap;
        int bodyHeight = Math.max(1, h - bodyTop - pad);
        int inner = Math.max(1, w - 2 * pad);

        // 넓은 화면을 먼저 해 본다: QR 한 변 = 아래 칸 높이, 상태 칸 = 본문 글자 × 20, 남는 폭이 설정 칸
        if (w >= 2 * h) {
            int infoWidth = textBody * INFO_CHARS;
            int qrSide = bodyHeight;
            int settings = inner - infoWidth - qrSide - 2 * gap;
            if (settings >= textBody * SETTINGS_MIN_CHARS) {
                int[] f = Report.fit(qrSide, qrSize);
                return new Layout(w, h, WIDE, u, textVerdict, textBody, textSmall, pad, gap, touch,
                    topHeight, bodyTop, bodyHeight, infoWidth, settings, pad + inner - qrSide, qrSide, f[0], f[1], false);
            }
        }

        // QR 먼저: QR이 먼저다(QR은 늘 보인다). QR 한 변 = 아래 칸 높이, 왼쪽 칸에는 버튼 하나 폭만 남긴다.
        // 왼쪽 칸이 버튼 두 개(가로)보다 좁으면 버튼을 세로로 쌓는다(리뷰 높음 1: 버튼 폭에 QR이 밀려 쪼그라들던 것)
        int button = Math.round(textBody * 9.5f);
        int qrSide = Math.min(bodyHeight, inner - gap - button);
        // 그래도 QR 한 변이 칸 1px로 그릴 크기(qrSize+8)보다 작으면 왼쪽 칸을 더 줄인다. Report.fit은 자리보다 작아도
        // 칸 1px로 그려 자리를 넘치므로, 화면이 허락하는 한 이 하한을 지킨다
        int qrMin = Math.min(qrSize + 8, Math.min(bodyHeight, inner));
        qrSide = Math.max(Math.max(1, qrMin), qrSide);
        int left = Math.max(0, inner - gap - qrSide);
        boolean stacked = left < button * 2 + gap;
        int[] f = Report.fit(qrSide, qrSize);
        return new Layout(w, h, QR_FIRST, u, textVerdict, textBody, textSmall, pad, gap, touch,
            topHeight, bodyTop, bodyHeight, 0, left, pad + inner - qrSide, qrSide, f[0], f[1], stacked);
    }

    /** 화면이 너무 작아 아래 칸이 들어가지 않는가(높이 약 50px 미만). 앱은 이때 그리지 않는다 */
    boolean tooSmall() {
        return bodyTop + bodyHeight > height || qrSide < 1;
    }

    /** QR 칸이 경계(4px)보다 작은가. 이때도 QR은 그린다 */
    boolean qrSmall() {
        return qrCell < QR_CELL_MIN;
    }

    /**
     * 상태 줄에 들어갈 판정 글자 크기. 판정 글자에서 본문 글자까지 줄여 한 줄에 들어가는 가장 큰 크기를 돌려준다.
     * 본문 글자에서도 넘치면 -1(흐르는 글자로 보인다).
     * 글자 폭은 크기에 비례한다고 보고, 부르는 쪽이 판정 글자 크기로 한 번 잰 폭(Paint.measureText)만 받는다.
     * (익명 클래스·람다를 쓰지 않는다: JDK 21 + d8 8.2가 익명 클래스에서 멈춘 적이 있음, StatusActivity 참고)
     * @param widthAtVerdict 판정 글자 크기(textVerdict)로 잰 문구 폭(px)
     * @param avail          상태 줄 안에서 글이 쓸 수 있는 폭(px)
     */
    int verdictSize(float widthAtVerdict, float avail) {
        if (widthAtVerdict <= avail) return textVerdict;
        if (widthAtVerdict <= 0 || avail <= 0) return -1;
        int s = (int) Math.floor(textVerdict * avail / widthAtVerdict);
        return s >= textBody ? s : -1;
    }

    @Override
    public String toString() {
        return width + "x" + height + " " + (kind == WIDE ? "WIDE" : "QR_FIRST") + " u=" + u
            + " text=" + textVerdict + "/" + textBody + "/" + textSmall + " pad=" + pad + " gap=" + gap + " touch=" + touch
            + " top=" + topHeight + " body=" + bodyTop + "+" + bodyHeight + " info=" + infoWidth + " settings=" + settingsWidth
            + " qr=" + qrX + "+" + qrSide + " cell=" + qrCell + " off=" + qrOffset + (buttonsStacked ? " 버튼세로" : "");
    }
}
