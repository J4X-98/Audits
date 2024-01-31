# Ethena Labs

**Date:** 24.10.2023-30.10.2023

**Platform:** Code4rena

# Findings summary

| Severity      | Count |
| :---          |  ---: |
| High          | 0     |
| Medium        | 1     |
| Low           | 2     |
| Non-Critical  | 2     |

# Table of Contents

| ID | Title |
| :--- | :--- |
| M-01 | [Approvals allow stakers to circumvent the blocklist](#m-01-approvals-allow-stakers-to-circumvent-the-blocklist) |
| L-01 | [Restricted users can still unstake their funds using unstake](#l-01-restricted-users-can-still-unstake-their-funds-using-unstake) |
| L-02 | [Users can only be blacklisted or removed from blacklist by the blacklist manager](#l-02-users-can-only-be-blacklisted-or-removed-from-blacklist-by-the-blacklist-manager) |
| NC-01 | [ Comment missing dash](#nc-01-comment-missing-dash) |
| NC-02 | [ Incorrect comment on `_orderBitmaps`](#nc-02-incorrect-comment-on-_orderbitmaps) |


# Medium Findings

## [M-01] Approvals allow stakers to circumvent the blocklist

### Impact
The staking functionality of the protocol is designed to restrict users from staking, unstaking, and transferring assets if they are assigned the FULL_RESTRICTED_STAKER_ROLE by the admin. However, there is a way for restricted users to potentially bypass these restrictions by exploiting the approval functionality of the underlying ERC20 shares.

The protocol's preventive measures include disallowing any transfers of tokens to or from restricted addresses, except for the burning of tokens from a restricted address. This exception is introduced to ensure that the redistributeLockedAmount() function does not consistently revert. This transfer restrictions also prevent restricted users from staking tokens. When a restricted user attempts to stake, a transfer from address(0) to the restricted user takes place, triggering a revert. This safeguard is implemented in the _beforeTokenTransfer() hook, as illustrated below:

```solidity
function _beforeTokenTransfer(address from, address to, uint256) internal virtual override {
	if (hasRole(FULL_RESTRICTED_STAKER_ROLE, from) && to != address(0)) {
		revert OperationNotAllowed();
	}
	if (hasRole(FULL_RESTRICTED_STAKER_ROLE, to)) {
		revert OperationNotAllowed();
	}
}
```

Furthermore, to prevent restricted users from unstaking their tokens, the _withdraw() function incorporates an additional requirement that the caller and the receiver of the withdrawal must not be restricted:

```solidity
if (hasRole(FULL_RESTRICTED_STAKER_ROLE, caller) || hasRole(FULL_RESTRICTED_STAKER_ROLE, receiver)) {
	revert OperationNotAllowed();
}
```

While this system may appear robust, there is still a potential vulnerability that allows restricted users to unstake and retrieve their stUSDe tokens. To exploit this vulnerability, a malicious user must maintain a second address under their control that is not restricted. They then grant approval to this unrestricted address for all their shares. In the event the user is restricted, they can use the unrestricted address to withdraw their shares. This circumvents the transfer hooks restrictions, as the shares are only burned, effectively transferring to address 0, which is allowed. Moreover, the restrictions within the _withdraw function do not activate in this scenario since neither the caller nor the receiver are restricted.

This functionality can be exploited in the case of there being a cooldown as well as in the case of there being no cooldown.

### Proof of Concept
To validate the issue I provide 2 test cases, one with a set cooldown and one without a set cooldown, that simulate the vulnerability. The test cases follows these steps:

A malicious user stakes tokens.
1. The malicious user approves their second address.
2. The malicious user gets blacklisted.
3. The malicious user uses their second address to withdraw all shares.
4. The malicious user transfers all funds from the second address or silo back to themselves.

<details>

```solidity
function testCircumventBlocklistWithoutCooldown() public {
  uint256 amount = 100 ether;

  //Cooldown is set to 0
  vm.startPrank(owner);
  stakedUSDe.setCooldownDuration(0);
  vm.stopPrank();

  //Alice has 100 USD
  usdeToken.mint(alice, amount);

  vm.startPrank(alice);

  //Alice deposits 100 USD
  usdeToken.approve(address(stakedUSDe), amount);
  stakedUSDe.deposit(amount, alice);

  //Alice gives bob (her second EOA) an approval of all her shares
  stakedUSDe.approve(bob, amount);
  vm.stopPrank();

  vm.startPrank(owner);
  //Alice gets blacklisted
  stakedUSDe.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
  vm.stopPrank();

  //Now alice retrieves her tokens using her second EOA
  vm.startPrank(bob);
  stakedUSDe.redeem(amount, bob, alice);
  require(usdeToken.balanceOf(bob) == amount, "Bob should have 100 USDe");

  //As the USDe token does not include a blocklist she can now transfer the tokens back to herself
  usdeToken.transfer(alice, amount);
  require(usdeToken.balanceOf(alice) == amount, "Alice should have 100 USDe");

  //Alice has now circumvented the blocklist, succesfully unstaked and retrieved her tokens
  vm.stopPrank();
}

function testCircumventBlocklistWithCooldown() public {
  uint256 amount = 100 ether;

  //Cooldown is set to 0
  vm.startPrank(owner);
  stakedUSDe.setCooldownDuration(1 days);
  vm.stopPrank();

  //Alice has 100 USD
  usdeToken.mint(alice, amount);

  vm.startPrank(alice);

  //Alice deposits 100 USD
  usdeToken.approve(address(stakedUSDe), amount);
  stakedUSDe.deposit(amount, alice);

  //Alice gives bob (her second EOA) an approval of all her shares
  stakedUSDe.approve(bob, amount);
  vm.stopPrank();

  vm.startPrank(owner);
  //Alice gets blacklisted
  stakedUSDe.grantRole(FULL_RESTRICTED_STAKER_ROLE, alice);
  vm.stopPrank();

  //Now alice starts withdrawing her tokens using her second EOA
  vm.startPrank(bob);
  stakedUSDe.cooldownAssets(amount, alice);
  vm.stopPrank();

  vm.warp(block.timestamp + 1 days);

  //Alice can just call the silo herself 
  vm.startPrank(alice);
  stakedUSDe.unstake(alice);
  vm.stopPrank();

  //Alice has now circumvented the blocklist, succesfully unstaked and retrieved her tokens
  require(usdeToken.balanceOf(alice) == amount, "Alice should have 100 USDe");
}
```

</details>

The testcases can be run by adding them to the StakedUSDeV2.blacklist.t.sol file and running using forge test.

### Tools Used
Manual Review

### Recommended Mitigation Steps
This issue can be easily resolved by implementing an additional check for whether the _owner (i.e., the user who granted approval) is restricted within the _withdraw() function. If the owner is restricted, the function should revert. This check can be implemented as follows:

```solidity
function _withdraw(address caller, address receiver, address _owner, uint256 assets, uint256 shares)
internal
override
nonReentrant
notZero(assets)
notZero(shares)
{
	if (hasRole(FULL_RESTRICTED_STAKER_ROLE, caller) || hasRole(FULL_RESTRICTED_STAKER_ROLE, receiver) || hasRole(FULL_RESTRICTED_STAKER_ROLE, _owner)) {
		revert OperationNotAllowed();
	}
	
	super._withdraw(caller, receiver, _owner, assets, shares);
	_checkMinShares();
}
```

# Low Findings

## [L-01] Restricted users can still unstake their funds using unstake

### Impact
The staking contract incorporates the capability to assign the role of `FULL_RESTRICTED_STAKER_ROLE` to a user. This role is typically assigned when the protocol becomes aware that the user is in control of stolen or sanctioned funds. A user with this role should not be able to unstake their `stUSDe` and withdraw `USDe` funds from the staking contract. However, a vulnerability in the current functionality allows a user to exploit this situation.

In the existing system, if a user invokes either `cooldownAssets()` or `cooldownShares()` before being designated as a restricted user and subsequently calls `unstake` while already restricted, the user can still withdraw their `USDe` from the staking contract.

### Proof of Concept
This [gist](https://gist.github.com/J4X-98/d0e7986ab32e00f28f0d92a09d81f096) provides a test case that illustrates the vulnerability described above. The test case follows these phases:

1. A malicious user stakes `USDe`.
2. The malicious user calls a cooldown-affected function to initiate withdrawal.
3. The malicious user becomes restricted.
4. The malicious user is still able to withdraw the funds.

### Tools Used
Manual Review

### Recommended Mitigation Steps
To address this issue, it is recommended to add an additional check in the `unstake` function to verify if the `msg.sender` or the receiver has the `FULL_RESTRICTED_STAKER_ROLE`. If either the sender or receiver has this role, any call to `unstake` should revert. This can be implemented by adding the following requirement to the `unstake` function:

```solidity
if if (hasRole(keccak256("FULL_RESTRICTED_STAKER_ROLE"), msg.sender) || hasRole(keccak256("FULL_RESTRICTED_STAKER_ROLE"), receiver)) {
	revert OperationNotAllowed();
}
```

## [L-02] Users can only be blacklisted or removed from blacklist by the blacklist manager

**Issue Description:**

The NatSpec documentation for the functions `addToBlacklist()` and `removeFromBlacklist()` inaccurately states, "Allows the owner (`DEFAULT_ADMIN_ROLE`) and blacklist managers to blacklist addresses." In practice, the `onlyRole(BLACKLIST_MANAGER_ROLE)` modifier permits only the holder of the `BLACKLIST_MANAGER_ROLE` to blacklist addresses, not the holder of the `DEFAULT_ADMIN_ROLE` role.

**Recommended Mitigation Steps:**

If the intended functionality aligns with the implemented code, the NatSpec description should be updated to reflect this and state that only blacklist managers can blacklist addresses.

If the intention is for both the holders of the `DEFAULT_ADMIN_ROLE` and `BLACKLIST_MANAGER_ROLE` to be able to call these functions, the require statement needs to be modified as follows:

```solidity
function addToBlacklist(address target, bool isFullBlacklisting)
external
notOwner(target)
{
	require(hasRole(BLACKLIST_MANAGER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender))
	bytes32 role = isFullBlacklisting ? FULL_RESTRICTED_STAKER_ROLE : SOFT_RESTRICTED_STAKER_ROLE;
	_grantRole(role, target);
}
```

```solidity
function removeFromBlacklist(address target, bool isFullBlacklisting)
external
notOwner(target)
{
	require(hasRole(BLACKLIST_MANAGER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender))
	bytes32 role = isFullBlacklisting ? FULL_RESTRICTED_STAKER_ROLE : SOFT_RESTRICTED_STAKER_ROLE;
	_revokeRole(role, target);
}
```

---


# Non-Critical

## [NC-01]  Comment missing dash
[EthenaMinting Line 68](https://github.com/code-423n4/2023-10-ethena/blob/main/contracts/EthenaMinting.sol#L68)

**Issue Description:**

The comment "// @notice custodian addresses" does not conform to the established style in the document, which uses three dashes before each `@notice`.

**Recommended Mitigation Steps:**

Revise the comment to adhere to the document's style by using three dashes before `@notice`, like this: "/// @notice custodian addresses."

---

## [NC-02]  Incorrect comment on `_orderBitmaps`
[EthenaMinting Line 78](https://github.com/code-423n4/2023-10-ethena/blob/main/contracts/EthenaMinting.sol#L78)

**Issue Description:**

The comment "/// @notice user deduplication" inaccurately describes the functionality of the variable `_orderBitmaps`. The variable is intended to track nonces for each user, not user deduplication.

**Recommended Mitigation Steps:**

Update the comment to accurately describe the functionality of the variable, as follows: "/// @notice user -> nonce deduplication."