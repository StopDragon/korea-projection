# Common USB Wi-Fi integration candidate

내장 Wi-Fi가 없는 Gen5W에서 USB Wi-Fi를 Korea Projection 내부 서비스로 준비하는 **선택형 통합 제안**입니다. 개인용 1.7.4.2의 실행 소스를 검토 가능한 오버레이와 작은 런타임 패치로 정리했습니다. 저장소의 기본 `nemesis-pkg/`와 공식 배포 버전은 바꾸지 않습니다. 이 폴더 자체는 설치 USB가 아닙니다.

내장 BCM/SDIO 라디오가 있으면 기존 경로를 우선합니다. USB는 실제 VID:PID와 `ff/ff/ff` 인터페이스, Android/플랫폼/커널 설정, 순정 모듈 지문, 드라이버별 필수 export와 배포 해시로 선택합니다. 같은 조건이면 차종 목록에 없는 차량도 조건부 시도합니다. 이름이나 커널 release/심볼 이름만으로 ABI 호환을 증명했다고 보지 않습니다. 자료가 없거나 다른 장치/프로세스가 소유한 경우에는 이유를 남기고 진단으로 멈춥니다.

AC 17개 ID와 RTL8831BU/RTL8851BU 6개 ID를 포함합니다. AX900mini의 실제 ID가 `0bda:b831`인 경우도 공통 경로로 선택합니다. `b831`은 source/driver8851의 패치를 적용해 컴파일했으며 binary alias 수정이나 `new_id` 강제 바인딩을 쓰지 않습니다. `b832`와 가상 CD ID는 제외합니다. 다른 커널·설정과 tcc897x에는 검증된 ABI 근거가 없어 자동 적재하지 않습니다.

선택한 드라이버는 적재 전 실패 보호를 기록하고, 같은 부팅의 적재 증명과 실제 USB/netdev 소유권을 확인합니다. 자체 AP/DHCP만 관리하고, 67번 DHCP bind 충돌이 확인될 때만 1067/68의 포트 변환을 사용합니다. 단일 데이터 포트의 저장/재부팅/USB 복사 흐름도 포함합니다. 동글 계열을 실행 중 바꾸면 재부팅을 요구합니다.

마지막 프로필과 관측 단계를 원자적으로 기억합니다. 펌웨어/커널/설정/드라이버/실제 USB/모드/지도/코드가 바뀌거나 실패하면 다시 검증하며, 캐시로 실물/소유권/필수 검사를 생략하지 않습니다. 바인딩·AP·DHCP·제어 TCP와 사용자가 확인한 화면/안정 시간을 구분합니다. 준비됨/TCP를 화면 성공으로 저장하지 않고 VIN/MAC/SSID/암호도 이력에 저장하지 않습니다.

차량 이름에 묶인 처리는 NX4HEV의 제공된 서명 모드/HT20 및 EV6의 순정 odex에 맞춘 보조 모드입니다. HMG-API 지도/모드 검사와 EV6 GPM/services/사양 검사를 유지합니다. 미완료 적재와 반복 AP 실패는 재시도 폭주를 막는 별도 보호 상태로 남깁니다.

## 공개 소스와 빌드 입력

`overlay/`는 새 실행 소스와 실제 사용하는 GPL 드라이버·대응 소스, EV6 보조 모드·대응 소스를 포함합니다. `runtime.patch`는 원본 1.7.4의 기존 코어를 복제하지 않고 필요한 변경만 표현합니다. 사용하지 않는 GRT/EV6 참조 바이너리와 개인용 설치 ZIP, 원본 사용자 로그, 개인 키는 커밋하지 않습니다. 개인용 설치본에 보관했던 참조 파일이 제외됐으며, 활성 연결 경로는 동일합니다.

원본 서명 파일은 빌더가 입력합니다. 서명이나 HMG-API 검사를 우회하지 않습니다.

```sh
# 공식 1.7.4 패키지: SHA-256 d33dae33…c4315 (prepare.py가 전체 해시 확인)
curl -fL -o /tmp/korea.projection-1.7.4.zip \
  https://github.com/StopDragon/korea-projection/releases/download/v1.7.4/korea.projection-1.7.4.zip
cd experimental/usbwifi-integration
python3 prepare.py --base-package /tmp/korea.projection-1.7.4.zip
python3 -m unittest discover -s tests -v
```

위 명령은 공개 입력만으로 전체 호스트 시험을 준비합니다. NX4 서명 모드를 실행하거나 전체 설치 ZIP을 만드는 시험은 아닙니다. 입력 없이 설치 ZIP을 생성하지 않습니다.

개인용 전체 구성 재현에는 제공된 NX4 1.7.4.1 패키지 ZIP도 필요합니다. 그 안의 **서명 모드 하나만** 해시 확인 후 추출하고 GRT 바이너리는 가져오지 않습니다. 해당 모드의 정확한 대응 hooks 소스를 이 작업에서 확정하지 못했으므로 공개 PR에는 싣지 않습니다. 공식 통합/배포 시에는 유지관리자가 그 소스·서명 모드 제공 방식을 결정해야 합니다.

```sh
python3 prepare.py --base-package /tmp/korea.projection-1.7.4.zip \
  --nx4-package /path/to/original-1.7.4.1/packages/korea.projection.zip
python3 build.py
# dist/KoreaProjection-1.7.4.2-Auto-USB.zip
```

입력 SHA-256과 모든 포함 바이너리 해시는 `prepare.py`, `build.py`, `ORIGINS.json`, 각 드라이버의 `SOURCE.txt`에 있습니다. 결과 `pkg/`, `dist/`는 Git에서 제외합니다. 설치/단일 포트 로그 복사/되돌리기 절차는 [usb/README.txt](usb/README.txt), 출처는 [usb/THIRD-PARTY.txt](usb/THIRD-PARTY.txt)를 확인하세요.

## 검증 범위

원래 개인용 조합의 호스트 시험 76개, 셸 문법 검사 126건과 AX 빌드 검사를 마쳤습니다. 공개 오버레이로 다시 준비한 76개 시험과 추가 빌드 입력 시험 2개도 통과했습니다. 현재 실행 소스는 30개 셸 파일의 문법 검사 90건을 통과했습니다. 세부 결과는 [VALIDATION.md](VALIDATION.md)와 PR/CI에 기록합니다. AP 조회 C 파서에는 Linux UBSan 시험도 제공합니다.

```sh
# Linux에서 AP capability 파서 검증 (실물 AP 시험 아님)
cc -Wall -Wextra -Werror -fsanitize=undefined \
  -Ipkg/usb/g70/source tests/ap_capabilities_test.c -o /tmp/ap-capabilities-test
/tmp/ap-capabilities-test
```

새 AX 모듈의 203개 필수 export는 수집한 G70 커널 export에 모두 존재합니다([AX-MODULE.json](AX-MODULE.json)). 이는 완전한 ABI 증명이나 AP/프로젝션/화면 안정성 성공을 뜻하지 않습니다.

통합판 전체와 G70 AX900mini의 실차 시험은 남아 있습니다. G70 이전 0.4.0에서는 실제 CarPlay 화면이 나왔지만 음악이 계속 나오는 동안 화면이 멈추는 증상이 있었습니다. 소유자가 이를 종료하려고 강제로 끊었습니다. 종료/재연결 로그를 자연 단절로 분류하지 않으며, 새 RX 체크섬 패치가 이 증상을 해결했다고 주장하지 않습니다. EV6 원 프로젝트의 실차 보고는 Android Auto이며 이 통합판의 CarPlay 검증은 아닙니다.
