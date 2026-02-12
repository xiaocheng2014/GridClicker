#!/bin/bash
set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."

# 项目配置
APP_NAME="GridClicker"
SRC_DIR="$PROJECT_ROOT/src"
DIST_DIR="$PROJECT_ROOT/dist"
BUILD_DIR="$DIST_DIR/$APP_NAME.app/Contents/MacOS"

# 确保目录存在
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR/$APP_NAME.app/Contents/Resources"

# 编译 Swift 源码
echo "正在编译 $APP_NAME..."
swiftc "$SRC_DIR/main.swift" -o "$BUILD_DIR/$APP_NAME"

# 生成 Info.plist (如果不存在)
PLIST="$DIST_DIR/$APP_NAME.app/Contents/Info.plist"
if [ ! -f "$PLIST" ]; then
    echo "正在生成 Info.plist 配置文件..."
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.user.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF
fi

echo "构建成功！应用程序位于: $DIST_DIR/$APP_NAME.app"
