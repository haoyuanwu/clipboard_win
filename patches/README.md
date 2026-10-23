# macOS 文件组功能同步

`macos-file-groups.patch` 对应 `haoyuanwu/SuperClipboard` 的提交
`63416c3ab0518c3cf2a07ed5c17a411be117b8d6`，包含：

- 列表、文件组封面和预览统一使用 `doc.on.doc.fill` 专用组图标。
- 拖入文件夹时使用原生确认窗口，可选择作为文件组、保留文件夹或取消。
- “下次不再询问”记住所选方式；设置 → 悬浮中转中可以改回每次询问。
- 展开第一层内容，保留子文件夹和空文件夹；单成员组保留组标识。
- 可选组字段向后兼容旧存档，并在中转、记事本和历史记录间保留。

在 macOS 原仓库根目录执行（将补丁路径换成实际位置）：

```sh
git apply --check /path/to/macos-file-groups.patch
git apply /path/to/macos-file-groups.patch
```

已验证补丁可应用到上述提交。当前 Windows 环境无法执行 Xcode 编译和 macOS 交互验证；
macOS 源码尚未推送，未创建或覆盖 GitHub Release。
