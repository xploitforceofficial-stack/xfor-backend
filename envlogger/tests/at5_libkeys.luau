local out = {}
for k, v in utf8 do out[#out+1] = k end
print(table.concat(out, ","))
for k, v in math do out[#out+1] = "M:" .. k end
print(table.concat(out, ","))
