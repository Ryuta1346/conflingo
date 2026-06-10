# ConfLingo

[English](README.md) | [日本語](README.ja.md) | **简体中文** | [한국어](README.ko.md) | [Español](README.es.md)

一款个人用 macOS 应用：在会议现场使用 Apple/macOS 内置 API 对 MacBook 麦克风音频进行实时转写，并以翻译字幕的形式显示。识别语言与目标语言可从操作系统支持的语言中自由选择（默认：英语 → 日语）。

- 语音转写：`Speech.framework`（macOS 26 的 `SpeechAnalyzer` / `SpeechTranscriber`，设备端处理）
- 翻译：`Translation.framework`（`TranslationSession`，设备端处理）
- UI：SwiftUI 双窗格布局（原文转写 / 译文）

📖 **详细使用方法（专业术语注册、现场技巧、故障排查）请参阅 [docs/usage.md](docs/usage.md)（英文，另有[日语版](docs/usage.ja.md)）。**

## 运行要求

- macOS 26.0 或更高版本 / Apple Silicon
- Xcode 26 或更高版本（用于构建）
- 仅首次启动时：需要网络连接以下载语音识别模型和翻译模型

## 构建与启动

```sh
# 构建
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug build

# 启动（打开 DerivedData 下生成的 .app）
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

运行测试：

```sh
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo -destination 'platform=macOS'
```

## 权限授予

1. **麦克风**：首次按下 Start 时会显示麦克风使用权限对话框。不授权则无法转写
2. **语音识别模型**：首次启动时若识别模型未安装，会自动开始下载（带进度显示）
3. **翻译模型**：若翻译模型未安装，会显示操作系统标准的下载确认对话框

如需重置麦克风权限：

```sh
tccutil reset Microphone com.gavrri.conflingo
```

如果不小心拒绝了授权，请在「系统设置 > 隐私与安全性 > 麦克风」中启用 ConfLingo。

## 使用方法

1. 启动应用（首次启动会进行模型检查与下载）
2. 通过**语言选择器**选择识别语言和目标语言（仅停止状态下可更改。更改后会自动进行可用性检查和模型下载）
3. 如有需要，输入会话名称
4. 在**专业术语栏**中以逗号分隔输入活动专属术语（演讲者姓名、产品名、技术术语）。按 Start 时这些术语会作为语音识别的 contextual strings 注册，从而提高专有名词的识别准确率（默认预置了 Code with Claude Tokyo 的术语。修改将在下次 Start 时生效）
5. 按 **Start**（⌘R）开始转写
   - 识别窗格：识别中的句子（partial）以浅色斜体显示，确定后追加到历史记录
   - 翻译窗格：仅翻译已确定的原文，按确定句逐条追加到历史记录
6. 按 **Stop**（⌘R）停止。再次按 Start 会继续追加到历史记录
7. **Save Markdown** 将整个会话保存为 Markdown
8. **A− / A＋**（⌘− / ⌘+）调整字号，勾选「置顶」可让窗口始终显示在最前面
9. **Clear** 清除历史记录（仅停止状态下可用）

## 分发

### 方式A：共享源码（推荐给拥有 Xcode 的开发者）

分享仓库 URL，让对方执行以下命令。不会出现 Gatekeeper 警告。

```sh
git clone <仓库URL> && cd conflingo
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo build
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

### 方式B：通过 AirDrop 发送 Release 构建的 zip

```sh
# 1. Release 构建（将输出目录固定为 build/）
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Release -derivedDataPath build build

# 2. 使用 ditto 打包 zip（zip -r 可能破坏签名和扩展属性，请勿使用）
ditto -c -k --sequesterRsrc --keepParent \
  build/Build/Products/Release/ConfLingo.app dist/ConfLingo-1.0.zip
```

通过 AirDrop 发送生成的 `dist/ConfLingo-1.0.zip`。**由于使用临时签名（未经公证），接收方首次启动时需要解除 Gatekeeper 限制**：

1. 解压后双击 →「无法打开，因为无法验证开发者」
2. 系统设置 > 隐私与安全性 >「仍要打开」
3. 之后即可正常启动（开发者也可以执行 `xattr -dr com.apple.quarantine ConfLingo.app`）

### 需要告知接收方的运行要求

- **macOS 26 或更高版本 + Apple Silicon**（低于此版本的 macOS 无法启动）
- **首次启动需要网络**：每台 Mac 需自行下载识别和翻译模型（数百 MB）。为防会场 Wi-Fi 信号不佳，建议收到后立即启动一次
- 首次按 Start 时会出现麦克风权限对话框 →「允许」

## 限制事项

- 假定使用 MacBook 内置麦克风拾取会场声音。无法捕获 Zoom / YouTube 等 Mac 内部音频（系统音频）
- 设计上不翻译识别中的句子（partial）（防止译文抖动）。翻译以确定句为单位，延迟约 2〜5 秒
- 仅停止状态下可切换语言。切换语言后已有的字幕历史会保留（Markdown 头部记录保存时的语言对）
- 不支持说话人分离、摘要、录音保存
- 未进行分发用签名/公证（以本地构建的个人使用为前提）
- 识别准确率受麦克风位置和环境噪音影响较大。建议将 MacBook 朝向扬声器方向，尽量坐在前排

## 架构

```
AVAudioEngine 麦克风输入（硬件格式）
  └ AVAudioConverter 转换为 SpeechAnalyzer 推荐格式
    └ AsyncStream<AnalyzerInput> → SpeechAnalyzer / SpeechTranscriber（volatileResults）
        ├ partial → SessionStore.volatileText（在识别窗格中浅色显示）
        └ final  → 确定后存入 SessionStore.segments → TranslationCoordinator 队列
            └ .translationTask 闭包内的 TranslationSession 逐条翻译
                └ SessionStore.applyTranslation → 显示在翻译窗格
```

| 文件 | 职责 |
|---|---|
| `Models/SessionStore.swift` | UI 的单一数据源。片段历史、partial、去重 |
| `Models/KeywordParser.swift` | 专业术语栏解析 + 活动预置术语 |
| `Models/LanguageCatalog.swift` | 语言显示名称与目标语言候选过滤 |
| `Services/AudioCaptureService.swift` | 麦克风输入、格式转换、权限请求 |
| `Services/SpeechTranscriptionService.swift` | SpeechAnalyzer / SpeechTranscriber 接线 |
| `Services/TranslationCoordinator.swift` | 翻译队列（ID 去重 + AsyncStream） |
| `Services/ModelAvailabilityService.swift` | 启动时的可用性检查与模型下载 |
| `Export/MarkdownExporter.swift` | Markdown 生成（纯函数） |
