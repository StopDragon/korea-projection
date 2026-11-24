package korea.projection.app;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;

/**
 * NEMESIS Manager > Korea Projection > Launch가 여는 화면. bin/status.sh(root)가 먼저 상태 파일을 쓰고,
 * 이 화면은 그것을 읽어 왼쪽에 상태표, 오른쪽에 제보용 QR을 보여 준다. 판단은 Report에 있다.
 * 1.5.5: 설치가 진행 중이면(서비스의 진행 기록 state=run) 먼저 진행 막대(0~100%)와 단계·경과 시간을 보여 준다.
 * 1초마다 다시 읽고, 끝나면(그리고 status.sh가 상태 파일을 새로 쓰면) 결과 화면으로 바뀐다.
 * 설치는 서비스가 하므로 이 화면을 닫아도 계속된다.
 */
public class StatusActivity extends Activity implements View.OnClickListener, Runnable {
    /** bin/status.sh가 쓰는 파일 (644, 비밀값 없음) */
    static final String STATUS = "/data/local/tmp/korea-projection-status.txt";
    /** svc/hotspot.sh가 쓰는 설치 진행 기록 (644, 비밀값 없음) */
    static final String PROG = "/data/local/tmp/korea-projection-progress.txt";
    static final String BOOT_ID = "/proc/sys/kernel/random/boot_id";
    /** 1.7.0: 제보 자료 저장 진행 기록(644, status.sh make_report가 씀). 토스트 대신 이 화면 맨 위에 보인다 */
    static final String RPROG = "/data/local/tmp/korea-projection-report-progress.txt";
    /** 1.7.1: svc/hotspot.sh notice가 쓰는 알림 기록(644, 토스트 대신). 이번 부팅의 줄만 보인다 */
    static final String NOTICE = "/data/local/tmp/korea-projection-notice.txt";
    /** 1.7.2: svc/hotspot.sh hint_write가 쓰는 상태 안내(644, 코드와 시각뿐). 이번 부팅의 것만 보인다 */
    static final String HINT = "/data/local/tmp/korea-projection-hint.txt";
    /** 알림을 보여 주는 시간(초): 그보다 오래된 안내는 지난 단계의 것이다 */
    static final long NOTICE_SHOW = 1800;
    /** 저장이 끝난 기록을 결과 화면에 보여 주는 시간(초): 그보다 오래된 완료 기록은 지난 Launch의 것이다 */
    static final int SAVE_SHOW = 600;
    /** 설치가 끝난 뒤 status.sh가 상태 파일을 다시 쓰기를 기다리는 최대 시간(초). 넘으면 있는 대로 보인다. */
    static final int AFTER_WAIT = 25;
    /** 1.7.3(R-3): 앱 개인 폴더(getFilesDir)의 요청 파일 이름. root 쪽(status.sh·hotspot.sh의 REQ)과 같아야 한다 */
    static final String REQ_NAME = "report.req";
    /** 1.7.3(U-3): [지금 재부팅] 요청 파일 이름. root 쪽(hotspot.sh RBREQ)과 같아야 한다. 앱을 지우면 폴더째 지워진다(K-1) */
    static final String RB_NAME = "reboot.req";
    /** 1.7.3(리뷰 M2): root 감시자가 재부팅 요청을 받지 않았거나 명령이 돌아왔을 때 남기는 결과(id·boot·code, 644) */
    static final String RBRES = "/data/local/tmp/korea-projection-reboot-result.txt";
    /** 베타 1 리뷰 3: root 감시자가 끝나는 시각(boot=…, until=부팅 뒤 초, 644) */
    static final String WATCHF = "/data/local/tmp/korea-projection-watch.txt";

    static final int GOOD = Ui.GOOD, WARN = Ui.WARN, BAD = Ui.BAD;
    /**
     * 1.8.0(SC-3): 앱이 바꾸기 요청을 보낼 수 있는 토글(drafts/1.8.0-work/app.md 제안 A, 오케스트레이터 승인 2026-11-18).
     * 자동 업데이트(와 옛 패키지의 동글)는 "준비 중"으로 보이고 눌리지 않는다.
     * 계기판·곡 정보는 무선 모드 기본값으로 켜져 있어 "사용 중"·켬으로 보이고 눌리지 않는다(소유자 11-25).
     */
    static final String[] LIVE_TOGGLES = new String[] { "debug", "dongle" };

    /**
     * 1.8.0(SC-3): 설정 요청 기다림. 화면의 1초 반복(this)과 따로 둔다: 다른 곳의 handler.removeCallbacks(this)가 이 기다림을 끊지 않게.
     * 익명 클래스 대신 이름 있는 클래스(JDK 21 + d8 8.2가 익명 클래스에서 멈춤).
     */
    static final class SetTick implements Runnable {
        final StatusActivity a;
        SetTick(StatusActivity a) { this.a = a; }
        @Override
        public void run() { a.settingsTick(); }
    }
    final SetTick setTick = new SetTick(this);
    /**
     * 1.8.0 베타 2(소유자 제보 11-23): 결과 화면이 앞에 있는 동안 상태·안내·알림 파일이 바뀌었는지 1초마다 본다.
     * 설치 진행 틱(this)·설정 기다림(setTick)과 따로 둔다. 익명 클래스 대신 이름 있는 클래스.
     */
    static final class StatPoll implements Runnable {
        final StatusActivity a;
        StatPoll(StatusActivity a) { this.a = a; }
        @Override
        public void run() { a.statTick(); }
    }
    final StatPoll statPoll = new StatPoll(this);
    /** 화면을 그린 때의 파일 지문과 지난 틱에 본 지문(Ui.statSig) */
    long shownSig, seenSig;
    /** 설정 칸 스크롤(다시 그릴 때 위치를 이어 가려고) */
    Widgets.Scroll setScroll;
    /** showStatus가 늦게 온 설정 답을 처리했는가(그때는 다시 그리기 전의 실패 이유를 되살리지 않는다) */
    boolean lateDone;
    /** 지금 화면의 상태 값(설정 결과를 반영해 줄을 다시 그릴 때 쓴다)과 설치 중인가 */
    Report stat;
    boolean installingNow;
    final java.util.List<Widgets.ToggleRow> toggleViews = new java.util.ArrayList<Widgets.ToggleRow>();
    /** 기다리는 설정 요청: 키(없으면 null), 켜기인가, 요청 id, 보낸 때(부팅 뒤 밀리초) */
    String setKey;
    boolean setOn;
    /** 베타 3(B3-2): 요청을 보낼 때 동글 꽂기 기다림 중이었는가(그때 끈 것은 바로 적용). 화면이 그사이 새 상태로 바뀌어도 보낸 때 값으로 문구를 고른다 */
    boolean setWait;
    /** 기다리는 요청이 동글 "자동으로 되돌리기"(dongle=auto)인가 */
    boolean setAuto;
    /** 동글 "자동으로 되돌리기" 버튼과 그 자리(차주가 고른 값일 때만 보임). 없으면 null */
    Widgets.Btn dgAutoBtn;
    Widgets.Pair dgAutoBox;
    long setId, setEl;
    /** 바꾸지 못한 줄과 그 이유(한 문장). 다음 요청을 보내면 지운다 */
    String setFailKey, setFailMsg;
    /** 상태 줄(흐르는 글자를 화면이 멈출 때 끄려고 둠) */
    Widgets.StatusLine statusLine;
    /** 화면이 앞에 있는가(onResume~onPause). 새로 만든 상태 줄의 흐르는 글자를 이것에 맞춘다(리뷰 2 낮음 9) */
    boolean resumed;
    /** 재부팅 확인 창(떠 있을 때만)과 지금 결과 화면(확인 창 크기를 같은 배치에서 정하려고) */
    Widgets.Confirm confirm;
    Widgets.Screen screenView;

