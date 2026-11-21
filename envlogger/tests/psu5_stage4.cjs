'use strict';

const fs = require('fs');
const path = require('path');
const lines = fs.readFileSync(path.join(__dirname, '..', '..', 'Samples', 'PSU', 'v5', '_rebuilt_lineated.lua'), 'utf8').split('\n');
console.log('total lines:', lines.length);
console.log('=== lines 115-130:');
for (let i = 114; i < 130 && i < lines.length; i++) {
    console.log(String(i + 1).padStart(4), JSON.stringify(lines[i]));
}
