const { readFileSync, writeFileSync } = require('node:fs');
const { wrap } = require('node:module');
const { Script } = require('node:vm');
const { setFlagsFromString } = require('node:v8');

// Match the uncompressed CommonJS Bytenode format expected by the patch.
setFlagsFromString('--no-lazy --no-flush-bytecode');
const [input, output] = process.argv.slice(2);
const script = new Script(wrap(readFileSync(input, 'utf8')));
writeFileSync(output, script.createCachedData());
