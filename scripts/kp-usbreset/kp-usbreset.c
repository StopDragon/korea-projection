/* SPDX-License-Identifier: AGPL-3.0-or-later */
/*
 * kp-usbreset — Korea Projection 동글 시험용 도우미
 *
 * 쓰는 법: kp-usbreset <usbfs 장치 노드 경로>
 *   노드를 쓰기 전용(O_WRONLY)으로 열고 USBDEVFS_RESET ioctl을 한 번 보낸 뒤 닫는다.
 *   usbfs ioctl은 쓰기 모드로 연 파일만 받는다(devio.c, FMODE_WRITE 아니면 -EPERM).
 *   표준 출력 한 줄과 종료 코드(메인·pkg-180 약속, 11-23):
 *     성공              "ok"                 종료 0
 *     open 실패         "err <errno> open"   종료 errno(255를 넘으면 255)
 *     ioctl 실패        "err <errno> ioctl"  종료 errno(255를 넘으면 255)
 *     인자 없음·틀림    표준 출력 없음, 표준 오류에 usage  종료 2
 *   (종료 2는 open의 ENOENT와 같으므로, 둘은 표준 출력 줄로 가른다)
 *
 * 다시 시도하거나 기다리지 않는다(한 번 보내고 끝, 반복 없음).
 * 노드를 만들거나 지우지도 않는다. 노드는 부르는 쪽이 준비한다.
 *
 * libc 없이 리눅스 ARM EABI 시스템 호출(svc #0, 번호는 r7)만 쓴다.
 * 그래서 정적 링크로 작게 만들 수 있다.
 * 니로(tcc897x)와 tcc803x의 32비트 사용자 공간 모두 EABI라 같은 바이너리가 돈다.
 */

/* ARM EABI 시스템 호출 번호(arch/arm/include/uapi/asm/unistd.h) */
#define KP_SYS_EXIT   1
#define KP_SYS_WRITE  4
#define KP_SYS_OPEN   5
#define KP_SYS_CLOSE  6
#define KP_SYS_IOCTL  54

#define KP_O_WRONLY   1
/* USBDEVFS_RESET = _IO('U', 20)(include/uapi/linux/usbdevice_fs.h) */
#define KP_USBDEVFS_RESET 0x5514
#define KP_USAGE_EXIT 2

static long kp_sys3(long nr, long a, long b, long c)
{
	register long r0 __asm__("r0") = a;
	register long r1 __asm__("r1") = b;
	register long r2 __asm__("r2") = c;
	register long r7 __asm__("r7") = nr;
	__asm__ volatile("svc #0"
			 : "+r"(r0)
			 : "r"(r1), "r"(r2), "r"(r7)
			 : "memory");
	return r0;
}

static unsigned long kp_len(const char *s)
{
	unsigned long n = 0;
	while (s[n])
		n++;
	return n;
}

static void kp_outfd(long fd, const char *s)
{
	kp_sys3(KP_SYS_WRITE, fd, (long)s, (long)kp_len(s));
}

static void kp_out(const char *s)
{
	kp_outfd(1, s);
}

/* 0~4095 정수를 10진수로 쓴다(나눗셈 없이, libgcc를 부르지 않게) */
static void kp_num(unsigned int v)
{
	static const unsigned int pw[] = { 1000, 100, 10, 1 };
	char b[5];
	int i, n = 0, started = 0;

	for (i = 0; i < 4; i++) {
		char d = '0';
		while (v >= pw[i]) {
			v -= pw[i];
			d++;
		}
		if (d != '0' || started || i == 3) {
			b[n++] = d;
			started = 1;
		}
	}
	b[n] = 0;
	kp_out(b);
}

/* 커널은 실패하면 -errno(-4095~-1)를 돌려준다 */
static int kp_fail(const char *what, long r)
{
	unsigned int e = (unsigned int)(-r);

	if (e > 4095)
		e = 255;
	kp_out("err ");
	kp_num(e);
	kp_out(" ");
	kp_out(what);
	kp_out("\n");
	/* 종료 코드는 0~255라 넘으면 255로 */
	return e > 255 ? 255 : (int)e;
}

/* sp[0] = argc, sp[1..] = argv(커널이 만든 처음 스택) */
int kp_main(long *sp)
{
	long argc = sp[0];
	const char *path;
	long fd, r;

	if (argc != 2) {
		kp_outfd(2, "usage: kp-usbreset <device-node>\n");
		return KP_USAGE_EXIT;
	}
	path = (const char *)sp[2];

	fd = kp_sys3(KP_SYS_OPEN, (long)path, KP_O_WRONLY, 0);
	if (fd < 0 && fd > -4096)
		return kp_fail("open", fd);

	r = kp_sys3(KP_SYS_IOCTL, fd, KP_USBDEVFS_RESET, 0);
	kp_sys3(KP_SYS_CLOSE, fd, 0, 0);
	if (r < 0 && r > -4096)
		return kp_fail("ioctl", r);

	kp_out("ok\n");
	return 0;
}

/* 들어오는 곳: 처음 스택을 kp_main에 넘기고, 돌려받은 값으로 exit */
__asm__(
	".text\n"
	".global _start\n"
	".type _start, %function\n"
	"_start:\n"
	"	mov r0, sp\n"
	"	bl kp_main\n"
	"	mov r7, #1\n"
	"	svc #0\n");
