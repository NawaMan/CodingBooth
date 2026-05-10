CXX      ?= clang++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra

SRC := main.cpp
BIN := main

.PHONY: all clean run

all: $(BIN)

$(BIN): $(SRC)
	$(CXX) $(CXXFLAGS) $(SRC) -o $(BIN)

run: $(BIN)
	./$(BIN)

clean:
	rm -f $(BIN)
