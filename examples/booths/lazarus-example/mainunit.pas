unit MainUnit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Spin;

type
  TMainForm = class(TForm)
    LimitLabel: TLabel;
    LimitEdit: TSpinEdit;
    FindButton: TButton;
    ResultMemo: TMemo;
    CountLabel: TLabel;
    procedure FindButtonClick(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

uses Primes;

procedure TMainForm.FindButtonClick(Sender: TObject);
var
  Found: TStringArray;
  Line: String;
  I: Integer;
begin
  Found := PrimesUpTo(LimitEdit.Value);
  Line := '';
  for I := 0 to High(Found) do
  begin
    if I > 0 then Line := Line + ', ';
    Line := Line + Found[I];
  end;
  ResultMemo.Text := Line;
  CountLabel.Caption := Format('%d primes up to %d', [Length(Found), LimitEdit.Value]);
end;

end.
