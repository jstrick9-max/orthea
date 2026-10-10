# Turns a Budibase query file into SQL with the given values (as Budibase does with parameters).
import sys,re,json
sql=open(sys.argv[1]).read(); vals=json.loads(sys.argv[2])
def lit(v): return "NULL" if v is None else "'"+str(v).replace("'","''")+"'"
print(re.sub(r"\{\{\s*(\w+)\s*\}\}", lambda m: lit(vals.get(m.group(1),"")), sql))
