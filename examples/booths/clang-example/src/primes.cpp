#include <iostream>
#include <string>
#include <vector>

// Installed with `install apt nlohmann-json3-dev` (see .booth/Boothfile).
#include <nlohmann/json.hpp>

static std::vector<int> primes_up_to(int n) {
    std::vector<int> result;
    if (n < 2) return result;
    std::vector<bool> sieve(static_cast<std::size_t>(n + 1), true);
    sieve[0] = sieve[1] = false;
    for (int i = 2; i * i <= n; ++i) {
        if (sieve[i]) {
            for (int j = i * i; j <= n; j += i) sieve[j] = false;
        }
    }
    for (int i = 2; i <= n; ++i) {
        if (sieve[i]) result.push_back(i);
    }
    return result;
}

int main(int argc, char** argv) {
    int upper = 20;
    bool as_json = false;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--json") {
            as_json = true;
        } else {
            upper = std::stoi(arg);
        }
    }

    auto primes = primes_up_to(upper);

    if (as_json) {
        // nlohmann/json (apt-installed) serializes the vector directly.
        nlohmann::json doc = primes;
        std::cout << doc.dump() << std::endl;
        return 0;
    }

    for (std::size_t i = 0; i < primes.size(); ++i) {
        std::cout << primes[i];
        if (i + 1 < primes.size()) std::cout << ", ";
    }
    std::cout << std::endl;
    return 0;
}
