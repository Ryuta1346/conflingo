# ConfLingo

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [한국어](README.ko.md) | **Español**

Una aplicación personal para macOS que transcribe en tiempo real el audio del micrófono del MacBook en salas de conferencias usando las API integradas de Apple/macOS, y muestra el resultado como subtítulos traducidos. El idioma de reconocimiento y el idioma de destino se pueden elegir libremente entre los idiomas compatibles con el sistema operativo (predeterminado: inglés → japonés).

- Transcripción: `Speech.framework` (`SpeechAnalyzer` / `SpeechTranscriber` de macOS 26, en el dispositivo)
- Traducción: `Translation.framework` (`TranslationSession`, en el dispositivo)
- UI: SwiftUI con dos paneles (transcripción original / texto traducido)

📖 **Para instrucciones detalladas (registro de términos técnicos, consejos para el evento, solución de problemas), consulta [docs/usage.md](docs/usage.md) (en inglés; también disponible en [japonés](docs/usage.ja.md)).**

## Requisitos

- macOS 26.0 o posterior / Apple Silicon
- Xcode 26 o posterior (para compilar)
- Solo en el primer arranque: se requiere conexión de red para descargar el modelo de reconocimiento de voz y el modelo de traducción

## Compilación y ejecución

```sh
# Compilar
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug build

# Ejecutar (abrir la .app generada bajo DerivedData)
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

Ejecutar las pruebas:

```sh
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo -destination 'platform=macOS'
```

## Permisos

1. **Micrófono**: Al pulsar Start por primera vez aparece el diálogo de permiso del micrófono. Sin él no se puede transcribir
2. **Modelo de reconocimiento de voz**: Si el modelo de reconocimiento no está instalado en el primer arranque, la descarga comienza automáticamente (con indicador de progreso)
3. **Modelo de traducción**: Si el modelo de traducción no está instalado, aparece el diálogo estándar de confirmación de descarga del sistema

Para restablecer el permiso del micrófono:

```sh
tccutil reset Microphone com.gavrri.conflingo
```

Si rechazaste el permiso por error, habilita ConfLingo en Configuración del Sistema > Privacidad y seguridad > Micrófono.

## Uso

1. Inicia la aplicación (en el primer arranque se ejecutan la comprobación y descarga de modelos)
2. Elige el idioma de reconocimiento y el idioma de destino con los **selectores de idioma** (solo se pueden cambiar mientras está detenida; al cambiarlos se ejecutan automáticamente la comprobación de disponibilidad y la descarga de modelos)
3. Introduce un nombre de sesión si lo necesitas
4. En el **campo de términos técnicos**, introduce términos específicos del evento (nombres de ponentes, nombres de productos, jerga técnica) separados por comas. Al pulsar Start se registran como contextual strings del reconocimiento de voz, mejorando la precisión con nombres propios (preconfigurado con términos para Code with Claude Tokyo; los cambios surten efecto a partir del siguiente Start)
5. Pulsa **Start** (⌘R) para iniciar la transcripción
   - Panel de reconocimiento: las frases en curso (partial) se muestran atenuadas y en cursiva, y se añaden al historial al confirmarse
   - Panel de traducción: solo se traducen las frases originales confirmadas, añadidas frase por frase
6. Pulsa **Stop** (⌘R) para detener. Al pulsar Start de nuevo se continúa añadiendo al historial
7. **Save Markdown** guarda la sesión completa como Markdown
8. **A− / A＋** (⌘− / ⌘+) ajusta el tamaño de fuente; la casilla «siempre visible» mantiene la ventana en primer plano
9. **Clear** descarta el historial (solo mientras está detenida)

## Distribución

### Opción A: Compartir el código fuente (recomendado para desarrolladores con Xcode)

Comparte la URL del repositorio y pide al destinatario que ejecute lo siguiente. No aparece la advertencia de Gatekeeper.

```sh
git clone <URL del repositorio> && cd conflingo
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo build
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

