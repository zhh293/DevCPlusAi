unit AgentUITheme;

interface

uses Windows, Graphics, SysUtils;

type
  TAgentUiPalette = record
    Panel: TColor;
    Surface: TColor;
    Elevated: TColor;
    Border: TColor;
    Text: TColor;
    Muted: TColor;
    Accent: TColor;
    Success: TColor;
    Error: TColor;
    Warning: TColor;
  end;

function AgentUiFontName(const Requested: String): String;
function AgentUiCodeFontName: String;
function AgentUiIsDark(Color: TColor): Boolean;
procedure AgentBuildPalette(EditorColor, TextColor: TColor;
  out Palette: TAgentUiPalette);

implementation

function AgentUiFontName(const Requested: String): String;
begin
  Result := Requested;
  if SameText(Result, '') or SameText(Result, 'MS Sans Serif') then
    Result := 'Segoe UI';
end;

function AgentUiCodeFontName: String;
begin
  Result := 'Consolas';
end;

function AgentUiIsDark(Color: TColor): Boolean;
var Rgb: Longint;
begin
  Rgb := ColorToRGB(Color);
  Result := (GetRValue(Rgb) + GetGValue(Rgb) + GetBValue(Rgb)) < 384;
end;

procedure AgentBuildPalette(EditorColor, TextColor: TColor;
  out Palette: TAgentUiPalette);
var Bg, Fg: Longint;
begin
  Bg := ColorToRGB(EditorColor);
  Fg := ColorToRGB(TextColor);
  Palette.Panel := EditorColor;
  Palette.Surface := RGB(
    (GetRValue(Bg) + GetRValue(Fg)) div 2,
    (GetGValue(Bg) + GetGValue(Fg)) div 2,
    (GetBValue(Bg) + GetBValue(Fg)) div 2);
  Palette.Elevated := RGB(
    (2 * GetRValue(Bg) + GetRValue(Fg)) div 3,
    (2 * GetGValue(Bg) + GetGValue(Fg)) div 3,
    (2 * GetBValue(Bg) + GetBValue(Fg)) div 3);
  Palette.Border := RGB(
    (3 * GetRValue(Bg) + GetRValue(Fg)) div 4,
    (3 * GetGValue(Bg) + GetGValue(Fg)) div 4,
    (3 * GetBValue(Bg) + GetBValue(Fg)) div 4);
  Palette.Text := TextColor;
  Palette.Muted := RGB(
    (2 * GetRValue(Fg) + GetRValue(Bg)) div 3,
    (2 * GetGValue(Fg) + GetGValue(Bg)) div 3,
    (2 * GetBValue(Fg) + GetBValue(Bg)) div 3);
  if AgentUiIsDark(EditorColor) then begin
    Palette.Accent := RGB(55, 148, 255);
    Palette.Success := RGB(78, 201, 176);
    Palette.Error := RGB(244, 135, 113);
    Palette.Warning := RGB(204, 167, 0);
  end else begin
    Palette.Accent := RGB(0, 102, 204);
    Palette.Success := RGB(16, 124, 16);
    Palette.Error := RGB(164, 38, 44);
    Palette.Warning := RGB(156, 101, 0);
  end;
end;

end.
