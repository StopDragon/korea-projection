package korea.projection.app;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.os.SystemClock;
import android.util.TypedValue;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

/**
 * 1.8.0(SC-2): 직접 그린 위젯. Holo 기본 위젯(Button·Switch·ProgressBar)을 쓰지 않는다(설계 3장 S-3).
 * - 크기는 dp가 아니라 뷰가 받은 픽셀로 계산한 Layout에서 온다(Screen이 크기를 받으면 모든 위젯의 size(Layout)를 부른다).
 * - onDraw 안에서 Paint·RectF·문자열을 새로 만들지 않는다(크기·글이 바뀔 때 미리 계산).
 * - 애니메이션은 없다(S-4). 누르는 동안 바탕색만 바뀐다. 예외는 상태 줄의 흐르는 글자 하나(소유자 결정 2026-11-16).
 * - 익명 클래스·람다를 쓰지 않는다(JDK 21 + d8 8.2가 익명 클래스에서 멈춘 적이 있음).
 * 판단(색·문구·토글 상태·숨길 줄)은 Ui에 있다.
 */
final class Widgets {
    private Widgets() { }

    /** Layout을 받아 크기·글자를 정하는 위젯 */
    interface Sized {
        void size(Layout l);
    }

    /** 보통 TextView의 글자 크기 종류(태그로 단다): 본문, 작은 글자 */
    static final String T_BODY = "b", T_SMALL = "s";

