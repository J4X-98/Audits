# Full Send Metacard

## Contract

I decided to look at this contract, as the underlying NFTs were very hyped around the youtube community (about 1 year ago) and i thought it would be an interesting contract to look at.

## Security measures

The contract implemented multiple security measures that were correctly implemented.

### Usage of constants for the SUPPLY values

### Correct Access restriction

## Findings

### [HIGH] Multiple mints for whitelist

According to the comments inside the contract the mintWhitelist() function should mint 1 token per whitelisted address. There is no check for this occuring, just for 0 < numberOfTokens <= 5, the wallets held NFTs notexceeding 10 as well as the total supply not exceeding MAX_WHITELIST_SUPPLY after the call. So any whitelisted address could mint (at max) 3000 NFTs if it was the first. This contradicts the documentation in the code:

```
@dev mints 1 token per whitelisted address, does not charge a fee
```

This resulted in 1132 addresses getting more than 1 NFT from the whitelist, and 147 address getting 10 NFTs. In addition only 2000, instead of 3000 addresses were able to claim a whitelist NFT. More info can be found in whitelist_abusers.csv.

POC: multiple_whitelist_mint.sol

### [HIGH] No free mints for whitelist

According to the documentation in the code the whitelisted minter should not need to pay for the minting, nevertheless the function requires the same payment (0.75 eth) per minted NFT. This is induced by adding the isCorrectPayment(cost, numberOfTokens) modifier in the head of the function, which will revert if not exatly 0.75 eth per NFT are transferred.

POC: no_free_mint.sol

### [LOW] Reduced amount of Firends&Family mints

Due to the owner minting the first 101 NFTs for himself, instead of 500 NFTs being available to the addresses inside the friendsFamilyMerkleTreee, only 399 are available, as by then the MAX_FRIENDS_SUPPLY is reached


### [GAS] Unneccesary Reentrancy Guard

The minting functions(mintFriendsFamily(), mintWhitelist(), mint()) are all secured against reentrancy attacks by using the nonReentrant modifier from OpenZeppelin's ReentrancyGuard (@openzeppelin/contracts/utils/Context.sol). This actually should not be needed as none of these functions does any external calls.

### [GAS] Unneccesary variable _collectionURI

This variable is not set / used in the deployed contract & could be removed.

### [INFO] Wrong error message in mintFriendsFamily()

If the amount exceeds the MAX_FRIENDS_SUPPLY (500) the error message "Purchase would exceed max number of whitelist tokens" is emitted, which can be misleading as it is the same error message that the mintWhitelist() dunctions emits in case of going over the threshold. This error message should be adapted to reflect the error that is happening. For example "Purchase would exceed max number of friends&family tokens"

### [INFO] Unlimited Owner minting

The function mintToAddress() allows the owner to mint an arbitrary amount of NFTs to a arbitrary address (up until the max_amount of NFTs is reached). This function was called once in tx 0xc456d6709ed68e049d9658bfeb4a8e148942043a2a9701011d73f2b86cb921df, giving NFT 1-101 to the address 0x8Fe22c83Ded0d0B5296445e628CB4B8F727dA228. In this case the owner used this to give the first 100 NFTs to himself, which is ok, but this could have also been abused badly, as he could also ahve given a lot to himself. To keep it more transaprent the developer could have hardocded that the first 100 NFTs get sent to the given address at the start and then it is not possible to mint any more NFTs as the owner.

POC: unlimited_owner_mint.sol

### [INFO] Easy Ownership transfer possible

As the contract uses the OpenZeppelin ownable.sol the ownership of the whole contract can easily be transferred to another address.

### [INFO] Strange Twitter posts

The twitter account for the metacard (@_metacard_j) includes some strange twitter posts from 2014 (looks a bit unprofessional).

### [INFO] Website down

The website mentioned on multiple blog posts (https://thefullsendnft.com) can not be reached anymore. A redirect to https://www.metacard.io/ would be a good idea to make it seem more professional.



