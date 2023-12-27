## Functional Contract Workflows

### Test Case 1
Description
Four users in two years period lock KSU, claim their rewards and unlock.

Steps:
- Admin adds 300 KSU to Lock Bonus Contract
- Alice locks 100 KSU for 30d
- Bob locks 400 KSU for 180d
- A reward of 500 USC is emitted to Lock Contract
- 30d pass
- Carol locks 500 KSU for 720d
- Alice collect her rewards - USDC
- Alice unlocks 50 KSU of her locked amount - KSU
- A reward of 200 USC is emitted to Lock Contract
- David locks 500 KSU for 360d
- Alice locks 800 KSU for 180d
- A reward of 600 USC is emitted to Lock Contract
- 180d pass
- Bob collect his rewards - USDC
- Bob unlocks 200 KSU of his locked amount - KSU
- A reward of 400 USC is emitted to Lock Contract
- 360d pass
- David collect his rewards - USDC
- David unlocks all of his locked amount - KSU
- 360d pass
- Carol collects her rewards - USDC
- Everyone unlocks
- Everyone claims