# Changelog

Todas as mudanças relevantes do Audra são registradas neste arquivo.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e o projeto adota o [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Unreleased]

## [0.1.0] - 2026-11-11

Primeira versão pública do Audra.

### Adicionado

- Transcrição de vídeos e áudios no dispositivo com o reconhecimento de fala do macOS (SpeechAnalyzer), com marcação de tempo por palavra.
- Detecção automática do idioma falado, com prioridade para o português do Brasil, e escolha manual do idioma por arquivo.
- Resumos estruturados com Apple Intelligence no dispositivo: visão geral, tópicos, pontos importantes, decisões, próximos passos e capítulos, em três níveis de detalhe.
- Integração opcional com o Claude (Anthropic API), que exige consentimento explícito e chave própria guardada no Keychain.
- Biblioteca com busca em todas as transcrições, fila de processamento, cancelamento e retomada de tarefas interrompidas.
- Exportação da transcrição em TXT, Markdown e SRT e do resumo em Markdown e PDF.
- Editor de vídeo com timeline de várias faixas (vídeo, áudio e texto), miniaturas, formas de onda, ímã de alinhamento, marcadores e histórico para desfazer e refazer.
- Ferramentas de edição: dividir, aparar, mover, duplicar, excluir fechando o espaço, velocidade de 0,25× a 4×, escala, posição, rotação, recorte, opacidade, fades e transições (dissolver, mergulho no preto ou no branco, deslizar e cortina).
- Edição de áudio: volume, silenciar, fades, separar e substituir o áudio original, trilhas extras e remoção de pausas longas.
- Títulos, textos e legendas com fontes, cores, caixa de fundo, posição e animações de entrada e saída.
- Edição pelo texto: remover, silenciar ou localizar na timeline um trecho selecionado na transcrição, com cortes ajustados ao silêncio.
- Legendas automáticas geradas a partir da transcrição, respeitando os cortes da edição.
- Exportação de vídeo em MP4 ou MOV (H.264 ou HEVC por hardware) e de áudio em M4A, com resolução, qualidade e quadros por segundo configuráveis.
- Projetos salvos automaticamente, sem alterar os arquivos originais.
- Interface em português, inglês e espanhol, que acompanha o idioma do sistema ou pode ser escolhida nos Ajustes.
- Visual escuro com destaque em violeta e atalhos de teclado nos menus do macOS.

[Unreleased]: https://github.com/steinertruthy/audra/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/steinertruthy/audra/releases/tag/v0.1.0
