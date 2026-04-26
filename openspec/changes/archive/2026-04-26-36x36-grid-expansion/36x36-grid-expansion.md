# Change: 36x36 Grid Expansion with Numbers

## 概要
将网格密度从 26x26 升级为 36x36，并引入数字标签 (0-9) 配合字母标签 (A-Z) 进行坐标定位。

## 变更内容
- **macOS (Swift)**: 
    - 更新 kGridRows/kGridCols 为 36。
    - 增加主键盘数字键 (0-9) 映射。
    - 优化 HintView 渲染逻辑，缩小标签尺寸。
- **Ubuntu (Python)**:
    - 更新 GRID_ROWS/GRID_COLS 为 36。
    - 更新输入校验，支持 A-Z 和 0-9 混合输入。
    - 缩小 PyQt 渲染的标签框大小。
- **文档**: 更新 README.md 和 openspec.md 为 v1.3.0。

## 结果
- 成功实现 36x36 密网格。
- 支持 AA-99 坐标定位。
- 应用已部署至 /Applications/GridClicker.app。
