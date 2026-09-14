#define _GNU_SOURCE
#include "CJournal.h"
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#if defined(__linux__)
#include <sys/syscall.h>
#include <linux/fs.h>
#endif
static void identity(const struct stat *s, me_file_identity *out) {
    out->inode = (uint64_t)s->st_ino; out->device = (uint64_t)s->st_dev;
    out->size = s->st_size; out->mode = s->st_mode; out->owner = s->st_uid;
#if defined(__APPLE__)
    out->modified_seconds = s->st_mtimespec.tv_sec; out->modified_nanoseconds = s->st_mtimespec.tv_nsec;
#else
    out->modified_seconds = s->st_mtim.tv_sec; out->modified_nanoseconds = s->st_mtim.tv_nsec;
#endif
}
int me_identity_path(const char *path, me_file_identity *out) { struct stat s; if (lstat(path, &s)) return -1; identity(&s, out); return 0; }
int me_identity_fd(int fd, me_file_identity *out) { struct stat s; if (fstat(fd, &s)) return -1; identity(&s, out); return 0; }
int me_identity_at(int fd, const char *name, me_file_identity *out) { struct stat s; if (fstatat(fd, name, &s, AT_SYMLINK_NOFOLLOW)) return -1; identity(&s, out); return 0; }
int me_open_directory(const char *path) { return open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC); }
int me_close(int fd) { return close(fd); }
uint32_t me_current_uid(void) { return (uint32_t)getuid(); }
int me_open_journal_lock(const char *path) {
    int fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) return -1;
    struct stat s;
    if (fstat(fd, &s) || !S_ISREG(s.st_mode) || s.st_uid != getuid() || (s.st_mode & 077) || s.st_nlink != 1) {
        close(fd); errno = EPERM; return -1;
    }
    if (flock(fd, LOCK_EX | LOCK_NB)) { int e = errno; close(fd); errno = e; return -1; }
    return fd;
}
int me_rename_exclusive(int source, const char *from, int target, const char *to) {
#if defined(__APPLE__)
    return renameatx_np(source, from, target, to, RENAME_EXCL);
#elif defined(__linux__)
    return (int)syscall(SYS_renameat2, source, from, target, to, RENAME_NOREPLACE);
#else
    errno = ENOTSUP; return -1;
#endif
}
static int retry_sync(int fd) { int rc; do { rc = fsync(fd); } while (rc && errno == EINTR); return rc; }
int me_sync_directory(int fd) {
    if (!retry_sync(fd)) return 0;
    if (errno == EINVAL || errno == ENOTSUP) return 1;
    return -1;
}
int me_sync_path(const char *path) {
    int fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return -1;
    int result = retry_sync(fd), saved = errno;
#if defined(__APPLE__)
    if (!result) {
        do { result = fcntl(fd, F_FULLFSYNC); } while (result && errno == EINTR);
        saved = errno;
        if (result && (saved == EINVAL || saved == ENOTSUP)) result = 1;
    }
#endif
    close(fd); errno = saved; return result;
}
char *me_realpath(const char *path) { return realpath(path, NULL); }
void me_free(void *pointer) { free(pointer); }
