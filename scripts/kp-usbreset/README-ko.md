# kp-usbreset (베타 3 동글 다시 붙이기 3단계용)

USB 장치 노드 하나에 `USBDEVFS_RESET` ioctl을 한 번 보내는 작은 도우미입니다. 우리가 직접 쓴 C 코드이고, 라이선스는 AGPL-3.0-or-later입니다(AGPL 소스 묶음에 넣음).

| 파일 | 내용 |
|---|---|
| `kp-usbreset.c` | 소스(libc 없이 ARM EABI 시스템 호출만 씀) |
| `build.sh` | 빌드 스크립트 |
| `kp-usbreset` | 바이너리, 4852바이트, SHA-256 `08b8362a6c1aa01bec6e71fc25fb72fbff82773e97e1ff63335d7902f43201b6` |

- 형식: ELF32 ARM, EABI5, 정적 링크, 공유 라이브러리 없음, `-march=armv7-a -marm`, 소프트 부동소수점(부동소수점 안 씀)
  - 니로(tcc897x)와 tcc803x의 32비트 사용자 공간 모두 ARM EABI라 같은 파일이 돕니다.
  - 차에서 돌려 보지는 않았습니다.
- 같은 툴체인으로 두 번 빌드했고, SHA-256이 같았습니다(재현 가능, 2026-11-23 KST).

## 쓰는 법

```bash
kp-usbreset /dev/.kp-usbr/004-002
```

| 결과 | 출력 한 줄 | 종료 코드 |
|---|---|---|
| 성공 | `kp-usbreset: ok` | 0 |
| 노드를 열지 못함 | `kp-usbreset: open err N` | N(errno, 예: 2 없음, 21 폴더) |
| ioctl 실패 | `kp-usbreset: ioctl err N` | N(예: 25 usbfs 노드가 아님, 22 장치 상태가 리셋 불가, 21 루트 허브) |
| 인자 틀림 | `kp-usbreset: usage …` | 22 |

- 한 번 보내고 끝납니다. 다시 시도하거나 기다리지 않습니다.
- 노드를 만들거나 지우지 않습니다. 노드는 부르는 쪽(서비스)이 준비합니다.
- **노드는 `/dev/bus/usb` 밖(우리 전용 폴더)에 만드세요.** 가드가 동글 자리를 빈 폴더로 바꿔 두었기 때문입니다. `/dev/bus/usb` 안에 만들면 순정이 그것을 새 장치로 보고 AOA를 다시 보낼 수 있습니다(dongle.md 4-27 (2)).
  - 만드는 법: `mknod <경로> c 189 <부번호>`. 부번호는 `(버스-1)×128 + (장치번호-1)`입니다(예: 버스 4·장치 2 → 385).
  - 쓰고 나면 지웁니다. 파일 권한은 서비스의 `umask 077`을 따릅니다.

## 빌드

```bash
TC=/work/tc bash build.sh /out
```

- `TC`: AOSP `platform/prebuilts/gcc/linux-x86/arm/arm-eabi-4.7`(kitkat-release) 폴더, `arm-eabi-gcc (GCC) 4.7`. 우리 동글 드라이버 빌드와 같은 툴체인입니다.
  - `bin/arm-eabi-gcc` sha256 `89a07707b49062910fdec9b55a7fb920809638fde0517a70cf669cb6e4d3661b`
- 우리는 Ubuntu 20.04 컨테이너(x86_64)에서 빌드했습니다.
- 크기를 줄인 방법
  - `-nostdlib -ffreestanding`: libc를 쓰지 않습니다.
  - `-Wl,-z,max-page-size=0x1000`: 기본 32KB 정렬로 생기는 빈 공간을 줄입니다.
  - `strip`: 기호와 주석을 지웁니다.
  - 나눗셈을 쓰지 않아 libgcc도 들어가지 않습니다.

## PC에서 확인한 것(2026-11-23 KST)

- Docker(Apple 실리콘 Mac)의 ARM 에뮬레이션으로 실행했습니다. 커널이 다른 USB 장치는 없어 성공 길은 확인하지 못했습니다.

| 경우 | 결과 |
|---|---|
| 없는 경로 `/nonexist` | `open err 2`, 종료 2 |
| 폴더 `/` | `open err 21`, 종료 21 |
| usbfs가 아닌 노드 `/dev/null` | `ioctl err 25`, 종료 25 |
| 보통 파일 | `ioctl err 25`, 종료 25(파일 내용은 그대로) |
| 인자 없음·두 개 | `usage`, 종료 22 |

- **차에서 확인 안 함:** 실제 동글 노드에 보냈을 때의 결과와 칩 상태, 커널 줄

## 니로 순정 커널(3.18.24)에서 `USBDEVFS_RESET`이 하는 일

kernel.org 3.18.24 소스 기준입니다(`drivers/usb/core/devio.c`, `hub.c`, `driver.c`). 차 커널은 TCC가 고친 부분이 있을 수 있습니다.

1. usbfs가 `proc_resetdevice` → `usb_reset_device`를 부릅니다.
   - 장치가 떼어졌거나 절전 상태면 -22(EINVAL)입니다. 루트 허브면 -21(EISDIR)입니다.
2. **리셋 전 드라이버 처리:** 붙어 있는 인터페이스 드라이버마다 보는 것이 다릅니다.
   - `pre_reset`·`post_reset`이 있으면 그것을 부릅니다.
   - 없으면 드라이버를 강제로 뗍니다(`usb_forced_unbind_intf`). **88x2bu는 `pre_reset`·`post_reset`이 없습니다**(`usb_intf.c`에는 `probe`·`reset_resume`만 있음).
   - 그래서 88x2bu가 붙어 있을 때 보내면, 드라이버 끊김 길(`rtw_dev_remove`)을 탑니다. 이것은 붙은 채 뽑기와 같은 쪽이고, 배포를 막는 조건입니다. **`nobind`(드라이버가 안 붙은 상태)에서만 쓰세요.**
3. **포트 리셋:** `usb_reset_and_verify_device` → `hub_port_init`이 부모 허브 포트에 리셋 신호를 보내고 장치 주소를 다시 줍니다.
   - **VBUS(전원)는 끊지 않습니다.** 칩의 USB 부분은 리셋 신호를 받습니다. Wi-Fi 부분 상태까지 풀리는지는 모릅니다(이번 시험이 가를 것).
   - 장치 번호(devnum)는 그대로입니다. 그래서 `/dev` 노드는 다시 생기지 않고, 순정도 새로 보지 않습니다.
4. **다시 확인:** 장치 설명자를 다시 읽어 바뀌었는지 봅니다. 그다음 SET_CONFIGURATION으로 구성과 대체 설정을 되살립니다.
   - 여기서 실패하거나 설명자가 바뀌었으면 `re_enumerate`로 갑니다. 이때는 논리적 끊김(`usb_logical_disconnect`)이 납니다. 장치가 새 번호로 다시 잡히고, 그 번호 자리는 가드가 막아 두었습니다.
5. **리셋 뒤 다시 붙이기:** 2번에서 떼었던 인터페이스(`needs_binding`)만 다시 붙입니다.
   - **원래 드라이버가 없던 인터페이스(`nobind`)는 저절로 다시 프로브되지 않습니다.**
   - 그래서 리셋 뒤에 프로브를 따로 일으켜야 합니다. 예: `/sys/bus/usb/drivers/rtl88x2bu/bind`에 인터페이스 이름(`4-1:1.0` 꼴)을 씁니다. 그 결과(`kp-protect: probe ret=… step=…`)로 리셋이 칩을 고쳤는지 가릅니다.
