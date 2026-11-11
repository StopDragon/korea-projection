이 폴더의 파일은 Korea Projection 자동 설정(svc/hotspot.sh의 setup_hmgapi)이 HMG-API에 넣습니다.

- wireless-carplay-aa.zip: 한국 차 빌드
  - HMG-API의 "Wireless CarPlay + Android Auto" 모드(VysseCodes, AGPL-3.0)를 바탕으로 한 한국 차 빌드 2.4.1입니다(Korea Projection 1.7.3). 확인된 한국 차의 지원 차 목록·패치 세트와, 한국 차용 코드 수정(계기판·HUD 회전 안내를 순정 한국 내비 번호로, 무선 안드로이드 오토, 무선 카플레이 곡 정보)이 들어 있습니다.
  - HMG-API 앱의 이 모드 설정에서 끄고 켤 수 있는 한국 차 빌드 설정: aa_ready_resend(무선 안드로이드 오토 준비 신호 다시 보내기), aa_name_hold(안드로이드 오토 계기판에서 같은 지점의 도로 이름만 바뀔 때 회전 아이콘 유지). 둘 다 기본 켬이고, 바꾸면 앱을 다시 시작해야 합니다.
  - 지금 들어 있는 차: 기아 니로 하이브리드(DEPEHEV.KOR 260902, 패치 세트 depehev), 현대 쏘나타 하이브리드 DN8(DN822HEV.KOR 260902, 패치 세트 dn822hev, 시험 지원), 현대 그랜저 하이브리드 IG(IGPEHEV.KOR 260902, 패치 세트 dn822hev 같이 씀, 시험 지원), 현대 벨로스터 N(JSN.KOR 260902, 패치 세트 dn822hev 같이 씀, 시험 지원), 현대 그랜저 2.5 IG PE(IGPE.KOR 260902, 패치 세트 dn822hev 같이 씀, 시험 지원)
  - 그 밖의 한국 차(Wi-Fi 칩이 있는 차)도 받습니다(자동 시험, 패치 세트 kor). 지도는 HMG-API가 그 차에서 만들고 확인합니다.
  - 대응 소스(AGPL-3.0): 코드(hooks.jar)의 소스는 포크 https://github.com/StopDragon/HMG-API 의 korea-build 브랜치(HMG-API v1.0.2에서 시작)에 있습니다. 우리가 바꾼 데이터(mod.json, patches.json, patches/)와 다시 만드는 방법은 공개 저장소 https://github.com/StopDragon/korea-projection 의 hmgapi-mod/ 폴더에 있습니다. 쏘나타 순정 체크섬은 차주 제보(HMG-API #91 Car Report)와 같습니다.
  - 원본 소스는 https://github.com/Open-HMG/HMG-API (예전 주소 VysseCodes/HMG-API) 입니다. 니로 지도 변경분은 PR #22 에 있습니다.
  - Korea Projection 개발 키로 서명했고, HMG-API의 신뢰 작성자 목록에는 없습니다.
  - HMG-API는 같은 키로 서명한 업데이트만 받습니다. 그래서 공식 모드로 바꾸려면 이 모드를 먼저 지워야 합니다. HMG-API 앱에서 지우거나 `hmgapid engine remove wireless-carplay-aa`를 실행한 뒤, 변경 사항을 적용합니다.
- maps/<제조사>/<차종>/<지역>/<펌웨어>/*.json: 차별 HMG-API 훅 지도
  - 차주 차에서 지도 확인(verify-map)을 통과한 것만 넣습니다. 설치할 때 그 차에서 다시 지도 확인을 합니다.
  - kia/niro/kor/260902: 2026-11-05 차에서 342개 지점을 확인했습니다(PR #22와 같은 내용).
  - hyundai/sonata/kor/260902: 쏘나타 차주의 Car Report(HMG-API #91, 2026-11-05)에서 HMG-API tools/report-map.py로 만들었습니다. 그 차에서 지도 확인 342개 지점 통과(실패 0). 상태는 probed(차에서 만든 지도)이고, 무선 카플레이 동작은 아직 확인되지 않았습니다.
  - hyundai/grandeur/kor/260902: 그랜저 하이브리드 차주의 Car Report(우리 이슈 #7, 2026-11-06)에서 같은 방법으로 만들었습니다. 그 차에서 지도 확인 342개 지점 통과. 무선 카플레이 동작은 아직 확인되지 않았습니다.
  - hyundai/veloster-n/kor/260902: 벨로스터 N 차주의 Car Report(우리 이슈 #8, 2026-11-06)에서 같은 방법으로 만들었습니다. 그 차에서 지도 확인 342개 지점 통과. 무선 카플레이 동작은 아직 확인되지 않았습니다.
  - hyundai/grandeur-gasoline/kor/260902: 그랜저 2.5 차주의 Car Report(우리 이슈 #2, 2026-11-06)에서 같은 방법으로 만들었습니다. 그 차에서 지도 확인 342개 지점 통과. 순정 체크섬이 그랜저 하이브리드와 같습니다. 무선 카플레이 동작은 아직 확인되지 않았습니다.

새 차를 추가하는 절차는 docs/car-report-guide.md(공개 저장소)를 봅니다. HMG-API 공식판이 그 차를 지원하게 되면 공식 모드와 지도로 바꿀 예정입니다.