    static TextView text(Context c, String s, String kind, int color) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextColor(color);
        t.setTag(kind);
        t.setIncludeFontPadding(false);
        return t;
    }

    /** 하위 뷰를 모두 돌며 크기를 정한다: Sized는 size(l), 태그가 달린 TextView는 글자 크기 */
    static void apply(View v, Layout l) {
        if (v instanceof Sized) ((Sized) v).size(l);
        else if (v instanceof TextView) {
            Object k = v.getTag();
            if (T_BODY.equals(k)) ((TextView) v).setTextSize(TypedValue.COMPLEX_UNIT_PX, l.textBody);
            else if (T_SMALL.equals(k)) ((TextView) v).setTextSize(TypedValue.COMPLEX_UNIT_PX, l.textSmall);
            if (k != null) {
                int ph = Math.round(1.4f * l.u), pv = Math.round(0.8f * l.u);
                // 바탕색이 있는 글(알림·먼저 할 일·저장 표시)만 안쪽 여백을 둔다
                if (v.getBackground() != null) v.setPadding(ph, pv, ph, pv);
            }
        }
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++) apply(g.getChildAt(i), l);
        }
    }

    /** 문구를 폭에 맞게 여러 줄로 나눈다(빈칸에서 나누고, 빈칸이 없으면 글자에서). 그리기 전에만 부른다 */
    static List<String> wrap(Paint p, String s, float w) {
        List<String> out = new ArrayList<String>();
        if (s == null || s.isEmpty()) return out;
        int i = 0;
        while (i < s.length()) {
            int n = p.breakText(s, i, s.length(), true, Math.max(1f, w), null);
            if (n <= 0) n = 1;
            int end = i + n;
            if (end < s.length()) {
                int sp = s.lastIndexOf(' ', end);
                if (sp > i) end = sp + 1;
            }
            out.add(s.substring(i, end).trim());
            i = end;
        }
        return out;
    }

    /** 한 줄에 넘치면 끝을 "…"로 자른다 */
    static String ellipsize(Paint p, String s, float w) {
        if (s == null) return "";
        if (p.measureText(s) <= w) return s;
        float dots = p.measureText("…");
        int n = p.breakText(s, true, Math.max(0f, w - dots), null);
        return n <= 0 ? "…" : s.substring(0, n) + "…";
    }

    static Paint paint(int color, boolean bold) {
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(color);
        if (bold) p.setTypeface(Typeface.DEFAULT_BOLD);
        return p;
    }

    private static final Paint.FontMetrics FM = new Paint.FontMetrics();

    /** 글 한 줄의 바탕선(위에서 잰 y): 줄 높이 h 안에서 가운데 */
    static float baseline(Paint p, float top, float h) {
        // 리뷰 낮음 5: onDraw에서 불리므로 객체를 새로 만들지 않고 하나를 다시 쓴다(화면 스레드에서만 부름)
        Paint.FontMetrics fm = FM;
        p.getFontMetrics(fm);
        return top + (h - (fm.descent - fm.ascent)) / 2f - fm.ascent;
    }

    // ------------------------------------------------------------------ 버튼

    /** 버튼(닫기·제보 파일 만들기·지금 재부팅): 둥근 사각형, 누르는 동안 밝은 바탕, 막히면 흐리게 */
    static final class Btn extends View implements Sized {
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG), edge = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint ink = paint(Ui.INK, false), ring = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF r = new RectF(), rr = new RectF();
        private String label, shown = "";
        private float radius, textX, textY;
        private boolean small;
        private int base = Ui.BTN, press = Ui.BTN_PRESS;
        /** 글에 맞는 폭(size 때 계산, wantWidth와 같음) */
        int want;
        private float edgeScale = 1f;

        Btn(Context c, String label, boolean small) {
            super(c);
            this.label = label;
            this.small = small;
            edge.setStyle(Paint.Style.STROKE);
            edge.setColor(Ui.BTN_EDGE);
            ring.setStyle(Paint.Style.STROKE);
            ring.setColor(Ui.FOCUS);
            setClickable(true);
            setFocusable(true);
        }

        @Override
        public void size(Layout l) {
            ink.setTextSize(small ? l.textSmall : l.textBody);
            edge.setStrokeWidth(Math.max(1f, l.u * 0.15f) * edgeScale);
            ring.setStrokeWidth(Math.max(2f, l.u * 0.4f));
            radius = 1.2f * l.u;
            want = wantWidth(l);
            prepare();
            invalidate();
        }

        /** 색 바꾸기(확인 창의 "취소"·"재부팅"): 바탕, 누를 때 바탕, 테두리, 글자, 테두리 굵기 배수 */
        void tone(int base, int press, int edgeColor, int inkColor, float edgeScale) {
            this.base = base;
            this.press = press;
            this.edgeScale = edgeScale;
            edge.setColor(edgeColor);
            ink.setColor(inkColor);
            invalidate();
        }

        /** 내용에 맞는 폭(글 + 양옆 2.4u씩) */
        int wantWidth(Layout l) {
            return Math.round(ink.measureText(label) + 4.8f * l.u);
        }

        @Override
        protected void onSizeChanged(int w, int h, int ow, int oh) {
            prepare();
        }

        private void prepare() {
            float w = getWidth(), h = getHeight();
            float half = edge.getStrokeWidth() / 2f;
            r.set(half, half, w - half, h - half);
            float rh = ring.getStrokeWidth() / 2f;
            rr.set(rh, rh, w - rh, h - rh);
            shown = ellipsize(ink, label, Math.max(0f, w - radius * 2));
            textX = (w - ink.measureText(shown)) / 2f;
            textY = baseline(ink, 0, h);
        }

        @Override
        protected void drawableStateChanged() {
            super.drawableStateChanged();
            invalidate();
        }

        @Override
        public void setEnabled(boolean e) {
            super.setEnabled(e);
            invalidate();
        }

        @Override
        protected void onDraw(Canvas c) {
            boolean on = isEnabled();
            fill.setColor(isPressed() && on ? press : base);
            ink.setAlpha(on ? 255 : 110);
            edge.setAlpha(on ? 255 : 110);
            c.drawRoundRect(r, radius, radius, fill);
            c.drawRoundRect(r, radius, radius, edge);
            // 리뷰 3 중간 1: 조그 다이얼·방향키 포커스가 어디 있는지 보이게(노란 굵은 테두리)
            if (isFocused()) c.drawRoundRect(rr, radius, radius, ring);
            c.drawText(shown, textX, textY, ink);
        }
    }

    /** 버튼 두 개: 가로(반씩) 또는 세로(위아래). 높이는 누르는 높이 */
    static final class Pair extends ViewGroup implements Sized {
        private boolean vertical;
        private int touch = 44, gap = 6;
        /** 버튼 하나를 글 폭만큼 왼쪽에 둔다(동글 "자동으로 되돌리기": 오른쪽 토글과 떨어지게) */
        boolean fitLeft;

        Pair(Context c, boolean vertical) {
            super(c);
            this.vertical = vertical;
        }

        void setVertical(boolean v) {
            if (v != vertical) { vertical = v; requestLayout(); }
        }

        @Override
        public void size(Layout l) {
            touch = l.touch;
            gap = l.gap;
            requestLayout();
        }

        private int shown() {
            int n = 0;
            for (int i = 0; i < getChildCount(); i++) if (getChildAt(i).getVisibility() != GONE) n++;
            return n;
        }

        @Override
        protected void onMeasure(int ws, int hs) {
            int w = MeasureSpec.getSize(ws), n = shown();
            int h = n == 0 ? 0 : vertical ? n * touch + (n - 1) * gap : touch;
            // 되돌리기 버튼은 위 토글 줄과 세로로도 한 칸 띄운다(잘못 눌러 토글이 바뀌지 않게, 리뷰 낮음 3)
            if (fitLeft && n > 0) h += gap;
            int cw = vertical || n <= 1 ? w : (w - gap * (n - 1)) / n;
            if (fitLeft && n == 1 && getChildAt(0) instanceof Btn) cw = Math.min(w, Math.max(touch, ((Btn) getChildAt(0)).want));
            for (int i = 0; i < getChildCount(); i++)
                getChildAt(i).measure(MeasureSpec.makeMeasureSpec(cw, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(touch, MeasureSpec.EXACTLY));
            setMeasuredDimension(w, h);
        }

        @Override
        protected void onLayout(boolean ch, int l, int t, int r, int b) {
            int x = 0, y = fitLeft ? gap : 0;
            for (int i = 0; i < getChildCount(); i++) {
                View v = getChildAt(i);
                if (v.getVisibility() == GONE) continue;
                v.layout(x, y, x + v.getMeasuredWidth(), y + touch);
                if (vertical) y += touch + gap; else x += v.getMeasuredWidth() + gap;
            }
        }
    }

    // ------------------------------------------------------------------ 상태 줄(맨 위)

    /**
     * 상태 줄: 판정 색 바탕 + 판정 문구, 늘 한 줄(설계 10장). 판정 글자에서 본문 글자까지 줄이고(Layout.verdictSize),
     * 그래도 넘치면 흐르는 글자: 처음 1.5초 멈춤, 초당 높이의 14%, 오른쪽 끝을 판정 색으로 흐리게. 화면이 보일 때만 움직이고
     * 창이 가려지거나 뷰가 떨어지면 멈춘다(멈추지 않는 반복 금지). 다음 틱은 이 뷰가 잡는다(화면의 1초 반복과 따로).
     */
    static final class StatusLine extends View implements Sized, Runnable {
        private final Paint bg = new Paint(Paint.ANTI_ALIAS_FLAG), ink = paint(Ui.INK, true), fade = new Paint();
        private final RectF r = new RectF();
        private String msg = "";
        private int level;
        private Layout lay;
        private float radius, padX, textY, textW, speed, loop;
        private boolean marquee, running, active = true;
        private long started;
        /** 33ms 틱(약 30번/초) */
        static final long TICK = 33;

        StatusLine(Context c) {
            super(c);
        }

        void set(String msg, int level) {
            this.msg = msg == null ? "" : msg;
            this.level = level;
            prepare();
            invalidate();
        }

        @Override
        public void size(Layout l) {
            lay = l;
            radius = 1.2f * l.u;
            padX = 2f * l.u;
            speed = 0.14f * l.height;
            prepare();
        }

        @Override
        protected void onSizeChanged(int w, int h, int ow, int oh) {
            prepare();
        }

        private void prepare() {
            bg.setColor(Ui.levelColor(level));
            ink.setColor(Ui.levelInk(level));
            if (lay == null) return;
            float w = getWidth(), h = getHeight(), avail = Math.max(0f, w - 2 * padX);
            r.set(0, 0, w, h);
            ink.setTextSize(lay.textVerdict);
            int s = lay.verdictSize(ink.measureText(msg), avail);
            // 리뷰 낮음 7: 비례로 고른 크기로 다시 재서 넘치면 흐르는 글자로(끝이 잘리지 않게)
            if (s > 0) { ink.setTextSize(s); if (ink.measureText(msg) > avail) s = -1; }
            marquee = s < 0 && avail > 0;
            // 폭을 아직 받지 않았으면(avail 0) s가 -1일 수 있어 본문 글자로 둔다(onSizeChanged에서 다시 정함)
            ink.setTextSize(marquee || s < 0 ? lay.textBody : s);
            textW = ink.measureText(msg);
            loop = textW + 3f * lay.u * 4;
            textY = baseline(ink, 0, h);
            float fw = 3f * lay.u;
            int col = Ui.levelColor(level);
            fade.setShader(new LinearGradient(w - fw, 0, w, 0, col & 0x00FFFFFF, col, Shader.TileMode.CLAMP));
            started = android.os.SystemClock.uptimeMillis();
            schedule();
        }

        private void schedule() {
            boolean want = marquee && active && getWindowVisibility() == VISIBLE && getWindowToken() != null;
            if (want && !running) { running = true; postDelayed(this, TICK); }
            else if (!want && running) { running = false; removeCallbacks(this); }
        }

        @Override
        public void run() {
            if (!running) return;
            running = false;
            invalidate();
            schedule();
        }

        @Override
        protected void onAttachedToWindow() {
            super.onAttachedToWindow();
            schedule();
        }

        @Override
        protected void onDetachedFromWindow() {
            running = false;
            removeCallbacks(this);
            super.onDetachedFromWindow();
        }

        @Override
        protected void onWindowVisibilityChanged(int v) {
            super.onWindowVisibilityChanged(v);
            schedule();
        }

        /** 리뷰 낮음 6: 화면(액티비티)이 멈추면 끄고 다시 보이면 켠다(창이 그대로 보여도 onPause면 멈춤) */
        void setActive(boolean a) {
            active = a;
            schedule();
        }

        /** 시험·리포트용: 지금 흐르는 글자인가 */
        boolean isMarquee() {
            return marquee;
        }

        @Override
        protected void onDraw(Canvas c) {
            c.drawRoundRect(r, radius, radius, bg);
            c.save();
            c.clipRect(padX, 0, getWidth() - padX, getHeight());
            if (!marquee) {
                c.drawText(msg, padX, textY, ink);
            } else {
                float sh = Ui.marqueeShift(android.os.SystemClock.uptimeMillis() - started, speed, loop);
                c.drawText(msg, padX - sh, textY, ink);
                c.drawText(msg, padX - sh + loop, textY, ink);
            }
            c.restore();
            if (marquee) c.drawRect(getWidth() - 3f * lay.u, 0, getWidth(), getHeight(), fade);
        }
    }

    // ------------------------------------------------------------------ 요약 [이름 | 값]

    /** 같은 묶음의 이름 칸 폭(모든 줄에서 가장 긴 이름). Layout이 바뀌면 다시 잰다 */
    static final class KvCol {
        Layout layout;
        float w;
    }

    /** 요약 한 줄: 이름(회색) | 값(색). 값은 한 줄, 넘치면 자름 */
    static final class Kv extends View implements Sized {
        private final Paint kp = paint(Ui.INK_DIM, false), vp = paint(Ui.INK, false);
        private final KvCol col;
        private final String k, v;
        private final boolean small;
        private String shown = "";
        private float gap, lineH;

        Kv(Context c, KvCol col, String k, String v, int color, boolean small) {
            super(c);
            this.col = col; this.k = k; this.v = v; this.small = small;
            vp.setColor(color);
        }

        @Override
        public void size(Layout l) {
            float ts = small ? l.textSmall : l.textBody;
            kp.setTextSize(ts);
            vp.setTextSize(ts);
            gap = 1.6f * l.u;
            lineH = ts * Layout.LINE;
            if (col.layout != l) { col.layout = l; col.w = 0; }
            col.w = Math.max(col.w, kp.measureText(k));
            requestLayout();
        }

        @Override
        protected void onMeasure(int ws, int hs) {
            setMeasuredDimension(MeasureSpec.getSize(ws), Math.round(lineH));
        }

        @Override
        protected void onSizeChanged(int w, int h, int ow, int oh) {
            shown = ellipsize(vp, v, Math.max(0f, w - col.w - gap));
        }

        @Override
        protected void onLayout(boolean ch, int l, int t, int r, int b) {
            // 이름 칸 폭은 다른 줄이 size()에서 늘릴 수 있어 배치 때 다시 자른다
            shown = ellipsize(vp, v, Math.max(0f, getWidth() - col.w - gap));
        }

        @Override
        protected void onDraw(Canvas c) {
            float y = baseline(kp, 0, getHeight());
            c.drawText(k, 0, y, kp);
            c.drawText(shown, col.w + gap, y, vp);
        }
    }

    // ------------------------------------------------------------------ 묶음 제목

    /** 묶음 제목(기본 기능·부가 기능·고급·자세히): 작은 굵은 회색 글자, 위에 1.2u 여백 */
    static final class Group extends View implements Sized {
        private final Paint ink = paint(Ui.INK_DIM, true);
        private final String title;
        private float top, lineH;

        Group(Context c, String title) {
            super(c);
            this.title = title;
        }

        @Override
        public void size(Layout l) {
            ink.setTextSize(l.textSmall);
            top = 1.2f * l.u;
            lineH = l.textSmall * Layout.LINE;
            requestLayout();
        }

        @Override
        protected void onMeasure(int ws, int hs) {
            setMeasuredDimension(MeasureSpec.getSize(ws), Math.round(top + lineH));
        }

        @Override
        protected void onDraw(Canvas c) {
            c.drawText(title, 0, baseline(ink, top, lineH), ink);
        }
    }

    // ------------------------------------------------------------------ 토글 줄

    /**
     * 토글 줄(줄 전체를 누름): 제목 + 딱지, 설명 한 줄(넘치면 자름), 고정 경고(자르지 않고 줄바꿈), 상태 줄, 오른쪽에 "켬"·"끔" 글자와
     * 트랙·원. 켜짐은 원이 오른쪽·초록, 꺼짐은 원이 왼쪽·회색, 적용 중·모름은 가운데(설계 3장: 색만으로 가르지 않음).
     * 누르는 동안 줄 바탕이 밝아진다(애니메이션 아님). 막힌 줄은 토글을 흐리게 그리고 누를 수 없다.
     */
    static final class ToggleRow extends View implements Sized {
        final Ui.Row row;
        private final Paint bg = new Paint(Paint.ANTI_ALIAS_FLAG), track = new Paint(Paint.ANTI_ALIAS_FLAG), knobP = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint title = paint(Ui.INK, false), desc = paint(Ui.INK_DESC, false), warn = paint(Ui.INK_WARN, false);
        private final Paint note = paint(Ui.INK_DESC, false), lbl = paint(Ui.INK, false), tagInk = paint(0xFFCCCCCC, false);
        private final Paint tagEdge = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF r = new RectF(), tr = new RectF(), kr = new RectF(), tagR = new RectF();
        private Layout lay;
        private float radius, padX, padY, lineB, lineS, ctlW, gapX;
        private int tw, th, knob;
        private String titleShown = "", descShown = "", noteShown = "", label = "";
        private List<String> pinned = new ArrayList<String>();
        private List<String> descLines;
        private boolean tagFits;

        ToggleRow(Context c, Ui.Row row) {
            super(c);
            this.row = row;
            tagEdge.setStyle(Paint.Style.STROKE);
            tagEdge.setColor(0xFF777777);
            setFocusable(row.enabled);
            setEnabled(row.enabled);
        }

        /** 새 상태로 다시 그린다(적용 중·결과). 줄 높이가 바뀔 수 있어 다시 잰다 */
        void update(Ui.Row n) {
            row.copy(n);
            setFocusable(row.enabled);
            setEnabled(row.enabled);
            if (lay != null) size(lay);
            prepare();
            invalidate();
        }

        @Override
        public void size(Layout l) {
            lay = l;
            title.setTextSize(l.textBody);
            desc.setTextSize(l.textSmall);
            warn.setTextSize(l.textSmall);
            note.setTextSize(l.textSmall);
            lbl.setTextSize(l.textSmall);
            tagInk.setTextSize(Math.round(l.textSmall * 0.9f));
            tagEdge.setStrokeWidth(Math.max(1f, l.u * 0.12f));
            radius = 1.2f * l.u;
            padX = 1.6f * l.u;
            padY = 0.8f * l.u;
            gapX = 1.6f * l.u;
            lineB = l.textBody * Layout.LINE;
            lineS = l.textSmall * Layout.LINE;
            int[] t = Ui.toggleSize(l);
            tw = t[0]; th = t[1]; knob = t[2];
            label = row.label();
            if (row.kind == Ui.KIND_ALWAYS) {
                lbl.setColor(Ui.INK_GOOD);
                ctlW = lbl.measureText(label);
            } else {
                ctlW = lbl.measureText("끔") + 0.8f * l.u + tw;
            }
            desc.setColor(row.descColor);
            prepare();
            requestLayout();
        }

        /** 글이 쓸 폭: 줄 폭 − 양옆 여백 − 토글 칸 − 간격 */
        private float textWidth(int w) {
            return Math.max(1f, w - 2 * padX - ctlW - gapX);
        }

        @Override
        protected void onMeasure(int ws, int hs) {
            int w = MeasureSpec.getSize(ws);
            if (lay == null) { setMeasuredDimension(w, 0); return; }
            // 고정 안내(동글 포트 안내)는 자르지 않는다
            pinned = wrap(warn, row.pinned, textWidth(w));
            // 실패 이유(빨강)·주의(노랑, 동글 문제 문구)는 자르지 않고 줄바꿈한다(리뷰 2 중간 3: 해야 할 일이 잘리지 않게)
            // 딱지가 제목 옆에 안 들어가면 줄바꿈하는 설명에도 "[딱지] "를 붙인다(prepare와 같은 기준, 리뷰 중간 2)
            float tw0 = textWidth(w);
            float tagW0 = row.tag.isEmpty() ? 0 : tagInk.measureText(row.tag) + 1.6f * lay.u;
            boolean fit0 = tagW0 > 0 && tagW0 + lay.u + title.measureText("가나다라") <= tw0;
            String d0 = tagW0 > 0 && !fit0 ? "[" + row.tag + "] " + row.desc : row.desc;
            descLines = row.descColor == Ui.INK_BAD || row.descColor == Ui.INK_WARN ? wrap(desc, d0, tw0) : null;
            int lines = (row.desc.isEmpty() ? 0 : descLines != null ? descLines.size() : 1) + pinned.size() + (row.note.isEmpty() ? 0 : 1);
            int h = Math.round(2 * padY + lineB + lines * lineS);
            setMeasuredDimension(w, Math.max(h, lay.touch));
        }

        @Override
        protected void onSizeChanged(int w, int h, int ow, int oh) {
            prepare();
        }

        /**
         * 그릴 값(자른 글, 딱지·트랙·원 자리)을 지금 크기와 상태로 다시 계산한다. 크기가 바뀔 때와 상태가 바뀔 때(update) 모두 부른다
         * (리뷰 높음 1: 줄 높이가 그대로면 onSizeChanged가 불리지 않아 원·설명이 옛 상태로 남던 것).
         */
        private void prepare() {
            int w = getWidth(), h = getHeight();
            if (lay == null || w <= 0 || h <= 0) return;
            r.set(0, 0, w, h);
            float tx = textWidth(w);
            float tagW = row.tag.isEmpty() ? 0 : tagInk.measureText(row.tag) + 1.6f * lay.u;
            // 딱지가 제목과 함께 들어가지 않으면 설명 줄 앞에 "[준비 중] "으로 붙인다(리뷰 낮음 8: 막힌 이유가 사라지지 않게)
            tagFits = tagW > 0 && tagW + lay.u + title.measureText("가나다라") <= tx;
            String d = tagW > 0 && !tagFits ? "[" + row.tag + "] " + row.desc : row.desc;
            titleShown = ellipsize(title, row.title, tagFits ? tx - tagW - lay.u : tx);
            descShown = ellipsize(desc, d, tx);
            noteShown = ellipsize(note, row.note, tx);
            if (tagFits) {
                float tl = padX + title.measureText(titleShown) + lay.u, tt = padY + lineB * 0.12f;
                tagR.set(tl, tt, tl + tagW, tt + lineB * 0.76f);
            }
            float cx = w - padX - tw, cy = (h - th) / 2f;
            tr.set(cx, cy, cx + tw, cy + th);
            int kx = Ui.knobX(Math.round(cx), tw, th, knob, row.state, row.busy);
            float ky = cy + (th - knob) / 2f;
            kr.set(kx, ky, kx + knob, ky + knob);
        }

        @Override
        protected void drawableStateChanged() {
            super.drawableStateChanged();
            invalidate();
        }

        @Override
        protected void onDraw(Canvas c) {
            if (lay == null) return;
            bg.setColor(isPressed() && row.enabled ? Ui.ROW_PRESS : Ui.ROW);
            c.drawRoundRect(r, radius, radius, bg);
            float y = padY;
            c.drawText(titleShown, padX, baseline(title, y, lineB), title);
            if (tagFits) {
                c.drawRoundRect(tagR, 0.6f * lay.u, 0.6f * lay.u, tagEdge);
                c.drawText(row.tag, tagR.left + 0.8f * lay.u, baseline(tagInk, tagR.top, tagR.height()), tagInk);
            }
            y += lineB;
            if (descLines != null) {
                for (int i = 0; i < descLines.size(); i++) { c.drawText(descLines.get(i), padX, baseline(desc, y, lineS), desc); y += lineS; }
            } else if (!row.desc.isEmpty()) { c.drawText(descShown, padX, baseline(desc, y, lineS), desc); y += lineS; }
            for (int i = 0; i < pinned.size(); i++) { c.drawText(pinned.get(i), padX, baseline(warn, y, lineS), warn); y += lineS; }
            if (!row.note.isEmpty()) c.drawText(noteShown, padX, baseline(note, y, lineS), note);

            float cy = getHeight() / 2f;
            if (row.kind == Ui.KIND_ALWAYS) {
                c.drawText(label, getWidth() - padX - ctlW, baseline(lbl, 0, getHeight()), lbl);
                return;
            }
            int a = row.enabled || row.busy ? 255 : 115;
            boolean on = row.state == Ui.ON && !row.busy;
            track.setColor(row.busy ? Ui.TRACK_BUSY : on ? Ui.GOOD : Ui.TRACK_OFF);
            track.setAlpha(a);
            knobP.setColor(row.busy ? Ui.WARN : on ? Ui.KNOB : Ui.KNOB_OFF);
            knobP.setAlpha(a);
            lbl.setAlpha(a);
            c.drawRoundRect(tr, th / 2f, th / 2f, track);
            c.drawOval(kr, knobP);
            c.drawText(label, tr.left - 0.8f * lay.u - lbl.measureText(label), baseline(lbl, cy - lineS / 2f, lineS), lbl);
        }
    }

    // ------------------------------------------------------------------ 진행 막대

    /** 진행 막대(설치·제보 저장): 회색 바탕 위 초록 채움, 0~100 */
    static final class Bar extends View implements Sized {
        private final Paint back = new Paint(Paint.ANTI_ALIAS_FLAG), front = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF r = new RectF();
        private int pct;

        Bar(Context c) {
            super(c);
            back.setColor(0xFF333333);
            front.setColor(Ui.GOOD);
        }

        /** 상태 칸 안에서는 높이를 정해 주지 않으므로(쌓기) 최소 높이 1.4u를 둔다 */
        @Override
        public void size(Layout l) {
            setMinimumHeight(Math.max(6, Math.round(1.4f * l.u)));
            requestLayout();
        }

        void setProgress(int p) {
            int v = p < 0 ? 0 : p > 100 ? 100 : p;
            if (v != pct) { pct = v; invalidate(); }
        }

        @Override
        protected void onDraw(Canvas c) {
            float w = getWidth(), h = getHeight(), rad = h / 2f;
            r.set(0, 0, w, h);
            c.drawRoundRect(r, rad, rad, back);
            if (pct > 0) {
                r.set(0, 0, Math.max(h, w * pct / 100f), h);
                c.drawRoundRect(r, rad, rad, front);
            }
        }
    }

    // ------------------------------------------------------------------ 상태 칸(위에서부터 쌓고 넘치면 숨김)

    /**
     * 위에서부터 쌓는 칸. 줄마다 순위(Ui.P_*)를 두고, 높이가 모자라면 Ui.fit으로 낮은 순위부터 숨긴다(숨긴 줄은 크기 0으로 둔다).
     * bottom으로 단 줄(버튼)은 칸 맨 아래에 붙인다(넓은 화면). 칸 높이를 정해 주지 않으면(AT_MOST) 내용 높이만 쓴다.
     */
    static final class Column extends ViewGroup implements Sized {
        private final List<Integer> prio = new ArrayList<Integer>();
        private final List<Boolean> bottom = new ArrayList<Boolean>();
        private boolean[] show = new boolean[0];
        private int gap = 6;
        /** 마지막으로 숨긴 줄 수(시험·로그용) */
        int hidden;

        Column(Context c) {
            super(c);
        }

        void add(View v, int p, boolean atBottom) {
            addView(v);
            prio.add(p);
            bottom.add(atBottom);
        }

        @Override
        public void size(Layout l) {
            gap = Math.round(0.7f * l.gap);
            requestLayout();
        }

        @Override
        protected void onMeasure(int ws, int hs) {
            int w = MeasureSpec.getSize(ws), avail = MeasureSpec.getSize(hs);
            boolean exact = MeasureSpec.getMode(hs) == MeasureSpec.EXACTLY;
            if (MeasureSpec.getMode(hs) == MeasureSpec.UNSPECIFIED) avail = Integer.MAX_VALUE / 2;
            int n = getChildCount();
            int[] hh = new int[n], pp = new int[n];
            for (int i = 0; i < n; i++) {
                View v = getChildAt(i);
                pp[i] = prio.get(i);
                if (v.getVisibility() == GONE) { hh[i] = 0; continue; }
                v.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED));
                hh[i] = v.getMeasuredHeight() + (v.getMeasuredHeight() > 0 ? gap : 0);
            }
            show = Ui.fit(hh, pp, avail + gap);
            int used = 0;
            hidden = 0;
            for (int i = 0; i < n; i++) { if (show[i]) used += hh[i]; else hidden++; }
            used = Math.max(0, used - gap);
            setMeasuredDimension(w, exact ? avail : Math.min(used, avail));
        }

        @Override
        protected void onLayout(boolean ch, int l, int t, int r, int b) {
            int n = getChildCount(), y = 0, w = r - l;
            int by = b - t;
            // 아래에 붙일 줄은 아래에서부터 위로 쌓는다
            for (int i = n - 1; i >= 0; i--) {
                View v = getChildAt(i);
                if (!bottom.get(i) || i >= show.length || !show[i] || v.getVisibility() == GONE) continue;
                by -= v.getMeasuredHeight();
                v.layout(0, by, w, by + v.getMeasuredHeight());
                by -= gap;
            }
            // 리뷰 중간 2: 숨길 수 없는 줄만으로도 넘치면 위 줄이 아래에 붙인 버튼에 겹치지 않게, 버튼 위에서 자른다
            int limit = by;
            for (int i = 0; i < n; i++) {
                View v = getChildAt(i);
                if (bottom.get(i) && i < show.length && show[i]) continue;
                if (i >= show.length || !show[i] || v.getVisibility() == GONE || y >= limit) { v.layout(0, 0, 0, 0); continue; }
                v.layout(0, y, w, Math.min(limit, y + v.getMeasuredHeight()));
                y += v.getMeasuredHeight() + gap;
            }
        }
    }

    // ------------------------------------------------------------------ 화면 전체

    /**
     * 상태 화면 전체. 받은 크기로 Layout.of를 계산하고(설계 4장: dp·DisplayMetrics가 아니라 받은 픽셀), 하위 뷰의 크기를 정한 뒤
     * 자리에 놓는다. 맨 위 [상태 줄][닫기], 아래 넓은 화면 [상태 칸 | 설정 칸 | QR], 그 밖은 [상태 칸 위 + 설정 아래 | QR].
     */
    /**
     * 설정 칸 스크롤(소유자 결정 11-18: 800×480에서 설정 부분을 스크롤로). 기본 Holo 막대는 가늘고 흐려 차에서 보이지 않아
     * 오른쪽에 굵은 막대를 직접 그린다. 내용이 다 보이면 막대를 그리지 않는다. 끝에서 튕기는 효과는 없다.
     */
    static final class Scroll extends ScrollView implements Sized {
        private final Paint track = paint(Ui.SCROLL_TRACK, false), thumb = paint(Ui.SCROLL_THUMB, false);
        private final RectF tr = new RectF(), th = new RectF();
        private final int[] pos = new int[2];
        private int bar = 4, minLen = 22;

        Scroll(Context c) {
            super(c);
            setOverScrollMode(OVER_SCROLL_NEVER);
            setVerticalScrollBarEnabled(false);
            setWillNotDraw(false);
        }

        @Override
        public void size(Layout l) {
            bar = Ui.scrollBarWidth(l);
            minLen = Math.max(bar * 2, l.touch / 2);
            // 막대 자리만큼 내용을 왼쪽으로(글이 막대 밑에 깔리지 않게)
            setPadding(0, 0, bar + Math.round(0.6f * l.u), 0);
            invalidate();
        }

        /** 다시 그린 화면에서 이어 보일 스크롤 위치(첫 배치 뒤 한 번, -1이면 없음). 내용이 줄었으면 ScrollView가 끝에 맞춘다 */
        int keepY = -1;
        /** 손가락이 닿아 있는 동안 true(그사이 화면을 다시 그리지 않게) */
        boolean touching;

        @Override
        protected void onLayout(boolean changed, int l, int t, int r, int b) {
            super.onLayout(changed, l, t, r, b);
            if (keepY >= 0) {
                scrollTo(0, keepY);
                keepY = -1;
            }
        }

        @Override
        public boolean dispatchTouchEvent(MotionEvent e) {
            int a = e.getActionMasked();
            if (a == MotionEvent.ACTION_DOWN) touching = true;
            else if (a == MotionEvent.ACTION_UP || a == MotionEvent.ACTION_CANCEL) touching = false;
            return super.dispatchTouchEvent(e);
        }

        @Override
        protected void dispatchDraw(Canvas c) {
            super.dispatchDraw(c);
            if (getChildCount() == 0) return;
            int h = getHeight();
            if (!Ui.scrollThumb(h, getChildAt(0).getHeight(), getScrollY(), minLen, pos)) return;
            // 그리는 판은 스크롤만큼 옮겨져 있으므로 보이는 자리에 맞춰 getScrollY()를 더한다
            float x = getWidth() - bar, y0 = getScrollY(), rad = bar / 2f;
            tr.set(x, y0, x + bar, y0 + h);
            th.set(x, y0 + pos[0], x + bar, y0 + pos[0] + pos[1]);
            c.drawRoundRect(tr, rad, rad, track);
            c.drawRoundRect(th, rad, rad, thumb);
        }
    }

    /**
     * 재부팅 확인 창(소유자 결정 11-18): AlertDialog 대신 이 화면 모양으로 직접 그린다. 화면 전체를 덮어 뒤를 어둡게 하고,
     * 가운데 창에 큰 제목 한 줄, 한두 문장, 버튼 둘("취소"가 기본: 밝은 바탕·굵은 흰 테두리·처음 포커스, "재부팅"은 빨간 글자).
     * 창 바깥을 누르거나 뒤로 가기는 취소. 연 뒤 Ui.CONFIRM_ARM_MS 안에 누른 "재부팅"은 받지 않는다(두 번 눌러 재부팅되지 않게).
     * 누른 결과는 이 뷰와 두 버튼의 클릭으로 화면(StatusActivity)이 받는다.
     */
    static final class Confirm extends ViewGroup implements Sized {
        final Btn cancel, ok;
        private final Paint panel = paint(Ui.ROW, false), edge = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint titleP = paint(Ui.INK, true), msgP = paint(Ui.INK, false);
        private final RectF box = new RectF();
        private final String title, msg;
        private List<String> lines = new ArrayList<String>();
        private Layout lay;
        private float radius, titleLine, msgLine;
        private int pad, btnH;
        private final long opened = SystemClock.uptimeMillis();
        private boolean downOutside;

        Confirm(Context c, String title, String msg, String cancelLabel, String okLabel) {
            super(c);
            this.title = title;
            this.msg = msg;
            edge.setStyle(Paint.Style.STROKE);
            edge.setColor(Ui.BTN_EDGE);
            cancel = new Btn(c, cancelLabel, false);
            cancel.tone(Ui.BTN_PRESS, 0xFF555555, Ui.INK, Ui.INK, 2f);
            ok = new Btn(c, okLabel, false);
            ok.tone(Ui.BTN, Ui.BTN_PRESS, Ui.BAD, Ui.INK_BAD, 1f);
            addView(cancel);
            addView(ok);
            setWillNotDraw(false);
            setClickable(true);
        }

        /** 리뷰 3 중간 2: 조그 다이얼·방향키 포커스가 창 밖(뒤 화면)으로 나가지 않게 두 버튼 사이에서만 옮긴다 */
        @Override
        public View focusSearch(View focused, int direction) {
            return focused == cancel ? ok : cancel;
        }

        /** 연 뒤 충분히 지났는가("재부팅"을 받아도 되는가) */
        boolean armed() {
            return SystemClock.uptimeMillis() - opened >= Ui.CONFIRM_ARM_MS;
        }

        @Override
        public void size(Layout l) {
            lay = l;
            edge.setStrokeWidth(Math.max(1f, l.u * 0.15f));
            radius = 1.2f * l.u;
            pad = Ui.confirmPad(l);
            btnH = Ui.confirmButton(l);
            requestLayout();
            invalidate();
        }

        @Override
        protected void onMeasure(int ws, int hs) {
            int w = MeasureSpec.getSize(ws), h = MeasureSpec.getSize(hs);
            setMeasuredDimension(w, h);
            Layout l = lay;
            if (l == null) {
                cancel.measure(MeasureSpec.makeMeasureSpec(0, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(0, MeasureSpec.EXACTLY));
                ok.measure(MeasureSpec.makeMeasureSpec(0, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(0, MeasureSpec.EXACTLY));
                return;
            }
            int pw = Math.min(w - 2 * l.pad, Ui.confirmWidth(l));
            float inner = Math.max(1, pw - 2 * pad);
            // 제목은 판정 글자 크기, 넘치거나 창이 화면보다 길면 본문 글자로 줄인다
            titleP.setTextSize(l.textVerdict);
            msgP.setTextSize(l.textBody);
            lines = wrap(msgP, msg, inner);
            int ph = Ui.confirmHeight(l, lines.size(), l.textVerdict);
            if (titleP.measureText(title) > inner || ph > h - 2 * l.pad) {
                titleP.setTextSize(l.textBody);
                ph = Ui.confirmHeight(l, lines.size(), l.textBody);
            }
            titleLine = titleP.getTextSize() * Layout.LINE;
            msgLine = l.textBody * Layout.LINE;
            float left = (w - pw) / 2f, top = Math.max(0f, (h - ph) / 2f);
            box.set(left, top, left + pw, top + ph);
            int bw = Math.max(0, (int) ((inner - l.gap) / 2));
            cancel.measure(MeasureSpec.makeMeasureSpec(bw, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(btnH, MeasureSpec.EXACTLY));
            ok.measure(MeasureSpec.makeMeasureSpec(bw, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(btnH, MeasureSpec.EXACTLY));
        }

        @Override
        protected void onLayout(boolean ch, int l, int t, int r, int b) {
            int x = Math.round(box.left) + pad, y = Math.round(box.bottom) - pad - btnH;
            // "취소"는 왼쪽(처음 포커스), "재부팅"은 오른쪽
            cancel.layout(x, y, x + cancel.getMeasuredWidth(), y + btnH);
            int ox = Math.round(box.right) - pad - ok.getMeasuredWidth();
            ok.layout(ox, y, ox + ok.getMeasuredWidth(), y + btnH);
        }

        @Override
        protected void onDraw(Canvas c) {
            c.drawColor(Ui.CONFIRM_DIM);
            c.drawRoundRect(box, radius, radius, panel);
            c.drawRoundRect(box, radius, radius, edge);
            float x = box.left + pad, y = box.top + pad;
            c.drawText(title, x, baseline(titleP, y, titleLine), titleP);
            y += titleLine + (lay != null ? lay.gap : 0);
            for (int i = 0; i < lines.size(); i++) {
                c.drawText(lines.get(i), x, baseline(msgP, y, msgLine), msgP);
                y += msgLine;
            }
        }

        /** 창 바깥에서 눌렀다 바깥에서 떼면 취소(클릭). 창 안의 빈 곳은 아무 일도 하지 않는다. 뒤 화면으로는 넘기지 않는다 */
        @Override
        public boolean onTouchEvent(MotionEvent e) {
            boolean out = !box.contains(e.getX(), e.getY());
            int a = e.getActionMasked();
            if (a == MotionEvent.ACTION_DOWN) downOutside = out;
            else if (a == MotionEvent.ACTION_UP && downOutside && out) performClick();
            else if (a == MotionEvent.ACTION_CANCEL) downOutside = false;
            return true;
        }
    }

    static final class Screen extends ViewGroup {
        final StatusLine status;
        final Btn close;
        final Column info;
        final View settings, qr;
        /** 넓은 화면에서만 보이는 상태 칸 줄(판·차 정보)과 버튼 묶음(넓은 화면은 세로, QR 먼저는 가로) */
        final List<View> wideOnly = new ArrayList<View>();
        Pair buttons;
        private final int qrSize;
        Layout layout;
        private int lw = -1, lh = -1;

        Screen(Context c, StatusLine status, Btn close, Column info, View settings, View qr, int qrSize) {
            super(c);
            this.status = status; this.close = close; this.info = info; this.settings = settings; this.qr = qr; this.qrSize = qrSize;
            setBackgroundColor(Ui.BG);
            addView(status); addView(close); addView(info); addView(settings); addView(qr);
        }

        @Override
        protected void onMeasure(int ws, int hs) {
            int w = MeasureSpec.getSize(ws), h = MeasureSpec.getSize(hs);
            if (w != lw || h != lh || layout == null) {
                lw = w; lh = h;
                layout = Layout.of(w, h, qrSize);
                boolean wide = layout.kind == Layout.WIDE;
                for (View v : wideOnly) v.setVisibility(wide ? VISIBLE : GONE);
                if (buttons != null) buttons.setVertical(wide || layout.buttonsStacked);
                for (int i = 0; i < getChildCount(); i++) apply(getChildAt(i), layout);
            }
            Layout l = layout;
            if (l.tooSmall()) {
                for (int i = 0; i < getChildCount(); i++)
                    getChildAt(i).measure(MeasureSpec.makeMeasureSpec(0, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(0, MeasureSpec.EXACTLY));
                setMeasuredDimension(w, h);
                return;
            }
            int closeW = Math.max(l.touch, close.wantWidth(l));
            int inner = w - 2 * l.pad;
            exact(close, closeW, l.topHeight);
            exact(status, Math.max(0, inner - closeW - l.gap), l.topHeight);
            exact(qr, l.qrSide, l.qrSide);
            if (l.kind == Layout.WIDE) {
                exact(info, l.infoWidth, l.bodyHeight);
                exact(settings, l.settingsWidth, l.bodyHeight);
            } else {
                // QR 먼저: 상태 칸은 내용 높이만(설정 칸에 묶음 제목 + 토글 한 줄은 남김, Ui.settingsMin), 설정이 나머지
                int cap = Math.max(0, l.bodyHeight - Ui.settingsMin(l) - l.gap);
                info.measure(MeasureSpec.makeMeasureSpec(l.settingsWidth, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(cap, MeasureSpec.AT_MOST));
                exact(settings, l.settingsWidth, Math.max(0, l.bodyHeight - info.getMeasuredHeight() - l.gap));
            }
            setMeasuredDimension(w, h);
        }

        private static void exact(View v, int w, int h) {
            v.measure(MeasureSpec.makeMeasureSpec(Math.max(0, w), MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(Math.max(0, h), MeasureSpec.EXACTLY));
        }

        @Override
        protected void onLayout(boolean ch, int left, int top, int right, int bottom) {
            Layout l = layout;
            if (l == null || l.tooSmall()) {
                for (int i = 0; i < getChildCount(); i++) getChildAt(i).layout(0, 0, 0, 0);
                return;
            }
            int x = l.pad, y = l.pad;
            status.layout(x, y, x + status.getMeasuredWidth(), y + l.topHeight);
            int cx = l.width - l.pad - close.getMeasuredWidth();
            close.layout(cx, y, cx + close.getMeasuredWidth(), y + l.topHeight);
            qr.layout(l.qrX, l.bodyTop, l.qrX + l.qrSide, l.bodyTop + l.qrSide);
            if (l.kind == Layout.WIDE) {
                info.layout(x, l.bodyTop, x + l.infoWidth, l.bodyTop + l.bodyHeight);
                int sx = x + l.infoWidth + l.gap;
                settings.layout(sx, l.bodyTop, sx + l.settingsWidth, l.bodyTop + l.bodyHeight);
            } else {
                int ih = info.getMeasuredHeight();
                info.layout(x, l.bodyTop, x + l.settingsWidth, l.bodyTop + ih);
                int sy = l.bodyTop + ih + l.gap;
                settings.layout(x, sy, x + l.settingsWidth, sy + settings.getMeasuredHeight());
            }
        }
    }
}
