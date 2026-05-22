@echo off
:: Ensure destination exists
if not exist "G:\comfyui\ComfyUI_windows_portable\ComfyUI\output\10240x5760jpegconverted" mkdir "G:\comfyui\ComfyUI_windows_portable\ComfyUI\output\10240x5760jpegconverted"

:: Change to source directory
cd /d "G:\comfyui\ComfyUI_windows_portable\ComfyUI\output\Upload"

:: Loop and convert
for %%i in (*.png) do (
    ffmpeg -n -i "%%i" -q:v 2 "G:\comfyui\ComfyUI_windows_portable\ComfyUI\output\10240x5760jpegconverted\%%~ni.jpg"
)

:: Keep window open to see results
pause