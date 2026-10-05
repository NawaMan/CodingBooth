// A deliberately tiny program, kept as a real file rather than echoed into the
// booth from the test: `booth -- a b c` joins its arguments into one string and
// runs that through a shell, so a `bash -c "<dart source>"` loses its quoting
// and silently becomes a different command.
void main() {
  final total = [1, 2, 3, 4, 5].fold<int>(0, (a, b) => a + b);
  print('SUM=$total');
}
