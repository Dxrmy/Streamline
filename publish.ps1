Write-Host "🚀 Publishing Streamline..." -ForegroundColor Cyan

# 1. Windows 11 (x64)
Write-Host "📦 Building for Windows 11 (x64)..." -ForegroundColor Yellow
dotnet publish Streamline.App -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o ./publish/win-x64

# 2. Raspberry Pi 4 (Linux ARM64)
Write-Host "📦 Building for Raspberry Pi (linux-arm64)..." -ForegroundColor Yellow
dotnet publish Streamline.App -c Release -r linux-arm64 --self-contained true -p:PublishSingleFile=true -o ./publish/linux-arm64

Write-Host "✅ Done!" -ForegroundColor Green
Write-Host "Windows Binary: ./publish/win-x64/Streamline.App.exe"
Write-Host "Pi Binary:      ./publish/linux-arm64/Streamline.App"
