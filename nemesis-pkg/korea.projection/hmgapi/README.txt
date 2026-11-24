이 폴더의 파일은 Korea Projection 자동 설정(svc/hotspot.sh의 setup_hmgapi)이 HMG-API에 넣습니다.

- wireless-carplay-aa.zip: 한국 차 빌드
  - HMG-API의 "Wireless CarPlay + Android Auto" 모드(VysseCodes, AGPL-3.0)를 바탕으로 한 한국 차 빌드 2.4.6입니다(Korea Projection 1.8.0). 2.4.6은 2.4.5와 코드가 같고, 내장 Wi-Fi가 없는 차도 Korea Projection이 USB Wi-Fi 동글을 확인한 차(속성 persist.kp.wifi_dongle=1)이면 받도록 지원 차 목록에 한 줄을 더했습니다. HMG-API 앱에서는 "Korea Projection: Wireless CarPlay + Android Auto"로 보입니다(1.7.3까지의 2.4.1 이하는 원래 이름 그대로 보임, 모드 id는 wireless-carplay-aa 그대로). 확인된 한국 차의 지원 차 목록·패치 세트와, 한국 차용 코드 수정(계기판·HUD 회전 안내, 무선 안드로이드 오토, 무선 카플레이 곡 정보)이 들어 있습니다.
  - 계기판·HUD 길안내는 지도 앱이 보낸 것을 순정 표대로 전달하고, 현대·기아 순정 내비 화면에 맞춰 보정합니다(2.4.3부터). 보정을 끄면 순정 표 그대로 전달합니다.
  - HMG-API 앱의 이 모드 설정에서 끄고 켤 수 있는 한국 차 빌드 설정입니다. 넷 다 기본 켬이고, 바꾸면 앱을 다시 시작해야 합니다.
    - tbt_fit: 앱에는 "Turn-by-turn fitted to the Hyundai/Kia navigation (near-turn view, distance bar)"로 보입니다. 계기판 길안내를 현대·기아 순정 내비 화면에 맞춰 보정합니다(곧 회전 큰 그림·남은 거리 막대·표 밖 회전 화살표·재탐색 문구·안드로이드 오토 도로 이름 유지). 끄면 지도 앱이 보낸 것을 순정 표대로만 전달합니다(무선 모드 2.4.2와 같음).
    - aa_name_hold: 앱에는 "Android Auto cluster: keep the turn icon when the phone sends a road name change for the same point"로 보입니다. 안드로이드 오토 계기판에서 같은 지점의 도로 이름만 바뀔 때 회전 아이콘을 유지합니다. tbt_fit이 켜졌을 때만 쓰입니다.
    - aa_ready_resend: 앱에는 "Wireless Android Auto: resend ready after phone projection starts"로 보입니다. 무선 안드로이드 오토 준비 신호 다시 보내기.
    - star_popup_skip: 앱에는 "Star key: skip the stock phone projection hint popup"로 보입니다. 별표 키를 눌렀을 때 순정 폰 프로젝션 안내 팝업을 건너뜁니다(2.4.5부터). 순정 무선 등록 폰이 없을 때만 건너뛰고, 등록 폰이 있으면 순정 목록 팝업이 그대로 뜹니다. 끄면 순정 그대로입니다.
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
