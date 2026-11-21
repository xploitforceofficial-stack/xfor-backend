'use strict';

const fs = require('fs');
const path = require('path');
const head = fs.readFileSync(path.join(__dirname, '..', '..', 'Samples', 'PSU', 'v5', '_rebuilt_lineated.lua'), 'utf8').split('\n').slice(0, 30).join('\n');
console.log('=== lineated head:');
console.log(head);
