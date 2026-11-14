# ConfLingo

[English](README.md) | [日本語](README.ja.md) | **简体中文** | [한국어](README.ko.md) | [Español](README.es.md)

一款提供会议字幕与会话辅助的个人用 macOS 应用。Conference 和 Meeting 均可选择麦克风、系统音频或两者。转写与可选翻译通过 Apple API 在本机处理；可选 AI 辅助使用用户选择的 LLM 连接。新会话默认使用转写模式。

- 语音转写：`Speech.framework`（macOS 26 的 `SpeechAnalyzer` / `SpeechTranscriber`，设备端处理）
- 翻译：`Translation.framework`（`TranslationSession`，设备端处理）
- UI：SwiftUI Conference / Meeting 界面、浮动小窗与共享资料库

📖 **详细使用方法（专业术语注册、现场技巧、故障排查）请参阅 [docs/usage.md](docs/usage.md)（英文，另有[日语版](docs/usage.ja.md)）。**

## 当前功能

- **Meeting：** 双输入转写、按输入选择翻译、浮动小窗、带来源的问答、可选自动建议、决策/行动候选确认及结束后的手动摘要。翻译尽可能保留所选术语的原文拼写；Meeting 尚不支持指定固定译词。
- **Sessions：** 通过「このMacに保存」显式保存确定的转写、译文、已完成的 AI 回答、候选确认状态、摘要和引用片段。支持按名称搜索、重启后只读查看、Markdown 导出与删除。不保存音频、完整源文档、API 密钥或 AI 授权。没有自动保存或云同步；删除会话不会删除导出的 Markdown 和原始文件。
- **资料库：** 会话前或进行中可导入 Markdown/Text 或选中的仓库文件。用「ライブラリに保存」将文档显式保存在本机，再通过「ライブラリから選択」复用。AI 发送授权不会保存。尚不支持 PDF/OCR。
- **两种模式的 AI 辅助：** 可选择 Gemini、OpenAI、Claude、Kimi、DeepSeek、OpenAI 兼容云服务，以及通过兼容服务器连接的 Qwen 等本地模型。密钥按连接分别存入 Keychain。只发送经授权的文本与资料片段，不发送音频；自动建议默认关闭。手动网页调查使用 Gemini/OpenAI/Claude 模型自带的搜索工具和现有密钥，无需另一搜索密钥。不支持 ChatGPT 订阅登录。

各服务的实际模型质量、Zoom/Meet/Teams 分别验收、VoiceOver 全流程以及 60 分钟耐久性仍待验证。请参阅[验收进度](plan.md)及[英文使用指南](docs/usage.md)。

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

1. **麦克风**：首次按下 Start 时会显示麦克风使用权限对话框。仅使用麦克风输入时需要；仅采集系统音频时不请求此权限
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

- 两种模式均支持麦克风、系统音频或双输入；Zoom/Meet/Teams 的分别验收仍待完成
- 设计上不翻译识别中的句子（partial）（防止译文抖动）。翻译延迟取决于模型、文本和设备；实际会议中的延迟验收仍待完成
- 仅停止状态下可切换语言。切换语言后已有的字幕历史会保留（Markdown 头部记录保存时的语言对）
- 不支持独立说话人识别或录音保存。Meeting 提供可选 AI 摘要
- 未进行分发用签名/公证（以本地构建的个人使用为前提）
- 识别准确率受麦克风位置和环境噪音影响较大。建议将 MacBook 朝向扬声器方向，尽量坐在前排

## 架构

共享转写路径、AI 辅助、资料库和 Sessions 的结构请参阅[最新架构图](README.md#architecture)。
