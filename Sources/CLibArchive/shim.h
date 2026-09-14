#ifndef MACEXPLORER_LIBARCHIVE_SHIM_H
#define MACEXPLORER_LIBARCHIVE_SHIM_H

/* The macOS SDK exports libarchive.tbd but some Xcode installations omit the
 * libarchive development headers. Use installed public headers where available;
 * otherwise declare only the opaque public ABI used by ExplorerCore. No private
 * structures, hard-coded library paths, Homebrew libraries, or implementation
 * details are used. The system libarchive remains the linked implementation.
 * API reference: https://www.libarchive.org/man/archive_read.3.html
 * Public declarations: https://github.com/apple-oss-distributions/libarchive
 */
#if __has_include(<archive.h>) && __has_include(<archive_entry.h>)
#include <archive.h>
#include <archive_entry.h>
#else
#include <sys/types.h>
#include <stddef.h>
#include <stdint.h>
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
const char *archive_error_string(struct archive *);
const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
mode_t archive_entry_perm(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);
#ifdef __cplusplus
}
#endif
#endif
#endif
