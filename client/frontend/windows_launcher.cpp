#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>

#include <cwchar>
#include <filesystem>
#include <string>
#include <system_error>
#include <vector>

namespace {
std::wstring moduleDirectory()
{
    std::vector<wchar_t> buffer(32768);
    const DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                            static_cast<DWORD>(buffer.size()));
    if (length == 0 || length >= buffer.size())
        return {};
    return std::filesystem::path(std::wstring(buffer.data(), length)).parent_path().wstring();
}

std::wstring quotedCommand(const std::wstring &path)
{
    return L"\"" + path + L"\"";
}

bool samePath(const std::wstring &left, const std::wstring &right)
{
    std::error_code error;
    const auto normalizedLeft = std::filesystem::weakly_canonical(left, error);
    if (error)
        return false;
    const auto normalizedRight = std::filesystem::weakly_canonical(right, error);
    if (error)
        return false;
    return _wcsicmp(normalizedLeft.c_str(), normalizedRight.c_str()) == 0;
}

bool processForExecutableExists(const std::wstring &expectedPath)
{
    const std::wstring expectedName = std::filesystem::path(expectedPath).filename().wstring();
    const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE)
        return false;

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    bool found = false;
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (_wcsicmp(entry.szExeFile, expectedName.c_str()) != 0)
                continue;
            const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,
                                               FALSE, entry.th32ProcessID);
            if (!process)
                continue;
            std::vector<wchar_t> path(32768);
            DWORD pathLength = static_cast<DWORD>(path.size());
            if (QueryFullProcessImageNameW(process, 0, path.data(), &pathLength)
                && samePath(std::wstring(path.data(), pathLength), expectedPath)) {
                found = true;
            }
            CloseHandle(process);
            if (found)
                break;
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return found;
}

std::wstring localLogDirectory()
{
    const DWORD size = GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
    if (size == 0)
        return {};
    std::vector<wchar_t> value(size);
    if (GetEnvironmentVariableW(L"LOCALAPPDATA", value.data(), size) == 0)
        return {};
    const auto directory = std::filesystem::path(value.data()) / L"PrismChat" / L"logs";
    std::error_code error;
    std::filesystem::create_directories(directory, error);
    return error ? std::wstring() : directory.wstring();
}

HANDLE openOutput(const std::wstring &path)
{
    SECURITY_ATTRIBUTES security{};
    security.nLength = sizeof(security);
    security.bInheritHandle = TRUE;
    const HANDLE handle = CreateFileW(path.c_str(), FILE_APPEND_DATA,
                                      FILE_SHARE_READ | FILE_SHARE_WRITE,
                                      &security, OPEN_ALWAYS,
                                      FILE_ATTRIBUTE_NORMAL, nullptr);
    if (handle != INVALID_HANDLE_VALUE)
        SetFilePointer(handle, 0, nullptr, FILE_END);
    return handle;
}

HANDLE openNull(DWORD access)
{
    SECURITY_ATTRIBUTES security{};
    security.nLength = sizeof(security);
    security.bInheritHandle = TRUE;
    return CreateFileW(L"NUL", access, FILE_SHARE_READ | FILE_SHARE_WRITE,
                       &security, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
}

bool startBackend(const std::wstring &executable,
                  const std::wstring &directory,
                  PROCESS_INFORMATION &process)
{
    const std::wstring logDirectory = localLogDirectory();
    HANDLE output = logDirectory.empty()
        ? INVALID_HANDLE_VALUE : openOutput(logDirectory + L"\\backend-out.log");
    HANDLE error = logDirectory.empty()
        ? INVALID_HANDLE_VALUE : openOutput(logDirectory + L"\\backend-error.log");
    HANDLE input = openNull(GENERIC_READ);
    if (output == INVALID_HANDLE_VALUE)
        output = openNull(GENERIC_WRITE);
    if (error == INVALID_HANDLE_VALUE)
        error = openNull(GENERIC_WRITE);

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
    startup.wShowWindow = SW_HIDE;
    startup.hStdInput = input;
    startup.hStdOutput = output;
    startup.hStdError = error;
    std::wstring command = quotedCommand(executable);
    std::vector<wchar_t> commandBuffer(command.begin(), command.end());
    commandBuffer.push_back(L'\0');
    const BOOL started = CreateProcessW(
        executable.c_str(), commandBuffer.data(), nullptr, nullptr, TRUE,
        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, nullptr,
        directory.c_str(), &startup, &process);

    if (input != INVALID_HANDLE_VALUE)
        CloseHandle(input);
    if (output != INVALID_HANDLE_VALUE)
        CloseHandle(output);
    if (error != INVALID_HANDLE_VALUE)
        CloseHandle(error);
    return started != FALSE;
}

bool startInterface(const std::wstring &executable,
                    const std::wstring &directory,
                    PROCESS_INFORMATION &process)
{
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_SHOWNORMAL;
    std::wstring command = quotedCommand(executable);
    std::vector<wchar_t> commandBuffer(command.begin(), command.end());
    commandBuffer.push_back(L'\0');
    return CreateProcessW(executable.c_str(), commandBuffer.data(),
                          nullptr, nullptr, FALSE, CREATE_UNICODE_ENVIRONMENT,
                          nullptr, directory.c_str(), &startup, &process) != FALSE;
}

int showError(const wchar_t *message)
{
    MessageBoxW(nullptr, message, L"PrismChat", MB_OK | MB_ICONERROR);
    return 1;
}
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    const std::wstring directory = moduleDirectory();
    if (directory.empty())
        return showError(L"Не удалось определить папку PrismChat.");

    const std::wstring backendPath = directory + L"\\PrismChat.exe";
    const std::wstring interfacePath = directory + L"\\PrismChatUi.exe";
    if (GetFileAttributesW(backendPath.c_str()) == INVALID_FILE_ATTRIBUTES)
        return showError(L"В папке PrismChat отсутствует PrismChat.exe.");
    if (GetFileAttributesW(interfacePath.c_str()) == INVALID_FILE_ATTRIBUTES)
        return showError(L"В папке PrismChat отсутствует PrismChatUi.exe.");

    PROCESS_INFORMATION backend{};
    const bool ownsBackend = !processForExecutableExists(backendPath);
    if (ownsBackend) {
        if (!startBackend(backendPath, directory, backend))
            return showError(L"Не удалось запустить бэкенд PrismChat.");
        Sleep(800);
    }

    PROCESS_INFORMATION interfaceProcess{};
    if (!startInterface(interfacePath, directory, interfaceProcess)) {
        if (ownsBackend) {
            TerminateProcess(backend.hProcess, 1);
            CloseHandle(backend.hThread);
            CloseHandle(backend.hProcess);
        }
        return showError(L"Не удалось запустить интерфейс PrismChat.");
    }

    CloseHandle(interfaceProcess.hThread);
    WaitForSingleObject(interfaceProcess.hProcess, INFINITE);
    DWORD exitCode = 0;
    GetExitCodeProcess(interfaceProcess.hProcess, &exitCode);
    CloseHandle(interfaceProcess.hProcess);

    if (ownsBackend) {
        if (WaitForSingleObject(backend.hProcess, 0) == WAIT_TIMEOUT) {
            TerminateProcess(backend.hProcess, 0);
            WaitForSingleObject(backend.hProcess, 2000);
        }
        CloseHandle(backend.hThread);
        CloseHandle(backend.hProcess);
    }
    return static_cast<int>(exitCode);
}
