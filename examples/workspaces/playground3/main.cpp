#include <iostream>
#include <numeric>
#include <string>
#include <vector>

int main() {
    std::vector<std::string> greetings = {"hello", "from", "clang"};
    for (auto& s : greetings) std::cout << s << " ";
    std::cout << std::endl;

    std::vector<int> xs{1, 2, 3, 4, 5};
    int sum = std::accumulate(xs.begin(), xs.end(), 0);
    std::cout << "sum(1..5) = " << sum << std::endl;

    return 0;
}
