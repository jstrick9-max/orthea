// Flags SQL that Budibase 3.37 (integrations/queries/sql.ts interpolateSQL) would mis-parameterise:
// an odd apostrophe (e.g. "patient's" in a comment) makes it think a {{ binding }} sits inside a
// '...' string, and a {{ binding }} written in a comment becomes an untyped $n.
// Either gives "could not determine data type of parameter $1".
// Usage: node consult/budibase/check-sql.js <file.sql>...   (exit 1 if any file is bad)
const fs = require("fs");
let bad = 0;
for (const f of process.argv.slice(2)) {
  const sql = fs.readFileSync(f, "utf8");
  const blocks = sql.match(/{{3}[^{}]*}{3}|{{2}[^{}]*}{2}/g) || [];
  const strings = sql.match(/'[^']*'/g) || [];
  const inString = blocks.filter(b => strings.some(s => s.includes(b)));
  const inComment = sql.split("\n").filter(l => /--.*{{/.test(l));
  if (inString.length || inComment.length) {
    bad = 1;
    console.log("BAD " + f);
    [...new Set(inString)].forEach(b => console.log("  treated as inside a '...' string: " + b));
    inComment.forEach(l => console.log("  binding in a comment: " + l.trim()));
  }
}
if (!bad) console.log("ok");
process.exit(bad);
