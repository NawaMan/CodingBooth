program greet;
{$mode objfpc}{$H+}
uses
  LazFileUtils, LazUTF8;
begin
  WriteLn('lazutils ', UTF8UpperCase('ok'), ' ', ExtractFileNameOnly('/x/greet.lpr'));
end.
