const LOCAL_NETWORKS = new Set(['localhost', 'hardhat']);

/**
 * Throws an error if the current network is not a local network.
 * Use this at the start of dev-only scripts to prevent accidental execution on production networks.
 */
export function requireLocalNetwork(networkName: string): void {
    if (!LOCAL_NETWORKS.has(networkName)) {
        throw new Error(
            `This script can only be run on local networks (localhost, hardhat). ` +
            `Current network: ${networkName}`,
        );
    }
}

/**
 * Get a required environment variable or throw an error.
 */
export function requireEnv(name: string): string {
    const value = process.env[name];
    if (!value) {
        throw new Error(
            `Missing required environment variable: ${name}`,
        );
    }
    return value;
}

/**
 * Get an optional environment variable with a default value.
 */
export function optionalEnv(name: string, defaultValue: string): string {
    return process.env[name] ?? defaultValue;
}

/**
 * Get a required environment variable and parse it as a BigInt.
 */
export function requireEnvBigInt(name: string): bigint {
    const value = requireEnv(name);
    return BigInt(value);
}

/**
 * Get a required environment variable and parse it as a number.
 */
export function requireEnvNumber(name: string): number {
    const value = requireEnv(name);
    const parsed = Number(value);
    if (isNaN(parsed)) {
        throw new Error(
            `Environment variable ${name} must be a valid number, got: ${value}`,
        );
    }
    return parsed;
}