    final Handler handler = new Handler();
    String boot;
    boolean watching;
    /** 1.7.0: 제보 자료 저장(RPROG)을 1초마다 읽는 중 */
    boolean saving;
    Widgets.Bar saveBar;
    TextView saveText;
    /**
     * 1.7.3(R-2·R-5): [제보 파일 만들기] 버튼과 기다리는 요청. reqId: 요청 id(없으면 null), reqEl: 보낸 때의 부팅 뒤 밀리초
     * (시계가 바뀌어도 맞게 SystemClock.elapsedRealtime), reqFailed: 실패를 보였지만 늦게 시작한 진행을 아직 기다림.
     */
    Widgets.Btn reportBtn;
    /** 1.7.3(U-3): [지금 재부팅] 버튼과 요청을 보낸 때(부팅 뒤 밀리초, 0이면 없음) */
    Widgets.Btn rebootBtn;
    long rbEl;
    /** 기다리는 재부팅 요청의 id(요청 파일 첫 칸). 결과 파일과 맞춰 본다 */
    long rbId;
    /**
     * 1.7.4(B-7·B-8): 이어진 install·sysw 거절 기록 파일(앱 폴더, "<boot_id> <처음 거절 부팅 뒤 초> <마지막 거절 부팅 뒤 초>").
     * 1.7.3은 화면 안의 횟수라 화면을 다시 열면 0이 됐다. 파일로 두어 다시 열어도 이어진다. 앱을 지우면 함께 지워진다
     */
    static final String RB_STUCK_NAME = "reboot-stuck.txt";
    /** 리뷰 반영: 기록 파일을 쓰지 못했을 때 대신 쓰는 화면 안 값(같은 3칸 한 줄, 화면을 다시 열면 사라짐). 있으면 파일보다 먼저 본다 */
    String rbStuckMem;
    String reqId;
    long reqEl;
    boolean reqFailed;
    long finishedAt;
    Widgets.Bar bar;
    TextView pctText, stageText, timeText, noticeText, hintText;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        start();
        apLenOnce();
    }

    /** 베타 3(B3-12): 이 프로세스에서 이미 띄웠는가(같은 부팅이면 ApCfg가 파일의 boot_id로도 건너뜀) */
    static boolean apLenStarted;

    /** 카플레이 AP 값의 길이 기록(ApCfg)을 뒤에서 한 번 띄운다. 어떤 실패도 화면을 막지 않는다 */
    void apLenOnce() {
        if (apLenStarted) return;
        apLenStarted = true;
        try {
            String bid = read(BOOT_ID);
            Object wifi = getApplicationContext().getSystemService(WIFI_SERVICE);
            Thread t = new Thread(new ApCfg(getFilesDir(), wifi, bid == null ? "" : bid.trim()), "kp-apcfg");
            t.setDaemon(true);
            t.setPriority(Thread.MIN_PRIORITY);
            t.start();
        } catch (Throwable ignored) { }
    }

    /** Launch를 다시 누르면(singleTask) 같은 화면을 새 상태로 다시 그린다 */
    @Override
    protected void onNewIntent(Intent i) {
        super.onNewIntent(i);
        setIntent(i);
        handler.removeCallbacks(this);
        start();
    }

    void start() {
        // 리뷰 2 중간 5: 설치 진행 화면으로 가면 설정 기다림을 멈춘다(기억 파일이 남아 다음 결과 화면에서 이어 본다)
        handler.removeCallbacks(setTick);
        handler.removeCallbacks(statPoll);
        setKey = null; setAuto = false;
        String bid = read(BOOT_ID);
        boot = bid == null ? null : bid.trim();
        finishedAt = 0;
        Report p = Report.parse(read(PROG));
        if (p.progRunning(boot, System.currentTimeMillis() / 1000)) {
            showProgress(p);
            watching = true;
            handler.postDelayed(this, 1000);
        } else {
            watching = false;
            showStatus();
        }
    }

    /** 화면이 가려지면 읽기를 멈추고, 다시 보이면 이어서 */
    @Override
    protected void onPause() {
        handler.removeCallbacks(this);
        handler.removeCallbacks(setTick);
        handler.removeCallbacks(statPoll);
        resumed = false;
        // 리뷰 낮음 3: 손을 뗀 표시를 못 받았어도 다시 보일 때 다시 그리기가 막히지 않게
        if (setScroll != null) setScroll.touching = false;
        if (statusLine != null) statusLine.setActive(false);
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        resumed = true;
        if (statusLine != null) statusLine.setActive(true);
        if (watching || saving || rbEl > 0) {
            handler.removeCallbacks(this);
            handler.postDelayed(this, 1000);
        }
        if (setKey != null) {
            handler.removeCallbacks(setTick);
            handler.postDelayed(setTick, 1000);
        }
        // 가려진 사이에 바뀐 것은 다음 틱에 보고 그린다
        if (screenView != null && !watching) {
            handler.removeCallbacks(statPoll);
            handler.postDelayed(statPoll, Ui.STAT_POLL_MS);
        }
    }

    @Override
    protected void onDestroy() {
        watching = false;
        saving = false;
        handler.removeCallbacks(this);
        handler.removeCallbacks(setTick);
        handler.removeCallbacks(statPoll);
        super.onDestroy();
    }

    /** 1초마다: 진행 기록을 다시 읽어 막대를 고치고, 끝났으면 결과 화면으로 */
    @Override
    public void run() {
        if (!watching) {
            // 리뷰 M1: 제보 저장(saveTick)이 다음 틱을 잡지만, 그것이 끝나도 재부팅 기다림이 남았으면 여기서 이어 잡는다
            if (saving) saveTick();
            boolean rb = rbEl > 0 && rebootTick();
            if (rb && !saving) {
                handler.removeCallbacks(this);
                handler.postDelayed(this, 1000);
            }
            return;
        }
        Report p = Report.parse(read(PROG));
        long now = System.currentTimeMillis() / 1000;
        if (p.progRunning(boot, now)) {
            update(p, now);
            handler.postDelayed(this, 1000);
            return;
        }
        // 끝남: status.sh(--wait)가 상태 파일을 새로 쓸 때까지 잠시(최대 AFTER_WAIT초) "결과 정리 중"
        if (finishedAt == 0) finishedAt = now;
        long t = 0;
        try { t = Long.parseLong(p.get("t")); } catch (NumberFormatException e) { t = 0; }
        long st = new File(STATUS).lastModified() / 1000;
        if (st >= t || now - finishedAt >= AFTER_WAIT) {
            watching = false;
            showStatus();
            return;
        }
        if (bar != null) bar.setProgress(100);
        if (pctText != null) pctText.setText("100%");
        if (stageText != null) stageText.setText("끝났습니다. 결과를 정리하는 중입니다…");
        handler.postDelayed(this, 1000);
    }

    /** 설치 진행 화면: 막대, %, 지금 단계, 경과 시간, 안내 */
    void showProgress(Report p) {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xFF121212);
        int pad = dp(24);
        root.setPadding(pad, pad, pad, pad);
        root.setGravity(Gravity.CENTER_VERTICAL);

        root.addView(text("Korea Projection " + appVersion() + " 설치 중", 26, Color.WHITE));
        stageText = text(p.get("stage"), 20, Color.WHITE);
        LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, -2);
        sp.topMargin = dp(16);
        root.addView(stageText, sp);

        // 1.8.0(SC-2): Holo 진행 막대 대신 직접 그린 막대
        bar = new Widgets.Bar(this);
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(-1, dp(28));
        bp.topMargin = dp(12);
        root.addView(bar, bp);

        LinearLayout line = new LinearLayout(this);
        line.setOrientation(LinearLayout.HORIZONTAL);
        pctText = text("", 22, Color.WHITE);
        line.addView(pctText, new LinearLayout.LayoutParams(0, -2, 1f));
        timeText = text("", 18, 0xFFB0B0B0);
        line.addView(timeText);
        root.addView(line);

        // 1.7.1: 설치 중 알림(토스트 대신)은 단계 아래에 최근 것 하나
        noticeText = text("", 17, 0xFFFFE082);
        LinearLayout.LayoutParams ntp = new LinearLayout.LayoutParams(-1, -2);
        ntp.topMargin = dp(10);
        root.addView(noticeText, ntp);

        // 1.7.3(U-7): 안내는 두 문장. 10분이 넘으면 "평소보다 오래 걸립니다" 문구로 바꾼다(update)
        hintText = text(Report.PROGRESS_HINT, 16, 0xFFB0B0B0);
        LinearLayout.LayoutParams hp = new LinearLayout.LayoutParams(-1, -2);
        hp.topMargin = dp(18);
        root.addView(hintText, hp);

        // 1.8.0(SC-2): 직접 그린 버튼. 이 화면은 설치 중에만 잠깐 보여 배치는 예전(dp) 그대로 두고, 글자 크기만 받은 화면 크기에서 정한다
        Widgets.Btn close = new Widgets.Btn(this, "닫기", false);
        android.util.DisplayMetrics pdm = getResources().getDisplayMetrics();
        close.size(Layout.of(pdm.widthPixels, pdm.heightPixels, 89));
        close.setOnClickListener(this);
        LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(dp(160), dp(56));
        cp.topMargin = dp(18);
        root.addView(close, cp);

        confirm = null; screenView = null;
        setContentView(root);
        update(p, System.currentTimeMillis() / 1000);
    }

    void update(Report p, long now) {
        int pct = p.progPct();
        if (bar != null) bar.setProgress(pct);
        if (pctText != null) pctText.setText(pct + "%");
        String step = p.progStep();
        if (stageText != null) stageText.setText(step.isEmpty() ? p.get("stage") : step + " · " + p.get("stage"));
        if (timeText != null) timeText.setText("경과 " + Report.mmss(p.progElapsed(now)));
        if (hintText != null) {
            String slow = p.progSlow(now, Report.upSec(read("/proc/uptime")));
            hintText.setText(slow.isEmpty() ? Report.PROGRESS_HINT : slow);
            hintText.setTextColor(slow.isEmpty() ? 0xFFB0B0B0 : 0xFFFFE082);
        }
        if (noticeText != null) {
            java.util.List<String[]> ns = Report.notices(read(NOTICE), boot, 1, now, NOTICE_SHOW);
            noticeText.setText(ns.isEmpty() ? "" : "알림 " + clock(ns.get(0)[0]) + "  " + ns.get(0)[1]);
        }
    }

    /** 알림 시각(초) → "HH:MM". 읽지 못하면 빈 값 */
    static String clock(String sec) {
        try {
            java.util.Calendar c = java.util.Calendar.getInstance();
            c.setTimeInMillis(Long.parseLong(sec) * 1000L);
            return String.format(java.util.Locale.US, "%02d:%02d", c.get(java.util.Calendar.HOUR_OF_DAY), c.get(java.util.Calendar.MINUTE));
        } catch (Exception e) {
            return "";
        }
    }

    String appVersion() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (Exception e) {
            return "";
        }
    }

    /**
     * 1.7.0: 제보 자료 저장 진행(RPROG). 진행 중이면 막대와 %, 끝나면 초록 "완료: USB를 빼셔도 됩니다", 실패면 빨강.
     * 이번 부팅의 기록만 본다. 진행 중 기록이 오래 갱신되지 않으면(STALE) 멈춘 것으로 보고 읽기를 그만둔다.
     */
    void saveTick() {
        Report rp = Report.parse(read(RPROG));
        long now = System.currentTimeMillis() / 1000;
        if (saveText == null) { saving = false; return; }
        // 1.7.3(R-5): 자기 요청(RPROG의 req·req2)의 진행이 보일 때까지는 보냄 → 기다리는 중 → 실패 문구.
        // 실패를 보인 뒤에도 REQ_LATE초까지는 늦게 시작한 진행이 보이면 이어 따라간다(서비스 점검 경로).
        if (reqId != null) {
            long el = android.os.SystemClock.elapsedRealtime();
            if (el < reqEl) reqEl = el;
            long waited = (el - reqEl) / 1000;
            int ph = Report.reqPhase(rp, boot, reqId, waited);
            if (ph == 0) {
                reqId = null;
                reqFailed = false;
                deleteReq();
            } else if (reqFailed) {
                if (waited >= Report.REQ_LATE) { reqId = null; reqFailed = false; saving = false; return; }
                handler.postDelayed(this, 1000);
                return;
            } else if (ph == 3) {
                reqFailed = true;
                deleteReq();
                if (saveBar != null) saveBar.setVisibility(View.GONE);
                showSave(Report.REQ_FAILED, BAD, Color.WHITE);
                if (reportBtn != null) reportBtn.setEnabled(true);
                handler.postDelayed(this, 1000);
                return;
            } else {
                showSave(ph == 1 ? Report.REQ_SENT : Report.REQ_WAITING, 0xFF263238, Color.WHITE);
                if (saveBar != null) saveBar.setVisibility(View.GONE);
                handler.postDelayed(this, 1000);
                return;
            }
        }
        saveText.setVisibility(View.VISIBLE);
        String st = rp.get("state");
        if (rp.progRunning(boot, now)) {
            if (reportBtn != null) reportBtn.setEnabled(false);
            int pct = rp.progPct();
            saveText.setText("제보 자료 저장 중 " + pct + "% · " + rp.get("stage") + " (USB를 빼지 마세요)");
            saveText.setBackgroundColor(0xFF263238);
            saveText.setTextColor(Color.WHITE);
            if (saveBar != null) { saveBar.setVisibility(View.VISIBLE); saveBar.setProgress(pct); }
            handler.postDelayed(this, 1000);
            return;
        }
        saving = false;
        if (reportBtn != null) reportBtn.setEnabled(true);
        if (saveBar != null) saveBar.setVisibility(View.GONE);
        if ("done".equals(st)) {
            saveText.setText(rp.get("stage"));
            saveText.setBackgroundColor(GOOD);
            saveText.setTextColor(Color.WHITE);
        } else if ("fail".equals(st)) {
            saveText.setText(rp.get("stage"));
            saveText.setBackgroundColor(BAD);
            saveText.setTextColor(Color.WHITE);
        } else {
            saveText.setText("제보 자료 저장 상태를 알 수 없습니다. USB의 KoreaProjection-report 폴더를 확인해 주세요.");
            saveText.setBackgroundColor(WARN);
            saveText.setTextColor(Color.BLACK);
        }
    }

    /** 이번 부팅에, 최근(SAVE_SHOW초 안) 쓰인 저장 기록이 있는가 */
    boolean saveRecent(Report rp) {
        if (!rp.progThisBoot(boot)) return false;
        try {
            return System.currentTimeMillis() / 1000 - Long.parseLong(rp.get("t")) <= SAVE_SHOW;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    /**
     * 결과 화면. 1.8.0(SC-2·SC-6): 직접 그린 위젯과 받은 픽셀로 계산한 배치(Layout, Widgets.Screen)로 다시 짰다(설계 10장).
     * 맨 위 [상태 줄][닫기], 아래 넓은 화면 [상태 칸 | 설정 칸 | QR], 그 밖은 [상태 칸 + 설정 | QR]. 요청·재부팅 흐름은 1.7.4 그대로다.
     */
    void showStatus() {
        bar = null; pctText = null; stageText = null; timeText = null; noticeText = null; hintText = null; rebootBtn = null; rbEl = 0;
        // 화면을 새로 그리면(setContentView) 확인 창도 사라진다
        confirm = null; screenView = null;
        saveBar = null; saveText = null; saving = false; reportBtn = null; reqId = null; reqFailed = false;
        handler.removeCallbacks(setTick);
        setKey = null; setFailKey = null; setFailMsg = null; setAuto = false;
        toggleViews.clear();
        dgAutoBtn = null; dgAutoBox = null; setScroll = null;
        handler.removeCallbacks(statPoll);
        // 지문은 읽기 전에 잡는다: 그리는 사이에 바뀌면 다음 틱이 다시 그린다
        shownSig = seenSig = Ui.statSig(read(STATUS), read(HINT), read(NOTICE));
        Report r = Report.parse(read(STATUS));
        Report p = Report.parse(read(PROG));
        long nowS = System.currentTimeMillis() / 1000;
        stat = r;

        // 상태 줄: 1.7.3(K-5·U-8) 상태 파일에 판정 결과가 있으면 그것을, 옛 상태 파일이면 이번 부팅의 진행 결과(재부팅 필요·실패)를
        Widgets.StatusLine status = new Widgets.StatusLine(this);
        statusLine = status;
        status.setActive(resumed);
        String pv = r.get("verdict_msg").isEmpty() ? p.progVerdict(boot) : null;
        int lv = pv != null ? p.progLevel() : r.level();
        status.set(pv != null ? pv : r.verdict(), lv);

        Widgets.Btn close = new Widgets.Btn(this, "닫기", true);
        // 익명 클래스 대신 이 화면이 직접 받는다 (JDK 21 + d8 8.2가 익명 클래스에서 멈춤)
        close.setOnClickListener(this);

        // ---- 상태 칸: 지금 상태 3줄 → 판·차 정보 6줄(넓은 화면만) → 먼저 할 일 → 안내·알림 → 저장 표시 → 버튼(아래에 붙임)
        Widgets.Column info = new Widgets.Column(this);
        java.util.List<View> wideOnly = new java.util.ArrayList<View>();
        Widgets.KvCol sumCol = new Widgets.KvCol(), infoCol = new Widgets.KvCol();
        for (String sl : r.summary()) {
            String[] kv = Ui.kv(sl);
            info.add(new Widgets.Kv(this, sumCol, kv[0], kv[1], Ui.tone(kv[1]), false), Ui.P_SUMMARY, false);
        }
        if (!r.empty() && !r.nobb()) {
            for (String[] kv : Ui.info(r)) {
                Widgets.Kv k = new Widgets.Kv(this, infoCol, kv[0], kv[1], Ui.INK, true);
                info.add(k, Ui.P_INFO, false);
                wideOnly.add(k);
            }
        }
        // 1.7.3(G-4): 먼저 할 일. 1.8.0: first_lv로 색을 고른다(K-5 내비 업데이트 먼저는 노랑). 설치 진행 결과가 판정을 대신할 때는 보이지 않는다
        if (pv == null && !r.firstTodo().isEmpty()) {
            int fl = Ui.firstLevel(r);
            TextView ft = Widgets.text(this, r.firstTodo(), Widgets.T_SMALL, Ui.levelInk(fl));
            ft.setBackgroundColor(Ui.levelColor(fl));
            info.add(ft, Ui.P_KEEP, false);
        }
        // 소유자 결정(11-18): 옛 내비 안내(노랑). 막지 않고 알리기만. 설치 진행 결과가 판정을 대신할 때는 보이지 않는다
        String navOld = pv == null ? Ui.navOldNotice(r) : "";
        if (!navOld.isEmpty()) {
            TextView nt = Widgets.text(this, navOld, Widgets.T_SMALL, Ui.levelInk(1));
            nt.setBackgroundColor(Ui.levelColor(1));
            info.add(nt, Ui.P_HINT, false);
        }
        // U-6: "안 됨"으로 끝나면 지우는 법(회색)
        if (pv == null && !r.endHint().isEmpty())
            info.add(Widgets.text(this, r.endHint(), Widgets.T_SMALL, Ui.INK_DESC), Ui.P_ENDHINT, false);
        // 1.7.2: 서비스가 정한 상태 안내(폰 블루투스 다시 켜기·아이폰 Wi-Fi·설정 바뀜)
        for (String[] h : Report.hints(read(HINT), boot, nowS)) {
            String msg = h[1] + (h[2].isEmpty() ? "" : " (" + clock(h[2]) + ")");
            boolean good = "0".equals(h[0]);
            TextView ht = Widgets.text(this, msg, Widgets.T_SMALL, good ? Ui.INK : 0xFF000000);
            ht.setBackgroundColor(good ? Ui.GOOD : Ui.WARN);
            info.add(ht, Ui.P_HINT, false);
        }
        // 1.7.1: 알림(토스트 대신): 이번 부팅의 최근 3개, 새것이 위. 1.7.3(U-5): 진행이 끝난 시각보다 앞선 알림은 숨긴다
        for (String[] n : Report.notices(read(NOTICE), boot, 3, nowS, NOTICE_SHOW, p.progEndedAt(boot))) {
            TextView nt = Widgets.text(this, "알림 " + clock(n[0]) + "  " + n[1], Widgets.T_SMALL, Ui.INK_WARN);
            nt.setBackgroundColor(Ui.NOTE_BG);
            info.add(nt, Ui.P_NOTICE, false);
        }
        // 대기 알림: 재부팅 뒤 적용되는 바꾼 설정(상태 파일 set_pending, 제안 키)
        String pend = Ui.pendingNotice(r);
        if (!pend.isEmpty()) {
            TextView pt = Widgets.text(this, pend, Widgets.T_SMALL, Ui.INK_WARN);
            pt.setBackgroundColor(Ui.NOTE_BG);
            info.add(pt, Ui.P_PENDING, false);
        }
        // 1.7.0: 제보 자료 저장 진행(토스트 대신). 1.7.3: 버튼을 누른 뒤의 안내도 여기에 보인다
        saveText = Widgets.text(this, "", Widgets.T_SMALL, Ui.INK);
        saveText.setBackgroundColor(0xFF263238);
        saveText.setVisibility(View.GONE);
        info.add(saveText, Ui.P_KEEP, false);
        saveBar = new Widgets.Bar(this);
        saveBar.setVisibility(View.GONE);
        info.add(saveBar, Ui.P_KEEP, false);

        // 1.7.3(R-2): [제보 파일 만들기]·[지금 재부팅]. busybox 없는 내비(nobb)는 Launch가 짧은 리포트를 USB에 쓰므로 버튼이 없다.
        // [지금 재부팅]은 확인 창을 띄우고(운행 중에도 막지 않음, D-13), root가 설치 중·마무리 중·제보 만드는 중이면 거절한다
        Widgets.Pair btns = null;
        if (!r.nobb()) {
            btns = new Widgets.Pair(this, true);
            reportBtn = new Widgets.Btn(this, "제보 파일 만들기", false);
            reportBtn.setOnClickListener(this);
            btns.addView(reportBtn);
            rebootBtn = new Widgets.Btn(this, "재부팅", false);
            rebootBtn.setOnClickListener(this);
            btns.addView(rebootBtn);
            info.add(btns, Ui.P_KEEP, true);
        }

        // ---- 설정 칸(이 칸만 세로 스크롤): 묶음과 토글 줄, 맨 아래 자세히(제보용)·만든이
        Widgets.Column list = new Widgets.Column(this);
        installingNow = p.qrBlocked(boot) || p.progRunning(boot, nowS);
        // 화면을 닫았다 열어도 보낸 설정 요청이 아직 기다릴 시간(SET_WAIT초) 안이면 이어 기다린다. 오래된 요청은 지운다
        // 1.8.0(SC-3): 보낸 설정 요청의 기억(settings.last). 답이 이미 와 있으면 결과를 보이고(늦은 답, 리뷰 2 중간 6),
        // 아직 기다릴 시간(SET_WAIT초) 안이면 이어 기다린다. 오래된 기억·요청은 지운다
        String sraw = read(new File(getFilesDir(), Ui.SET_LAST).getPath());
        long[] sq = Report.reqParse(sraw, boot);
        String[] skv = Ui.settingsKv(sraw);
        long sel = android.os.SystemClock.elapsedRealtime();
        String lateCode = null;
        Report lateRes = null;
        if (sq != null && skv != null && Ui.contains(LIVE_TOGGLES, skv[0]) && sel >= sq[1]) {
            lateRes = Report.parse(read(Ui.SET_RES));
            lateCode = Ui.settingsAnswer(lateRes, boot, sq[0], skv[0]);
            long age = (sel - sq[1]) / 1000;
            if (lateCode != null || age < Ui.SET_WAIT) {
                setKey = skv[0]; setOn = "on".equals(skv[1]); setAuto = "auto".equals(skv[1]); setId = sq[0]; setEl = sq[1];
                // 다시 그린 뒤 이어 보는 요청: 보낸 때 값은 남기지 않았으니 지금 상태 값으로 본다
                setWait = stat != null && Ui.dongleWait(stat);
            } else {
                // 기다릴 시간은 지났다: 남은 요청은 지우고(root가 늦게 바꾸지 않게), 기억은 SET_LATE초까지 두어 늦은 답을 맞춰 본다
                try { new File(getFilesDir(), Ui.SET_NAME).delete(); } catch (Exception ignored) { }
                if (age >= Ui.SET_LATE) forgetSetting();
            }
        } else {
            forgetSetting();
        }
        for (Ui.Row row : Ui.rows(r, installingNow, setKey, null, null, LIVE_TOGGLES)) {
            if (!row.group.isEmpty()) list.add(new Widgets.Group(this, row.group), Ui.P_KEEP, false);
            Widgets.ToggleRow tr = new Widgets.ToggleRow(this, row);
            tr.setOnClickListener(this);
            toggleViews.add(tr);
            list.add(tr, Ui.P_KEEP, false);
            if ("dongle".equals(row.key)) {
                // 소유자 결정(11-18 밤): 토글과 떨어진 왼쪽 아래 작은 버튼. 보임·누름은 refreshRows가 정한다
                dgAutoBtn = new Widgets.Btn(this, Ui.DG_AUTO_BTN, true);
                dgAutoBtn.setOnClickListener(this);
                dgAutoBox = new Widgets.Pair(this, false);
                dgAutoBox.fitLeft = true;
                dgAutoBox.addView(dgAutoBtn);
                list.add(dgAutoBox, Ui.P_KEEP, false);
                showAutoBtn(Ui.dongleAutoBtn(r, row));
            }
        }
        lateDone = setKey != null && lateCode != null;
        if (lateDone) finishSetting(lateCode, lateRes);
        else if (setKey != null) handler.postDelayed(setTick, 1000);
        list.add(new Widgets.Group(this, "자세히(제보용)"), Ui.P_KEEP, false);
        for (String[] row : r.rows())
            list.add(Widgets.text(this, row[0] + ": " + row[1], Widgets.T_SMALL, 0xFFB0B0B0), Ui.P_KEEP, false);
        list.add(Widgets.text(this, r.nobb()
            ? "QR을 휴대폰 카메라로 찍으면 제보 화면(GitHub)이 열립니다. USB의 KoreaProjection-report 폴더 파일도 "
                + "함께 올려 주세요."
            : "QR을 휴대폰 카메라로 찍으면 내용이 채워진 제보 화면(GitHub)이 열립니다. "
                + "비밀번호, SSID, 휴대폰 이름, MAC은 들어 있지 않습니다.", Widgets.T_SMALL, Ui.INK_FAINT), Ui.P_KEEP, false);
        android.util.DisplayMetrics dm = getResources().getDisplayMetrics();
        list.add(Widgets.text(this, "확인 " + r.get("made") + " · 앱 " + appVersion() + " · 화면 " + dm.widthPixels + "x" + dm.heightPixels
            + " (밀도 " + dm.density + ")", Widgets.T_SMALL, Ui.INK_FAINT), Ui.P_KEEP, false);
        // 소유자 결정 2026-11-16: 만든이 줄(메일만, 제보는 QR의 GitHub 이슈로)
        list.add(Widgets.text(this, "만든이: StopDragon · hello@stopdragon.kr", Widgets.T_SMALL, Ui.INK_FAINT), Ui.P_KEEP, false);
        // 소유자 결정(11-18): 설정 부분은 스크롤(800×480처럼 낮은 화면). 굵은 막대를 직접 그리는 Widgets.Scroll
        Widgets.Scroll sv = new Widgets.Scroll(this);
        sv.addView(list);
        setScroll = sv;

        // ---- QR(맨 오른쪽). 1.7.3(U-2·U-3): 설치 중·재부팅 전에는 같은 자리에 안내
        View qrv;
        QrCode q = null;
        if (p.qrBlocked(boot)) {
            TextView qt = Widgets.text(this, Report.QR_BLOCKED, Widgets.T_BODY, Ui.INK);
            qt.setGravity(Gravity.CENTER);
            qrv = qt;
        } else {
            try {
                q = QrCode.encode(r.issueUrl().getBytes("UTF-8"));
            } catch (Exception e) {
                q = null;
            }
            qrv = new QrView(this, q);
        }
        // 배치는 버전 18(89칸)을 기준으로 잡는다(링크 상한 560자, 소유자 결정 2026-11-16). 만들지 못했으면 같은 크기로 비운다
        Widgets.Screen screen = new Widgets.Screen(this, status, close, info, sv, qrv, q != null ? q.size : 89);
        screen.wideOnly.addAll(wideOnly);
        screen.buttons = btns;

        Report rp = Report.parse(read(RPROG));
        // 화면을 닫았다 열어도 보낸 요청이 아직 받히지 않았으면(REQ_FAIL초 안) 기다림을 이어 보인다. 오래된 요청은 지운다.
        long[] rq = Report.reqParse(read(reqFile().getPath()), boot);
        long el = android.os.SystemClock.elapsedRealtime();
        if (rq != null && el >= rq[1] && (el - rq[1]) / 1000 < Report.REQ_FAIL && reportBtn != null) {
            reqId = String.valueOf(rq[0]);
            reqEl = rq[1];
            reportBtn.setEnabled(false);
        } else if (reqFile().exists()) {
            deleteReq();
        }
        if (reqId != null || saveRecent(rp)) {
            saving = true;
            saveTick();
        }

        // 리뷰 L2: 화면을 다시 그릴 때 남은 재부팅 요청: 이번 부팅·RB_WAIT초 안이면 기다림을 이어 보이고, 아니면 지운다
        // (감시자가 늦게 받아 예고 없이 재부팅하지 않게. root도 40초 넘은 요청은 받지 않는다)
        File rbf = new File(getFilesDir(), RB_NAME);
        long[] rbq = Report.reqParse(read(rbf.getPath()), boot);
        if (rbq != null && rebootBtn != null && el >= rbq[1] && (el - rbq[1]) / 1000 < Report.RB_WAIT) {
            rbEl = rbq[1]; rbId = rbq[0];
            rebootBtn.setEnabled(false);
            showSave(Report.RB_SENT, 0xFF263238, Color.WHITE);
            handler.removeCallbacks(this);
            handler.postDelayed(this, 1000);
        } else if (rbf.exists()) {
            try { rbf.delete(); } catch (Exception ignored) { }
        }
        screenView = screen;
        setContentView(screen);
        if (resumed) handler.postDelayed(statPoll, Ui.STAT_POLL_MS);
    }

    /** 지금 다시 그리면 안 되는 때: 확인 창, 설정·재부팅·제보 기다림, 설치 진행 화면, 설정 칸을 손가락으로 끄는 중 */
    boolean redrawBusy() {
        return confirm != null || setKey != null || rbEl > 0 || saving || watching
            || (setScroll != null && setScroll.touching);
    }

    /** 1초마다(결과 화면이 앞에 있을 때만): 파일이 바뀌어 두 틱 같으면 다시 그린다 */
    void statTick() {
        if (!resumed || screenView == null || watching) return;
        long cur = Ui.statSig(read(STATUS), read(HINT), read(NOTICE));
        int st = Ui.redrawStep(shownSig, seenSig, cur, redrawBusy());
        seenSig = cur;
        if (st == Ui.REDRAW_NOW) {
            redrawStatus();
            return;
        }
        handler.postDelayed(statPoll, Ui.STAT_POLL_MS);
    }

    /**
     * 결과 화면을 새 상태로 다시 그린다. 차주가 보던 것은 이어 간다: 설정 칸 스크롤 위치, 아래 안내 한 줄(설정 결과 등),
     * 바꾸지 못한 줄의 이유, 조그 다이얼 포커스(같은 버튼·같은 토글).
     */
    void redrawStatus() {
        int y = setScroll != null ? setScroll.getScrollY() : 0;
        String msg = null;
        int bg = 0, fg = 0;
        if (saveText != null && saveText.getVisibility() == View.VISIBLE) {
            msg = saveText.getText().toString();
            fg = saveText.getCurrentTextColor();
            android.graphics.drawable.Drawable d = saveText.getBackground();
            bg = d instanceof android.graphics.drawable.ColorDrawable ? ((android.graphics.drawable.ColorDrawable) d).getColor() : 0xFF263238;
        }
        String failKey = setFailKey, failMsg = setFailMsg;
        View f = getCurrentFocus();
        String focusKey = null;
        int focusBtn = 0;
        if (f instanceof Widgets.ToggleRow) focusKey = ((Widgets.ToggleRow) f).row.key;
        else if (f != null && f == dgAutoBtn) focusBtn = 1;
        else if (f != null && f == reportBtn) focusBtn = 2;
        else if (f != null && f == rebootBtn) focusBtn = 3;
        else if (f != null && screenView != null && f == screenView.close) focusBtn = 4;

        showStatus();

        if (setScroll != null) setScroll.keepY = y;
        // 다시 그린 화면이 스스로 보인 안내(최근 제보 저장 결과 등)가 있으면 그것이 먼저다
        if (msg != null && saveText != null && saveText.getVisibility() != View.VISIBLE) showSave(msg, bg, fg);
        // 리뷰 중간 1: 늦은 답을 이번에 처리했거나 요청을 다시 기다리면 옛 이유를 되살리지 않는다
        if (Ui.keepFail(failKey, lateDone, setFailKey, setKey)) {
            setFailKey = failKey; setFailMsg = failMsg;
            refreshRows();
        }
        View nf = null;
        if (focusKey != null) {
            for (Widgets.ToggleRow tv : toggleViews) if (focusKey.equals(tv.row.key)) nf = tv;
        } else if (focusBtn == 1) nf = dgAutoBtn;
        else if (focusBtn == 2) nf = reportBtn;
        else if (focusBtn == 3) nf = rebootBtn;
        else if (focusBtn == 4 && screenView != null) nf = screenView.close;
        if (nf != null && nf.isShown() && nf.isFocusable()) nf.requestFocus();
    }

    @Override
    public void onClick(View v) {
        // 확인 창이 떠 있으면 그 창만 다룬다: "재부팅"(연 뒤 잠시 지난 뒤)만 요청하고, 나머지(취소·바깥·뒤 화면 버튼)는 닫기만
        if (confirm != null) {
            boolean go = v == confirm.ok && confirm.armed();
            if (v == confirm.ok && !go) return;
            closeConfirm();
            // 리뷰 3 낮음 5: 닫은 뒤 포커스를 "지금 재부팅" 버튼으로 되돌린다
            if (rebootBtn != null) rebootBtn.requestFocus();
            if (!go) return;
            // 리뷰 3 낮음 3: 창을 오래 열어 둔 사이 바뀌었을 수 있으니 누를 때 한 번 더 본다(연 때와 같은 조건)
            if (Report.rbBusy(reqId != null && !reqFailed, Report.parse(read(RPROG)), boot, System.currentTimeMillis() / 1000)) {
                showSave(Report.RB_BUSY, WARN, Color.BLACK);
                return;
            }
            if (Report.watchGone(read(WATCHF), boot, android.os.SystemClock.elapsedRealtime() / 1000)) {
                showSave(Report.RB_NOWATCH, WARN, Color.BLACK);
                return;
            }
            requestReboot();
            return;
        }
        // 1.8.0: 토글 줄(닫기로 넘어가지 않게 여기서 끝낸다)
        if (v instanceof Widgets.ToggleRow) {
            requestSetting((Widgets.ToggleRow) v);
            return;
        }
        if (v == dgAutoBtn) {
            requestAuto();
            return;
        }
        if (v == reportBtn) {
            requestReport();
            return;
        }
        if (v == rebootBtn) {
            // 리뷰 M1: 제보 파일을 만드는 중이면 재부팅을 막는다(root도 막는다). 재리뷰 중간 2: 막는 것은 "진행 기록이 만드는 중"이거나
            // "내 요청이 아직 기다리는 중(REQ_FAIL초 안)"일 때뿐이다. 실패를 보인 뒤 늦은 진행을 기다리는 동안(reqFailed)은 막지 않는다
            if (Report.rbBusy(reqId != null && !reqFailed, Report.parse(read(RPROG)), boot, System.currentTimeMillis() / 1000)) {
                showSave(Report.RB_BUSY, WARN, Color.BLACK);
                return;
            }
            // 베타 1 리뷰 3: 받을 감시자가 끝났으면(Launch 뒤 10분) 요청을 보내지 않고 바로 알린다(RB_WAIT 기다린 뒤 RESET 안내 대신)
            if (Report.watchGone(read(WATCHF), boot, android.os.SystemClock.elapsedRealtime() / 1000)) {
                showSave(Report.RB_NOWATCH, WARN, Color.BLACK);
                return;
            }
            // 확인 창(소유자 결정 11-18: 직접 그린 창, "취소"가 기본). 누른 결과는 이 화면의 onClick이 받는다
            showConfirm();
            return;
        }
        finish();
    }

    /** 재부팅 확인 창을 이 화면 위에 띄운다. 크기는 지금 결과 화면의 배치(없으면 화면 크기)에서 */
    void showConfirm() {
        if (confirm != null) return;
        Layout l = screenView != null ? screenView.layout : null;
        if (l == null) {
            android.util.DisplayMetrics dm = getResources().getDisplayMetrics();
            l = Layout.of(dm.widthPixels, dm.heightPixels, 89);
        }
        Widgets.Confirm cf = new Widgets.Confirm(this, Ui.RB_ASK, Report.RB_CONFIRM, Ui.RB_CANCEL, Ui.RB_OK);
        cf.setOnClickListener(this);
        cf.cancel.setOnClickListener(this);
        cf.ok.setOnClickListener(this);
        Widgets.apply(cf, l);
        addContentView(cf, new android.view.ViewGroup.LayoutParams(-1, -1));
        confirm = cf;
        // 조그 다이얼·방향키로 누르면 "취소"가 먼저(실수로 재부팅되지 않게)
        cf.cancel.setFocusableInTouchMode(true);
        cf.cancel.requestFocus();
    }

    void closeConfirm() {
        if (confirm == null) return;
        android.view.ViewParent vp = confirm.getParent();
        if (vp instanceof android.view.ViewGroup) ((android.view.ViewGroup) vp).removeView(confirm);
        confirm = null;
    }

    /** 확인 창이 떠 있으면 뒤로 가기는 취소 */
    @Override
    public void onBackPressed() {
        if (confirm != null) {
            closeConfirm();
            return;
        }
        super.onBackPressed();
    }

    /**
     * 1.7.3(U-3): 앱은 reboot.req만 쓴다. root 감시자(status.sh --watch)가 막는 조건(설치 중·설치 마무리·시스템 영역을 바꾸는 작업·제보 만드는 중·다른 부팅·40초 지남)을
     * 다시 보고 재부팅한다. RB_WAIT초 뒤에도 이 화면이 살아 있으면 재부팅하지 못한 것으로 알린다.
     */
    void requestReboot() {
        long el = android.os.SystemClock.elapsedRealtime();
        if (!writeReq(RB_NAME, el)) {
            showSave(Report.REQ_WRITE_FAILED, BAD, Color.WHITE);
            return;
        }
        rbEl = el; rbId = el;
        if (rebootBtn != null) rebootBtn.setEnabled(false);
        showSave(Report.RB_SENT, 0xFF263238, Color.WHITE);
        handler.removeCallbacks(this);
        handler.postDelayed(this, 1000);
    }

    /** 재부팅 기다림. 더 기다려야 하면 true */
    boolean rebootTick() {
        long el = android.os.SystemClock.elapsedRealtime();
        if (el < rbEl) rbEl = el;
        // 리뷰 M2: root가 받지 않았다고 답했으면(설치 마무리 중 등) RB_WAIT초를 기다리지 않고 그 이유에 맞게 알린다
        Report res = Report.parse(read(RBRES));
        File sf = new File(getFilesDir(), RB_STUCK_NAME);
        long nowS = el / 1000;
        // 화면 안 값이 있으면(파일 쓰기가 실패했던 경우) 그것이 가장 새 값이다
        String st = rbStuckMem != null ? rbStuckMem : read(sf.getPath());
        long since = Report.stuckSince(st, boot, nowS);
        String ans = Report.rbAnswer(res, boot, rbId, since, nowS);
        if (ans == null && (el - rbEl) / 1000 < Report.RB_WAIT) return true;
        // 답이 install·sysw 거절이면 처음 거절 시각(없으면 지금)과 이번 거절 시각을 남기고, 다른 답·답 없음이면 지운다.
        // 파일을 쓰지 못하면 화면 안 값으로 대신한다. 8~9장 리뷰 L3: guard(시간이 지나면 풀림)는 기록을 만들지도 지우지도 않는다
        if (ans != null && Report.rbStuckCode(res)) {
            String line = Report.stuckLine(boot, since < 0 ? nowS : since, nowS);
            if (writeText(sf, line)) rbStuckMem = null;
            else {
                // 쓰지 못했으면 옛 파일이 다음에 앞서지 않게 지우고 화면 안 값으로 이어 간다
                rbStuckMem = line;
                try { sf.delete(); } catch (Exception ignored) { }
            }
        } else if (!"guard".equals(res.get("code").trim()) || ans == null) {
            rbStuckMem = null;
            try { sf.delete(); } catch (Exception ignored) { }
        }
        rbEl = 0;
        try { new File(getFilesDir(), RB_NAME).delete(); } catch (Exception ignored) { }
        // 아무도 답하지 않았으면(감시자 없음) 지금처럼 RESET 안내
        if (ans == null) ans = Report.RB_FAILED;
        if (Report.RB_FAILED.equals(ans)) showSave(ans, BAD, Color.WHITE);
        else showSave(ans, WARN, Color.BLACK);
        if (rebootBtn != null) rebootBtn.setEnabled(true);
        return false;
    }

    /**
     * 1.8.0(SC-3): 토글을 누름. 앱은 settings.req만 쓰고(임시 파일 → 이름 바꾸기), root가 처리해 답 파일을 쓴다.
     * 한 번에 하나: 답을 받거나 SET_WAIT초가 지나기 전에는 다른 토글을 막는다. 앱은 켜짐 여부를 혼자 믿지 않는다(답의 결과로만 바꿈).
     */
    void requestSetting(Widgets.ToggleRow v) {
        Ui.Row row = v.row;
        if (setKey != null || !row.enabled || !Ui.contains(LIVE_TOGGLES, row.key)) return;
        sendSetting(row.key, row.state != Ui.ON ? "on" : "off");
    }

    /** 동글 "자동으로 되돌리기": 동글 줄을 누를 수 있고 차주가 고른 값일 때만 dongle=auto를 보낸다 */
    void requestAuto() {
        if (setKey != null || stat == null) return;
        Ui.Row dg = null;
        for (Widgets.ToggleRow tv : toggleViews) if ("dongle".equals(tv.row.key)) dg = tv.row;
        if (Ui.dongleAutoBtn(stat, dg) != 2) return;
        sendSetting("dongle", "auto");
    }

    /** 요청 한 줄을 쓰고 답을 기다린다. val: on·off·auto(동글만) */
    void sendSetting(String key, String val) {
        boolean on = "on".equals(val);
        long el = android.os.SystemClock.elapsedRealtime();
        String line = Ui.settingsLine(el, boot, key, val);
        // 리뷰 2 낮음 7: 부팅 id를 못 읽으면 root가 받지 않으므로 바로 알린다. 기억 파일을 먼저 쓰고 요청 파일을 쓴다
        if (boot == null || boot.isEmpty() || !writeText(new File(getFilesDir(), Ui.SET_LAST), line)
                || !writeText(new File(getFilesDir(), Ui.SET_NAME), line)) {
            forgetSetting();
            setFailKey = key;
            setFailMsg = Ui.SET_WRITE_FAILED;
            refreshRows();
            return;
        }
        setKey = key; setOn = on; setAuto = "auto".equals(val); setId = el; setEl = el;
        setWait = stat != null && Ui.dongleWait(stat);
        setFailKey = null; setFailMsg = null;
        refreshRows();
        handler.removeCallbacks(setTick);
        handler.postDelayed(setTick, 1000);
    }

    /**
     * 설정 요청 기다림(1초마다). 답이 오면 그 결과, SET_WAIT초가 지나면 끝낸다. 그때 요청 파일이 아직 있으면 지우고(root가 받지 않음)
     * 실패로, 이미 없으면 root가 가져간 것이라 "결과를 아직 받지 못함"으로 둔다(리뷰 2 높음 1). 늦은 답은 기억 파일로 다음에 맞춰 본다.
     */
    void settingsTick() {
        if (setKey == null) return;
        long el = android.os.SystemClock.elapsedRealtime();
        if (el < setEl) setEl = el;
        Report res = Report.parse(read(Ui.SET_RES));
        String code = Ui.settingsAnswer(res, boot, setId, setKey);
        if (code != null) { finishSetting(code, res); return; }
        if ((el - setEl) / 1000 < Ui.SET_WAIT) {
            handler.postDelayed(setTick, 1000);
            return;
        }
        File rq = new File(getFilesDir(), Ui.SET_NAME);
        boolean dropped = false;
        try { dropped = rq.exists() && rq.delete(); } catch (Exception ignored) { dropped = false; }
        setFailKey = setKey;
        if (dropped) {
            // root가 받지 않았다: 아무것도 바뀌지 않았으니 기억도 지운다
            forgetSetting();
            setFailMsg = Ui.SET_FAILED;
        } else {
            setFailMsg = Ui.SET_UNKNOWN;
        }
        setKey = null; setAuto = false;
        refreshRows();
    }

    /** 답(code)으로 끝낸다: ok면 상태 값을 답의 val로 고치고 결과 문구, 아니면 토글을 원래 값 그대로 두고 이유 한 문장 */
    void finishSetting(String code, Report res) {
        handler.removeCallbacks(setTick);
        forgetSetting();
        boolean val = Ui.settingValue(res, setOn);
        String[] out = setAuto ? Ui.autoResult(code) : Ui.settingsResult(code, setKey, val, setWait);
        if ("ok".equals(out[1])) {
            if (stat != null) {
                if (setAuto) Ui.applyAuto(stat);
                else Ui.applySetting(stat, setKey, setOn, res);
            }
            setFailKey = null; setFailMsg = null;
            if (!out[0].isEmpty()) showSave(out[0], GOOD, Color.WHITE);
        } else {
            setFailKey = setKey;
            setFailMsg = out[0];
        }
        setKey = null; setAuto = false;
        refreshRows();
    }

    /** 요청·기억 파일을 지운다(남은 요청을 root가 늦게 받아 바꾸지 않게. root도 60초 넘은 요청은 버린다) */
    void forgetSetting() {
        try { new File(getFilesDir(), Ui.SET_NAME).delete(); } catch (Exception ignored) { }
        try { new File(getFilesDir(), Ui.SET_LAST).delete(); } catch (Exception ignored) { }
    }

    /** 토글 줄을 지금 상태(stat·기다리는 요청·실패)로 다시 그린다 */
    void refreshRows() {
        if (stat == null) return;
        java.util.List<Ui.Row> rows = Ui.rows(stat, installingNow, setKey, setFailKey, setFailMsg, LIVE_TOGGLES);
        for (Widgets.ToggleRow tv : toggleViews)
            for (Ui.Row n : rows)
                if (n.key.equals(tv.row.key)) tv.update(n);
        for (Ui.Row n : rows) if ("dongle".equals(n.key)) showAutoBtn(Ui.dongleAutoBtn(stat, n));
    }

    /** "자동으로 되돌리기" 버튼: 0 숨김, 1 보이되 막힘, 2 누를 수 있음 */
    void showAutoBtn(int st) {
        if (dgAutoBox == null || dgAutoBtn == null) return;
        int vis = st == 0 ? View.GONE : View.VISIBLE;
        if (dgAutoBox.getVisibility() != vis) dgAutoBox.setVisibility(vis);
        dgAutoBtn.setEnabled(st == 2);
    }

    /** 1.7.4(B-7·B-8): 앱 폴더의 작은 파일 쓰기(임시 파일 → 이름 바꾸기). 실패하면 아무것도 남기지 않고 false */
    static boolean writeText(File f, String text) {
        File tmp = new File(f.getPath() + ".tmp");
        java.io.FileOutputStream out = null;
        boolean ok = false;
        try {
            out = new java.io.FileOutputStream(tmp);
            out.write(text.getBytes("UTF-8"));
            out.close();
            out = null;
            ok = tmp.renameTo(f);
        } catch (Exception e) {
            ok = false;
        } finally {
            if (out != null) try { out.close(); } catch (Exception ignored) { }
        }
        if (!ok) tmp.delete();
        return ok;
    }

    /** 요청 파일 쓰기: 임시 파일 → 이름 바꾸기(root 쪽이 반쯤 쓴 파일을 읽지 않게). 내용은 Report.reqLine 한 줄 */
    boolean writeReq(String name, long el) {
        File f = new File(getFilesDir(), name);
        File tmp = new File(getFilesDir(), name + ".tmp");
        java.io.FileOutputStream out = null;
        boolean ok = false;
        try {
            out = new java.io.FileOutputStream(tmp);
            out.write(Report.reqLine(el, boot).getBytes("UTF-8"));
            out.close();
            out = null;
            ok = tmp.renameTo(f);
        } catch (Exception e) {
            ok = false;
        } finally {
            if (out != null) try { out.close(); } catch (Exception ignored) { }
        }
        if (!ok) tmp.delete();
        return ok;
    }

    /** 저장 표시줄에 한 줄(배경색·글자색) */
    void showSave(String msg, int bg, int fg) {
        if (saveText == null) return;
        saveText.setText(msg);
        saveText.setBackgroundColor(bg);
        saveText.setTextColor(fg);
        saveText.setVisibility(View.VISIBLE);
    }

    File reqFile() {
        return new File(getFilesDir(), REQ_NAME);
    }

    void deleteReq() {
        try { reqFile().delete(); } catch (Exception ignored) { }
    }

    /**
     * 1.7.3(R-2): 버튼을 누름. 막을 때(USB 없음·설치 중·만드는 중)는 짧은 문구만. 아니면 요청 파일을 쓰고(임시 파일 → 이름 바꾸기:
     * root 쪽이 반쯤 쓴 파일을 읽지 않게) 기다림 표시로 바꾼다. 요청 파일에는 요청 id(부팅 뒤 밀리초)·boot_id·부팅 뒤 초만 쓴다. USB를 읽지 못하면 막지 않는다(root가 다시 본다).
     */
    void requestReport() {
        long now = System.currentTimeMillis() / 1000;
        long el = android.os.SystemClock.elapsedRealtime();
        String why = Report.reqBlock(Report.parse(read(PROG)), Report.parse(read(RPROG)), boot, now,
            Report.usbMounted(read("/proc/mounts")));
        if (why != null) {
            showSave(why, WARN, Color.BLACK);
            return;
        }
        if (!writeReq(REQ_NAME, el)) {
            showSave(Report.REQ_WRITE_FAILED, BAD, Color.WHITE);
            return;
        }
        reqId = String.valueOf(el);
        reqEl = el;
        reqFailed = false;
        if (reportBtn != null) reportBtn.setEnabled(false);
        if (saveBar != null) saveBar.setVisibility(View.GONE);
        showSave(Report.REQ_SENT, 0xFF263238, Color.WHITE);
        saving = true;
        handler.removeCallbacks(this);
        handler.postDelayed(this, 1000);
    }

    TextView text(String s, int sp, int color) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        return t;
    }

    int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }

    static String read(String path) {
        InputStream in = null;
        try {
            in = new FileInputStream(path);
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
            return out.toString("UTF-8");
        } catch (Exception e) {
            return null;
        } finally {
            if (in != null) try { in.close(); } catch (Exception ignored) { }
        }
    }

}
