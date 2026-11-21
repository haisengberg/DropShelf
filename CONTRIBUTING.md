# Contributing to DropShelf

感谢你愿意为 DropShelf 做出贡献！无论是提 Bug、改进交互体验，还是贡献新功能，都非常欢迎。

## 本地开发

只需要 macOS 13+ 和系统自带的命令行工具（`xcode-select --install`）：

```bash
# 仅编译当前芯片架构，快速验证改动
./build.sh --arch arm64

# 运行编译出的应用
open dist/DropShelf.app
```

验证发布包（Apple Silicon + Intel 通用包）：

```bash
./build.sh --release
```

## 提交建议

- **保持轻量与零依赖**：优先使用系统原生 AppKit / Foundation / Quartz / Carbon 框架，不引入重型第三方依赖。
- **不申请多余权限**：尽量避免引入需要「辅助功能」或「屏幕录制」权限的功能；若确有必要，请做成可选开关。
- **代码风格**：保持 Swift 文件结构清晰、职责单一；提交 PR 前请确认 `./build.sh` 编译无报错且 `codesign --verify` 通过。
- **Commit 信息**：简明描述改动内容即可（如 `feat: add keyboard shortcut customization`、`fix: adjust shake threshold`）。
