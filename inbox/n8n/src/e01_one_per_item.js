// E01 · One per message — after the uploads, one item per message to hand to E02.
const seen = new Set();
const out = [];
for (const i of $input.all()) {
  const id = i.json.itemId ?? $('Plan uploads').all()[i.pairedItem?.item ?? 0]?.json.itemId;
  if (id && !seen.has(String(id))) { seen.add(String(id)); out.push({ json: { itemId: String(id) } }); }
}
return out;