### Opción B: Enviar por AirDrop un zip de la compilación Release

```sh
# 1. Compilación Release (fijando la salida en build/)
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Release -derivedDataPath build build

# 2. Crear el zip con ditto (zip -r puede dañar las firmas y los atributos extendidos)
ditto -c -k --sequesterRsrc --keepParent \
  build/Build/Products/Release/ConfLingo.app dist/ConfLingo-1.0.zip
```

Envía el `dist/ConfLingo-1.0.zip` resultante por AirDrop. **Como la aplicación tiene firma ad-hoc (sin notarización), el destinatario debe omitir Gatekeeper en el primer arranque**:

1. Descomprimir y hacer doble clic → «no se puede abrir porque no se puede verificar el desarrollador»
2. Configuración del Sistema > Privacidad y seguridad > «Abrir de todos modos»
3. Después se inicia con normalidad (los desarrolladores también pueden ejecutar `xattr -dr com.apple.quarantine ConfLingo.app`)

### Requisitos que comunicar a los destinatarios

- **macOS 26 o posterior + Apple Silicon** (no se inicia en versiones anteriores de macOS)
- **Red necesaria en el primer arranque**: cada Mac descarga los modelos de reconocimiento y traducción (varios cientos de MB). Por si el Wi-Fi del recinto es débil, pide que inicien la aplicación nada más recibirla
- Diálogo de permiso del micrófono en el primer Start → «Permitir»

## Limitaciones

- Se asume que el audio de la sala se capta con el micrófono integrado del MacBook. No se puede capturar el audio interno del Mac (audio del sistema), como Zoom / YouTube
- Por diseño, las frases en curso (partial) no se traducen (para evitar traducciones inestables). La traducción se retrasa unos 2–5 segundos respecto a las frases confirmadas
- Los idiomas solo se pueden cambiar mientras está detenida. Al cambiar de idioma se conserva el historial de subtítulos existente (la cabecera del Markdown registra el par de idiomas en el momento de guardar)
- No se admiten la separación de hablantes, los resúmenes ni la grabación de audio
- Sin firma ni notarización para distribución (pensada para uso personal con compilaciones locales)
- La precisión del reconocimiento depende mucho de la posición del micrófono y del ruido ambiental. Orienta el MacBook hacia los altavoces y, si es posible, siéntate en las filas delanteras

## Arquitectura

```
Entrada de micrófono AVAudioEngine (formato de hardware)
  └ AVAudioConverter convierte al formato preferido de SpeechAnalyzer
    └ AsyncStream<AnalyzerInput> → SpeechAnalyzer / SpeechTranscriber (volatileResults)
        ├ partial → SessionStore.volatileText (mostrado atenuado en el panel de reconocimiento)
        └ final  → confirmado en SessionStore.segments → cola de TranslationCoordinator
            └ TranslationSession dentro del closure .translationTask traduce secuencialmente
                └ SessionStore.applyTranslation → mostrado en el panel de traducción
```

| Archivo | Responsabilidad |
|---|---|
| `Models/SessionStore.swift` | Única fuente de verdad de la UI. Historial de segmentos, partials, deduplicación |
| `Models/KeywordParser.swift` | Análisis del campo de términos técnicos + preajustes del evento |
| `Models/LanguageCatalog.swift` | Nombres de idiomas y filtrado de candidatos de destino |
| `Services/AudioCaptureService.swift` | Entrada de micrófono, conversión de formato, solicitud de permisos |
| `Services/SpeechTranscriptionService.swift` | Cableado de SpeechAnalyzer / SpeechTranscriber |
| `Services/TranslationCoordinator.swift` | Cola de traducción (deduplicación por ID + AsyncStream) |
| `Services/ModelAvailabilityService.swift` | Comprobación de disponibilidad y descarga de modelos al inicio |
| `Export/MarkdownExporter.swift` | Generación de Markdown (función pura) |
