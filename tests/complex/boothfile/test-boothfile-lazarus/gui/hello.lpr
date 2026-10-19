program hello;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, StdCtrls;
var
  F: TForm;
  B: TButton;
begin
  Application.Initialize;
  F := TForm.CreateNew(nil);
  B := TButton.Create(F);
  B.Caption := 'Hello';
  B.Parent := F;
  WriteLn('LCL form built: ', F.ClassName, ' with ', B.Caption);
  F.Free;
end.
