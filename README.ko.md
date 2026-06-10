# ConfLingo

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | **한국어** | [Español](README.es.md)

컨퍼런스 현장에서 MacBook 마이크 음성을 Apple/macOS 내장 API로 실시간 전사하고, 번역 자막으로 표시하는 개인용 macOS 앱입니다. 인식 언어와 번역 대상 언어는 OS가 지원하는 언어 중에서 자유롭게 선택할 수 있습니다(기본값: 영어 → 일본어).

- 전사: `Speech.framework` (macOS 26의 `SpeechAnalyzer` / `SpeechTranscriber`, 온디바이스)
- 번역: `Translation.framework` (`TranslationSession`, 온디바이스)
- UI: SwiftUI 2분할 화면 (원문 전사 / 번역문)

📖 **자세한 사용법(전문 용어 등록 방법, 현장 팁, 문제 해결)은 [docs/usage.md](docs/usage.md)(영어, [일본어판](docs/usage.ja.md)도 있음)를 참조하세요.**

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

1. **마이크**: 처음 Start를 누를 때 마이크 사용 권한 대화상자가 표시됩니다. 허용하지 않으면 전사할 수 없습니다
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

- 행사장 소리는 MacBook 내장 마이크로 수음하는 것을 전제로 합니다. Zoom / YouTube 등 Mac 내부 음성(시스템 오디오)은 캡처할 수 없습니다
- 인식 중인 문장(partial)은 번역하지 않는 설계입니다(번역 흔들림 방지). 번역은 확정 문장 단위로 약 2〜5초 지연됩니다
- 언어 변경은 정지 중에만 가능합니다. 언어를 전환해도 기존 자막 기록은 유지됩니다(Markdown 헤더에는 저장 시점의 언어 쌍이 기록됨)
- 화자 분리, 요약, 녹음 저장은 지원하지 않습니다
- 배포용 서명·공증은 하지 않았습니다(로컬 빌드 개인 사용 전제)
- 인식 정확도는 마이크 위치와 주변 소음의 영향을 크게 받습니다. MacBook을 스피커 방향으로 향하게 하고 가능하면 앞좌석을 권장합니다

## 아키텍처

```
AVAudioEngine 마이크 입력 (하드웨어 포맷)
  └ AVAudioConverter로 SpeechAnalyzer 권장 포맷으로 변환
    └ AsyncStream<AnalyzerInput> → SpeechAnalyzer / SpeechTranscriber (volatileResults)
        ├ partial → SessionStore.volatileText (인식 패널에 흐리게 표시)
        └ final  → SessionStore.segments에 확정 → TranslationCoordinator 큐로
            └ .translationTask 클로저 내의 TranslationSession이 순차 번역
                └ SessionStore.applyTranslation → 번역 패널에 표시
```

| 파일 | 책임 |
|---|---|
| `Models/SessionStore.swift` | UI의 단일 정보원. 세그먼트 기록·partial·중복 제거 |
| `Models/KeywordParser.swift` | 전문 용어란 파싱 + 이벤트용 프리셋 |
| `Models/LanguageCatalog.swift` | 언어 표시명·번역 대상 후보 정리 |
| `Services/AudioCaptureService.swift` | 마이크 입력·포맷 변환·권한 요청 |
| `Services/SpeechTranscriptionService.swift` | SpeechAnalyzer / SpeechTranscriber 연결 |
| `Services/TranslationCoordinator.swift` | 번역 큐 (ID 중복 제거 + AsyncStream) |
| `Services/ModelAvailabilityService.swift` | 시작 시 가용성 확인·모델 다운로드 |
| `Export/MarkdownExporter.swift` | Markdown 생성 (순수 함수) |
