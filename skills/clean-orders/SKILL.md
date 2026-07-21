---
name: clean-orders
description: Limpa um arquivo JSON de pedidos removendo produtos cujo barcode/EAN está em uma lista. Auto-detecta o campo de barcode (barcode/ean/gtin/sku) e o array de produtos (products/items/lineItems). Remove pedidos que ficam vazios após a filtragem. Aceita override de nomes de campo via flags.
argument-hint: <input-orders.json> <barcodes.json> [output.json] [--barcode-field=X] [--products-field=Y] [--dry-run]
allowed-tools: Bash(node ${CLAUDE_SKILL_DIR}/scripts/clean.js *), Read
disable-model-invocation: true
---

# Clean Orders

Esta skill remove produtos de um arquivo JSON de pedidos com base em uma lista de barcodes/EANs. Pedidos que ficam sem nenhum produto após a filtragem são removidos do output.

## Argumentos

Posicionais (na ordem):

1. `<input.json>` — **obrigatório**. Arquivo JSON de pedidos. Deve ser um array JSON no nível raiz, onde cada item é um pedido contendo um array de produtos.
2. `<barcodes.json>` — **obrigatório**. Lista de barcodes. Aceita dois formatos:
   - Array de strings: `["7891150066175", "7891150068537"]`
   - Array de objetos: `[{"barcode": "..."}, {"ean": "..."}]`
3. `[output.json]` — opcional. Default: `<input-basename>.cleaned.json` no mesmo diretório do input.

Flags opcionais (podem aparecer em qualquer posição):

- `--barcode-field=<nome>` — força o nome do campo de barcode (em vez de auto-detectar entre `barcode`, `ean`, `ean13`, `gtin`, `gtin13`, `upc`, `code`, `sku`).
- `--products-field=<nome>` — força o nome do array de produtos (em vez de auto-detectar entre `products`, `items`, `lineItems`, `orderItems`, `lines`).
- `--dry-run` — apenas reporta o que seria feito, sem escrever o output.
- `--help` ou `-h` — imprime ajuda do script.

## Procedimento

### Passo 1 — Validar argumentos

Se o usuário não passou pelo menos 2 argumentos posicionais, mostre a sintaxe e pare:

```
Uso: /clean-orders <input.json> <barcodes.json> [output.json]
Flags: --barcode-field=NOME --products-field=NOME --dry-run
```

### Passo 2 — Validar arquivos existem

Antes de executar, confira que `$1` e `$2` existem:

```bash
test -f "$1" && test -f "$2"
```

Se algum não existir, mostre uma mensagem clara apontando qual arquivo está faltando.

### Passo 3 — Executar o script

Repasse **todos os argumentos** (posicionais e flags) ao script Node:

```bash
node "${CLAUDE_SKILL_DIR}/scripts/clean.js" "$@"
```

O script é responsável por:
- Carregar e parsear os dois JSONs (com erro claro se inválido)
- Auto-detectar (ou aplicar override) do campo de barcode e do array de produtos
- Filtrar produtos cujo barcode está na lista
- Remover pedidos que ficam vazios
- Escrever o output (a menos que `--dry-run`)
- Imprimir um sumário no stdout

### Passo 4 — Reportar

Exiba a saída do script ao usuário sem reformatar. Se o script saiu com código ≠ 0:

- Código 2 → argumentos faltando. Mostre a sintaxe novamente.
- Código 1 → erro de detecção, parsing ou estrutura. Leia a mensagem do erro e sugira o flag de override correspondente (ex: `--barcode-field=ean` se a auto-detecção falhou em produtos).

Não tente "consertar" arquivos malformados — reporte o erro e deixe o usuário decidir.

## Exemplos

```bash
# Caso simples (estrutura padrão MongoDB-export)
/clean-orders maio.orders.json barcodes.json

# Output customizado
/clean-orders maio.orders.json barcodes.json maio.cleaned.json

# Estrutura não-padrão (Shopify-like)
/clean-orders shopify-orders.json blocklist.json --products-field=line_items --barcode-field=sku

# Só simular
/clean-orders maio.orders.json barcodes.json --dry-run
```
