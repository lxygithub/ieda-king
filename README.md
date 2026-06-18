# Share Timeline

接收来自其他应用的分享文件，按时间线以天为单位展示。

## 功能

- 接收分享的图片、文字、文档、链接等
- 按天分组的时间线视图
- 点击查看文件详情（图片支持缩放预览）
- 用其他应用打开文件
- 支持 Android 和 iOS 分享入口
- 数据持久化（重启不丢失）

## 使用

```bash
flutter pub get
flutter run
```

### 从其他应用分享到此应用

- **Android**: 分享菜单中选「时间线」
- **iOS**: 分享菜单中选「时间线」
- 分享的文字/图片/文件会自动出现在时间线中

## 技术栈

- Flutter + Material 3
- Provider 状态管理
- `receive_sharing_intent` 接收分享
- `photo_view` 图片缩放浏览
- `open_filex` 外部打开文件
- `shared_preferences` 持久化

## 项目结构

```
lib/
├── main.dart                 # 入口 + 分享监听
├── models/
│   └── shared_file.dart      # 数据模型 (File, FileType)
├── providers/
│   └── timeline_provider.dart # 状态管理 + 持久化
├── screens/
│   ├── timeline_screen.dart  # 时间线主页
│   └── detail_screen.dart    # 文件详情页
├── utils/
│   └── file_handler.dart     # 文件处理 (复制/分类/提取预览)
└── widgets/
    ├── day_group.dart         # 日期分组组件
    └── file_card.dart         # 文件卡片组件
```
