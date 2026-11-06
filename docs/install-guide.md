# Korea Projection 설치 가이드 (처음 하시는 분용)

컴퓨터에 익숙하지 않아도 따라 할 수 있게 한 단계씩 적었습니다. 순서대로 하시면 됩니다.

> ⚠️ 차량 소프트웨어를 바꾸는 일입니다. 모든 책임은 차 주인에게 있습니다.
> 설치는 **차를 세운 상태**에서만 하세요.

## 한눈에 보기

1. 준비물 확인 (NEMESIS, HMG-API)
2. USB를 **FAT32**로 포맷
3. **USB용 설치 파일**(`korea-projection-버전-usb.zip`) 받기
4. 압축을 풀고 **안에 있는 것**을 USB **맨 위**에 복사 (안쪽 `korea.projection.zip`은 풀지 않기)
5. 내비 화면이 다 뜬 뒤 USB를 꽂고 **예** 누르기
6. USB를 빼고 **2~3분 기다리기** ("무선 카플레이 설정을 마쳤습니다" 안내)
7. 시동 끄고 → 문 열었다 닫고 → 다시 켜기
8. 아이폰에서 무선 카플레이 연결

가장 많이 틀리는 곳은 **4번**입니다. 아래 [4단계](#4단계-usb에-복사하기)의 그림을 꼭 확인하세요.

---

## 1단계: 준비물 확인

| 준비물 | 설명 |
|---|---|
| 지원 차량 | 지금 확인된 차: **기아 니로 하이브리드(2020, DE PE)**, 내비 소프트웨어 `DEPEHEV.KOR.0000.V039.001.260902`. 차 테스트 중: **현대 쏘나타 하이브리드(2021, DN8)**, `DN822HEV.KOR.0000.V039.001.260902`. 다른 한국 차는 설치는 되지만 핫스팟을 켜지 않고 대기만 합니다([README 지원 차량](../README.md#지원-차량)) |
| NEMESIS | 1.16 이상이 차에 설치되어 있어야 합니다. 설치 방법: [NEMESIS 안내](https://github.com/xwtk/hmg_nemesis) |
| HMG-API | 1.0.2 이상이 차에 설치되어 있어야 합니다. 설치 방법: [HMG-API 안내](https://github.com/VysseCodes/HMG-API) |
| HMG-API 무선 모드 | **따로 설치하지 않아도 됩니다.** 확인된 차에서는 Korea Projection 1.5부터 자동으로 설치합니다 |
| USB 메모리 | **32GB 이하**를 쓰세요. 그보다 크면 Windows에서 FAT32로 포맷할 수 없습니다 |
| 컴퓨터 | Windows PC 또는 Mac |
| 아이폰 | 무선 카플레이를 지원하는 아이폰 |

**NEMESIS와 HMG-API가 이미 있는지 확인하는 법:** 내비에서 NEMESIS Manager를 열고 My Packages에 **HMG-API**가 보이면 됩니다.

`wireless.projection` 패키지는 **필요 없습니다.** 이미 있다면 그대로 두셔도 됩니다.

---

## 2단계: USB를 FAT32로 포맷하기

> ⚠️ 포맷하면 USB 안의 파일이 **모두 지워집니다.** 필요한 파일은 먼저 옮겨 두세요.
> 블랙박스·음악용으로 쓰던 USB보다는 **설치 전용 USB**를 따로 쓰시는 게 편합니다.

### Windows

1. USB를 PC에 꽂습니다.
2. 파일 탐색기(폴더 모양 아이콘)를 열고 왼쪽에서 **내 PC**를 누릅니다.
3. USB 드라이브(예: `USB 드라이브 (E:)`)를 **마우스 오른쪽 버튼**으로 누르고 **포맷...**을 고릅니다.
4. **파일 시스템**을 **FAT32**로 바꿉니다.
   - 목록에 FAT32가 없다면 USB가 32GB보다 큰 것입니다. 32GB 이하 USB를 쓰세요(exFAT·NTFS는 고르지 마세요).
5. **빠른 포맷**에 체크된 그대로 **시작**을 누르고, 경고가 나오면 **확인**을 누릅니다.

### Mac

1. USB를 Mac에 꽂습니다.
2. **디스크 유틸리티**를 엽니다(Spotlight에서 "디스크 유틸리티" 검색).
3. 왼쪽 목록에서 USB를 고르고 위쪽 **지우기**를 누릅니다.
4. 다음처럼 고르고 **지우기**를 누릅니다.
   - 이름: 아무거나 (예: `NEMESIS`)
   - 포맷: **MS-DOS(FAT)** (ExFAT이 아닙니다)
   - 방식(보이는 경우): **마스터 부트 레코드**

---

## 3단계: 설치 파일 받기

1. [최신 릴리스 페이지](https://github.com/StopDragon/korea-projection/releases/latest)를 엽니다.
2. 아래 **Assets**에서 **`korea-projection-버전-usb.zip`**을 받습니다(예: `korea-projection-1.5.1-usb.zip`).

| 파일 | 누가 받나요 |
|---|---|
| `korea-projection-버전-usb.zip` | **대부분의 사용자는 이것을 받으세요.** USB에 넣을 것이 모두 들어 있습니다 |
| `korea.projection-버전.zip` | 패키지만 들어 있습니다. 직접 `NEMESIS.data`를 만들거나 셸로 설치하는 분용입니다 |

`NEMESIS.data` 파일은 직접 만들지 않으셔도 됩니다. USB용 설치 파일 안에 미리 만들어 넣었습니다.
(메모장으로 직접 만들면 이름이 `NEMESIS.data.txt`가 되어 차가 알아보지 못하는 일이 많았습니다.)

---

## 4단계: USB에 복사하기

### USB 안이 이렇게 되어야 합니다

```
USB (맨 위)
├─ NEMESIS.data
├─ README.txt
└─ packages            ← 폴더
    └─ korea.projection.zip   ← 압축 파일 그대로 (풀지 않음)
```

USB를 열었을 때 **`NEMESIS.data`와 `packages` 폴더가 바로 보여야** 합니다.

### 이렇게 하면 안 됩니다

| 잘못된 모양 | 왜 안 되나요 |
|---|---|
| `USB/korea-projection-1.5.1-usb/NEMESIS.data` | 폴더째로 넣었습니다. 차는 USB **맨 위**의 `NEMESIS.data`만 찾습니다 |
| `USB/korea-projection-1.5.1-usb.zip` | 압축을 풀지 않았습니다 |
| `USB/packages/korea.projection/NEMESIS.data …` | 안쪽 `korea.projection.zip`까지 풀었습니다. 이 파일은 **zip 그대로** 있어야 합니다 |
| `USB/korea.projection.zip` (packages 폴더 없음) | 차는 `packages/korea.projection.zip` 위치에서 찾습니다 |
| `USB/NEMESIS.data.txt` | 이름 끝에 `.txt`가 붙었습니다. 받은 파일을 그대로 쓰세요 |

### Windows에서

1. 받은 `korea-projection-버전-usb.zip`을 **마우스 오른쪽 버튼**으로 누르고 **압축 풀기...**(또는 **모두 압축 풀기**)를 고릅니다.
2. 새 폴더가 열립니다. 그 폴더 **안으로 들어가서** `NEMESIS.data`, `README.txt`, `packages`가 보이는지 확인합니다.
3. `Ctrl + A`로 세 개를 모두 고르고 `Ctrl + C`로 복사합니다.
4. USB 드라이브를 열고(**아무 폴더에도 들어가지 않은 상태**) `Ctrl + V`로 붙여 넣습니다.
5. `packages` 폴더를 열어 `korea.projection.zip`이 **압축 파일 모양 그대로** 있는지 확인합니다. 열어 보거나 풀지 마세요.

반디집·알집 같은 프로그램을 쓰신다면 "여기에 풀기"보다 **"폴더명으로 풀기"**를 고른 뒤, 위 2~5번처럼 폴더 **안의 것**을 USB로 옮기세요.

### Mac에서

1. Safari로 받으면 자동으로 압축이 풀려 **다운로드 폴더에 `korea-projection-버전-usb` 폴더**가 생깁니다.
   - 압축이 풀리지 않고 `.zip`으로 남아 있다면 두 번 눌러 푸세요.
2. 그 폴더 **안으로 들어가서** `NEMESIS.data`, `README.txt`, `packages`를 모두 고릅니다(`⌘ + A`).
3. Finder 왼쪽의 USB로 **끌어다 놓습니다.** USB 창을 열었을 때 세 개가 바로 보여야 합니다.
4. `packages` 폴더 안의 `korea.projection.zip`은 **두 번 누르지 마세요.** 누르면 Mac이 압축을 풀어 버립니다. 풀린 폴더가 생겼다면 그 폴더만 지우고 zip은 남겨 두세요.

### 다 넣었으면

- 한 USB에는 한 패키지만 설치할 수 있습니다. 전에 HMG-API 같은 다른 패키지를 설치하던 USB라면, 복사할 때 `NEMESIS.data`를 **덮어쓰기**하세요.
- 컴퓨터에서 USB를 **안전하게 제거**(Windows: 작업 표시줄의 USB 아이콘 → 꺼내기 / Mac: Finder에서 꺼내기 ⏏)한 뒤 뽑습니다.

---

## 5단계: 차에 설치하기

1. 차를 세우고 시동(또는 전원)을 켭니다.
2. **내비 화면이 다 뜰 때까지** 1~2분 기다립니다.
3. USB를 차의 USB 단자에 꽂습니다.
4. 화면에 Korea Projection을 설치할지 묻는 창이 뜨면 **60초 안에 예**를 누릅니다.
   - 시간이 지나면 저절로 취소됩니다. USB를 뺐다가 다시 꽂으면 다시 묻습니다.
   - 확인된 차가 아니면 경고 색으로 표시될 수 있습니다. 그래도 설치는 됩니다(설치 후 대기만 함).
5. 설치가 끝났다는 안내가 나오면 **USB를 뺍니다.**
   - USB를 꽂아 둔 채로 두면 유선 연결을 먼저 시도해서 무선 연결이 안 될 수 있습니다.
6. **2~3분 기다립니다.** 확인된 차에서는 Korea Projection이 HMG-API 무선 모드와 그 차의 지도를 자동으로 갖춥니다.
   - **"무선 카플레이 설정을 마쳤습니다. 차를 껐다 켜 주세요"**가 뜨면 다음으로 넘어갑니다.
   - 이미 다 갖춰진 차(업데이트 등)에서는 이 안내 없이 바로 다음으로 넘어가도 됩니다.
   - "HMG-API 앱에서 변경 사항을 적용…" 같은 다른 안내가 뜨면, 그 안내를 따른 뒤 다음으로 넘어갑니다.
7. 시동을 끄고 → **문을 열었다 닫고** → 다시 켭니다. (내비가 완전히 꺼졌다 켜지게 하려는 것입니다.)

---

## 6단계: 아이폰 연결과 확인

1. 아이폰에서 **설정 → 일반 → CarPlay**를 엽니다.
2. **사용 가능한 차량**에 차가 보이면 누릅니다. 처음 한 번은 블루투스 연결을 함께 묻습니다.
3. 내비 화면에 카플레이가 뜨면 성공입니다.

**잘 되는지 확인하려면:** 내비에서 NEMESIS Manager → My Packages → Korea Projection → **Launch**를 누르세요.

- 맨 위가 **초록색**이면 준비된 상태입니다.
- 노랑·빨강이면 화면의 **QR을 폰 카메라로 찍어** 제보해 주세요. 내용이 채워진 제보 양식이 열립니다.

---

## 업데이트하는 법

설치와 똑같습니다. 새 버전의 `korea-projection-버전-usb.zip`을 받아 4~5단계를 그대로 하세요.
USB에 이전 파일이 있으면 **덮어쓰기**하면 됩니다. 업데이트할지 물으면 **예**를 누르세요.

---

## 잘 안 될 때

| 증상 | 확인할 것 |
|---|---|
| USB를 꽂아도 아무 창도 안 뜸 | ① USB가 **FAT32**인지 ② `NEMESIS.data`가 USB **맨 위**에 있는지(폴더 안 X) ③ 이름이 `NEMESIS.data.txt`가 아닌지 ④ 내비 화면이 다 뜬 뒤에 꽂았는지 ⑤ NEMESIS가 차에 설치되어 있는지 |
| 한 번 취소했더니 다시 안 물어봄 | 같은 USB는 꽂을 때 한 번만 묻습니다. **뺐다가 다시 꽂으세요** |
| 패키지를 찾을 수 없다는 오류 | `packages/korea.projection.zip`이 그 위치·그 이름으로 있는지, 압축을 풀어 버리지 않았는지 확인하세요 |
| 설치는 됐는데 카플레이가 안 뜸 | ① USB를 뺐는지 ② 시동을 끄고 문을 열었다 닫은 뒤 다시 켰는지 ③ HMG-API가 설치되어 있는지 ④ Launch 상태 화면의 색 |
| 다른 한국 차인데 안 됨 | 아직 확인되지 않은 차는 핫스팟을 켜지 않습니다. [내 차 제보 가이드](car-report-guide.md)대로 리포트 두 개를 보내 주시면 그 차를 추가합니다 |
| 내비가 휴대폰 핫스팟(일반 Wi-Fi)에 안 붙음 | 정상입니다. 무선 카플레이용 핫스팟이 켜져 있는 동안에는 Wi-Fi를 함께 쓸 수 없습니다 |

그래도 안 되면 [이슈](https://github.com/StopDragon/korea-projection/issues/new?template=car-report.yml)로 알려 주세요. 차종, 내비 소프트웨어 버전, Launch 화면 색을 함께 적어 주시면 빨리 볼 수 있습니다.
비밀번호, 휴대폰 이름, 차대번호(VIN)는 **적지 마세요.**

---

## 직접 만들고 싶은 분 (고급)

USB용 설치 파일 대신 패키지 zip(`korea.projection-버전.zip`)만 쓰려면:

1. 받은 파일 이름을 `korea.projection.zip`으로 바꿔 USB의 `packages` 폴더에 넣습니다.
2. USB 맨 위에 `NEMESIS.data`를 만들고 아래 세 줄을 넣습니다. 파일 이름 끝에 `.txt`가 붙지 않게 하세요(Windows는 탐색기 **보기 → 파일 확장명**을 켜면 보입니다).

```ini
[nemesis]
type=install
path=packages/korea.projection.zip
```

셸을 쓸 수 있다면: `nemesis install /storage/usb0/packages/korea.projection.zip`
