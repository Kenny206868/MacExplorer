#ifndef MACEXPLORER_JOURNAL_H
#define MACEXPLORER_JOURNAL_H
#include <sqlite3.h>
#include <stdint.h>
#include <stddef.h>
typedef struct {
    uint64_t inode, device;
    int64_t size, modified_seconds, modified_nanoseconds;
    uint32_t mode, owner;
} me_file_identity;
int me_identity_path(const char *, me_file_identity *);
int me_identity_fd(int, me_file_identity *);
int me_identity_at(int, const char *, me_file_identity *);
int me_open_directory(const char *);
int me_open_journal_lock(const char *);
int me_close(int);
int me_rename_exclusive(int, const char *, int, const char *);
int me_sync_directory(int);
int me_sync_path(const char *);
uint32_t me_current_uid(void);
char *me_realpath(const char *);
void me_free(void *);
#endif
