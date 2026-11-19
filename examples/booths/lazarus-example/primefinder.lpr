program PrimeFinder;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, SysUtils, MainUnit, Primes;

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);

  // `primefinder --self-test N`: load the real form, press its button, print what
  // it shows, and quit — a check that runs without anyone clicking.
  if ParamStr(1) = '--self-test' then
  begin
    MainForm.LimitEdit.Value := StrToIntDef(ParamStr(2), 20);
    MainForm.FindButton.Click;
    WriteLn(MainForm.Caption, ': ', MainForm.ResultMemo.Text);
    WriteLn(MainForm.CountLabel.Caption);
    Exit;
  end;

  Application.Run;
end.
