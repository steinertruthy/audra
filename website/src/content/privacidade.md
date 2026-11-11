<!-- REVISÃO JURÍDICA PENDENTE: ver docs/legal-review.md antes de considerar este texto definitivo. -->

Última atualização: 11 de novembro de 2026.

Esta política explica como o aplicativo Audra para macOS e o site oficial do Audra tratam informações. O princípio é simples: **o Audra foi projetado para processar seus arquivos no seu próprio Mac**.

# Resumo

- O Audra não tem contas, não exige cadastro e não coleta dados de uso, estatísticas ou relatórios de erro.
- Seus vídeos, áudios, transcrições, resumos e projetos ficam no seu Mac.
- Nenhum arquivo é enviado para servidores do Audra — o projeto não opera servidores.
- Dados só saem do seu Mac nas situações descritas abaixo, sempre por uma ação sua.

# O que o aplicativo processa

Quando você importa um vídeo ou áudio, o Audra lê o arquivo, extrai o áudio temporariamente e gera a transcrição usando o reconhecimento de fala do próprio macOS (SpeechAnalyzer), que roda no dispositivo. Os resumos são gerados, por padrão, pelo Apple Intelligence, também no dispositivo.

O Audra **nunca altera nem copia os arquivos originais**. As edições de vídeo são salvas como projetos separados, que apenas fazem referência aos arquivos.

# O que fica guardado no seu Mac

- **Biblioteca de transcrições e resumos**: em `~/Library/Application Support/Audra`.
- **Projetos de edição**: na mesma pasta, em `Projects`.
- **Cópias de compatibilidade**: para formatos como MKV ou WebM, quando o FFmpeg está instalado, uma cópia reproduzível é criada na pasta `Media`.
- **Arquivos temporários**: áudio extraído, miniaturas e formas de onda ficam no cache do sistema e podem ser apagados em Ajustes › Armazenamento.
- **Chave de API opcional**: se você informar uma chave da Anthropic, ela é guardada no Keychain do macOS.

Você pode apagar esses dados a qualquer momento removendo itens da biblioteca, enviando projetos para o Lixo ou apagando as pastas acima.

# Quando algum dado sai do seu Mac

## Modelos de fala da Apple

Na primeira vez que um idioma é usado, o macOS baixa o modelo de reconhecimento de fala correspondente a partir dos servidores da Apple. Esse download é feito pelo sistema operacional e segue a [política de privacidade da Apple](https://www.apple.com/br/legal/privacy/). O áudio dos seus vídeos não é enviado nesse processo.

## Resumos com o Claude (opcional e desativado por padrão)

Se você escolher o Claude como modelo de resumo, ativar a permissão de envio em Ajustes › Resumo e informar sua própria chave de API, **o texto da transcrição** (não o vídeo nem o áudio) será enviado à API da Anthropic para gerar o resumo. Esse tratamento segue os termos e a [política de privacidade da Anthropic](https://www.anthropic.com/legal/privacy). Sem essa ativação explícita, nada é enviado.

## FFmpeg (opcional)

Se você instalar o FFmpeg, o Audra o executa localmente para converter formatos como MKV e WebM. Nada é enviado pela rede nesse processo.

# O site oficial

O site é hospedado no **GitHub Pages**. O GitHub pode registrar informações técnicas das visitas, como endereço IP, conforme a [Declaração de Privacidade do GitHub](https://docs.github.com/pt/site-policy/privacy-policies/github-general-privacy-statement).

- O site **não usa cookies, ferramentas de análise ou rastreadores**.
- Para exibir a versão mais recente, o seu navegador consulta a API pública do GitHub (`api.github.com`). O resultado fica salvo temporariamente no armazenamento da sessão do navegador e é descartado ao fechar a aba.
- Os downloads do aplicativo são servidos pelo GitHub Releases.

# Crianças

O Audra não coleta dados de nenhum usuário, incluindo crianças.

# Seus direitos

Como o projeto não coleta nem armazena dados pessoais em servidores, não há dados mantidos por nós para acessar, corrigir ou excluir. Os dados gerados pelo app ficam sob seu controle, no seu Mac. Para dados tratados pela Apple, pela Anthropic ou pelo GitHub, consulte as políticas desses serviços.

# Alterações

Esta política pode ser atualizada quando o funcionamento do Audra mudar. As alterações são registradas no [histórico do repositório](https://github.com/steinertruthy/audra/commits/main) e a data no topo desta página é atualizada.

# Contato

Dúvidas sobre privacidade podem ser enviadas como uma [issue no GitHub](https://github.com/steinertruthy/audra/issues). Não inclua informações pessoais ou trechos de transcrições nas mensagens públicas.
