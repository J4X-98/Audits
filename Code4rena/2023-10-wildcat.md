# Wildcat Finance

**Date:** 16.10.2023-26.10.2023

**Platform:** Code4rena

# Findings summary

| Severity      | Count |
| :---          |  ---: |
| High          | 0     |
| Medium        | 1     |
| Low           | 11    |
| Non-Critical  | 8     |

# Table of Contents

| ID | Title |
| :--- | :--- |
| M-01 | [Rebasing tokens will get frozen in a closed market](#m-01-rebasing-tokens-will-get-frozen-in-a-closed-market) |
| L-01 | [Sanctioned Lenders can taint markets](#l-01-sanctioned-lenders-can-taint-markets) |
| L-02 | [Lenders can fronrun removal](#l-02-lenders-can-fronrun-removal) |
| L-03 | [Lenders can also deposit when not authorized on the controller](#l-03-lenders-can-also-deposit-when-not-authorized-on-the-controller) |
| L-04 | [No controllers can be deployed if certain tokens are chosen as `feeAsset`](#l-04-no-controllers-can-be-deployed-if-certain-tokens-are-chosen-as-feeasset) |
| L-05 | [ Rebasing tokens will lead to borrowers needing to pay a lower APR](#l-05-rebasing-tokens-will-lead-to-borrowers-needing-to-pay-a-lower-apr) |
| L-06 | [ Reserve ratio can be set to 100%](#l-06-reserve-ratio-can-be-set-to-100) |
| L-07 | [ `scaleFactor` can theoretically overflow](#l-07-scalefactor-can-theoretically-overflow) |
| L-08 | [ Misleading ERC20 queries `balanceOf()` and `totalSupply()`](#l-08-misleading-erc20-queries-balanceof-and-totalsupply) |
| L-09 | [Closed markets can't be reopened](#l-09-closed-markets-cant-be-reopened) |
| L-10 | [Choosable prefix allows borrowers to mimic other borrowers.](#l-10-choosable-prefix-allows-borrowers-to-mimic-other-borrowers) |
| L-11 | [Interest continues to accrue up to the expiry.](#l-11-interest-continues-to-accrue-up-to-the-expiry) |
| NC-01 | [ Badly named constant `BIP`](#nc-01-badly-named-constant-bip) |
| NC-02 | [ Incorrect documentation on capacity resizing](#nc-02-incorrect-documentation-on-capacity-resizing) |
| NC-03 | [ Incorrect documentation on authentication process](#nc-03-incorrect-documentation-on-authentication-process) |
| NC-04 | [ Incorrect documentation of `registerControllerFactory()`](#nc-04-incorrect-documentation-of-registercontrollerfactory) |
| NC-05 | [ Incorrect documentation of `removeControllerFactory()`](#nc-05-incorrect-documentation-of-removecontrollerfactory) |
| NC-06 | [ Documentation of functions is missing](#nc-06-documentation-of-functions-is-missing) |
| NC-07 | [ Incorrect comment in `_depositBorrowWithdraw()`](#nc-07-incorrect-comment-in-_depositborrowwithdraw) |
| NC-08 | [ `getDeployedControllers()` will not return the last index](#nc-08-getdeployedcontrollers-will-not-return-the-last-index) |

# Medium Findings

## [M-01] Rebasing tokens will get frozen in a closed market

### Impact
As per the information and documentation, the protocol does not exclude rebasing tokens, which could be used as underlying assets for newly created markets. This issue primarily pertains to rebasing tokens that increase a holder's balance over time.

When a borrower closes a market, a snapshot is taken of the current fees, interest, and other parameters, and a final scale factor is calculated for all lenders. If there is insufficient liquidity to fulfill this factor, the remaining needed tokens are transferred from the borrower to the market. Subsequently, lenders have the option to burn their market tokens to retrieve the amount of underlying assets they are entitled to based on the scaleFactor.

The problem arises when there is a arbitraril long time gap between the market's closure and the lender's withdrawal of their tokens. As rebasing tokens continue to accrue interest during this period, the market's balance keeps increasing. Unfortunately, these additional tokens cannot be retrieved from the market and remain there indefinitely. The borrower cannot withdraw anything from the market anymore, and the lenders can only withdraw based on the snapshot taken when the market was closed.

### Proof of Concept
An example proof of concept could unfold as follows:

1. A borrower creates a vault with a rebasing underlying token.
2. Lenders deposit funds into the vault.
3. The borrower utilizes the capital and at some point recoups the investment.
4. The borrower intends to repay the lenders and calls `closeMarket()`.
5. The final scale factor is calculated, and all liquidity is now in the market.
6. While lenders don't reclaim their tokens, the market's balance continues to accrue tokens.
7. When lenders claim their tokens, all newly accrued tokens remain in the market and cannot be retrieved.

### Tools Used
Manual Review

### Recommended Mitigation Steps

**Simple Solution:** The simple approach involves either excluding rebasing tokens from the protocol or adding a warning to the documentation. This warning would inform users that in this edge case, any newly accrued tokens between the market's closure and the withdrawal will be lost.

**Complex Solution:** The more intricate solution entails calculating the withdrawalScaleFactor by dividing the amount of underlying tokens in the vault by the amount of market tokens. This approach should ensure accuracy, as after closing, the market should have exactly `scaleFactor * marketToken.totalSupply()` of the underlying tokens. However, implementing this solution introduces potential new vulnerabilities and rounding issues. The decision on which solution to adopt ultimately rests with the protocol team.


# Low Findings

## [L-01] Sanctioned Lenders can taint markets

### Impact
The existing system has been carefully designed to account for OFAC sanctions. In the event that an individual is sanctioned by OFAC and either the `nukeFromOrbit()` function is triggered or the user attempts to withdraw funds, their funds are redirected to an escrow. The rationale behind this approach is to safeguard other users' funds in the market, preventing contamination that could lead to further sanctions for lenders and borrowers.

The primary issue arises when a user is sanctioned by OFAC, and one of the following two scenarios occurs (assuming `nukeFromOrbit()` was not called with the user's address):
1. The user has never had funds in the market.
2. The user does not attempt to withdraw funds following the sanction.

In both of these cases, the user retains the ability to deposit money into the market if they have been authorized by the borrower. This has the effect of tainting all funds in the market, whether due to an accidental interaction or malicious intent, where a user purposely interacts with a sanctioned address to contaminate their own address and subsequently deposits negligible amounts into a market.

### Proof of Concept
A provided gist illustrates the two distinct scenarios mentioned above:
1. In the first test case, a user who has already been approved but has never interacted with the market gets sanctioned by OFAC. Subsequently, the user interacts with the market, contaminating the other users' deposits.
2. In the second test case, a user has already deposited funds into the contract when they become sanctioned. The user refrains from attempting to withdraw their funds and deposits another token, thereby contaminating all other users with them, as they are unable to retrieve their tokens.

To test this proof of concept, it can be easily added to the test/market folder and executed using the `forge test` command.

### Tools Used
Manual Review

### Recommended Mitigation Steps
This issue can be promptly mitigated with a straightforward adjustment. To address this problem, an additional check should be introduced in the deposit functionality. This check will verify whether a user is sanctioned based on the Chainalysis oracle, and if so, it will revert the transaction when the user attempts to deposit. An adapted deposit functionality could be structured as follows:

```solidity
function depositUpTo(
uint256 amount
) public virtual nonReentrant returns (uint256 /* actualAmount */) {
	// Get current state
	MarketState memory state = _getUpdatedState();
	
	if (state.isClosed) {
	revert DepositToClosedMarket();
	}
	
	if (sentinel.isSanctioned(borrower, msg.sender)) {
	revert DepositFromSanctionedAddress();
	}

	...
}
```

This implementation would also necessitate the addition of a new custom error, namely `DepositFromSanctionedAddress`.

## [L-02] Lenders can fronrun removal

### Impact
The access to a controller's markets is controlled by the borrower who deployed the controller. The borrower is responsible for updating the authorization of lenders using the `authorizeLenders()` function of the `WildcatMarketController`. After this step, the borrower must invoke the `updateLenderAuthorization()` function, specifying the lender and market addresses they wish to update. The same process applies when a borrower wants to revoke a lender's authorization for their market. In such cases, the borrower must first call `deauthorizeLenders()` and subsequently invoke `updateLenderAuthorization()` to deauthorize the lender, preventing further deposits into the market.

The issue here is that the deauthorization process is non-atomic. Consequently, a lender can monitor the emission of the `LenderDeauthorized` event with their address and front-run the subsequent call to `updateLenderAuthorization`, thereby retaining the ability to deposit into the market. Since there is no requirement that both of these functions must be called in the same transaction, this situation can occur.

### Proof of Concept
This [gist](https://gist.github.com/J4X-98/194b48f327a70b9d3e39840b74ca9087) demonstrates the precise scenario described above. In this example, a lender monitors the emission of the `LenderDeauthorized` event and front runs the subsequent call to continue depositing into the market.

### Tools Used
Manual Review

### Recommended Mitigation Steps
To address this issue, two potential solutions are available.

**1. Atomic Removal**
Introduce atomicity by directly invoking `updateLenderAuthorization()` within `deauthorizeLenders()` with the complete list of markets. However, this approach may encounter difficulties if the list of markets becomes excessively long, making it challenging to update all of them in a single transaction.

**2. Check on deposit**
This method, while consuming more gas, safeguards against front-running issues and denial-of-service (DOS) attacks in scenarios involving numerous markets. In this mitigation approach, every call to deposit should verify if the lender is still authorized on the controller and permit the lender to deposit only if they are authorized. This would also eliminate the need for tracking authorization at the market level.

This can be achieved by adding a check like the following to the `depositUpTo()` function:

```solidity
require(IWildcatMarketController(controller).isAuthorizedLender(msg.sender), "Caller is not authorized lender");
```

## [L-03] Lenders can also deposit when not authorized on the controller
[WildcatMarketController Line 169](https://github.com/code-423n4/2023-10-wildcat/blob/main/src/WildcatMarketController.sol#L169)

**Issue Description:**

The contest description incorrectly states that "Lenders that are authorized on a given controller (i.e. granted a role) can deposit assets to any markets that have been launched through it.". However, this is not the case as borrowers need to call `updateLenderAuthorization()` when deauthorizing a lender. If a borrower forgets to call this function, the lender can be deauthorized on the controller but still deposit new funds into the market until the lender or someone else calls `updateLenderAuthorization`.

**Recommended Mitigation Steps:**

It is recommended to update the documentation to state that this is only correct if `updateLenderAuthorization()` was called afterward. If the intent is to have the functionality work as described in the contest description, an atomic removal of lenders would need to be implemented.

---
## [L-04] No controllers can be deployed if certain tokens are chosen as `feeAsset`
[WildcatMarketController Line 345](https://github.com/code-423n4/2023-10-wildcat/blob/main/src/WildcatMarketController.sol#L345)

**Issue Description:**

The `MarketControllerFactory` allows for setting an `originationFeeAsset` as well as `originationFeeAmount`, which are used to send a fee to the recipient each time a new market is deployed. When a market is deployed, the `originationFeeAmount` of the `originationFeeAsset` is transferred from the borrower to the `feeRecipient`. There is one additional check in place that verifies if the `originationFeeAsset` address is 0 and only transfers a fee if it is not zero.

```solidity
if (originationFeeAsset != address(0)) {
	originationFeeAsset.safeTransferFrom(borrower, parameters.feeRecipient, originationFeeAmount);
}
```

The issue with this implementation is that some tokens, like [LEND](https://www.coingecko.com/de/munze/aave-old), may revert in case of a zero transfer. This means that if a token like [LEND](https://www.coingecko.com/de/munze/aave-old) is set as the `originationFeeAsset`, and later on the fee is reduced to zero, this function will always fail to execute, preventing any new markets from being deployed.

Additionally, not checking for zero transfers could lead to gas waste in the case of a token that does not revert but simply transfers nothing during a zero transfer.

**Recommended Mitigation Steps:**

To fix this issue, an additional check needs to be added to the if clause, ensuring that `originationFeeAmount` is greater than zero:

```solidity
if (originationFeeAsset != address(0) && originationFeeAmount > 0) {
	originationFeeAsset.safeTransferFrom(borrower, parameters.feeRecipient, originationFeeAmount);
}
```

## [L-05]  Rebasing tokens will lead to borrowers needing to pay a lower APR

**Issue Description:**

Rebasing tokens, which are not excluded from the contest, can be used as underlying assets for markets deployed using the protocol. Rebasing tokens can be implemented in various ways, but the critical point is when the balance of addresses holding the tokens gradually increases. As borrowers/market contracts hold these tokens while they are lent, the newly accrued tokens may either be credited to the borrower, or inside the market itself, which would count as the borrower adding liquidity. This can result in the borrower needing to pay a lower Annual Percentage Rate (APR) than initially set.

**Recommended Mitigation Steps:**

This issue can be mitigated in several ways:

- **Option 1:** Disallow rebasing tokens from the protocol to prevent this situation.
- **Option 2:** Add a warning to the documentation, informing users that when lending rebasing tokens, the rebasing interest their tokens gain while inside the market will be counted as the borrower paying down their debt.
- **Option 3 (Complicated):** Implement functionality for rebasing tokens by checking the market's balance at each interaction and adding the change to a separate variable that tracks rebasing awards.

---
## [L-06]  Reserve ratio can be set to 100%
[MarketControllerFactory Line 85](https://github.com/code-423n4/2023-10-wildcat/blob/c5df665f0bc2ca5df6f06938d66494b11e7bdada/src/WildcatMarketControllerFactory.sol#L85)

**Issue Description:**

The protocol allows borrowers to set a reserve ratio that they must maintain to avoid being charged a delinquency fee. In the current implementation, this parameter can be set to 100%, rendering the entire functionality redundant, as borrowers would not be able to withdraw any funds from the market. Additionaly the market would fall into delinquency immediately after the start.

**Recommended Mitigation Steps:**

To mitigate this issue, modify the check on `maximumReserveRatioBips` to revert if `constraints.maximumReserveRatioBips >= 10000`.

---
## [L-07]  `scaleFactor` can theoretically overflow
[FeeMath Line 169](https://github.com/code-423n4/2023-10-wildcat/blob/c5df665f0bc2ca5df6f06938d66494b11e7bdada/src/libraries/FeeMath.sol#L169)

**Issue Description:**

The `scaleFactor` of a market is multiplied by the fee rate to increase the scale. In a very rare edge case, where a market has a 100% interest (e.g., a junk bond) and is renewed each year with the borrower paying lenders the full interest, the scale factor would overflow after 256 years (as the scale factor doubles every year) when it attempts to increase during the withdrawal amount calculation.

**Recommended Mitigation Steps:**

While this issue is unlikely to occur in practice, a check should be added in the withdrawal process to prevent an overflow. If an overflow is detected, lenders should be forced to withdraw with a scale factor of `uint256.max`, and the borrower should close the market.

---
## [L-08]  Misleading ERC20 queries `balanceOf()` and `totalSupply()`
[WildcatMarketToken Line 16](https://github.com/code-423n4/2023-10-wildcat/blob/c5df665f0bc2ca5df6f06938d66494b11e7bdada/src/market/WildcatMarketToken.sol#L16)
[WildcatMarketToken Line 22](https://github.com/code-423n4/2023-10-wildcat/blob/c5df665f0bc2ca5df6f06938d66494b11e7bdada/src/market/WildcatMarketToken.sol#L22)

**Issue Description:**

The `WildcatMarketToken` contract includes standard `ERC20` functions, `balanceOf()` and `totalSupply()`. However, these functions return the balance of the underlying tokens instead of the market tokens. This discrepancy between the function names and their actual behavior could lead to confusion or issues when interacting with other protocols.

**Recommended Mitigation Steps:**

To address this issue, it is recommended to rename the existing functions to `balanceOfScaled()` and `totalScaledSupply()`, and additionally implement `balanceOf()` and `totalSupply()` functions that return the balance of the market token.

---
## [L-09] Closed markets can't be reopened
[WildcatMarket Line 142](https://github.com/code-423n4/2023-10-wildcat/blob/main/src/market/WildcatMarket.sol#L142)

**Issue Description:**

Markets include a functionality where users can close markets directly, effectively transferring all funds back into the market and setting the `isClosed` parameter of the state to true. While this prevents new lenders from depositing into the market, it only allows lenders to withdraw their funds and interest. The issue is that, once a borrower uses this function, the market cannot be reopened. If the borrower wants to have another market for the same asset, they must deploy a new market with a new prefix to avoid salt collisions. If a borrower does this often it might end up in the Market names looking like "CodearenaV1234.56DAI" due to new prefixes being needed each time. Additionally the markets list would get more and more bloated. 

**Recommended Mitigation Steps:**

To mitigate this issue, borrowers should be allowed to reset a market. This would require all lenders to withdraw their funds before the reset, but it would reset all parameters, including the scale factor, allowing the market to be restarted.

---
## [L-10] Choosable prefix allows borrowers to mimic other borrowers.
[WildcatMarketBase Line 97](https://github.com/code-423n4/2023-10-wildcat/blob/main/src/market/WildcatMarketBase.sol#L97)

**Issue Description:**

When a new market is deployed, its name and prefix are generated by appending the underlying asset's name and symbol to the name and symbol prefixes provided by the borrower. In the contest description this is explained as Code4rena deploying a market and passing Code4rena as name prefix and C4 as symbol prefix.

A malicious borrower could exploit this functionality to deploy markets for other well-known assets with the same Code4rena prefixes, potentially tricking lenders into lending them money and mimicking other borrowers. This could lead to confusion and potentially fraudulent activities.

**Recommended Mitigation Steps:**

The recommended solution for this is to let each borrower choose a borrower identifier (that gets issued to them by wildcat). This in the Code4rena example would be the "Code4rena" and "C4" strings. Now the hashes (hashes instead of strings to save gas on storage cost) of those identifiers get stored onchain whenever a new borrower gets added. Whenever Code4rena deploys a new market they pass their identifier as well as a chosen Postfix which would allow them to deploy multiple markets for the same asset (for example with different interest rates). The protocol then verifies if the identifiers match the hash and revert if that is not the case. The market mame would then for example look like this "Code4renaShortTermDAI".

## [L-11] Interest continues to accrue up to the expiry.

**Issue Description:**

The whitepaper on page 12 states that interest ceases to be paid at the time when tokens get burned or when withdrawals are queued in the line "Interest ceases to be paid on Bob's deposit from the moment that the whcWETH tokens were burned, regardless of the length of the withdrawal cycle". However, the actual code behavior differs. In the Wildcat protocol's implementation, interest continues to accrue until the expiration of the withdrawal period, as evident in the code snippet below:

```solidity
if (state.hasPendingExpiredBatch()) {
  uint256 expiry = state.pendingWithdrawalExpiry;
  // Interest accrual only if time has passed since last update.
  // This condition is only false when withdrawalBatchDuration is 0.
  if (expiry != state.lastInterestAccruedTimestamp) {
    (uint256 baseInterestRay, uint256 delinquencyFeeRay, uint256 protocolFee) = state
      .updateScaleFactorAndFees(
        protocolFeeBips,
        delinquencyFeeBips,
        delinquencyGracePeriod,
        expiry
      );
    emit ScaleFactorUpdated(state.scaleFactor, baseInterestRay, delinquencyFeeRay, protocolFee);
  }
  _processExpiredWithdrawalBatch(state);
}
```

**Recommended Mitigation Steps:**

To address this issue, there are two potential courses of action:

If the intended behavior is for interest to continue accruing until the withdrawal period expires, then the documentation should be updated to align with the current code behavior.

If the documentation accurately reflects the intended interest-accrual behavior (i.e., interest should stop accruing when withdrawals are queued), then the conditional statement as shown in the code snippet should be removed from the function _getUpdatedState().


# Non-Critical Findings

## [NC-01]  Badly named constant `BIP`
[MathUtils Line 6](https://github.com/code-423n4/2023-10-wildcat/blob/main/src/libraries/MathUtils.sol#L6)

**Issue Description:**

The variable `BIP` is used to represent the maximum BIP in the protocol, where at most different rates can be set to 10,000, equivalent to 100%. The variable name could be misleading, as it may incorrectly suggest that it represents one BIP, which should be equal to 1.

**Recommended Mitigation Steps:**

To enhance clarity, rename the variable to `MAX_BIP`.

---
## [NC-02]  Incorrect documentation on capacity resizing

**Issue Description:**

The [whitepaper]((https://github.com/wildcat-finance/wildcat-whitepaper/blob/main/whitepaper_v0.2.pdf)) (on page 5) states that the "maximum capacity of a vault can be adjusted at will up or down by the borrower depending on the current need." However, the `maxCapacity` can only be reduced down to the current liquidity inside the market, as per the code. This discrepancy between the documentation and the code could lead to misunderstandings.

```solidity
if (_maxTotalSupply < state.totalSupply()) {
	revert NewMaxSupplyTooLow();
}
```

**Recommended Mitigation Steps:**

Revise the whitepaper to accurately reflect that the "maximum capacity of a vault can be adjusted at will, but only down to the current supply of the market."

---
## [NC-03]  Incorrect documentation on authentication process
[Whitepaper, page 7](https://github.com/wildcat-finance/wildcat-whitepaper/blob/main/whitepaper_v0.2.pdf)

**Issue Description:**

The whitepaper states that "Vaults query a specified controller to determine who can interact." However, the interaction rights are set by the controller on the market. There is no callback from the market to the controller, except for the initial call of the lender when authorization is null. The whitepaper should be updated to align with the actual code implementation.

**Recommended Mitigation Steps:**

Update the documentation to describe the functionality as it exists in the code.

---
## [NC-04]  Incorrect documentation of `registerControllerFactory()`
[WildcatArchController Line 106](https://github.com/code-423n4/2023-10-wildcat/blob/main/src/WildcatArchController.sol#L106)

**Issue Description:**

The documentation in the [GitBook](https://wildcat-protocol.gitbook.io/wildcat/technical-deep-dive/component-overview/wildcatarchcontroller.sol) states that the function `registerControllerFactory()` only reverts if "The controller factory has already been registered." This is inaccurate because the function also uses the `onlyOwner()` modifier, which causes it to revert if called by someone other than the owner.

**Recommended Mitigation Steps:**

Revise the documentation to include the statement "Called by someone other than the owner."

---
## [NC-05]  Incorrect documentation of `removeControllerFactory()`
[WildcatArchController Line 113](https://github.com/code-423n4/2023-10-wildcat/blob/main/src/WildcatArchController.sol#L113)

**Issue Description:**

The documentation in the GitBook](https://wildcat-protocol.gitbook.io/wildcat/technical-deep-dive/component-overview/wildcatarchcontroller.sol) states that the function `removeControllerFactory()` only reverts if "The controller factory address does not exist or has been removed." This is not entirely accurate, as the function also employs the `onlyOwner()` modifier, causing it to revert if called by someone other than the owner.

**Recommended Mitigation Steps:**

Update the documentation to include the statement "Called by someone other than the owner."

---
## [NC-06]  Documentation of functions is missing

**Issue Description:**

[The GitBook](https://wildcat-protocol.gitbook.io/wildcat/technical-deep-dive/component-overview/wildcatarchcontroller.sol) documentation lists numerous functions in the component overview section that lack descriptions. This omission can make it challenging for users and developers to understand the purpose and usage of these functions.

**Recommended Mitigation Steps:**

Provide descriptions for the missing functions in the documentation to enhance clarity and understanding.

---
## [NC-07]  Incorrect comment in `_depositBorrowWithdraw()`
[BaseMarketTest Line 71](https://github.com/code-423n4/2023-10-wildcat/blob/main/test/BaseMarketTest.sol#L71)

**Issue Description:**

Inside the function the comments state that 80% of the market assets get borrowed and 100% of withdrawal get withdrawn. This is not the case as instead the provided parameters `depositAmount`, `borrowAmount` and `withdrawalAmount` are used. There are no require statements in the function that check for these requirements 80%/100% being fulfilled by the parameters.

**Recommended Mitigation Steps:**

To address this issue, consider either adding require statements to verify that the parameters adhere to the stated percentages, or remove the comments if they no longer apply to the function's functionality.


## [NC-08]  `getDeployedControllers()` will not return the last index
[WildcatMarketControllerFactory Line 138](https://github.com/code-423n4/2023-10-wildcat/blob/main/src/WildcatMarketControllerFactory.sol#L138)

**Issue Description:**

The `getDeployedControllers()` function takes a start and end index of the controllers to be retrieved. However, due to the current implementation of the function, it only returns controllers from the start index to `end-1`. In other words, the controller at the `end` index is not included in the returned list. 

**POC:**

This simple POC can be added to the WIldcatMarketController test to check for the issue.

```solidity
function test_getControllers() external {
//Deploy 10 contracts
	for(uint256 i = 0; i < 10; i++)
	{
		controllerFactory.deployController();
	}
	  
	//Want to access 2-7 (6 controllers)
	address[] memory controllers = controllerFactory.getDeployedControllers(2, 7);
	
	//Check that the length is correct
	require(controllers.length == 5, "We have not received an incorrect number");
	
	//We only received controllers 2-6 due to the implementation
}
```

The same issue also exists in the functions `WildcatMarketController.getAuthorizedLenders()`, `WildcatMarketController.getControlledMarkets()` , `WildcatArchController.getRegisteredBorrowers()`, 
`WildcatArchController.getRegisteredControllerFactories()`, 
`WildcatArchController.getRegisteredControllers()` and
`WildcatArchController.getRegisteredMarkets()`.

**Recommended Mitigation Steps:**

To resolve this issue, the `getDeployedControllers()` function should be rewritten as follows:

```solidity
function getDeployedControllers(
uint256 start,
uint256 end
) external view returns (address[] memory arr) {
	uint256 len = _deployedControllers.length();
	end = MathUtils.min(end, len-1);
	uint256 count = end - start + 1;
	arr = new address[](count);
	for (uint256 i = 0; i < count; i++) {
		arr[i] = _deployedControllers.at(start + i);
	}
}
```

The same change should be applied to other affected functions as well.