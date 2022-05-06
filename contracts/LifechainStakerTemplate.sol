//SPDX-License-Identifier: MIT License
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

//Fees for staking:
// 1.5%  Staking Pool Rewards
// 1.5%  Token Burn Fee
//Fees are paid both upon staking and unstaking from the pool.

pragma solidity ^0.8.0;

contract LifechainStakerTemplate is ERC20 {
    ERC20 private nativeToken;
    StakerBag[] private stakes;
    address private distributor;
    uint256 private stakingRewardsBag;
    address private burnAddress = 0x000000000000000000000000000000000000dEaD;

    constructor(address _NativeTokenAddress, address _distributorAddress)
        ERC20("Staked Lifechain Token", "SLCT")
    {
        nativeToken = ERC20(_NativeTokenAddress);
        stakingRewardsBag = 0;
        distributor = _distributorAddress;
    }

    // The StakerBag struct allows for simple calculations of the staker's contributions
    struct StakerBag {
        uint256 startTime;
        uint256 stopTime;
        uint256 stakedTokens;
        address ownerAddress;
    }

    function getStakingRewardsBag()
        external
        view
        returns (uint256 totalRewards)
    {
        totalRewards = stakingRewardsBag;
    }

    function getStake(uint256 stakeIndex)
        external
        view
        returns (StakerBag memory selectedBag)
    {
        selectedBag = stakes[stakeIndex];
    }

    function getStakeValue(uint256 index, uint256 endTime)
        public
        view
        returns (uint256 bagValue)
    {
        StakerBag memory selectedBag = stakes[index];
        bagValue = 0;
        if (selectedBag.stopTime == 0) {
            bagValue =
                ((endTime - selectedBag.startTime) / 86400) *
                selectedBag.stakedTokens;
        } else {
            bagValue =
                ((selectedBag.stopTime - selectedBag.startTime) / 86400) *
                selectedBag.stakedTokens;
        }
    }

    //This function is temporarily public for testing purposes
    function stakeWithTimeParameters(
        uint256 startTime,
        uint256 stopTime,
        uint256 _stakedTokenAmount
    )
        public
        returns (
            uint256 burnFeePaid,
            uint256 stakingFeePaid,
            uint256 sLCTMinted
        )
    {
        //A. Check for a sufficient balance and send vlr to staking contract
        require(
            nativeToken.balanceOf(msg.sender) >= (_stakedTokenAmount),
            "Insufficient enterprise token balance"
        );

        //B. Calculate fees
        stakingFeePaid = (_stakedTokenAmount * 15) / 1000;
        stakingRewardsBag += stakingFeePaid; //increment the staking rewards fee bag
        burnFeePaid = (_stakedTokenAmount * 15) / 1000;

        //C. Mint staked vlr to represent a portion of ownership
        sLCTMinted = _stakedTokenAmount - (stakingFeePaid + burnFeePaid);
        _mint(msg.sender, sLCTMinted);

        //D. Add staker bags
        _createStakeBag(startTime, stopTime, sLCTMinted, msg.sender);

        // //E.  Work with fees and burns
        nativeToken.transferFrom(msg.sender, burnAddress, burnFeePaid);
        nativeToken.transferFrom(
            msg.sender,
            address(this),
            _stakedTokenAmount - burnFeePaid
        );
    }

    function stake(uint256 _stakedAmount) external {
        stakeWithTimeParameters(block.timestamp, 0, _stakedAmount);
    }

    function unstake(uint256 _unstakedAmount)
        external
        returns (
            uint256 burnFeePaid,
            uint256 stakingFeePaid,
            uint256 tokensReturned,
            uint256 stakingRewardsReturned
        )
    {
        require(
            balanceOf(msg.sender) >= _unstakedAmount,
            "Insufficient staked VLR"
        );

        stakingFeePaid = (_unstakedAmount * 15) / 1000;
        stakingRewardsBag += stakingFeePaid;
        burnFeePaid = (_unstakedAmount * 15) / 1000;

        uint256 totalSupply = totalSupply();
        //two ratios are used to determine the amount of staking fee rewards that an unstaking user is owed
        // 1.)  The Total Amount of Staking Fees Collected/ The Total Amount of Tokens in the contract
        // 2.)  The user's staked tokens/ the contract's total supply prior to unstaking
        // We multiply the two ratios by the total amount of staking fees collected to determine staking fees returned to user

        stakingRewardsReturned =
            ((stakingRewardsBag**2) * (_unstakedAmount)) /
            ((stakingRewardsBag * totalSupply) +
                (totalSupply**2) -
                (totalSupply * _unstakedAmount));
        stakingRewardsBag -= stakingRewardsReturned;
        tokensReturned = stakingRewardsReturned + _unstakedAmount;
        nativeToken.transfer(
            msg.sender,
            tokensReturned - stakingFeePaid - burnFeePaid
        );
        _burn(msg.sender, _unstakedAmount);

        nativeToken.transfer(burnAddress, burnFeePaid);

        _closeUnstakedBags(msg.sender, _unstakedAmount);
    }

    function _createStakeBag(
        uint256 startTime,
        uint256 stopTime,
        uint256 stakedTokens,
        address owner
    ) private {
        StakerBag memory newBag;
        newBag.startTime = startTime;
        newBag.stopTime = stopTime;
        newBag.stakedTokens = stakedTokens;
        newBag.ownerAddress = owner;
        stakes.push(newBag);
    }

    // this function sets the stoptime to block.timestamp for removed staking, leaving a remainder with stoptime=0 when it exists
    function _closeUnstakedBags(address owner, uint256 totalRemoved) private {
        uint256 stakeSum = 0;
        for (uint256 i = 0; i < stakes.length; i++) {
            if (stakes[i].ownerAddress == owner) {
                if (stakeSum + stakes[i].stakedTokens <= totalRemoved) {
                    stakes[i].stopTime = block.timestamp;
                    stakeSum += stakes[i].stakedTokens;
                } else {
                    uint256 remainder = (stakeSum + stakes[i].stakedTokens) -
                        totalRemoved;
                    stakes[i].stakedTokens = remainder;
                }
            }
        }
    }
}
