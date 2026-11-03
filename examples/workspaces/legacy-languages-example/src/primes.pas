{ Primes up to 30, in Pascal. }
program Primes;
var
  n, d: integer;
  isPrime: boolean;
begin
  write('Pascal:');
  for n := 2 to 30 do
  begin
    isPrime := true;
    d := 2;
    while d * d <= n do
    begin
      if n mod d = 0 then isPrime := false;
      d := d + 1;
    end;
    if isPrime then write(' ', n);
  end;
  writeln;
end.
