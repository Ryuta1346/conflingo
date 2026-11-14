# ConfLingo

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | **한국어** | [Español](README.es.md)

컨퍼런스 자막과 회의 지원을 제공하는 개인용 macOS 앱입니다. Conference와 Meeting에서 마이크, 시스템 오디오 또는 두 입력을 함께 선택할 수 있습니다. 전사와 선택적 번역은 Apple API로 이 Mac에서 처리하고, 선택적 AI 지원은 사용자가 지정한 LLM 연결을 사용합니다. 새 세션은 전사 모드로 시작합니다.

- 전사: `Speech.framework` (macOS 26의 `SpeechAnalyzer` / `SpeechTranscriber`, 온디바이스)
- 번역: `Translation.framework` (`TranslationSession`, 온디바이스)
- UI: SwiftUI Conference / Meeting 화면, 작은 창과 공통 라이브러리

📖 **자세한 사용법(전문 용어 등록 방법, 현장 팁, 문제 해결)은 [docs/usage.md](docs/usage.md)(영어, [일본어판](docs/usage.ja.md)도 있음)를 참조하세요.**

## 현재 기능

- **Meeting:** 두 입력 전사, 입력별 선택적 번역, 작은 창, 근거가 있는 질문/답변, 선택적 자동 제안, 결정/할 일 후보 확인과 종료 후 수동 요약을 제공합니다. 선택한 용어의 원문 표기를 가능한 한 유지하지만, Meeting에서 고정 번역어를 지정하는 기능은 없습니다.
- **Sessions:** 「このMacに保存」으로 확정 전사, 번역, 완료된 AI 답변, 후보 확인 상태, 요약과 인용 발췌를 명시적으로 저장합니다. 이름 검색, 재시작 후 읽기, Markdown 내보내기와 삭제가 가능합니다. 음성, 원본 문서 전체, API 키와 AI 허용 상태는 저장하지 않습니다. 자동 저장·클라우드 동기화는 없으며 세션 삭제는 내보낸 Markdown이나 원본 파일을 삭제하지 않습니다.
- **자료 라이브러리:** 세션 전이나 도중에 Markdown/Text 또는 선택한 저장소 파일을 가져옵니다. 「ライブラリに保存」으로 문서를 이 Mac에 저장하고 「ライブラリから選択」으로 재사용합니다. AI 전송 허용 상태는 저장하지 않습니다. PDF/OCR은 아직 지원하지 않습니다.
- **양쪽 모드의 AI 지원:** Gemini, OpenAI, Claude, Kimi, DeepSeek, OpenAI 호환 클라우드와 호환 서버를 통한 Qwen 등의 로컬 모델을 선택합니다. API 키는 연결별로 Keychain에 저장합니다. 허용한 텍스트·자료 발췌를 전송하며 음성은 보내지 않습니다. 자동 제안은 기본 꺼짐입니다. 수동 웹 조사는 Gemini/OpenAI/Claude 모델의 검색 도구와 기존 키를 사용하며 별도 검색 키가 필요 없습니다. ChatGPT 구독 로그인은 지원하지 않습니다.

제공자별 품질, Zoom/Meet/Teams별 실사용, VoiceOver 전체 경로와 60분 내구성 검증은 남아 있습니다. [검증 현황](plan.md)과 [영문 사용 안내](docs/usage.md)를 확인하세요.

## 동작 요건

- macOS 26.0 이상 / Apple Silicon
- Xcode 26 이상 (빌드에 사용)
- 최초 1회만: 음성 인식 모델과 번역 모델 다운로드를 위해 네트워크 연결 필요

## 빌드 및 실행

