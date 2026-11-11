package korea.projection.app;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
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
public class StatusActivity extends Activity implements View.OnClickListener, Runnable, android.content.DialogInterface.OnClickListener {
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

    static final int GOOD = 0xFF2E7D32, WARN = 0xFFF9A825, BAD = 0xFFC62828;

    final Handler handler = new Handler();
    String boot;
    boolean watching;
    /** 1.7.0: 제보 자료 저장(RPROG)을 1초마다 읽는 중 */
    boolean saving;
    ProgressBar saveBar;
    TextView saveText;
    /**
     * 1.7.3(R-2·R-5): [제보 파일 만들기] 버튼과 기다리는 요청. reqId: 요청 id(없으면 null), reqEl: 보낸 때의 부팅 뒤 밀리초
     * (시계가 바뀌어도 맞게 SystemClock.elapsedRealtime), reqFailed: 실패를 보였지만 늦게 시작한 진행을 아직 기다림.
     */
    Button reportBtn;
    /** 1.7.3(U-3): [지금 재부팅] 버튼과 요청을 보낸 때(부팅 뒤 밀리초, 0이면 없음) */
    Button rebootBtn;
    long rbEl;
    /** 기다리는 재부팅 요청의 id(요청 파일 첫 칸). 결과 파일과 맞춰 본다 */
    long rbId;
    /** 재리뷰 M2: 이어진 install·sysw 거절 수(이 화면이 살아 있는 동안) */
    int rbStuck;
    String reqId;
    long reqEl;
    boolean reqFailed;
    long finishedAt;
    ProgressBar bar;
    TextView pctText, stageText, timeText, noticeText, hintText;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        start();
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
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (watching || saving || rbEl > 0) {
            handler.removeCallbacks(this);
            handler.postDelayed(this, 1000);
        }
    }

    @Override
    protected void onDestroy() {
        watching = false;
        saving = false;
        handler.removeCallbacks(this);
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

        bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(100);
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

        Button close = new Button(this);
        close.setText("닫기");
        close.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        close.setOnClickListener(this);
        LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(dp(160), -2);
        cp.topMargin = dp(18);
        root.addView(close, cp);

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

    /** 결과 화면(1.5.4까지의 화면). 설치 결과가 재부팅 필요·실패면 맨 위 판정을 그 문구로 바꾼다. */
    void showStatus() {
        bar = null; pctText = null; stageText = null; timeText = null; noticeText = null; hintText = null; rebootBtn = null; rbEl = 0;
        saveBar = null; saveText = null; saving = false; reportBtn = null; reqId = null; reqFailed = false;
        Report r = Report.parse(read(STATUS));
        Report p = Report.parse(read(PROG));

        // 가로로 둘: 왼쪽은 글(판정·표·안내·버튼), 오른쪽은 화면 높이를 다 쓰는 정사각형 QR.
        // QR을 먼저(가중치 없이) 재므로 높이만큼 자리를 먼저 받고, 왼쪽이 남은 폭을 쓴다.
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.HORIZONTAL);
        root.setBackgroundColor(0xFF121212);
        int pad = dp(12);
        root.setPadding(pad, pad, pad, pad);

        LinearLayout left = new LinearLayout(this);
        left.setOrientation(LinearLayout.VERTICAL);
        left.setPadding(0, 0, dp(16), 0);

        left.addView(text("Korea Projection " + r.get("pkgver"), 24, Color.WHITE));
        // 1.7.3(K-5·U-8): 상태 파일에 판정 결과가 있으면 그것을 쓴다(설치 진행 결과·남은 재부팅 횟수까지 들어 있음). 옛 상태 파일이면
        // 예전처럼 이번 부팅의 진행 결과(재부팅 필요·실패)가 판정을 대신한다
        String pv = r.get("verdict_msg").isEmpty() ? p.progVerdict(boot) : null;
        TextView verdict = text(pv != null ? pv : r.verdict(), 19, Color.WHITE);
        int lv = pv != null ? p.progLevel() : r.level();
        verdict.setBackgroundColor(lv == 0 ? GOOD : lv == 1 ? WARN : BAD);
        if (lv == 1) verdict.setTextColor(Color.BLACK);
        verdict.setPadding(dp(10), dp(6), dp(10), dp(6));
        LinearLayout.LayoutParams vp = new LinearLayout.LayoutParams(-1, -2);
        vp.topMargin = dp(6);
        vp.bottomMargin = dp(8);
        left.addView(verdict, vp);
        // 1.7.3(G-4): 먼저 할 일(노랑), U-6: "안 됨"으로 끝나면 지우는 법(회색). 설치 진행 결과가 판정을 대신할 때는 보이지 않는다
        if (pv == null && !r.firstTodo().isEmpty()) {
            TextView ft = text(r.firstTodo(), 16, Color.BLACK);
            ft.setBackgroundColor(WARN);
            ft.setPadding(dp(10), dp(4), dp(10), dp(4));
            LinearLayout.LayoutParams fp = new LinearLayout.LayoutParams(-1, -2);
            fp.bottomMargin = dp(4);
            left.addView(ft, fp);
        }
        if (pv == null && !r.endHint().isEmpty()) {
            TextView eh = text(r.endHint(), 14, 0xFFB0B0B0);
            LinearLayout.LayoutParams ep = new LinearLayout.LayoutParams(-1, -2);
            ep.bottomMargin = dp(6);
            left.addView(eh, ep);
        }

        // 1.7.2: 서비스가 정한 상태 안내(폰 블루투스 다시 켜기·아이폰 Wi-Fi·설정 바뀜). 화면을 열 때 읽는다
        // (베타 1: 무선 AA 준비됨·연결됨은 판정 줄이 카플레이와 함께 한 줄로 말한다)
        for (String[] h : Report.hints(read(HINT), boot, System.currentTimeMillis() / 1000)) {
            String msg = h[1] + (h[2].isEmpty() ? "" : " (" + clock(h[2]) + ")");
            boolean good = "0".equals(h[0]);
            TextView ht = text(msg, 17, good ? Color.WHITE : Color.BLACK);
            ht.setBackgroundColor(good ? GOOD : WARN);
            ht.setPadding(dp(10), dp(4), dp(10), dp(4));
            LinearLayout.LayoutParams hp = new LinearLayout.LayoutParams(-1, -2);
            hp.bottomMargin = dp(4);
            left.addView(ht, hp);
        }

        // 1.7.1: 알림(토스트 대신): 이번 부팅의 최근 3개, 새것이 위
        // 1.7.3(U-5): 진행이 끝난 시각보다 앞선 알림(지난 단계의 "재부팅하지 마세요" 등)은 숨긴다
        for (String[] n: Report.notices(read(NOTICE), boot, 3, System.currentTimeMillis() / 1000, NOTICE_SHOW, p.progEndedAt(boot))) {
            TextView nt = text("알림 " + clock(n[0]) + "  " + n[1], 16, Color.BLACK);
            nt.setBackgroundColor(0xFFFFE082);
            nt.setPadding(dp(10), dp(4), dp(10), dp(4));
            LinearLayout.LayoutParams np = new LinearLayout.LayoutParams(-1, -2);
            np.bottomMargin = dp(4);
            left.addView(nt, np);
        }

        // 1.7.3(R-2): [제보 파일 만들기] 버튼. Launch는 제보 파일을 만들지 않는다(예전 안내대로 Launch만 누른 분도 보이게 위쪽에).
        // busybox 없는 내비(nobb)는 Launch가 지금처럼 짧은 리포트를 USB에 쓰므로 버튼이 없다.
        // 베타 1(소유자 요청): [지금 재부팅]은 [제보 파일 만들기] 옆에 늘 둔다(예전에는 "재부팅 필요"일 때만 QR 자리에).
        // 누르면 확인 창을 띄우고(운행 중에도 막지 않음, D-13), root가 설치 중·마무리 중·제보 만드는 중이면 거절한다.
        if (!r.nobb()) {
            LinearLayout btns = new LinearLayout(this);
            btns.setOrientation(LinearLayout.HORIZONTAL);
            reportBtn = new Button(this);
            reportBtn.setText("제보 파일 만들기");
            reportBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
            reportBtn.setOnClickListener(this);
            btns.addView(reportBtn, new LinearLayout.LayoutParams(-2, dp(56)));
            rebootBtn = new Button(this);
            rebootBtn.setText("지금 재부팅");
            rebootBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
            rebootBtn.setOnClickListener(this);
            LinearLayout.LayoutParams rbb = new LinearLayout.LayoutParams(-2, dp(56));
            rbb.leftMargin = dp(12);
            btns.addView(rebootBtn, rbb);
            LinearLayout.LayoutParams rbp = new LinearLayout.LayoutParams(-2, -2);
            rbp.bottomMargin = dp(4);
            left.addView(btns, rbp);
        }

        // 1.7.0: 제보 자료 저장 진행(토스트 대신). 1.7.3: 버튼을 누른 뒤의 안내도 여기에 보인다
        saveText = text("", 17, Color.WHITE);
        saveText.setPadding(dp(10), dp(6), dp(10), dp(6));
        saveText.setVisibility(View.GONE);
        left.addView(saveText, new LinearLayout.LayoutParams(-1, -2));
        saveBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        saveBar.setMax(100);
        saveBar.setVisibility(View.GONE);
        LinearLayout.LayoutParams sbp = new LinearLayout.LayoutParams(-1, dp(14));
        sbp.bottomMargin = dp(8);
        left.addView(saveBar, sbp);
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

        LinearLayout table = new LinearLayout(this);
        table.setOrientation(LinearLayout.VERTICAL);
        // 1.7.3(U-9): 차주용 요약 3줄을 위에, 기존 표는 "자세히(제보용)" 아래 회색으로(QR 내용은 그대로)
        java.util.List<String> sum = r.summary();
        for (String sl : sum) {
            TextView st = text(sl, 18, Color.WHITE);
            st.setPadding(0, dp(2), 0, dp(2));
            table.addView(st);
        }
        if (!sum.isEmpty()) {
            TextView dt = text("자세히(제보용)", 13, 0xFF808080);
            dt.setPadding(0, dp(8), 0, dp(2));
            table.addView(dt);
        }
        for (String[] row : r.rows()) {
            LinearLayout line = new LinearLayout(this);
            line.setOrientation(LinearLayout.HORIZONTAL);
            line.addView(text(row[0], 16, 0xFFB0B0B0), new LinearLayout.LayoutParams(0, -2, 1.1f));
            line.addView(text(row[1], 16, Color.WHITE), new LinearLayout.LayoutParams(0, -2, 1f));
            line.setPadding(0, dp(2), 0, dp(2));
            table.addView(line);
        }
        ScrollView sv = new ScrollView(this);
        sv.addView(table);
        left.addView(sv, new LinearLayout.LayoutParams(-1, 0, 1f));

        TextView hint = text(r.nobb()
            ? "오른쪽 QR을 폰 카메라로 찍으면 제보 화면(GitHub)이 열립니다. USB의 KoreaProjection-report 폴더 파일을 "
                + "함께 올려 주시면 지원을 검토하는 데 도움이 됩니다. 개인정보는 들어 있지 않습니다."
            : "오른쪽 QR을 폰 카메라로 찍으면 내용이 채워진 제보 화면(GitHub)이 열립니다. "
                + "비밀번호, SSID, 휴대폰 이름, MAC은 들어 있지 않습니다.", 14, 0xFFB0B0B0);
        hint.setPadding(0, dp(6), 0, dp(6));
        left.addView(hint);

        LinearLayout bottom = new LinearLayout(this);
        bottom.setOrientation(LinearLayout.HORIZONTAL);
        bottom.setGravity(Gravity.CENTER_VERTICAL);
        Button close = new Button(this);
        close.setText("닫기");
        close.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        // 익명 클래스 대신 이 화면이 직접 받는다 (JDK 21 + d8 8.2가 익명 클래스에서 멈춤)
        close.setOnClickListener(this);
        bottom.addView(close, new LinearLayout.LayoutParams(dp(160), -2));
        android.util.DisplayMetrics dm = getResources().getDisplayMetrics();
        TextView made = text("  확인 " + r.get("made") + " · 앱 " + appVersion() + " · 화면 " + dm.widthPixels + "x" + dm.heightPixels
            + " (밀도 " + dm.density + ")", 12, 0xFF808080);
        bottom.addView(made);
        left.addView(bottom);

        if (p.qrBlocked(boot)) {
            // 1.7.3(U-2·U-3): 설치 중·재부팅 전에는 QR 대신 안내. 베타 1: [지금 재부팅]은 왼쪽 버튼 줄로 옮겼고,
            // 재부팅 안내는 판정 줄에서 한 번만 한다(이 문구는 재부팅을 다시 말하지 않음)
            LinearLayout side = new LinearLayout(this);
            side.setOrientation(LinearLayout.VERTICAL);
            side.setGravity(Gravity.CENTER);
            side.setPadding(dp(12), 0, 0, 0);
            side.addView(text(Report.QR_BLOCKED, 20, Color.WHITE));
            root.addView(side, new LinearLayout.LayoutParams(dp(320), -1));
        } else {
            QrCode q = null;
            try {
                q = QrCode.encode(r.issueUrl().getBytes("UTF-8"));
            } catch (Exception e) {
                q = null;
            }
            QrView qr = new QrView(this, q);
            // 높이는 부모를 꽉 채우고, 폭은 QrView가 높이와 같게 정한다
            root.addView(qr, new LinearLayout.LayoutParams(-2, -1));
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
        root.addView(left, 0, new LinearLayout.LayoutParams(0, -1, 1f));
        setContentView(root);
    }

    @Override
    public void onClick(View v) {
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
            // 확인 창. 익명 클래스 대신 이 화면이 직접 받는다(JDK 21 + d8 8.2가 익명 클래스에서 멈춤)
            new android.app.AlertDialog.Builder(this)
                .setTitle("지금 재부팅")
                .setMessage(Report.RB_CONFIRM)
                .setPositiveButton("재부팅", this)
                .setNegativeButton("취소", this)
                .show();
            return;
        }
        finish();
    }

    /** 확인 창의 버튼: 재부팅만 요청한다(취소는 닫기만) */
    @Override
    public void onClick(android.content.DialogInterface d, int which) {
        d.dismiss();
        if (which == android.content.DialogInterface.BUTTON_POSITIVE) requestReboot();
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
        String ans = Report.rbAnswer(res, boot, rbId, rbStuck);
        if (ans == null && (el - rbEl) / 1000 < Report.RB_WAIT) return true;
        // 답이 install·sysw 거절이면 이어진 수를 세고, 다른 답·답 없음이면 0으로
        // 8~9장 리뷰 L3: guard(시간이 지나면 풀림)는 세지도 않고 앞의 수를 지우지도 않는다
        if (ans != null && Report.rbStuckCode(res)) rbStuck++;
        else if (!"guard".equals(res.get("code").trim()) || ans == null) rbStuck = 0;
        rbEl = 0;
        try { new File(getFilesDir(), RB_NAME).delete(); } catch (Exception ignored) { }
        // 아무도 답하지 않았으면(감시자 없음) 지금처럼 RESET 안내
        if (ans == null) ans = Report.RB_FAILED;
        if (Report.RB_FAILED.equals(ans)) showSave(ans, BAD, Color.WHITE);
        else showSave(ans, WARN, Color.BLACK);
        if (rebootBtn != null) rebootBtn.setEnabled(true);
        return false;
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
