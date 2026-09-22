// Independent watchdog: releases only processes this helper successfully stopped.
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/stat.h>
#include <signal.h>
#include <poll.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>

static const char *targetPath = "/System/Library/CoreServices/OSDUIHelper.app/Contents/MacOS/OSDUIHelper";
static volatile sig_atomic_t exiting = 0;
static void onSignal(int n) { (void)n; exiting = 1; }
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static int identity(pid_t pid, struct proc_bsdinfo *info) {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (pid <= 1 || proc_pidpath(pid, path, sizeof(path)) <= 0 || strcmp(path, targetPath)) return 0;
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, info, sizeof(*info)) == sizeof(*info)
        && info->pbi_uid == getuid();
}
static int same(pid_t pid, const struct proc_bsdinfo *saved) {
    struct proc_bsdinfo current;
    return identity(pid, &current) && current.pbi_start_tvsec == saved->pbi_start_tvsec
        && current.pbi_start_tvusec == saved->pbi_start_tvusec;
}
int main(void) {
    signal(SIGTERM, onSignal); signal(SIGINT, onSignal); signal(SIGHUP, onSignal);
    signal(SIGPIPE, SIG_IGN);
    // Fail closed if the expected system executable is not root-owned.
    struct stat st;
    if (lstat(targetPath, &st) || !S_ISREG(st.st_mode) || st.st_uid != 0) return 2;
    pid_t owned = 0; struct proc_bsdinfo saved = {0};
    double heartbeat = now();
    setvbuf(stdout, NULL, _IOLBF, 0);
    puts("waiting");
    while (!exiting && now() - heartbeat < 3.0) {
        struct pollfd input = { STDIN_FILENO, POLLIN | POLLHUP, 0 };
        int ready = poll(&input, 1, 40);
        if (ready < 0 && errno != EINTR) break;
        if (ready > 0) {
            char bytes[64]; ssize_t count = read(STDIN_FILENO, bytes, sizeof(bytes));
            if (count <= 0) break;
            heartbeat = now();
        }
        if (exiting) break;
        if (owned) {
            if (same(owned, &saved)) {
                struct proc_bsdinfo current;
                if (identity(owned, &current) && current.pbi_status != 4) {
                    if (kill(owned, SIGSTOP) != 0) { puts("failed"); break; }
                    puts("active");
                }
                continue;
            }
            owned = 0; puts("waiting");
        }
        int size = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
        if (size <= 0) continue;
        pid_t *pids = calloc(1, (size_t)size + 4096);
        if (!pids) break;
        int count = proc_listpids(PROC_ALL_PIDS, 0, pids, size + 4096) / sizeof(pid_t);
        for (int i = 0; i < count; ++i) {
            struct proc_bsdinfo info;
            if (!identity(pids[i], &info)) continue;
            // SSTOP = 4. Never take ownership of a process paused by another app.
            if (info.pbi_status == 4) { puts("conflict"); exiting = 1; break; }
            if (kill(pids[i], SIGSTOP) == 0) {
                owned = pids[i]; saved = info; puts("active");
            } else { puts("failed"); exiting = 1; }
            break;
        }
        free(pids);
    }
    if (owned && same(owned, &saved)) {
        if (kill(owned, SIGCONT) != 0) { perror("restore"); return 3; }
        puts("restored");
    }
    return 0;
}
