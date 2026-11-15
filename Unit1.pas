unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtDlgs, ExtCtrls,
  StdCtrls, LCLIntf, LCLType, Math;

type

  { TForm1 }

  TForm1 = class(TForm)
    ButtonLoad: TButton;
    ButtonTransform: TButton;
    ButtonSaveNearest: TButton;
    ButtonSaveBilinear: TButton;
    ButtonSaveBicubic: TButton;
    EditAngle: TEdit;
    EditScale: TEdit;
    EditSkew: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Image1: TImage;
    Image2: TImage;
    Image3: TImage;
    Image4: TImage;
    OpenPictureDialog1: TOpenPictureDialog;
    SavePictureDialog1: TSavePictureDialog;
    procedure ButtonLoadClick(Sender: TObject);
    procedure ButtonTransformClick(Sender: TObject);
    procedure ButtonSaveNearestClick(Sender: TObject);
    procedure ButtonSaveBilinearClick(Sender: TObject);
    procedure ButtonSaveBicubicClick(Sender: TObject);
  private
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

function ConvertTo24Bit(aValue: TBitmap): TBitmap;
begin
  Result := TBitmap.Create;
  if aValue.PixelFormat <> pf24bit then
  begin
    Result.PixelFormat := pf24bit;
    Result.SetSize(aValue.Width, aValue.Height);
    Result.Canvas.Draw(0, 0, aValue);
  end
  else
    Result.Assign(aValue);
end;

// считывание пикселя с "продлением" граничных пикселей наружу (clamp),
// чтобы не выйти за границы массива при интерполяции у краёв изображения
function GetPixelClamped(bmp: TBitmap; x, y, w, h: Integer): TColor;
begin
  if x < 0 then x := 0;
  if x >= w then x := w - 1;
  if y < 0 then y := 0;
  if y >= h then y := h - 1;
  Result := bmp.Canvas.Pixels[x, y];
end;

function GetChannelClamped(bmp: TBitmap; x, y, w, h, channel: Integer): byte;
var
  c: TColor;
begin
  c := GetPixelClamped(bmp, x, y, w, h);
  case channel of
    0: Result := GetRValue(c);
    1: Result := GetGValue(c);
  else
    Result := GetBValue(c);
  end;
end;

function ClampByte(v: real): byte;
begin
  if v < 0 then
    Result := 0
  else if v > 255 then
    Result := 255
  else
    Result := round(v);
end;

// ---------------------------------------------------------------------
// 1. Интерполяция по ближайшему соседу: g(x,y) = f(round(x), round(y))
// ---------------------------------------------------------------------
function SampleNearest(bmp: TBitmap; x, y: real; w, h: Integer): TColor;
begin
  Result := GetPixelClamped(bmp, round(x), round(y), w, h);
end;

// ---------------------------------------------------------------------
// 2. Билинейная интерполяция по 4 ближайшим пикселям (l,k), (l+1,k),
//    (l,k+1), (l+1,k+1), где l=floor(x), k=floor(y), a=x-l, b=y-k
// ---------------------------------------------------------------------
function SampleBilinear(bmp: TBitmap; x, y: real; w, h: Integer): TColor;
var
  l, k, ch: Integer;
  a, b, v: real;
  res: array[0..2] of byte;
begin
  l := floor(x);
  k := floor(y);
  a := x - l;
  b := y - k;
  for ch := 0 to 2 do
  begin
    v := (1 - a) * (1 - b) * GetChannelClamped(bmp, l,     k,     w, h, ch)
       + a       * (1 - b) * GetChannelClamped(bmp, l + 1, k,     w, h, ch)
       + b       * (1 - a) * GetChannelClamped(bmp, l,     k + 1, w, h, ch)
       + a * b             * GetChannelClamped(bmp, l + 1, k + 1, w, h, ch);
    res[ch] := ClampByte(v);
  end;
  Result := RGB(res[0], res[1], res[2]);
end;

// ---------------------------------------------------------------------
// 3. Бикубическая интерполяция по окну 4x4 (16 пикселей) со смещениями
//    di,dj = -1,0,1,2 от точки (l,k) - формула из методички (полином
//    шестой степени). Веса представлены в разделимом виде: вклад точки
//    со смещением (di,dj) равен wa[di]*wb[dj], где wa/wb - кубические
//    весовые функции Лагранжа по соответствующей оси; это тот же
//    16-точечный полином, записанный компактнее, чем через c1..c16.
//    l=floor(x), k=floor(y), a=x-l, b=y-k.
// ---------------------------------------------------------------------
function SampleBicubic(bmp: TBitmap; x, y: real; w, h: Integer): TColor;
var
  l, k, ch, di, dj: Integer;
  a, b, v: real;
  wa, wb: array[-1..2] of real;
  res: array[0..2] of byte;
