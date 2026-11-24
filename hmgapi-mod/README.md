# 한국 차 빌드 무선 모드: 대응 소스

Korea Projection 패키지에 들어 있는 `nemesis-pkg/korea.projection/hmgapi/wireless-carplay-aa.zip`(한국 차 빌드)의 대응 소스(AGPL-3.0 6조)와, 이 모드를 직접 다시 만드는 방법을 담았습니다.

## 바탕이 된 것

- **HMG-API**(VysseCodes, AGPL-3.0)의 "Wireless CarPlay + Android Auto" 모드입니다. Korea Projection 1.5.1~1.5.6은 업스트림 **2.1.0** 코드 그대로였고, 1.5.7부터는 아래 "1.5.7부터"의 포크 코드입니다(1.7.1은 한국 차 빌드 **2.3.0**, 1.7.2는 **2.4.0**).
  - 저장소: https://github.com/Open-HMG/HMG-API (예전 주소 `VysseCodes/HMG-API`에서 옮겨졌습니다)
  - 태그: `v1.0.2` (커밋 `180185de2c57afb2cca4858d0be7828e8f1051d6`)
  - 모드 폴더: `mods/wireless-carplay-aa/`
- **1.5.6까지 코드는 업스트림 그대로였습니다.** Korea Projection 1.5.1~1.5.6에 든 `hooks.jar`는 업스트림 v1.0.0·v1.0.1·v1.0.2 릴리스의 `hooks.jar`와 바이트까지 같습니다.
  - SHA-256: `b8525dfc1d0ce7539a5c7d4cae331ddc0464d78394f61ba72172e554fc7e973d`
  - 그 소스는 위 태그의 `mods/wireless-carplay-aa/src/`입니다. `files/`, `recipes/`, `settings.json`, `stubs/`도 업스트림 그대로입니다.

## 우리가 바꾼 파일

| 파일 | 바꾼 내용 |
|---|---|
| `wireless-carplay-aa/mod.json` | 지원 차 목록(`system`)에 한국 차를 더했습니다. 확인된 차(`KOR` 260902)와, Wi-Fi 칩이 있는 그 밖의 한국 차(`hmgapi.wifi`)입니다 |
| `wireless-carplay-aa/patches.json` | 한국 차 모델 코드를 패치 세트에 이었습니다 |
| `wireless-carplay-aa/patches/depehev`, `dn822hev`, `kor` | 한국 차 패치 세트입니다. `stock`은 순정 파일 13개의 md5 목록(텍스트)이고, `expect`는 빈 파일입니다. 순정 프로그램 조각은 들어 있지 않습니다 |
| `META-HMGAPI/` (배포 zip 안) | Korea Projection 개발 키로 다시 서명했습니다. 서명 키는 공개하지 않습니다 |

- 니로 하이브리드는 2026-11-05에 추가했습니다. 쏘나타 하이브리드, 그랜저 하이브리드·2.5, 벨로스터 N은 2026-11-05~06에 차주 제보로 추가했습니다.
- `add-car.py`: 차주 제보 파일로 위 데이터와 차별 지도를 만들고 모드를 서명하는 도구입니다. 우리 작업 폴더 구조(`niro-carplay-build/`)를 기준으로 짜여 있어 그대로는 돌지 않을 수 있습니다. 무엇을 바꾸는지 보는 참고용으로 둡니다.

## 직접 다시 만들기 (자기 키로 서명해 넣기)

준비물은 JDK 17, Android SDK(build-tools, `android.jar`), Python 3입니다. HMG-API `build.sh`와 같습니다.

- `ANDROID_HOME`을 SDK 폴더로 두고, `java`·`javac`가 JDK 17을 가리키게 합니다. JDK 21과 d8 8.x를 함께 쓰면 빌드가 멈춥니다.
- `hooks.jar`의 바이트는 d8 버전에 따라 달라집니다. 업스트림 v1.0.2 릴리스는 d8 9.2.4로 빌드됐고, 이 d8은 Android SDK **build-tools 37.0.0**에 들어 있습니다.
  - **JDK 17 + build-tools 37.0.0으로 v1.0.2를 빌드하면 `hooks.jar`가 배포본과 바이트까지 같습니다**(SHA-256 `b8525dfc…`, 2026-11-07 PC에서 확인).
- 이 절차는 PC에서 임시 키로 끝까지 돌려 확인했습니다(2026-11-07). 이때는 d8 8.2.2를 써서 `hooks.jar` 바이트가 달랐고, 서명 말고 나머지 파일은 배포본과 같았습니다.

