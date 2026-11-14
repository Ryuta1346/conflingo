# ConfLingo

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [한국어](README.ko.md) | **Español**

Una aplicación personal para macOS con subtítulos para conferencias y asistencia para reuniones. Conference y Meeting permiten usar el micrófono, el audio del sistema o ambos. La transcripción y la traducción opcional se procesan en este Mac mediante las API de Apple; la asistencia de IA opcional usa la conexión LLM elegida. Las sesiones nuevas empiezan en modo de transcripción.

- Transcripción: `Speech.framework` (`SpeechAnalyzer` / `SpeechTranscriber` de macOS 26, en el dispositivo)
- Traducción: `Translation.framework` (`TranslationSession`, en el dispositivo)
- UI: SwiftUI con Conference, Meeting, panel flotante y bibliotecas compartidas

📖 **Para instrucciones detalladas (registro de términos técnicos, consejos para el evento, solución de problemas), consulta [docs/usage.md](docs/usage.md) (en inglés; también disponible en [japonés](docs/usage.ja.md)).**

## Funciones actuales

- **Meeting:** transcripción de dos entradas, traducción opcional por entrada, panel flotante, preguntas con fuentes, sugerencias automáticas opcionales, revisión de decisiones/acciones y resumen manual al terminar. Las traducciones conservan la grafía original de los términos seleccionados cuando es posible; no hay traducciones fijas configurables en Meeting.
- **Sessions:** «このMacに保存» guarda explícitamente transcripciones finales, traducciones y respuestas completadas, estados de revisión, resúmenes y extractos citados. Permite búsqueda por nombre, lectura tras reiniciar, exportación Markdown y borrado. No guarda audio, documentos fuente completos, claves ni permisos de IA. No hay guardado automático ni sincronización; borrar una sesión no borra los Markdown exportados ni los originales.
- **Biblioteca:** importar Markdown/Text o archivos seleccionados de un repositorio antes o durante una sesión. «ライブラリに保存» conserva explícitamente los documentos en este Mac; «ライブラリから選択» permite reutilizarlos. No conserva los permisos de envío a IA. PDF/OCR aún no está disponible.
- **IA en ambos modos:** Gemini, OpenAI, Claude, Kimi, DeepSeek, nubes compatibles con OpenAI y modelos locales como Qwen mediante un servidor compatible. Claves separadas por conexión en Keychain. Las preguntas pueden enviar texto y extractos autorizados; no audio. Las sugerencias automáticas están desactivadas inicialmente. La investigación web manual usa las herramientas del modelo Gemini/OpenAI/Claude y la misma clave, sin otra clave de búsqueda. No se admite iniciar sesión con una suscripción de ChatGPT.

La calidad con cada proveedor, las pruebas específicas de Zoom/Meet/Teams, VoiceOver completo y la resistencia durante 60 minutos siguen pendientes. Consulta el [estado de aceptación](plan.md) y la [guía de uso en inglés](docs/usage.md).

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

1. **Micrófono**: Al pulsar Start por primera vez aparece el diálogo de permiso del micrófono. Solo es necesario al usar el micrófono; el modo de audio del sistema no solicita este permiso
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

- Ambos modos admiten micrófono, audio del sistema o ambos; las pruebas específicas de Zoom/Meet/Teams siguen pendientes
- Por diseño, las frases en curso (partial) no se traducen (para evitar traducciones inestables). La latencia depende del modelo, el texto y el equipo; su validación en reuniones reales está pendiente
- Los idiomas solo se pueden cambiar mientras está detenida. Al cambiar de idioma se conserva el historial de subtítulos existente (la cabecera del Markdown registra el par de idiomas en el momento de guardar)
- No se admiten la identificación individual de hablantes ni la grabación de audio. Meeting ofrece resúmenes opcionales con IA
- Sin firma ni notarización para distribución (pensada para uso personal con compilaciones locales)
- La precisión del reconocimiento depende mucho de la posición del micrófono y del ruido ambiental. Orienta el MacBook hacia los altavoces y, si es posible, siéntate en las filas delanteras

## Arquitectura

La ruta de transcripción compartida, la asistencia de IA, la biblioteca y Sessions se describen en el [diagrama de arquitectura actualizado](README.md#architecture).
