import sys
import platform
import datetime

def main():
    print("Python Environment Check")
    print("-" * 30)
    print("Python version:", sys.version)
    print("Platform:", platform.system(), platform.release())
    print("Current time:", datetime.datetime.now())
    print("Test math: 2 + 2 =", 2 + 2)
    print("All systems operational!")

if __name__ == "__main__":
    main()