begin
  l := floor(x);
  k := floor(y);
  a := x - l;
  b := y - k;

  wa[-1] := -a * (a - 1) * (a - 2) / 6;
  wa[0]  := (a + 1) * (a - 1) * (a - 2) / 2;
  wa[1]  := -a * (a + 1) * (a - 2) / 2;
  wa[2]  := a * (a + 1) * (a - 1) / 6;

  wb[-1] := -b * (b - 1) * (b - 2) / 6;
  wb[0]  := (b + 1) * (b - 1) * (b - 2) / 2;
  wb[1]  := -b * (b + 1) * (b - 2) / 2;
  wb[2]  := b * (b + 1) * (b - 1) / 6;

  for ch := 0 to 2 do
  begin
    v := 0;
    for di := -1 to 2 do
      for dj := -1 to 2 do
        v := v + wa[di] * wb[dj] * GetChannelClamped(bmp, l + di, k + dj, w, h, ch);
    res[ch] := ClampByte(v);
  end;
  Result := RGB(res[0], res[1], res[2]);
end;

// ---------------------------------------------------------------------
// Применяет к изображению аффинное преобразование (масштабирование k,
// поворот на угол phi, скос shx по оси X), методом обратного отображения:
// для каждого пикселя результата ищем координаты в источнике и берём
// оттуда цвет выбранным методом интерполяции (method: 0-ближайший сосед,
// 1-билинейная, 2-бикубическая).
// ---------------------------------------------------------------------
procedure ApplyAffine(src, dst: TBitmap; w, h: Integer;
  phi, k, shx: real; method: Integer);
var
  i, j: Integer;
  cx, cy, x, y, x1, y1, x2, y2, xs, ys: real;
  col: TColor;
begin
  cx := w / 2;
  cy := h / 2;
  dst.PixelFormat := pf24bit;
  dst.SetSize(w, h);
  dst.Canvas.Brush.Color := RGB(255, 255, 255);
  dst.Canvas.FillRect(Rect(0, 0, w, h));

  for i := 0 to w - 1 do
    for j := 0 to h - 1 do
    begin
      x := i - cx;
      y := j - cy;
      // 1) отменяем поворот
      x1 := x * cos(-phi) - y * sin(-phi);
      y1 := x * sin(-phi) + y * cos(-phi);
      // 2) отменяем скос по X: x' = x + shx*y  =>  x = x' - shx*y
      x2 := x1 - shx * y1;
      y2 := y1;
      // 3) отменяем масштаб
      xs := x2 / k + cx;
      ys := y2 / k + cy;

      case method of
        0: col := SampleNearest(src, xs, ys, w, h);
        1: col := SampleBilinear(src, xs, ys, w, h);
      else
        col := SampleBicubic(src, xs, ys, w, h);
      end;
      dst.Canvas.Pixels[i, j] := col;
    end;
end;

procedure TForm1.ButtonLoadClick(Sender: TObject);
var
  tmp: TBitmap;
begin
  if OpenPictureDialog1.Execute then
  begin
    Image1.Picture.LoadFromFile(OpenPictureDialog1.FileName);
    if Image1.Picture.Bitmap.PixelFormat <> pf24bit then
    begin
      tmp := ConvertTo24Bit(Image1.Picture.Bitmap);
      Image1.Picture.Bitmap.Assign(tmp);
      tmp.Free;
    end;
    Image1.Stretch := True;
    Image1.Proportional := True;
  end;
end;

procedure TForm1.ButtonTransformClick(Sender: TObject);
var
  phi, k, shx: real;
  w, h: Integer;
  fs: TFormatSettings;
begin
  if Image1.Picture.Graphic = nil then
  begin
    ShowMessage('Сначала загрузите изображение!');
    Exit;
  end;

  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';

  if not TryStrToFloat(Trim(EditAngle.Text), phi, fs) then
    phi := 0;
  phi := phi * pi / 180; // градусы -> радианы

  if not TryStrToFloat(Trim(EditScale.Text), k, fs) then
    k := 1;
  if k = 0 then
    k := 1;

  if not TryStrToFloat(Trim(EditSkew.Text), shx, fs) then
    shx := 0;

  w := Image1.Picture.Bitmap.Width;
  h := Image1.Picture.Bitmap.Height;

  ApplyAffine(Image1.Picture.Bitmap, Image2.Picture.Bitmap, w, h, phi, k, shx, 0);
  ApplyAffine(Image1.Picture.Bitmap, Image3.Picture.Bitmap, w, h, phi, k, shx, 1);
  ApplyAffine(Image1.Picture.Bitmap, Image4.Picture.Bitmap, w, h, phi, k, shx, 2);

  Image2.Stretch := True; Image2.Proportional := True; Image2.Invalidate;
  Image3.Stretch := True; Image3.Proportional := True; Image3.Invalidate;
  Image4.Stretch := True; Image4.Proportional := True; Image4.Invalidate;
end;

procedure TForm1.ButtonSaveNearestClick(Sender: TObject);
begin
  if SavePictureDialog1.Execute then
    Image2.Picture.SaveToFile(SavePictureDialog1.FileName);
end;

procedure TForm1.ButtonSaveBilinearClick(Sender: TObject);
begin
  if SavePictureDialog1.Execute then
    Image3.Picture.SaveToFile(SavePictureDialog1.FileName);
end;

procedure TForm1.ButtonSaveBicubicClick(Sender: TObject);
begin
  if SavePictureDialog1.Execute then
    Image4.Picture.SaveToFile(SavePictureDialog1.FileName);
end;

end.
