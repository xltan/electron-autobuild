const { strictEqual } = require('node:assert');
const { readFileSync } = require('node:fs');
const { wrap } = require('node:module');
const { Script } = require('node:vm');
const { setFlagsFromString } = require('node:v8');

setFlagsFromString('--no-lazy --no-flush-bytecode');
const [input, cache] = process.argv.slice(2);
const script = new Script(wrap(readFileSync(input, 'utf8')), { cachedData: readFileSync(cache) });
strictEqual(script.cachedDataRejected, false, 'Electron rejected this code cache');
