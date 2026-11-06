이 폴더의 파일은 Korea Projection 자동 설정(svc/hotspot.sh의 setup_hmgapi)이 HMG-API에 넣습니다.

- wireless-carplay-aa.zip: 한국 차 빌드
  - HMG-API의 "Wireless CarPlay + Android Auto" 2.1.0 모드(VysseCodes, AGPL-3.0)에, 확인된 한국 차의 지원 차 목록과 패치 세트를 더해 빌드한 것입니다.
  - 지금 들어 있는 차: 기아 니로 하이브리드(DEPEHEV.KOR 260902), 현대 쏘나타 하이브리드(DN822HEV.KOR 260902)
  - 원본 소스는 https://github.com/VysseCodes/HMG-API 입니다. 니로 변경분은 PR VysseCodes/HMG-API#22 에 있습니다.
    쏘나타 변경분은 StopDragon/HMG-API의 maps/hyundai-sonata-dn822hev-kor-260902 브랜치(니로 브랜치 위)에 있습니다.
  - Korea Projection 개발 키로 서명했고, HMG-API의 신뢰 작성자 목록에는 없습니다.
  - HMG-API는 같은 키로 서명한 업데이트만 받습니다. 그래서 공식 모드로 바꾸려면 이 모드를 먼저 지워야 합니다. HMG-API 앱에서 지우거나 `hmgapid engine remove wireless-carplay-aa`를 실행한 뒤, 변경 사항을 적용합니다.
- maps/<제조사>/<차종>/<지역>/<펌웨어>/*.json: 차별 HMG-API 훅 지도
  - 차주 차에서 지도 확인(verify-map)을 통과한 것만 넣습니다.
  - kia/niro/kor/260902: 2026-11-05 차에서 342개 지점을 확인했습니다(PR #22와 같은 내용).
  - hyundai/sonata/kor/260902: 차주 Car Report(2026-11-06, 이슈 #4)의 차 위 지도에서 만들었습니다. 그 차에서 지도 확인
    (verify-map)을 통과했습니다(342개 지점, 실패 0). 지점은 니로와 모두 같고 순정 파일 md5만 다릅니다.

새 차를 추가하는 절차는 docs/car-report-guide.md(공개 저장소)를 봅니다. HMG-API 공식판이 그 차를 지원하게 되면 공식 모드와 지도로 바꿀 예정입니다.
