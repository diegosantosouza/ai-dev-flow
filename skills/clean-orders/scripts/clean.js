#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const BARCODE_CANDIDATES = ['barcode', 'ean', 'ean13', 'gtin', 'gtin13', 'upc', 'code', 'sku'];
const PRODUCTS_CANDIDATES = ['products', 'items', 'lineItems', 'orderItems', 'lines'];

function parseArgs(argv) {
  const positional = [];
  const flags = {};
  for (const a of argv.slice(2)) {
    if (a.startsWith('--')) {
      const [k, ...rest] = a.slice(2).split('=');
      flags[k] = rest.length ? rest.join('=') : true;
    } else if (a !== '') {
      positional.push(a);
    }
  }
  return { positional, flags };
}

function loadJson(p, label) {
  if (!fs.existsSync(p)) {
    console.error(`ERRO: arquivo ${label} não encontrado: ${p}`);
    process.exit(1);
  }
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch (e) {
    console.error(`ERRO ao parsear ${label} (${p}): ${e.message}`);
    process.exit(1);
  }
}

function pickField(sample, candidates, override, label) {
  if (override) {
    if (sample && typeof sample === 'object' && override in sample) return override;
    console.error(`ERRO: campo override "${override}" não existe no ${label}.`);
    console.error(`Amostra: ${JSON.stringify(sample).slice(0, 300)}`);
    process.exit(1);
  }
  for (const c of candidates) {
    if (sample && typeof sample === 'object' && c in sample) return c;
  }
  return null;
}

function extractBarcodeSet(list, overrideField) {
  if (!Array.isArray(list)) {
    console.error('ERRO: lista de barcodes não é um array.');
    process.exit(1);
  }
  if (list.length === 0) {
    console.error('AVISO: lista de barcodes vazia. Nada a fazer.');
    process.exit(0);
  }
  if (typeof list[0] === 'string' || typeof list[0] === 'number') {
    return new Set(list.map(v => String(v)));
  }
  const field = pickField(list[0], BARCODE_CANDIDATES, overrideField, 'item da lista de barcodes');
  if (!field) {
    console.error(`ERRO: não detectei campo de barcode na lista. Tentei: ${BARCODE_CANDIDATES.join(', ')}`);
    console.error(`Use --barcode-field=NOME para forçar.`);
    process.exit(1);
  }
  return new Set(list.map(item => String(item?.[field] ?? '')).filter(v => v.length > 0));
}

function detectProductsField(orders, overrideField) {
  if (overrideField) return overrideField;
  for (const o of orders) {
    if (!o || typeof o !== 'object') continue;
    for (const c of PRODUCTS_CANDIDATES) {
      if (Array.isArray(o[c])) return c;
    }
  }
  return null;
}

function detectProductBarcodeField(orders, productsField, overrideField) {
  if (overrideField) return overrideField;
  for (const o of orders) {
    const arr = o?.[productsField];
    if (!Array.isArray(arr)) continue;
    for (const p of arr) {
      if (p && typeof p === 'object') {
        for (const c of BARCODE_CANDIDATES) {
          if (c in p) return c;
        }
      }
    }
  }
  return null;
}

function defaultOutputPath(inputPath) {
  const dir = path.dirname(inputPath);
  const ext = path.extname(inputPath);
  const base = path.basename(inputPath, ext);
  return path.join(dir, `${base}.cleaned${ext || '.json'}`);
}

function main() {
  const { positional, flags } = parseArgs(process.argv);

  if (flags.help || flags.h) {
    console.log('Uso: clean-orders <input.json> <barcodes.json> [output.json]');
    console.log('Flags opcionais:');
    console.log('  --barcode-field=NOME    força o nome do campo barcode (default: auto-detect)');
    console.log('  --products-field=NOME   força o nome do array de produtos (default: auto-detect)');
    console.log('  --dry-run               não escreve o output, só reporta');
    process.exit(0);
  }

  if (positional.length < 2) {
    console.error('ERRO: argumentos insuficientes.');
    console.error('Uso: clean-orders <input.json> <barcodes.json> [output.json]');
    process.exit(2);
  }

  const [inputPath, barcodesPath, outputArg] = positional;
  const outputPath = outputArg || defaultOutputPath(inputPath);

  const orders = loadJson(inputPath, 'input');
  const barcodesData = loadJson(barcodesPath, 'barcodes');

  if (!Array.isArray(orders)) {
    console.error('ERRO: input precisa ser um array JSON de pedidos no nível raiz.');
    process.exit(1);
  }

  const barcodeSet = extractBarcodeSet(barcodesData, flags['barcode-field']);

  const productsField = detectProductsField(orders, flags['products-field']);
  if (!productsField) {
    console.error(`ERRO: não detectei array de produtos nos pedidos. Tentei: ${PRODUCTS_CANDIDATES.join(', ')}`);
    console.error(`Use --products-field=NOME para forçar.`);
    process.exit(1);
  }

  const productBarcodeField = detectProductBarcodeField(orders, productsField, flags['barcode-field']);
  if (!productBarcodeField) {
    console.error(`ERRO: não detectei campo de barcode nos produtos. Tentei: ${BARCODE_CANDIDATES.join(', ')}`);
    console.error(`Use --barcode-field=NOME para forçar.`);
    process.exit(1);
  }

  let removedProducts = 0;
  let removedOrders = 0;
  let affectedOrders = 0;
  let totalOriginalProducts = 0;

  const cleaned = [];
  for (const order of orders) {
    if (!order || typeof order !== 'object') {
      cleaned.push(order);
      continue;
    }
    const products = order[productsField];
    if (!Array.isArray(products)) {
      cleaned.push(order);
      continue;
    }
    totalOriginalProducts += products.length;
    const before = products.length;
    const filtered = products.filter(p => {
      const bc = String(p?.[productBarcodeField] ?? '');
      return !barcodeSet.has(bc);
    });

    if (filtered.length === before) {
      cleaned.push(order);
      continue;
    }

    removedProducts += (before - filtered.length);
    affectedOrders++;

    if (filtered.length === 0) {
      removedOrders++;
      continue;
    }

    cleaned.push({ ...order, [productsField]: filtered });
  }

  if (!flags['dry-run']) {
    fs.writeFileSync(outputPath, JSON.stringify(cleaned, null, 2));
  }

  console.log('=== CLEAN-ORDERS — Sumário ===');
  console.log(`Input:           ${inputPath}`);
  console.log(`Barcodes:        ${barcodesPath} (${barcodeSet.size} barcodes únicos)`);
  console.log(`Output:          ${flags['dry-run'] ? '(dry-run, não escrito)' : outputPath}`);
  console.log(`Campo products:  "${productsField}"  ${flags['products-field'] ? '(override)' : '(auto)'}`);
  console.log(`Campo barcode:   "${productBarcodeField}"  ${flags['barcode-field'] ? '(override)' : '(auto)'}`);
  console.log('');
  console.log(`Pedidos no input:               ${orders.length}`);
  console.log(`Produtos no input:              ${totalOriginalProducts}`);
  console.log(`Pedidos afetados:               ${affectedOrders}`);
  console.log(`Pedidos removidos (ficaram vazios): ${removedOrders}`);
  console.log(`Produtos removidos:             ${removedProducts}`);
  console.log(`Pedidos no output:              ${cleaned.length}`);
}

main();
