unit Primes;

{$mode objfpc}{$H+}

interface

uses SysUtils;

// The primes up to Limit, ascending.
function PrimesUpTo(Limit: Integer): TStringArray;

implementation

function PrimesUpTo(Limit: Integer): TStringArray;
var
  Sieve: array of Boolean;
  I, J, Count: Integer;
begin
  Result := nil;
  if Limit < 2 then Exit;
  SetLength(Sieve, Limit + 1);
  for I := 2 to Limit do Sieve[I] := True;
  I := 2;
  while I * I <= Limit do
  begin
    if Sieve[I] then
    begin
      J := I * I;
      while J <= Limit do
      begin
        Sieve[J] := False;
        Inc(J, I);
      end;
    end;
    Inc(I);
  end;
  Count := 0;
  SetLength(Result, Limit);
  for I := 2 to Limit do
    if Sieve[I] then
    begin
      Result[Count] := IntToStr(I);
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

end.