```sh
# 빌드
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug build

# 실행 (DerivedData 아래에 생성된 .app 열기)
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

테스트 실행:

```sh
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo -destination 'platform=macOS'
```

## 권한 허용

1. **마이크**: 처음 Start를 누를 때 마이크 사용 권한 대화상자가 표시됩니다. 마이크 입력을 사용할 때만 필요하며 시스템 오디오만 사용하는 경우에는 요청하지 않습니다
2. **음성 인식 모델**: 최초 실행 시 인식 모델이 설치되어 있지 않으면 자동으로 다운로드가 시작됩니다(진행 상황 표시)
3. **번역 모델**: 번역 모델이 설치되어 있지 않으면 OS 표준 다운로드 확인 대화상자가 표시됩니다

마이크 권한을 다시 설정하려면:

```sh
tccutil reset Microphone com.gavrri.conflingo
```

권한을 거부해 버린 경우 「시스템 설정 > 개인정보 보호 및 보안 > 마이크」에서 ConfLingo를 활성화하세요.

## 사용법

1. 앱 실행 (최초 실행 시 모델 확인 및 다운로드가 진행됨)
2. **언어 선택기**에서 인식 언어와 번역 대상 언어를 선택 (정지 중에만 변경 가능. 변경하면 가용성 확인과 모델 다운로드가 자동으로 실행됨)
3. 필요하면 세션 이름 입력
4. **전문 용어 입력란**에 이벤트 고유의 용어(발표자 이름, 제품명, 기술 용어)를 쉼표로 구분하여 입력합니다. Start 시 음성 인식의 contextual strings로 등록되어 고유명사의 인식 정확도가 향상됩니다(기본값으로 Code with Claude Tokyo용 용어가 사전 설정되어 있음. 변경 사항은 다음 Start부터 반영)
5. **Start**(⌘R)로 전사 시작
   - 인식 패널: 인식 중인 문장(partial)은 흐린 이탤릭체로 표시되며, 확정되면 기록에 추가됨
   - 번역 패널: 확정된 원문만 번역되어 확정 문장 단위로 기록에 추가됨
6. **Stop**(⌘R)으로 정지. Start로 재개하면 기록에 이어서 추가됨
7. **Save Markdown**으로 세션 전체를 Markdown으로 저장
8. **A− / A＋**(⌘− / ⌘+)로 글꼴 크기 조정, 「항상 위」 체크박스로 창을 항상 앞에 표시
9. **Clear**로 기록 삭제 (정지 중에만 가능)

## 배포

### 방법A: 소스 공유 (Xcode가 있는 개발자에게 권장)

저장소 URL을 전달하고 상대방에게 다음을 실행하게 합니다. Gatekeeper 경고가 표시되지 않습니다.

```sh
git clone <저장소URL> && cd conflingo
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo build
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

### 방법B: Release 빌드의 zip을 AirDrop으로 전송

```sh
# 1. Release 빌드 (출력 경로를 build/로 고정)
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Release -derivedDataPath build build

# 2. ditto로 zip 생성 (zip -r은 서명과 확장 속성을 손상시킬 수 있으므로 사용하지 않음)
ditto -c -k --sequesterRsrc --keepParent \
  build/Build/Products/Release/ConfLingo.app dist/ConfLingo-1.0.zip
```

생성된 `dist/ConfLingo-1.0.zip`을 AirDrop으로 전송합니다. **애드혹 서명(공증 없음)이므로 받는 쪽은 최초 실행 시 Gatekeeper 해제가 필요합니다**:

1. 압축 해제 후 더블 클릭 → 「개발자를 확인할 수 없기 때문에 열 수 없습니다」
2. 시스템 설정 > 개인정보 보호 및 보안 > 「그래도 열기」
3. 이후에는 정상적으로 실행됨 (개발자라면 `xattr -dr com.apple.quarantine ConfLingo.app`도 가능)

### 공유 상대에게 전달할 동작 요건

- **macOS 26 이상 + Apple Silicon** (그 미만의 macOS에서는 실행되지 않음)
- **최초 실행 시 네트워크 필수**: 인식·번역 모델(수백 MB)을 각자의 Mac이 다운로드합니다. 행사장 Wi-Fi가 불안정할 경우를 대비해 받는 즉시 한 번 실행하도록 안내
- 최초 Start 시 마이크 권한 대화상자 → 「허용」

## 제한 사항

- 양쪽 모드에서 마이크·시스템 오디오·두 입력을 지원합니다. Zoom/Meet/Teams별 실사용 검증은 남아 있습니다
- 인식 중인 문장(partial)은 번역하지 않는 설계입니다(번역 흔들림 방지). 번역 지연은 모델·문장·기기에 따라 달라지며 실회의 지연 검증은 남아 있습니다
- 언어 변경은 정지 중에만 가능합니다. 언어를 전환해도 기존 자막 기록은 유지됩니다(Markdown 헤더에는 저장 시점의 언어 쌍이 기록됨)
- 개별 화자 식별과 녹음 저장은 지원하지 않습니다. Meeting에서는 선택적 AI 요약을 제공합니다
- 배포용 서명·공증은 하지 않았습니다(로컬 빌드 개인 사용 전제)
- 인식 정확도는 마이크 위치와 주변 소음의 영향을 크게 받습니다. MacBook을 스피커 방향으로 향하게 하고 가능하면 앞좌석을 권장합니다

## 아키텍처

공통 전사 경로, AI 지원, 자료 라이브러리와 Sessions의 구성은 [최신 아키텍처 다이어그램](README.md#architecture)을 참조하세요.
