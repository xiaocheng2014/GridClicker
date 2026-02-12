# GridClicker for macOS

这是 GridClicker 的 macOS 原生版本，使用 Swift 编写。

## 🛠️ 编译与运行

请确保已安装 Xcode 命令行工具。

1. **构建**:
   ```bash
   chmod +x scripts/build.sh
   ./scripts/build.sh
   ```

2. **部署**:
   ```bash
   sudo cp -R ./dist/GridClicker.app /Applications/
   sudo xattr -cr /Applications/GridClicker.app
   open /Applications/GridClicker.app
   ```

## ⚙️ 权限说明

GridClicker 需要 **辅助功能 (Accessibility)** 权限来拦截键盘事件并控制鼠标。
如果无法运行，请前往 `系统设置 -> 隐私与安全性 -> 辅助功能`，删除旧的 GridClicker 并重新添加。

## 📂 目录结构
- `src/main.swift`: 核心 Swift 源码。
- `scripts/build.sh`: 自动化编译脚本。
