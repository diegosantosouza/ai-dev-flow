# Skill: `/clean-orders`

Remove produtos de um arquivo JSON de pedidos com base em uma lista de barcodes/EANs.

## Uso

```bash
/clean-orders <input.json> <barcodes.json> [output.json] [flags]
```

### Argumentos

| # | Nome | Obrigatório | Descrição |
|---|------|-------------|-----------|
| 1 | input | sim | Arquivo JSON de pedidos (array no nível raiz) |
| 2 | barcodes | sim | Lista de barcodes (array de strings ou objetos) |
| 3 | output | não | Default: `<input>.cleaned.json` no mesmo diretório |

### Flags

| Flag | Default | Descrição |
|------|---------|-----------|
| `--barcode-field=X` | auto | Força o nome do campo de barcode no produto |
| `--products-field=X` | auto | Força o nome do array de produtos no pedido |
| `--dry-run` | off | Não escreve output, só reporta |
| `--help` | — | Mostra ajuda |

### Auto-detecção

**Campo de barcode** — tenta nesta ordem: `barcode`, `ean`, `ean13`, `gtin`, `gtin13`, `upc`, `code`, `sku`.

**Array de produtos** — tenta nesta ordem: `products`, `items`, `lineItems`, `orderItems`, `lines`.

## Formatos aceitos para `barcodes.json`

```json
["7891150066175", "7891150068537"]
```

ou

```json
[
  {"barcode": "7891150066175"},
  {"barcode": "2001020000016", "description": "comida japonesa"}
]
```

ou (com override `--barcode-field=ean`):

```json
[{"ean": "7891150066175"}]
```

## Comportamento

- Produtos cujo barcode está na lista são removidos do array do pedido.
- Se um pedido ficar **sem nenhum produto** após a filtragem, o pedido inteiro é removido do output.
- Demais pedidos são preservados intactos.
- Match é por **string exata** — `076840376810` e `76840376810` são tratados como barcodes distintos.

## Códigos de saída

| Código | Significado |
|--------|-------------|
| 0 | Sucesso |
| 1 | Erro de leitura/parse/detecção |
| 2 | Argumentos faltando |

## Exemplos

```bash
# Padrão MongoDB-export
/clean-orders maio.orders.json barcodes.json

# Output customizado
/clean-orders maio.orders.json barcodes.json maio.cleaned.json

# Shopify-like
/clean-orders orders.json block.json --products-field=line_items --barcode-field=sku

# Simulação
/clean-orders orders.json blocklist.json --dry-run
```

## Estrutura

```
~/.claude/skills/clean-orders/
├── SKILL.md           # Instruções para o Claude executar a skill
├── README.md          # Este arquivo
└── scripts/
    └── clean.js       # Worker Node.js (zero dependências)
```
