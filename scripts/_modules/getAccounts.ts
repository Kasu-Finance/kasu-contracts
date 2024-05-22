import * as hre from 'hardhat';
import * as dotenv from 'dotenv';
import { Signer, Wallet } from 'ethers';

export async function getAccounts(networkName: string) {
    const envPath = `${__dirname}/../_env/.${networkName}.env`;
    dotenv.config({ path: envPath });

    const signers: Signer[] = await hre.ethers.getSigners();

    // replace with env vars
    const deployerKey = process.env.DEPLOYER_KEY ?? '';
    const adminKey = process.env.ADMIN_KEY ?? '';

    if (deployerKey) signers[0] = new Wallet(deployerKey, hre.ethers.provider);
    if (adminKey) signers[1] = new Wallet(adminKey, hre.ethers.provider);

    // const addresses = await Promise.all(
    //     signers.map(async (it) => await it.getAddress()),
    // );
    // console.log(addresses);
    return signers;
}
