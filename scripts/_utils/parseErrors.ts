import { ethers } from 'hardhat';
import * as AcceptedRequestsCalculationAbi from '../../artifacts/src/core/clearing/AcceptedRequestsCalculation.sol/AcceptedRequestsCalculation.json';
import * as AcceptedRequestsExecutionAbi from '../../artifacts/src/core/clearing/AcceptedRequestsExecution.sol/AcceptedRequestsExecution.json';
import * as ClearingCoordinatorAbi from '../../artifacts/src/core/clearing/ClearingCoordinator.sol/ClearingCoordinator.json';
import * as ClearingStepsAbi from '../../artifacts/src/core/clearing/ClearingSteps.sol/ClearingSteps.json';
import * as PendingRequestsPriorityCalculationAbi from '../../artifacts/src/core/clearing/PendingRequestsPriorityCalculation.sol/PendingRequestsPriorityCalculation.json';

export function parseKasuError(error: any): void {
    console.error('Error in transaction');
    parseError(error, getKasuAbis());
}

function getKasuAbis(): any[] {
    const kasuAbis = [
        ...AcceptedRequestsCalculationAbi.abi,
        ...AcceptedRequestsExecutionAbi.abi,
        ...ClearingCoordinatorAbi.abi,
        ...ClearingStepsAbi.abi,
        ...PendingRequestsPriorityCalculationAbi.abi,
    ];
    return kasuAbis;
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
