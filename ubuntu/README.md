# GridClicker for Ubuntu

这是 GridClicker 的 Linux 移植版，专为 Ubuntu (Regolith/GNOME) 环境优化。使用 Python + PyQt6 实现。

## 🚀 快速开始

1. **直接运行**:
   ```bash
   chmod +x run.sh
   ./run.sh
   ```

2. **构建 DEB 包**:
   ```bash
   ./package.sh
   ```

## 🔧 系统集成 (Systemd)

为了实现开机自启和更稳定的运行，建议安装生成的 `.deb` 包并启用服务：

```bash
# 安装
sudo dpkg -i gridclicker_1.0.0_all.deb

# 启动并设置开机自启
systemctl --user enable --now gridclicker
```

## ⚠️ 环境要求
- **显示协议**: 必须运行在 **X11** 环境下（Wayland 暂不支持全局拦截）。
- **权限**: `pynput` 库在某些系统下可能需要访问 `/dev/input` 的权限。

## 📂 目录结构
- `main.py`: Python 源码。
- `package.sh`: DEB 打包脚本。
- `gridclicker.service`: Systemd 服务定义。
