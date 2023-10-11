import {builtinModules} from 'node:module';
import fs from 'node:fs';
const pkg = JSON.parse(fs.readFileSync(process.env.PWD+'/package.json').toString());
if(!pkg.dependencies) pkg.dependencies={};
const file = process.env.DEST_FILE ? process.env.DEST_FILE : pkg.exports && pkg.exports.require ? pkg.exports.require : 'index.cjs';

const config = {
	input: process.env.START_FILE,
	output: [{
		format: 'cjs',
		file: file,
		interop: 'auto',
		freeze: false,
		strict: false
	}],
	external: [
		...Object.keys(pkg.dependencies),
		...builtinModules,
	],
}

export default config;
