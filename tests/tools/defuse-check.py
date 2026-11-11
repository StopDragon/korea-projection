#!/usr/bin/env python3
# 베타 2 차주 제보(#64) 뒤: 패키지 셸 스크립트의 맨 위(함수 밖) 기본값 대입이 그보다 아래에서 처음 정해지는 변수를 참조하는지 찾는다.
# 예: KTB=${KTB:-$BK/ktime}이 BK=… 보다 위에 있으면 차에서는 BK가 비어 /ktime이 된다(stub-test는 BK를 환경으로 넘겨 놓쳤다).
# - ${X:-기본값} 꼴로 기본값을 함께 준 참조는 괜찮은 것으로 본다(AAOFF·APON_ORIG 꼴).
# - status.sh·post.sh·preun.sh는 svc/hotspot.sh를 . 으로 읽으므로, 그 줄 뒤에서는 hotspot.sh의 맨 위 변수를 정의된 것으로 본다.
# - 대입 값은 첫 ;까지만 본다(한 줄에 여러 문장).
# 또 "> 파일 2>/dev/null" 순서(파일을 못 열면 그 오류가 ap.log로 감)도 찾는다. 찾으면 줄마다 한 줄씩 내고 종료 코드 1.
import re, sys
PKG = sys.argv[1] if len(sys.argv) > 1 else 'nemesis-pkg/korea.projection'
FILES = ['svc/hotspot.sh', 'bin/status.sh', 'bin/carreport.sh', 'scripts/post.sh', 'scripts/preun.sh']
ASSIGN = re.compile(r'^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
FUNC = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*\(\)\s*\{')
def toplevel(path):
    out, depth = [], 0
    for n, l in enumerate(open(path, encoding='utf-8'), 1):
        s = l.rstrip('\n'); st = s.strip()
        if depth == 0 and FUNC.match(st):
            # 한 줄 함수(… }로 끝남)는 건너뛰고, 여러 줄 함수는 맨 앞 }까지 건너뛴다
            if not re.search(r'\}\s*$', st) or st.endswith('{'): depth = 1
            continue
        if depth:
            if s.startswith('}'): depth = 0
            continue
        out.append((n, s))
    return out
def defs(path):
    d = {}
    for n, s in toplevel(path):
        m = ASSIGN.match(s.strip())
        if m and m.group(1) not in d: d[m.group(1)] = n
    return d
def refs(val):
    # ${X:-…} 꼴은 빼고, $X·${X}·${X%…} 등만
    out = []
    for m in re.finditer(r'\$\{([A-Za-z_][A-Za-z0-9_]*)([^}]?)|\$([A-Za-z_][A-Za-z0-9_]*)', val):
        if m.group(1):
            if m.group(2) in (':', '-', '='): continue
            out.append(m.group(1))
        else: out.append(m.group(3))
    return out
bad = []
H = PKG + '/svc/hotspot.sh'
hdefs = defs(H)
for f in FILES:
    p = PKG + '/' + f
    lines = toplevel(p); d = defs(p)
    src = None
    if f != 'svc/hotspot.sh':
        for n, s in lines:
            if re.search(r'(^|\s)\.\s+\S*svc/hotspot\.sh', s): src = n; break
    for n, s in lines:
        st = s.strip()
        if st.startswith('#'): continue
        m = ASSIGN.match(st)
        if not m: continue
        name, val = m.group(1), m.group(2).split(';')[0]
        for r in refs(val):
            if r == name: continue
            if src and src < n and r in hdefs: continue
            dl = d.get(r)
            if dl is not None and dl > n: bad.append('%s:%d %s=…가 %s(%d행에서 처음 정함)를 먼저 씀' % (f, n, name, r, dl))
    for n, l in enumerate(open(p, encoding='utf-8'), 1):
        if l.lstrip().startswith('#'): continue
        if re.search(r'(?<![0-9&>])>>? *[^ &|;\'"(){}]+ +2>/dev/null', l) or re.search(r'(?<![0-9&>])>>? *"[^"]*" +2>/dev/null', l):
            bad.append('%s:%d "> 파일 2>/dev/null" 순서(파일을 못 열면 오류가 로그로 감): %s' % (f, n, l.strip()[:80]))
for b in bad: print(b)
sys.exit(1 if bad else 0)
