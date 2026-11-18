// Standalone check of the Linux transport's TLS diagnostics and embedded-CA
// fallback. Built and run by tests/linux/run_tls_fallback_test.sh.
#include <cstdarg>
#include <cstdio>
#include <string>
#include <vector>

static std::vector<std::string> g_lines;

namespace Log {
void Write(const char* fmt, ...) {
    char buf[4096];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    g_lines.emplace_back(buf);
    printf("  log: %s\n", buf);
}
}  // namespace Log

#include "../../src/platform/linux/http_transport_linux.cpp"

static bool Logged(const char* needle) {
    for (const auto& l : g_lines)
        if (l.find(needle) != std::string::npos) return true;
    return false;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <expect: fallback|system|fail> <url>\n", argv[0]);
        return 2;
    }
    std::string expect = argv[1];
    std::string url = argv[2];
    auto t = CreateHttpTransport("[Test]");
    if (!t->Init()) { printf("FAIL: init\n"); return 1; }

    auto r1 = t->RequestUrl("GET", url, "", {});
    printf("request 1: status=%d tlsFailure=%d\n", r1.status, (int)r1.tlsFailure);
    size_t linesAfterFirst = g_lines.size();
    auto r2 = t->RequestUrl("GET", url, "", {});
    printf("request 2: status=%d tlsFailure=%d\n", r2.status, (int)r2.tlsFailure);

    bool retried2 = false;
    for (size_t i = linesAfterFirst; i < g_lines.size(); ++i)
        if (g_lines[i].find("retrying with embedded") != std::string::npos) retried2 = true;

    bool ok = false;
    if (expect == "fallback") {
        ok = r1.status > 0 && r2.status > 0 && Logged("retrying with embedded") &&
             Logged("embedded CA bundle works") && Logged("[TLS-DIAG]") && !retried2;
    } else if (expect == "system") {
        ok = r1.status > 0 && r2.status > 0 && !Logged("retrying with embedded") && !Logged("[TLS-DIAG]");
    } else if (expect == "fail") {
        ok = r1.status == 0 && r1.tlsFailure && Logged("embedded CA bundle also failed") &&
             Logged("verify=") && Logged("[TLS-DIAG]");
    }
    printf("%s: expect=%s\n", ok ? "PASS" : "FAIL", expect.c_str());
    return ok ? 0 : 1;
}
