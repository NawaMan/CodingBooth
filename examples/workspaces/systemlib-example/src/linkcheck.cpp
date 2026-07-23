// linkcheck — read a list of URLs, check each one with libcurl, and record the
// result in a SQLite database. One row per check: url, checked_at (UTC), status.
//
// A URL is DEAD when libcurl cannot complete the request (DNS / connect / timeout)
// or when the final HTTP status is >= 400. Otherwise it is ALIVE.
//
// The whole point of this example is that it links two real *system* libraries
// installed with apt — libcurl (HTTPS) and SQLite (storage) — not header-only ones.

#include <curl/curl.h>
#include <sqlite3.h>

#include <cstdio>
#include <ctime>
#include <fstream>
#include <string>
#include <vector>

namespace {

// libcurl hands us the response body in chunks; we only want the status, so throw
// it away — but we must still consume it (return the byte count) or curl errors.
size_t discard_body(char*, size_t size, size_t nmemb, void*) {
    return size * nmemb;
}

// Current time as a UTC ISO-8601 string, e.g. 2026-07-22T18:30:05Z.
// std::gmtime (not gmtime_r) so this compiles under strict -std=c++17; the program
// is single-threaded, so the shared static std::tm it returns is fine.
std::string utc_now() {
    const std::time_t t = std::time(nullptr);
    const std::tm* tm = std::gmtime(&t);
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", tm);
    return buf;
}

// Trim surrounding whitespace.
std::string trim(const std::string& s) {
    const char* ws = " \t\r\n";
    const auto a = s.find_first_not_of(ws);
    if (a == std::string::npos) return "";
    const auto b = s.find_last_not_of(ws);
    return s.substr(a, b - a + 1);
}

struct Result {
    bool ok = false;      // request completed AND HTTP status < 400
    std::string status;   // "200", "DEAD: HTTP 404", or "DEAD: <curl error>"
};

Result check_url(CURL* curl, const std::string& url) {
    Result r;
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_IPRESOLVE, CURL_IPRESOLVE_V4);  // containers often lack IPv6
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);            // follow redirects
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, discard_body);   // ignore the body
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 5L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "systemlib-linkcheck/1.0");

    const CURLcode rc = curl_easy_perform(curl);
    if (rc != CURLE_OK) {
        r.ok = false;
        r.status = std::string("DEAD: ") + curl_easy_strerror(rc);
        return r;
    }

    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
    r.ok = (http_code > 0 && http_code < 400);
    r.status = r.ok ? std::to_string(http_code)
                    : "DEAD: HTTP " + std::to_string(http_code);
    return r;
}

}  // namespace

int main(int argc, char** argv) {
    const std::string url_file = (argc > 1) ? argv[1] : "urls.txt";
    const std::string db_path  = (argc > 2) ? argv[2] : "linkcheck.db";

    // --- Read the URL list (skip blank lines and '#' comments) ---
    std::ifstream in(url_file);
    if (!in) {
        std::fprintf(stderr, "error: cannot open URL file: %s\n", url_file.c_str());
        return 1;
    }
    std::vector<std::string> urls;
    std::string line;
    while (std::getline(in, line)) {
        const std::string u = trim(line);
        if (u.empty() || u[0] == '#') continue;
        urls.push_back(u);
    }
    if (urls.empty()) {
        std::fprintf(stderr, "error: no URLs found in %s\n", url_file.c_str());
        return 1;
    }

    // --- Open SQLite and make sure the table exists ---
    sqlite3* db = nullptr;
    if (sqlite3_open(db_path.c_str(), &db) != SQLITE_OK) {
        std::fprintf(stderr, "error: cannot open database: %s\n", sqlite3_errmsg(db));
        return 1;
    }
    const char* ddl =
        "CREATE TABLE IF NOT EXISTS checks ("
        "  id         INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  url        TEXT NOT NULL,"
        "  checked_at TEXT NOT NULL,"
        "  status     TEXT NOT NULL"
        ");";
    char* errmsg = nullptr;
    if (sqlite3_exec(db, ddl, nullptr, nullptr, &errmsg) != SQLITE_OK) {
        std::fprintf(stderr, "error: create table: %s\n", errmsg);
        sqlite3_free(errmsg);
        sqlite3_close(db);
        return 1;
    }

    sqlite3_stmt* ins = nullptr;
    sqlite3_prepare_v2(db,
        "INSERT INTO checks (url, checked_at, status) VALUES (?, ?, ?);",
        -1, &ins, nullptr);

    // --- Check every URL with libcurl, recording each result ---
    curl_global_init(CURL_GLOBAL_DEFAULT);
    CURL* curl = curl_easy_init();
    if (!curl) {
        std::fprintf(stderr, "error: curl init failed\n");
        sqlite3_close(db);
        return 1;
    }

    const std::string now = utc_now();
    int alive = 0, dead = 0;

    std::printf("Checking %zu URLs...\n\n", urls.size());
    std::printf("%-48s %-6s %s\n", "URL", "RESULT", "STATUS");
    std::printf("%-48s %-6s %s\n", "------------------------------------------------",
                "------", "------");

    for (const auto& url : urls) {
        const Result r = check_url(curl, url);
        if (r.ok) ++alive; else ++dead;
        std::printf("%-48.48s %-6s %s\n", url.c_str(), r.ok ? "ALIVE" : "DEAD",
                    r.status.c_str());

        sqlite3_bind_text(ins, 1, url.c_str(),      -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(ins, 2, now.c_str(),      -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(ins, 3, r.status.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_step(ins);
        sqlite3_reset(ins);
    }

    curl_easy_cleanup(curl);
    curl_global_cleanup();
    sqlite3_finalize(ins);

    std::printf("\nSummary: %d alive, %d dead. Recorded %zu rows to %s\n",
                alive, dead, urls.size(), db_path.c_str());

    // --- Read the rows back out (proves the SQLite round-trip) ---
    std::printf("\nJust recorded (read back from SQLite):\n");
    sqlite3_stmt* sel = nullptr;
    sqlite3_prepare_v2(db,
        "SELECT url, checked_at, status FROM checks ORDER BY id DESC LIMIT ?;",
        -1, &sel, nullptr);
    sqlite3_bind_int(sel, 1, static_cast<int>(urls.size()));
    while (sqlite3_step(sel) == SQLITE_ROW) {
        std::printf("  %-42.42s  %s  %s\n",
                    reinterpret_cast<const char*>(sqlite3_column_text(sel, 0)),
                    reinterpret_cast<const char*>(sqlite3_column_text(sel, 1)),
                    reinterpret_cast<const char*>(sqlite3_column_text(sel, 2)));
    }
    sqlite3_finalize(sel);
    sqlite3_close(db);
    return 0;
}
