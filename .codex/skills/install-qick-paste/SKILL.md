---
name: install-qick-paste
description: Instala ou atualiza o plugin Qick Paste neste computador Omarchy a partir do checkout local, valida a instalação e posiciona o widget na barra. Use quando pedirem para instalar, configurar, reinstalar ou atualizar o Qick Paste.
---

# Instalar ou atualizar o Qick Paste

Este skill é autocontido no repositório para poder ser usado por qualquer ferramenta de agente que reconheça `AGENTS.md` ou consiga ler este arquivo diretamente.

## Antes de executar

Leia o `AGENTS.md` na raiz e confirme que o sistema dispõe dos comandos `omarchy`, `omarchy-shell`, `jq`, `wl-copy`, `wl-paste`, `wtype`, `perl`, `setpriv` e `node`.

A instalação modifica `~/.config/omarchy/plugins/qick-paste/` e a configuração da barra. Peça autorização antes de executar se a ferramenta exigir consentimento para alterações fora do repositório.

Não apague o histórico em `~/.local/state/omarchy/`. Não edite `/usr/share/omarchy/`.

## Fluxo

1. Na raiz do repositório, execute `make validate`.
2. Execute `skills/install-qick-paste/scripts/install.sh`.
3. Confirme que `omarchy plugin list --json` contém `qick-paste` e que o plugin está habilitado.
4. Reinicie o shell com `omarchy restart shell`.
5. Informe se foi uma instalação nova, uma atualização local ou uma atualização Git.

O instalador é idempotente. Ele copia somente os arquivos de runtime, preserva o estado do usuário, posiciona o widget na seção direita antes de `omarchy.power` e reinicia o shell ao final. Quando o destino é um clone Git, ele usa `omarchy plugin update qick-paste` em vez de sobrescrever o checkout.

Para apenas inspecionar o que seria feito, use:

```bash
skills/install-qick-paste/scripts/install.sh --dry-run
```

Se a validação, atualização ou descoberta do plugin falhar, pare e mostre o erro; não tente contornar a validação oficial nem substituir configurações inteiras do Omarchy.
