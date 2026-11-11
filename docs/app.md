# Aplicativo macOS

Documentação técnica do app em `app/`. Para instalar e usar, veja o [README](../README.md).

## Funcionalidades

### Transcrição e resumo

- **Transcrição no dispositivo** com `SpeechAnalyzer`/`SpeechTranscriber` (macOS 26), offline após o download do modelo de cada idioma, com marcação de tempo por palavra.
- **Detecção automática de idioma** com prioridade para pt-BR (compara pt-BR, en-US e es-ES em um trecho de 40 s). O idioma também pode ser fixado nos Ajustes ou escolhido por arquivo, no cabeçalho da transcrição, para transcrever de novo.
- **Resumo** com Apple Intelligence (Foundation Models) em map-reduce para vídeos longos; integração **opcional** com o Claude (Anthropic API), só com consentimento explícito e chave no Keychain.
- **Biblioteca** (SwiftData) com busca global, fila de processamento, cancelamento, retomada e detecção de arquivos já processados.
- **Exportação**: transcrição em TXT, Markdown e SRT; resumo em Markdown e PDF.

### Editor de vídeo

- **Projetos** em `~/Library/Application Support/Audra/Projects` (JSON, gravação atômica), com desfazer/refazer e estado da timeline restaurado ao reabrir. Os arquivos originais nunca são alterados.
- **Timeline** com faixas de vídeo, áudio e texto; miniaturas e formas de onda em cache; mover entre faixas, aparar, dividir, duplicar, excluir fechando o espaço, ímã, zoom, marcadores, bloquear/silenciar/ocultar faixas. Só o trecho visível é desenhado.
- **Clipes**: velocidade 0,25×–4× (sem mudar o tom), escala, posição, rotação, recorte, opacidade, fades e transições (dissolver, mergulho no preto/branco, deslizar, cortina).
- **Áudio**: volume, silenciar, fades, separar e substituir o áudio original, trilhas extras, remoção de pausas longas.
- **Textos e legendas** com fontes, cores, fundo, posição e animações; legendas automáticas a partir da transcrição que respeitam os cortes.
- **Edição pelo texto**: selecionar palavras (⇧-clique, clique duplo na frase) e *Remover trecho*, *Silenciar*, *Localizar na timeline* ou *Criar legenda*; cortes ajustados ao silêncio pela forma de onda.
- **Exportação** MP4/MOV (H.264 ou HEVC por hardware) e M4A, com resolução, qualidade e FPS, progresso real e cancelamento.

### Interface

- Português, inglês e espanhol (acompanha o idioma do sistema ou é escolhido em Ajustes › Geral).
- Atalhos de teclado nos menus **Clipe** e **Reprodução** da barra de menus.

## Arquitetura

```text
app/Sources/Audra
├── App/                 Ponto de entrada, estado global (AppModel), menus, modo CLI, harness de depuração
├── Design/              Tokens visuais (Theme), componentes e barra superior própria
├── Models/              Recording (SwiftData), trechos, palavras, resumo e status
├── Services/
│   ├── Media/           Inspeção, extração de áudio em streaming (16 kHz mono), ponte FFmpeg
│   ├── Transcription/   SpeechEngine, detecção de idioma, segmentação em blocos
│   ├── Summary/         Protocolo Summarizer, Apple Intelligence (map-reduce), Claude
│   ├── Processing/      ProcessingCenter: fila serial, estágios, progresso, cancelamento, retomada
│   ├── Export/          Renderizadores TXT/MD/SRT e PDF
│   └── Support/         Formatação, preferências, Keychain, caminhos, localização (tr)
├── Editor/
│   ├── Model/           EditProject (valor puro, Codable) e operações de timeline testáveis
│   ├── Engine/          CompositionBuilder, AudraCompositor (Core Image/Metal), exportador, caches
│   └── Views/           Timeline, monitor, inspetor, painéis e exportação
└── Views/               Biblioteca: início, transcrições, projetos, resultados, processamento, ajustes
```

- **Pipeline de transcrição:** importar → (proxy FFmpeg se necessário) → extrair áudio → detectar idioma → transcrever (resultados em tempo real) → salvar → resumir. Cada etapa é cancelável.
- **Motor de edição:** a timeline, o monitor e a exportação usam a mesma composição gerada pelo `CompositionBuilder`, então a pré-visualização é exatamente o que é exportado.
- **Localização:** os textos da interface usam `tr("…")` com a frase em português como chave; as traduções ficam em `Services/Support/Translations.swift`.

## Linha de comando

```bash
build/Audra.app/Contents/MacOS/Audra --transcribe video.mp4 [--language pt-BR] [--summary] [--srt]
build/Audra.app/Contents/MacOS/Audra --render-demo video.mp4 pasta-de-saida   # verifica o motor de edição
```

## Limitações conhecidas

- **Identificação de participantes** não está disponível: o motor de fala nativo não oferece diarização.
- A detecção automática compara pt-BR, inglês e espanhol; para outros idiomas, escolha o idioma manualmente.
- Formatos como MKV, WebM e AVI exigem o FFmpeg instalado.
- Os resumos são gerados por IA e identificados como tal; não são citações literais do vídeo.