```sh
git clone https://github.com/Open-HMG/HMG-API.git
cd HMG-API
git checkout v1.0.2

# 1. 이 폴더의 데이터를 업스트림 모드 폴더에 덮어씁니다
cp -R <이 저장소>/hmgapi-mod/wireless-carplay-aa/. mods/wireless-carplay-aa/

# 2. 내 모드 키를 만듭니다(처음 한 번). 키 파일은 남에게 주지 않습니다
mkdir -p out/engine-host
javac --release 8 -d out/engine-host core/runtime/java/hmgapi/engine/*.java
java -cp out/engine-host hmgapi.engine.Signing keygen ~/my-mod.key

# 3. hooks.jar를 소스에서 빌드하고 내 키로 서명합니다
sh tools/mkmodpkg.sh mods/wireless-carplay-aa ~/my-mod.key
# → out/packages/wireless-carplay-aa-2.1.0.zip
```

### 차에 넣을 때 주의

- HMG-API는 **같은 id, 같은 키로 서명한 업데이트만** 받습니다. 그래서 Korea Projection이 넣은 모드를 먼저 지워야 합니다.
  - 지우는 방법: HMG-API 앱에서 모드를 지우거나 `hmgapid engine remove wireless-carplay-aa`를 실행한 뒤 변경 사항을 적용합니다.
- 그다음 직접 만든 zip을 HMG-API 앱으로 설치합니다. 내 키는 HMG-API 신뢰 작성자 목록에 없습니다. Korea Projection 모드도 목록에 없는 키로 서명되어 있고, 그대로 설치되고 있습니다.
- Korea Projection 자동 설정은 모드가 지워진 기록이 있으면 다시 넣지 않습니다.

## 1.5.7부터

계기판·HUD 회전 안내 수정부터 모드의 Java 코드가 업스트림과 달라집니다. 그 코드는 포크 `StopDragon/HMG-API`의 `korea-build` 브랜치(업스트림 `v1.0.2`에서 시작)에 둡니다. 릴리스마다 이 README와 릴리스 설명에 그 커밋과 `hooks.jar` SHA-256을 적습니다.

| Korea Projection | 모드 | 바뀐 코드 | `hooks.jar` SHA-256 |
|---|---|---|---|
| 1.5.7 | 2.1.1 | 계기판·HUD 회전 안내(각도 없는 회전, 대체 화살표, 다시 보내기) | 릴리스 설명 참고 |
| 1.7.0 | 2.2.0 | 무선 안드로이드 오토(우리 핫스팟을 AA에 알림) | `42c2fbb2f0b1cc014154b8a8531b53b3f634753ee11f3fc156eda9c97f5b81ab` |
| 1.7.1 | 2.3.0 | 계기판·HUD 번호를 순정 한국 내비와 같게(램프·회전교차로·차로 조합, 안드로이드 오토 포함), 무선 카플레이 곡 정보, 디버그 때만 순정 관찰 기록 | `83aac4ca2dada357e031ea06dd058babe874eab7b9c3dc6ddecc981042128ac2`(포크 커밋 `38b4432`, 곡 정보는 `577434c`) |
| 1.7.2 | 2.4.0 | 곧 회전 큰 그림과 거리 막대(막대는 순정 단속 정보 프레임의 막대 칸에도), 경로 탐색·재탐색 화면, 안내 끝 지우기, 애플 지도 이름 번갈아 와도 지우지 않기, 블루투스 SPP 재시도, NQ5 훅 꺼짐 고침, 안드로이드 오토 글자 깨짐 고침 | `bcedcf279d62e06272425f5d0536dd5a752c2b3ba9e1d79e307a066296f866ce`(포크 커밋 `29c4e30`, `b02a141`) |
| 1.7.3 | 2.4.1 | 릴리스 설명 참고 | `07efaa70250663d0bfea13c29f839d20d7ef8073d67c36a0d132254145e29699` |
| 1.7.4 | 2.4.5 | 계기판 길안내를 순정 표대로 전달하고 보정을 얹음(설정 `tbt_fit`: 큰 그림·막대·표 밖 화살표·재탐색), 회전이 바뀌는 순간의 프레임 수정, 좌회전 옆길 각도, 별표 키 순정 안내 팝업 건너뜀(설정 `star_popup_skip`). 포크 커밋 `b573ac6` | `6205d04888e4bdbdf2f120cf0695a81b0236471ccdfc88f1fa744884a19cb4e5` |
| 1.8.0 | 2.4.9 | USB Wi-Fi 동글 차 지원(2.4.6~2.4.8), 순정 방화벽이 있는 차(캐스퍼 EV 등)에서 무선 안드로이드 오토 연결 통로를 엶(설정 `aa_firewall`) | 릴리스 설명 참고 |

- 1.7.1의 차로 조합 그림 표는 seogaemo(커밋 `26eeb97`, AGPL-3.0)에서 옮겼습니다. 출처는 소스 파일 머리말에 적었습니다.

## 라이선스

이 폴더는 AGPL-3.0입니다(저장소 `LICENSE`, 원저작권 고지는 `NOTICE.md`).
