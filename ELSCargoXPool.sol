// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./DSMath.sol";

contract ELSCargoXPool is ReentrancyGuard, Ownable, DSMath {
    IERC20 token;
    address distributionFeeAddress;
    uint256 private fee;
    uint256 private totalStakedBalance;
    uint256 private totalAddresses;
    uint256 private totalDistributedRewards;
    uint256 private totalPaidRewards;
    uint256 private rewardPerToken;
    address[] private stakingAddresses;
    enum AddressStatus {
        DELETED,
        ACTIVE
    }
    mapping(address => uint256) private rewards;
    mapping(address => uint256) private rewardsPaid;
    mapping(address => uint256) private userStakedBalance;
    mapping(address => uint256) private userRewardTally;
    mapping(address => StakeAddress) private addressesByAddress;

    constructor(IERC20 _token, address _distributionFeeAddress, uint256 _fee) {
        token = _token;
        distributionFeeAddress = _distributionFeeAddress;
        fee = _fee;
        rewardPerToken = 0;
    }

    struct StakeAddress {
        uint256 id;
        address userAddress;
        AddressStatus status;
    }

    // get total staked balance in pool
    function getTotalStakedBalance() external view returns (uint256) {
        return totalStakedBalance;
    }

    // get current fee
    function getCurrentFee() external view returns (uint256) {
        return fee;
    }

    // get total addresses that staked at pool
    function getTotalAddresses() external view returns (uint256) {
        return totalAddresses;
    }

    // get total amount of distributed rewards
    function getTotalDistributedRewards() external view returns (uint256) {
        return totalDistributedRewards;
    }

    // get total amount of paid (withdrawn) rewards
    function getTotalPaidRewards() external view returns (uint256) {
        return totalPaidRewards;
    }

    // get pool balance
    function getPoolCXOBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // get fee rewards
    function getRewardPerToken() external view returns (uint256) {
        return rewardPerToken;
    }

    // get all staking addresses
    function getStakingAddresses() external view returns (address[] memory) {
        return stakingAddresses;
    }

    // get address status
    function getAddressStatus(
        address _userPublicAddress
    ) external view returns (AddressStatus) {
        return addressesByAddress[_userPublicAddress].status;
    }

    // get active addresses
    function getActiveAddresses() external view returns (address[] memory) {
        uint count;

        for (uint i = 0; i < stakingAddresses.length; i++) {
            if (userStakedBalance[stakingAddresses[i]] > 0) {
                count++;
            }
        }

        address[] memory activeAddresses = new address[](count);
        uint j;

        for (uint i = 0; i < stakingAddresses.length; i++) {
            if (userStakedBalance[stakingAddresses[i]] > 0) {
                activeAddresses[j] = stakingAddresses[i];
                j++;
            }
        }

        return activeAddresses;
    }

    // get user staked balance
    function getUserStakedBalance(
        address _userPublicAddress
    ) external view returns (uint256) {
        return userStakedBalance[_userPublicAddress];
    }

    // get user reward tally
    function getUserRewardTally(
        address _userPublicAddress
    ) external view returns (uint256) {
        return userRewardTally[_userPublicAddress];
    }

    // get user rewards
    function getUserPaidRewards(
        address _userPublicAddress
    ) external view returns (uint256) {
        return rewardsPaid[_userPublicAddress];
    }

    // get user earned rewards
    function getUserEarnedRewards(
        address _userPublicAddress
    ) public view returns (uint256) {
        return
            DSMath.sub(
                DSMath.wmul(
                    userStakedBalance[_userPublicAddress],
                    rewardPerToken
                ),
                userRewardTally[_userPublicAddress]
            );
    }

    // owner of the pool can change distribution fee address
    function changeDistributionFeeAddress(
        address _newAddress
    ) external onlyOwner {
        distributionFeeAddress = _newAddress;

        emit DistributionFeeAddressChanged(_newAddress);
    }

    // owner of the pool can change fee, but not more than 80%
    function changeFee(uint256 _newFee) external onlyOwner {
        // Fee that high will only be in case if Polygon network gets congested and there will be high Polygon transaction fees, normaly it will be 10%
        require(_newFee <= 80, "Fee cannot be more than 80%.");

        fee = _newFee;

        emit FeeChanged(_newFee);
    }

    // distribute rewards to stakers
    function distributeRewards() external nonReentrant {
        // calculate amount of rewards for distribution
        uint256 totalRewardsIncludingFee = DSMath.sub(
            DSMath.sub(token.balanceOf(address(this)), totalStakedBalance),
            totalDistributedRewards
        );
        require(
            totalRewardsIncludingFee >= 1 * 10 ** 18,
            "There is not enough rewards to distribute."
        );

        // calculate distribution fee
        uint256 distributionFee = DSMath.wdiv(
            DSMath.wmul(totalRewardsIncludingFee, fee),
            100
        );

        // remove fee distributionFee from totalRewards for distribution
        uint256 totalRewards = DSMath.sub(
            totalRewardsIncludingFee,
            distributionFee
        );

        // add current rewards to total distributed rewards
        totalDistributedRewards = DSMath.add(
            totalDistributedRewards,
            totalRewards
        );

        // calculate new reward per token
        rewardPerToken = DSMath.add(
            rewardPerToken,
            DSMath.wdiv(totalRewards, totalStakedBalance)
        );

        // send distribution fee to pool owner
        SafeERC20.safeTransfer(token, distributionFeeAddress, distributionFee);
        emit RewardsDistributed(totalRewardsIncludingFee);
    }

    // save staking address to storage
    function saveStakingAddress(address _userPublicAddress) private {
        uint256 addressID = addressesByAddress[_userPublicAddress].id;

        if (addressID > 0) {
            addressesByAddress[_userPublicAddress].status = AddressStatus
                .ACTIVE;
        } else {
            totalAddresses++;

            StakeAddress memory stakeAddress = StakeAddress(
                totalAddresses,
                _userPublicAddress,
                AddressStatus.ACTIVE
            );
            addressesByAddress[_userPublicAddress] = stakeAddress;

            stakingAddresses.push(_userPublicAddress);
        }
    }

    // set status of address to "deleted"
    function deleteStakingAddress(address _userPublicAddress) private {
        addressesByAddress[_userPublicAddress].status = AddressStatus.DELETED;
    }

    // stake function
    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "You can't stake 0 CXO?");

        require(
            DSMath.add(_amount, totalStakedBalance) <= 250000 * 10 ** 18,
            "Maximum staking amount for this pool is 250000 CXO."
        );

        // check if user have enough CXO tokens in wallet
        uint256 userWalletBalance = token.balanceOf(msg.sender);
        require(
            _amount <= userWalletBalance,
            "You don't have enough CXO in your wallet?"
        );

        // withdraw rewards first
        uint256 reward = getUserEarnedRewards(msg.sender);
        require(reward == 0, "Please withdraw rewards first!");

        // save staking address to storage
        saveStakingAddress(msg.sender);

        totalStakedBalance = DSMath.add(totalStakedBalance, _amount);
        userStakedBalance[msg.sender] = DSMath.add(
            userStakedBalance[msg.sender],
            _amount
        );
        userRewardTally[msg.sender] = DSMath.add(
            userRewardTally[msg.sender],
            DSMath.wmul(rewardPerToken, _amount)
        );

        SafeERC20.safeTransferFrom(token, msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    // withdraw staked assets back to user wallet
    function withdraw(uint256 _amount) external nonReentrant {
        require(_amount > 0, "You can't withdraw 0 CXO?");

        require(
            _amount <= totalStakedBalance,
            "Total supply of staked CXO is not sufficient?"
        );

        require(
            _amount <= userStakedBalance[msg.sender],
            "You don't have staked amount you want to withdraw!"
        );

        // withdraw rewards first
        uint256 reward = getUserEarnedRewards(msg.sender);
        require(reward == 0, "Please withdraw rewards first!");

        // check if user wants to withdraw whole stack - delete address
        if (userStakedBalance[msg.sender] == _amount) {
            deleteStakingAddress(msg.sender);
        }

        totalStakedBalance = DSMath.sub(totalStakedBalance, _amount);
        userStakedBalance[msg.sender] = DSMath.sub(
            userStakedBalance[msg.sender],
            _amount
        );
        userRewardTally[msg.sender] = DSMath.sub(
            userRewardTally[msg.sender],
            DSMath.wmul(rewardPerToken, _amount)
        );

        SafeERC20.safeTransfer(token, msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    // withdraw rewards to user wallet
    function withdrawRewards() public nonReentrant {
        uint256 reward = getUserEarnedRewards(msg.sender);
        require(reward > 0, "You have no rewards to withdraw.");

        uint256 rewardsLeft = DSMath.sub(
            token.balanceOf(address(this)),
            totalStakedBalance
        );

        // there can be minimal deviation, because of rounding up
        if (reward > rewardsLeft) {
            reward = rewardsLeft;
        }

        userRewardTally[msg.sender] = DSMath.wmul(
            userStakedBalance[msg.sender],
            rewardPerToken
        );
        rewardsPaid[msg.sender] = DSMath.add(rewardsPaid[msg.sender], reward);
        totalDistributedRewards = DSMath.sub(totalDistributedRewards, reward);
        totalPaidRewards = DSMath.add(totalPaidRewards, reward);

        SafeERC20.safeTransfer(token, msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    /* ========== EVENTS ========== */
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event RewardsDistributed(uint256 amount);
    event FeeChanged(uint256 newFee);
    event DistributionFeeAddressChanged(address newAddress);
}
