"""A tiny program to open in Zed — syntax highlighting, outline, and go-to-definition all work on it."""


def greet(name: str) -> str:
    return f"Hello, {name}, from Zed in a booth!"


if __name__ == "__main__":
    print(greet("world"))
