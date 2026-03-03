# 简谱译 JianPuYi

AI 驱动的音乐简谱识别应用，拍照即可识别简谱并播放。

## 架构

| 模块 | 技术 | 说明 |
|------|------|------|
| 前端 | Flutter (Dart) | Android / iOS 跨平台 |
| 后端 | Python (FastAPI) | AI 图像识别服务 |
| 数据库 | SQLite | 本地轻量存储 |

## 项目结构

```
JianPuYi-OpenSource/
├── app/                  # Flutter 前端
│   ├── lib/main.dart
│   └── pubspec.yaml
├── server/               # Python 后端
│   ├── main.py
│   ├── ocr_engine.py
│   └── requirements.txt
├── database/
│   └── schema.sql
└── README.md
```

## 快速开始

### 下载 APK

访问 [Actions](../../actions) 页面，点击最新构建，下载 `jianpuyi-apk`。

### 本地开发

```bash
cd app
flutter pub get
flutter run
```

### 启动后端

```bash
cd server
pip install -r requirements.txt
python main.py
```

## 功能

- 拍照识别简谱
- 音符序列显示与播放
- 历史记录管理
- 收藏功能
- 转调功能（开发中）

## License

MIT
