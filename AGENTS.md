# Quick Paste: instruções para agentes

## Sobre o projeto

Quick Paste é um plugin de histórico visual da área de transferência para a barra do Omarchy 4.x. Ele é executado dentro do `omarchy-shell` (Quickshell), abre um painel inferior com itens de texto, imagem e arquivos e permite recolocar e colar um item selecionado.

Componentes principais:

- `manifest.json`: identidade, versão, tipo e ponto de entrada do plugin.
- `BarWidget.qml`: widget exibido na barra.
- `QuickPaste.qml`: painel e interação principal.
- `ClipboardHistory.js`: modelo e persistência do histórico.
- `capture.sh`: captura segura de texto ou imagem do clipboard.
- `paste.sh`: restaura o item escolhido e simula a colagem.
- `tests/clipboard-history.test.js`: testes do modelo de histórico.

O estado persistente pertence ao usuário e fica em `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/`. Ele não faz parte do checkout e não deve ser apagado durante instalação, atualização ou testes.

## Regra principal

Toda modificação deve ser concebida e validada para o Omarchy. Compatibilidade com outro desktop ou distribuição pode ser útil, mas nunca pode degradar a experiência, as convenções ou a integração nativa com a versão suportada do Omarchy.

Antes de alterar integração, instalação, QML, comandos do shell ou layout da barra:

1. Consulte os comandos disponíveis com `omarchy <grupo> --help` ou `omarchy commands` em vez de presumir uma interface.
2. Prefira APIs e comandos públicos do Omarchy, especialmente `omarchy plugin`, `omarchy bar` e `omarchy restart`.
3. Nunca edite `/usr/share/omarchy/`; esse diretório pode ser lido como referência, mas pertence ao pacote e será substituído em atualizações.
4. Mantenha configurações e plugins do usuário em `~/.config/omarchy/` e dados persistentes em `$XDG_STATE_HOME` ou `~/.local/state`.
5. Preserve hot reload, posicionamento na barra, tema, escala, navegação por teclado e comportamento Wayland esperados no Omarchy.
6. Não introduza dependências externas sem verificar se já fazem parte do Omarchy suportado ou sem documentar claramente a necessidade.

## Convenções de implementação

- Trate conteúdo do clipboard como não confiável. Preserve texto Unicode, espaços e quebras de linha; nunca avalie seu conteúdo como shell.
- Não capture itens marcados como sensíveis e não exponha conteúdo do clipboard em logs.
- Use caminhos XDG e coloque variáveis de shell entre aspas.
- Não bloqueie o processo duradouro do `omarchy-shell`; operações potencialmente lentas devem permanecer nos helpers externos.
- Mantenha `manifest.json` compatível com o schema aceito por `omarchy plugin validate`.
- Ao mudar comportamento persistente, preserve ou migre o histórico já existente.
- Não inclua no pacote arquivos de desenvolvimento como `.git`, testes ou instruções para agentes.

## Validação obrigatória

Depois de qualquer mudança, execute:

```bash
make validate
```

Isso roda os testes JavaScript e a validação oficial do manifest/plugin. Para mudanças visuais ou de interação, também verifique o plugin no `omarchy-shell` real, incluindo abertura, fechamento, teclado, mouse, rolagem, colagem de texto e imagem e adaptação ao tema. Se o ambiente não permitir esse teste manual, registre essa limitação no relatório final.

## Instalação e atualização

Instale o plugin publicado com `omarchy plugin add https://github.com/pretodev/quick-paste.git --enable` e posicione-o com `omarchy bar move quick-paste --section right --before omarchy.power`. Para mudanças no fluxo de instalação local, mantenha o skill em `.codex/skills/install-qick-paste/` sincronizado com o ID `quick-paste`.
