# 동글 드라이버 소스 (GPL-2.0)

이 패키지의 `88x2bu.ko`(Realtek RTL88x2BU USB Wi-Fi 드라이버)를 다시 빌드하는 데 필요한 파일입니다.

| 파일 | 내용 |
|---|---|
| `SOURCE.txt` | 원본 드라이버 주소와 커밋, 패치·커널·툴체인 정보, 빌드된 `88x2bu.ko`의 해시 |
| `patches/` | 원본 드라이버에 적용한 패치 (이름 순서대로) |
| `build.sh`, `inner-build.sh` | 빌드 스크립트 |
| `config_tcc803x.txt` | 빌드에 쓴 커널 설정 |
| `COPYING` | GPL-2.0 전문 |

## 원본 드라이버

https://github.com/cilynx/rtl88x2bu (GPL-2.0), 커밋 `fc158d1f71b9e5dfcd1fccaf4d28725b65086e3b`

## 이 패키지에서 더한 패치

- `0004-rx-checksum-offload-off.patch` (4.14.0): 받는 데이터의 TCP 검사를 동글 칩에 맡기지 않고 커널이 직접 하게 함. 칩 검사 뒤에 깨진 데이터가 안드로이드 오토까지 가서 연결이 끊기던 것(`bad record mac`)을 막기 위함.

## 빌드

Docker가 필요합니다. 이 폴더에서 `./build.sh`를 실행하면 `out/88x2bu.ko`와 `out/SOURCE.txt`가 만들어집니다.

## 라이선스

원본 드라이버와 패치 모두 GPL-2.0입니다(`COPYING`).

## 출처 (GPL 고지 유지)

패치 0001~0003, 빌드 스크립트, 4.13.2까지의 `88x2bu.ko`는 jmk-wifi 1.3.4가 GPL-2.0으로 공개한 드라이버 소스입니다
(https://github.com/JongMinKim-93/jmk-gen5w-ioniq5). GPL에 따라 원래 파일과 그 안의 표기는 바꾸지 않고 그대로 둡니다.
그 제작자는 이 패키지와 관계가 없으며 이 패키지를 보증하지 않습니다.

