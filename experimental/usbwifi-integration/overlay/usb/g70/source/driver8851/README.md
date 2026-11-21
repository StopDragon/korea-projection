# Private KP 1.7.4.2 common RTL8831BU / RTL8851BU build

This copy adds `0005-rtl8831bu-id-table.patch` to the original EV6 kernel adaptations.
Its compiled table contains b831, b851, 2001:332a, 2c4e:0128, 3625:010b, 7392:e611,
all with ff/ff/ff interface matching. B832 and virtual-CD IDs are not matched.
No binary alias rewriting or sysfs new_id injection is used.

The shared conditional backend is available on G70 and other products that meet
its Android/platform/kernel/config/stock-module/export checks. A matching release
string or symbol-name list alone is never an ABI proof. All actual AX dongle/AP/
projection/display/stability tests on these vehicles remain outstanding.

Use the supplied build scripts on Linux/Docker. This workspace used the pinned
AOSP gcc 4.7 and Ubuntu 20.04 under QEMU. An emulated assembler crash was retried
with one make job and a 64 MiB host stack, after every tracked source file was
compared with the pinned source archive plus all five patches. Code-generation
flags, source, kernel config and toolchain were unchanged during the retry.
`SOURCE.txt` describes the resulting module; the upstream archive, patches,
config and GPL license are included. Runtime requires exactly the pinned binary.

Primary mapping references:
https://github.com/torvalds/linux/blob/master/drivers/net/wireless/realtek/rtw89/rtw8851bu.c
https://github.com/biglinux/rtl8831/blob/main/os_dep/linux/usb_intf.c
Manufacturer chipset description: https://iptime.com/products/807?pd=1

Original EV6 build instructions follow:

# RTL8851BU 실험 드라이버 소스 (GPL-2.0)

> ⚠️ **실험(EXPERIMENTAL):** 실물 동글로 시험하지 않았습니다. 이 차 커널용으로 빌드되는 것과, 빌드 검사(커널 버전 표시, 커널 심볼, 커널 설정, 모듈 파라미터)를 통과하는 것까지만 확인했습니다.

이 패키지의 `modules/8851bu.ko`(Realtek RTL8851BU USB Wi-Fi 6 드라이버)를 다시 빌드하는 데 필요한 파일입니다.

| 파일 | 내용 |
|---|---|
| `SOURCE.txt` | 원본 드라이버 주소와 커밋, 패치·커널·툴체인 정보, 빌드된 `8851bu.ko`의 해시 |
| `patches/` | 원본에 적용한 패치 4개 (이름 순서대로) |
| `build.sh`, `inner-build.sh` | 빌드 스크립트 (Docker, `../driver`와 같은 커널·툴체인 준비) |
| `config_tcc803x.txt` | 빌드에 쓴 차량 커널 설정 |
| `COPYING` | GPL-2.0 전문 |

## 원본 드라이버
Realtek 제조사 드라이버 https://github.com/fofajardo/rtl8851bu (GPL-2.0), 커밋 `9e37e7a1101316a05d5daede91549ea779b64539`

## 패치
1. `0001` 차량 플랫폼(Telechips tcc803x, ARMv7, Linux 3.18.24-tcc)용 빌드 설정
2. `0002` 드라이버가 잡은 동글을 usbfs로 열지 못하게 막음 (순정 안드로이드 오토의 "지원하지 않는 기기" 알림 방지)
3. `0003` 갑자기 뽑았을 때의 보호 (일부만 옮김)
4. `0004` Linux 3.18 / gcc 4.7로 빌드되게 고침

## 빌드
Docker가 필요합니다. 이 폴더에서 `./build.sh`를 실행하면 `out/8851bu.ko`와 `out/SOURCE.txt`가 만들어집니다.
