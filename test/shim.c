/* Runs the sibling <name>.mjs with node.
 *
 * The test fixtures fake external programs by writing scripts and putting them on PATH.
 * That works on POSIX, where a shebang makes a file executable. Windows has no shebang:
 * CreateProcess refuses anything but an executable image. This launcher is compiled once
 * and copied under each faked name, so the fixture's dispatch on its own file name keeps
 * working and the tests can run on a Windows host.
 */
#include <windows.h>
#include <process.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

int wmain(int argc, wchar_t **argv) {
    wchar_t self[MAX_PATH];
    DWORD length = GetModuleFileNameW(NULL, self, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        fwprintf(stderr, L"shim: cannot read own path\n");
        return 127;
    }
    if (length > 4 && _wcsicmp(self + length - 4, L".exe") == 0) self[length - 4] = L'\0';

    wchar_t script[MAX_PATH + 8];
    if (_snwprintf(script, MAX_PATH + 8, L"%s.mjs", self) < 0) {
        fwprintf(stderr, L"shim: script name too long\n");
        return 127;
    }

    wchar_t **arguments = (wchar_t **)calloc((size_t)argc + 3, sizeof(wchar_t *));
    if (!arguments) return 127;
    int next = 0;
    arguments[next++] = L"node";
    arguments[next++] = script;
    for (int index = 1; index < argc; index++) arguments[next++] = argv[index];
    arguments[next] = NULL;

    int status = _wspawnvp(_P_WAIT, L"node", (const wchar_t *const *)arguments);
    free(arguments);
    if (status < 0) {
        fwprintf(stderr, L"shim: could not start node for %ls\n", script);
        return 127;
    }
    return status;
}
