/* SPDX-License-Identifier: MIT-0
 * Read-only hostapd STATUS request. Outputs only allowlisted non-secret fields.
 * No ATTACH, configuration commands, station addresses or raw reply output.
 */
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <stddef.h>
#include <unistd.h>
#include <poll.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

static int digits(const char *s) {
    size_t n = strlen(s);
    if (!n || n > 8) return 0;
    for (size_t i = 0; i < n; i++) if (s[i] < '0' || s[i] > '9') return 0;
    return 1;
}

static int state_ok(const char *s) {
    static const char *states[] = {
        "UNINITIALIZED", "DISABLED", "COUNTRY_UPDATE", "ACS", "HT_SCAN",
        "DFS", "ENABLED", "CAC", "UNKNOWN", NULL
    };
    for (int i = 0; states[i]; i++) if (!strcmp(s, states[i])) return 1;
    return 0;
}

static socklen_t address(struct sockaddr_un *out, const char *path) {
    size_t n = strlen(path);
    if (n >= sizeof(out->sun_path)) return 0;
    memset(out, 0, sizeof(*out));
    out->sun_family = AF_UNIX;
    memcpy(out->sun_path, path, n + 1);
    socklen_t len = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + n + 1);
#ifdef __APPLE__
    out->sun_len = (unsigned char)len;
#endif
    return len;
}

int main(int argc, char **argv) {
    struct sockaddr_un local, peer;
    char path[sizeof(local.sun_path)], reply[4096];
    int fd = -1, result = 1, bound = 0, state_seen = 0;
    const char *error = "usage";
    int saved_errno = 0;
    if (argc != 3) goto done;
    int n = snprintf(path, sizeof(path), "%s/g70c-%ld", argv[2], (long)getpid());
    if (n < 0 || (size_t)n >= sizeof(path)) { error = "path_too_long"; goto done; }
    socklen_t plen = address(&peer, argv[1]);
    socklen_t llen = address(&local, path);
    if (!plen || !llen) { error = "path_too_long"; goto done; }
    fd = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (fd < 0) { error = "socket"; goto system_error; }
    /* PID-specific client path inside the package's private Wi-Fi runtime dir. */
    if (bind(fd, (struct sockaddr *)&local, llen) < 0) { error = "bind"; goto system_error; }
    bound = 1;
    /* hostapd may run as wifi UID; parent directory already restricts access. */
    if (chmod(path, 0666) < 0) { error = "permissions"; goto system_error; }
    if (sendto(fd, "STATUS", 6, 0, (struct sockaddr *)&peer, plen) != 6) {
        error = "send"; goto system_error;
    }
    struct pollfd pending = {fd, POLLIN, 0};
    n = poll(&pending, 1, 500);
    if (n == 0) { error = "timeout"; goto done; }
    if (n < 0) { error = "poll"; goto system_error; }
    ssize_t received = recv(fd, reply, sizeof(reply) - 1, 0);
    if (received <= 0) { error = "receive"; goto system_error; }
    reply[received] = 0;
    char *save = NULL;
    for (char *line = strtok_r(reply, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        char *equal = strchr(line, '=');
        if (!equal) continue;
        *equal++ = 0;
        if (!strcmp(line, "state") && state_ok(equal)) {
            printf("ctrl.state=%s\n", equal); state_seen = 1;
        } else if (!strcmp(line, "freq") && digits(equal)) {
            printf("ctrl.freq=%s\n", equal);
        } else if (!strcmp(line, "channel") && digits(equal)) {
            printf("ctrl.channel=%s\n", equal);
        } else if ((!strcmp(line, "num_sta[0]") || !strcmp(line, "num_sta")) && digits(equal)) {
            printf("ctrl.stations=%s\n", equal);
        }
    }
    if (!state_seen) { error = "no_state_in_reply"; goto done; }
    result = 0;
    goto done;
system_error:
    saved_errno = errno;
done:
    if (result) {
        printf("ctrl.error=%s\n", error);
        if (saved_errno) printf("ctrl.errno=%d\n", saved_errno);
    }
    if (fd >= 0) close(fd);
    if (bound) unlink(path);
    return result;
}
