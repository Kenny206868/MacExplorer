#ifndef MACEXPLORER_LIBARCHIVE_SHIM_H
#define MACEXPLORER_LIBARCHIVE_SHIM_H
/* Public opaque libarchive ABI when the Xcode SDK omits development headers. */
#if __has_include(<archive.h>) && __has_include(<archive_entry.h>)
#include <archive.h>
#include <archive_entry.h>
#else
#include <sys/types.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>
#ifdef __cplusplus
extern "C" {
#endif
struct archive;
struct archive_entry;
#define ARCHIVE_EOF 1
#define ARCHIVE_OK 0
#define ARCHIVE_RETRY (-10)
#define ARCHIVE_WARN (-20)
#define ARCHIVE_FAILED (-25)
#define ARCHIVE_FATAL (-30)
struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_all(struct archive *);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_data_skip(struct archive *);
int archive_read_free(struct archive *);
int archive_read_add_passphrase(struct archive *, const char *);
int archive_read_open_fd(struct archive *, int, size_t);
int archive_format(struct archive *);
int archive_filter_count(struct archive *);
int archive_filter_code(struct archive *, int);
#define ARCHIVE_FORMAT_BASE_MASK 0xff0000
#define ARCHIVE_FORMAT_ZIP 0x50000
#define ARCHIVE_FORMAT_TAR 0x30000
#define ARCHIVE_FILTER_NONE 0
#define ARCHIVE_FILTER_GZIP 1
#define ARCHIVE_FILTER_BZIP2 2
#define ARCHIVE_FILTER_XZ 6
struct archive *archive_write_new(void);
int archive_write_set_format_zip(struct archive *);
int archive_write_set_format_pax_restricted(struct archive *);
int archive_write_add_filter_gzip(struct archive *);
int archive_write_add_filter_bzip2(struct archive *);
int archive_write_add_filter_xz(struct archive *);
int archive_write_open_fd(struct archive *, int);
int archive_write_header(struct archive *, struct archive_entry *);
ssize_t archive_write_data(struct archive *, const void *, size_t);
int archive_write_finish_entry(struct archive *);
int archive_write_close(struct archive *);
int archive_write_free(struct archive *);
struct archive_entry *archive_entry_new(void);
struct archive_entry *archive_entry_clone(struct archive_entry *);
void archive_entry_free(struct archive_entry *);
void archive_entry_set_pathname(struct archive_entry *, const char *);
void archive_entry_set_filetype(struct archive_entry *, unsigned int);
void archive_entry_set_perm(struct archive_entry *, mode_t);
void archive_entry_set_size(struct archive_entry *, int64_t);
void archive_entry_set_mtime(struct archive_entry *, time_t, long);
const char *archive_format_name(struct archive *);
const char *archive_error_string(struct archive *);
const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
mode_t archive_entry_perm(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);
int archive_entry_mtime_is_set(struct archive_entry *);
time_t archive_entry_mtime(struct archive_entry *);
long archive_entry_mtime_nsec(struct archive_entry *);
#ifdef __cplusplus
}
#endif
#endif
#endif
