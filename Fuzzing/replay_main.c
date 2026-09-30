/*
    replay_main.c - runs fuzz inputs through the harness without libFuzzer.

    Apple clang ships no libFuzzer runtime, so on a stock Mac the harness is
    built with this driver instead. It feeds each file (or each file in each
    directory) named on the command line to LLVMFuzzerTestOneInput once.
    Build with ASan and UBSan so a memory error or undefined behavior aborts.

    Usage: replay-bridge [-timeout=SECONDS] PATH...

    -timeout matches libFuzzer's flag: an input that runs longer than this
    many seconds (default 25) is reported as a hang and aborts the run.
*/

/* scandir, alphasort, alarm, and stat are POSIX.1-2008; glibc hides them under -std=c11 without this. */
#define _POSIX_C_SOURCE 200809L

#include <dirent.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

static const char *CurrentPath = "";
static unsigned TimeoutSeconds = 25;
static unsigned InputCount = 0;

static void OnTimeout(int signal_number)
{
    (void)signal_number;
    /* Only async-signal-safe calls here. */
    static const char message[] = "replay-bridge: timeout (hang) on input: ";
    write(STDERR_FILENO, message, sizeof(message) - 1);
    write(STDERR_FILENO, CurrentPath, strlen(CurrentPath));
    write(STDERR_FILENO, "\n", 1);
    abort();
}

static int RunFile(const char *path)
{
    FILE *file = fopen(path, "rb");
    uint8_t *buffer;
    long length;
    size_t count;

    if (file == NULL || fseek(file, 0, SEEK_END) != 0 || (length = ftell(file)) < 0 || fseek(file, 0, SEEK_SET) != 0)
    {
        fprintf(stderr, "replay-bridge: cannot read %s\n", path);
        if (file != NULL)
            fclose(file);
        return 1;
    }

    /* malloc(0) may return NULL, so always allocate at least one byte. */
    buffer = malloc((size_t)length + 1);
    if (buffer == NULL)
    {
        fclose(file);
        fprintf(stderr, "replay-bridge: out of memory reading %s\n", path);
        return 1;
    }
    count = fread(buffer, 1, (size_t)length, file);
    fclose(file);

    CurrentPath = path;
    alarm(TimeoutSeconds);
    LLVMFuzzerTestOneInput(buffer, count);
    alarm(0);
    free(buffer);
    ++InputCount;
    return 0;
}

/* Runs a directory's regular files in name order, so repeated runs match. */
static int RunDirectory(const char *path)
{
    struct dirent **entries;
    int count = scandir(path, &entries, NULL, alphasort);
    int failures = 0;

    if (count < 0)
    {
        fprintf(stderr, "replay-bridge: cannot open %s\n", path);
        return 1;
    }

    for (int i = 0; i < count; ++i)
    {
        char file[4096];
        struct stat info;

        if (entries[i]->d_name[0] != '.'
            && snprintf(file, sizeof(file), "%s/%s", path, entries[i]->d_name) < (int)sizeof(file)
            && stat(file, &info) == 0 && S_ISREG(info.st_mode))
            failures |= RunFile(file);
        free(entries[i]);
    }
    free(entries);
    return failures;
}

int main(int argc, char **argv)
{
    int failures = 0;
    int paths = 0;

    signal(SIGALRM, OnTimeout);

    for (int i = 1; i < argc; ++i)
    {
        struct stat info;

        if (strncmp(argv[i], "-timeout=", 9) == 0)
        {
            TimeoutSeconds = (unsigned)strtoul(argv[i] + 9, NULL, 10);
            continue;
        }

        ++paths;
        if (stat(argv[i], &info) != 0)
        {
            fprintf(stderr, "replay-bridge: no such file or directory: %s\n", argv[i]);
            failures = 1;
        }
        else if (S_ISDIR(info.st_mode))
            failures |= RunDirectory(argv[i]);
        else
            failures |= RunFile(argv[i]);
    }

    if (paths == 0)
    {
        fprintf(stderr, "usage: %s [-timeout=SECONDS] PATH...\n", argv[0]);
        return 2;
    }

    printf("replay-bridge: ran %u input(s)\n", InputCount);
    return failures;
}
