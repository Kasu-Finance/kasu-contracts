import { ethers } from 'hardhat';
import fs from 'fs';
import path from 'path';

export function parseKasuError(error: any) {
    console.error('Error in transaction');
    return parseError(error, getKasuAbis());
}

function getKasuAbis(): any[] {
    const jsonPaths = findJsonFiles(`${__dirname}/../../artifacts/src`);
    return jsonPaths
        .flatMap((it) => parseJsonFile(it)['abi'])
        .filter((it) => it.type === 'error');
}

function parseError(error: any, abis: any): void {
    if (hasKey(error, 'data')) {
        // decoding error based on ABI
        const interfaces = new ethers.Interface(abis);
        const parsedError = interfaces.parseError(error.data);
        if (!parsedError) {
            console.error(`Could not parse error.`, error.data);
            throw error;
        }
        console.error(`Error name:`, parsedError.name);
        console.error(`Error args:`, parsedError.args);
    } else {
        console.error(error);
        throw new Error('Unknown error: Error object has no data attribute');
    }
}

function hasKey<O extends object>(obj: O, key: keyof any): key is keyof O {
    return key in obj;
}

function findJsonFiles(rootDirectory: string): string[] {
    let jsonFiles: string[] = [];

    function searchDirectory(directory: string) {
        const entries = fs.readdirSync(directory, { withFileTypes: true });

        for (const entry of entries) {
            const fullPath = path.join(directory, entry.name);

            if (entry.isDirectory()) {
                searchDirectory(fullPath);
            } else if (entry.isFile()) {
                if (
                    entry.name.endsWith('.json') &&
                    !entry.name.endsWith('.dbg.json')
                ) {
                    jsonFiles.push(fullPath);
                }
            }
        }
    }

    searchDirectory(rootDirectory);
    return jsonFiles;
}

function parseJsonFile(filePath: string): any {
    const fileContent = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(fileContent);
}
