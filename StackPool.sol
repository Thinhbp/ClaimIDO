
pragma solidity ^0.8.7;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


contract BSCSBSCSIDOPool is
    Ownable,
    ReentrancyGuard,
    ERC20("BSCS BSCS IDO Pool", "BSCS-BSCS")
{
    using SafeMath for uint256;

    // The address of the smart chef factory
    address public BSCS_CASTLE_FACTORY;

    // Whether a limit is set for users
    bool public hasUserLimit;

    // Whether a limit is set for the pool
    bool public hasPoolLimit;

    // Whether it is initialized
    bool public isInitialized;

    // Accrued token per share
    mapping(ERC20 => uint256) public accTokenPerShare;

    // The block number when staking starts.
    uint256 public stakingBlock;

    // The block number when staking end.
    uint256 public stakingEndBlock;

    // The block number when unstaking starts.
    uint256 public unStakingBlock;

    // The fee applies when unstaking.
    uint256 public unStakingFee;

    // The period where fee applies.
    uint256 public feePeriod;

    // The fee collector.
    address public feeCollector;

    // The block number when BSCStaion mining ends.
    uint256 public bonusEndBlock;

    // The block number when BSCStaion mining starts.
    uint256 public startBlock;

    // The block number of the last pool update
    uint256 public lastRewardBlock;

    // The pool limit per user (0 if none)
    uint256 public poolLimitPerUser;

    // The pool cap (0 if none)
    uint256 public poolCap;

    // Whether the pool's staked token balance can be remove by owner
    bool private isRemovable;

    // BSCStaion tokens created per block.
    mapping(ERC20 => uint256) public rewardPerBlock;

    // The precision factor
    mapping(ERC20 => uint256) public PRECISION_FACTOR;

    // The reward token
    ERC20[] public rewardTokens;

    // The staked token
    ERC20 public stakedToken;

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => UserInfo) public userInfo;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 lastStakingBlock;
        mapping(ERC20 => uint256) rewardDebt; // Reward debt
    }
    
    
    // store staking by user
    struct UserStake {
       address addr;
       uint256 amount;
       uint256 startStakeBlock;
       uint256 endStakeBlock;
    }
    // user address to stake details
    mapping(address => UserStake[]) public stakeDetails;
    uint256 public lockingDuration;

    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event NewRewardPerBlock(uint256 rewardPerBlock, ERC20 token);
    event NewPoolLimit(uint256 poolLimitPerUser);
    event NewPoolCap(uint256 poolCap);
    event RewardsStop(uint256 blockNumber);
    event Withdraw(address indexed user, uint256 amount);
    event NewRewardToken(ERC20 token, uint256 rewardPerBlock, uint256 p_factor);
    event RemoveRewardToken(ERC20 token);
    event NewStakingBlocks(uint256 startStakingBlock, uint256 endStakingBlock);
    event NewUnStakingBlock(uint256 startUnStakingBlock);

    constructor() public {
        BSCS_CASTLE_FACTORY = msg.sender;
    }

    /*
     * @notice Initialize the contract
     * @param _stakedToken: staked token address
     * @param _rewardToken: reward token address
     * @param _rewardPerBlock: reward per block (in rewardToken)
     * @param _startBlock: start block
     * @param _bonusEndBlock: end block
     * @param _poolLimitPerUser: pool limit per user in stakedToken (if any, else 0)
     * @param _poolCap: pool cap in stakedToken (if any, else 0)
     * @param _admin: admin address with ownership
     */
    function initialize(
        ERC20 _stakedToken,
        ERC20[] memory _rewardTokens,
        uint256[] memory _rewardPerBlock,
        uint256[] memory _startEndBlocks,
        uint256[] memory _stakingBlocks,
        uint256 _unStakingBlock,
        uint256[] memory _feeSettings,
        address _feeCollector,
        uint256 _poolLimitPerUser,
        uint256 _poolCap,
        bool _isRemovable,
        address _admin
    ) external {
        require(!isInitialized, "Already initialized");
        require(msg.sender == BSCS_CASTLE_FACTORY, "Not factory");
        require(
            _rewardTokens.length == _rewardPerBlock.length,
            "Mismatch length"
        );

        require(address(_stakedToken) != address(0),"Invalid address");
        require(address(_feeCollector) != address(0),"Invalid address");
        require(address(_admin) != address(0),"Invalid address");

        // Make this contract initialized
        isInitialized = true;

        stakedToken = _stakedToken;
        rewardTokens = _rewardTokens;
        startBlock = _startEndBlocks[0];
        bonusEndBlock = _startEndBlocks[1];

        require(
            _stakingBlocks[0] < _stakingBlocks[1],
            "Staking block exceeds end staking block"
        );
        stakingBlock = _stakingBlocks[0];
        stakingEndBlock = _stakingBlocks[1];
        unStakingBlock = _unStakingBlock;
        unStakingFee = _feeSettings[0];
        feePeriod = _feeSettings[1];
        feeCollector = _feeCollector;
        isRemovable = _isRemovable;

        if (_poolLimitPerUser > 0) {
            hasUserLimit = true;
            poolLimitPerUser = _poolLimitPerUser;
        }
        if (_poolCap > 0) {
            hasPoolLimit = true;
            poolCap = _poolCap;
        }

        uint256 decimalsRewardToken;
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            decimalsRewardToken = uint256(_rewardTokens[i].decimals());
            require(decimalsRewardToken < 30, "Must be inferior to 30");
            PRECISION_FACTOR[_rewardTokens[i]] = uint256(
                10**(uint256(30).sub(decimalsRewardToken))
            );
            rewardPerBlock[_rewardTokens[i]] = _rewardPerBlock[i];
        }

        // Set the lastRewardBlock as the startBlock
        lastRewardBlock = startBlock;

        // Transfer ownership to the admin address who becomes owner of the contract
        transferOwnership(_admin);
    }
    
    function setLockingDuration(uint256 _numbBlocks) external onlyOwner{
        lockingDuration = _numbBlocks;
    }
    
    function enterStakeUser(uint256 _amount) internal returns(bool success) {
        UserStake memory currentStake;
    
        currentStake.addr = msg.sender;
        currentStake.amount = _amount;
        currentStake.startStakeBlock = block.number;
        currentStake.endStakeBlock = block.number + lockingDuration;
    
        stakeDetails[msg.sender].push(currentStake);

        return true;
    }
    
    function getUserStakedCount(address _user) 
        internal 
        returns(uint256) 
    {
        uint256 numStakes;
        for(uint256 i = 0; i < stakeDetails[_user].length;  i++) {
            numStakes++;
        }
        return numStakes;
    }
    
    function getStakedSchedule(address _user) 
        external 
        returns 
        (uint256[] memory, uint256[] memory, uint256[] memory)
    {
        uint256 stakedCount = getUserStakedCount(_user);
        uint256[] memory startStake = new uint256[](stakedCount);
        uint256[] memory endStake = new uint256[](stakedCount);
        uint256[] memory amount = new uint256[](stakedCount);
      
        for (uint256 i = 0; i < stakedCount; i++) {
            startStake[i] = stakeDetails[msg.sender][i].startStakeBlock; 
            endStake[i] = stakeDetails[msg.sender][i].endStakeBlock;
            amount[i] = stakeDetails[msg.sender][i].amount;
        }

        return (startStake, endStake, amount);
    }
    
    function getUnstakeAmount(address _user) public view returns(uint256) {
        uint256 claimAmount;
        for(uint256 i = 0; i < stakeDetails[_user].length;  i++) {
            if (stakeDetails[_user][i].endStakeBlock < block.number) {
                claimAmount += stakeDetails[_user][i].amount;   
            }
        }
        
        return claimAmount;
    }
   
    function leaveStakeUser() internal returns(uint256) {
        require(msg.sender != address(0), "Invalid address");
        uint256 claimAmount;
        for(uint256 i = 0; i < stakeDetails[msg.sender].length;  i++) {
            if (stakeDetails[msg.sender][i].endStakeBlock < block.number) {
                claimAmount += stakeDetails[msg.sender][i].amount;   
                delete stakeDetails[msg.sender][i];
            }
        }
        
        return claimAmount;
    }
    
    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function deposit(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(stakingBlock <= block.number, "Staking has not started");
        require(stakingEndBlock >= block.number, "Staking has ended");
        
        require(enterStakeUser(_amount),'Unabled to stake');
        
        if (hasPoolLimit) {
            uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));
            require(
                _amount.add(stakedTokenSupply) <= poolCap,
                "Pool cap reached"
            );
        }

        if (hasUserLimit) {
            require(
                _amount.add(user.amount) <= poolLimitPerUser,
                "User amount above limit"
            );
        }
        
        _updatePool();

        if (user.amount > 0) {
            uint256 pending;
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                pending = user
                .amount
                .mul(accTokenPerShare[rewardTokens[i]])
                .div(PRECISION_FACTOR[rewardTokens[i]])
                .sub(user.rewardDebt[rewardTokens[i]]);
                if (pending > 0) {
                    ERC20(rewardTokens[i]).transfer(
                        address(msg.sender),
                        pending
                    );
                }
            }
        }

        if (_amount > 0) {
            user.amount = user.amount.add(_amount);
            ERC20(stakedToken).transferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            _mint(address(msg.sender), _amount);
        }
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            user.rewardDebt[rewardTokens[i]] = user
            .amount
            .mul(accTokenPerShare[rewardTokens[i]])
            .div(PRECISION_FACTOR[rewardTokens[i]]);
        }

        user.lastStakingBlock = block.number;

        emit Deposit(msg.sender, _amount);
    }

    function safeERC20Transfer(ERC20 erc20, address _to, uint256 _amount) 
      private 
    { 
        uint256 balance = erc20.balanceOf(address(this));
        if (_amount > balance) {
            erc20.transfer(_to, balance); 
        }  else {
        erc20.transfer(_to, _amount); }
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function withdraw(bool isHarvest) external nonReentrant {
        uint256 _amount = 0;
        
         // only check for Unstake token
        if(isHarvest == false){ 
            _amount = leaveStakeUser();
            require(_amount > 0, "Invalid amount");     
        }
        
        UserInfo storage user = userInfo[msg.sender];
       
        require(user.amount >= _amount, "Amount to withdraw too high");

        _updatePool();

        // uint256 pending = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
        uint256 pending;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            pending = user
            .amount
            .mul(accTokenPerShare[rewardTokens[i]])
            .div(PRECISION_FACTOR[rewardTokens[i]])
            .sub(user.rewardDebt[rewardTokens[i]]);
            if (pending > 0) {
                // ERC20(rewardTokens[i]).transfer(address(msg.sender), pending);
                safeERC20Transfer(ERC20(rewardTokens[i]), address(msg.sender),pending);
            }
        }
        // If _amount > 0 ==> Unstake Token
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            _burn(address(msg.sender), _amount);
            _amount = collectFee(_amount, user);
            ERC20(stakedToken).transfer(address(msg.sender), _amount);
            //_burn(address(msg.sender),_amount);
        }
        // Harvest
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            user.rewardDebt[rewardTokens[i]] = user
            .amount
            .mul(accTokenPerShare[rewardTokens[i]])
            .div(PRECISION_FACTOR[rewardTokens[i]]);
        }

        emit Withdraw(msg.sender, _amount);
    }

    function collectFee(uint256 _amount, UserInfo storage user)
        internal
        returns (uint256)
    {
        uint256 blockPassed = block.number.sub(user.lastStakingBlock);
        if (feePeriod == 0 || (feePeriod > 0 && feePeriod >= blockPassed)) {
            uint256 collectedAmt = _amount.mul(unStakingFee).div(10000);
            ERC20(stakedToken).transfer(feeCollector, collectedAmt);
            return _amount.sub(collectedAmt);
        }
        return _amount;
    }


    /*
     * @notice Stop rewards
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            ERC20(rewardTokens[i]).transfer(address(msg.sender), _amount);
        }
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount)
        external
        onlyOwner
    {
        require(
            _tokenAddress != address(stakedToken),
            "Cannot be staked token"
        );
        // require(_tokenAddress != address(rewardToken), "Cannot be reward token");
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            require(
                _tokenAddress != address(rewardTokens[i]),
                "Cannot be reward token"
            );
        }

        ERC20(_tokenAddress).transfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /*
     * @notice Allow owner to remove all staked token from pool.
     * @param _amount: amount to withdraw (in stakedToken)
     * @dev Only callable by owner
     */
    function emergencyRemoval(uint256 _amount) external onlyOwner {
        require(isRemovable, "The pool is not removable");
        require(
            stakedToken.balanceOf(address(this)) >= _amount,
            "Amount exceeds pool balance"
        );
        if (_amount > 0) {
            ERC20(stakedToken).transfer(address(msg.sender), _amount);
        }
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner
     */
    function stopReward() external onlyOwner {
        bonusEndBlock = block.number;
    }

    /* Fee updates
     *  Only callable by owner
     */
    function updateFeePeriod(uint256 _newFeePeriod) external onlyOwner {
        feePeriod = _newFeePeriod;
    }

    function updateUnstakingFee(uint256 _newFee) external onlyOwner {
        unStakingFee = _newFee;
    }

    function updateFeeCollector(address _newCollector) external onlyOwner {
        require(_newCollector != feeCollector, "Already the fee collector");
        feeCollector = _newCollector;
    }

    /*
     * @notice Update pool limit per user
     * @dev Only callable by owner.
     * @param _hasUserLimit: whether the limit remains forced
     * @param _poolLimitPerUser: new pool limit per user
     */
    function updatePoolLimitPerUser(
        bool _hasUserLimit,
        uint256 _poolLimitPerUser
    ) external onlyOwner {
        require(hasUserLimit, "Must be set");
        if (_hasUserLimit) {
            // require(_poolLimitPerUser > poolLimitPerUser, "New limit must be higher");
            poolLimitPerUser = _poolLimitPerUser;
        } else {
            hasUserLimit = _hasUserLimit;
            poolLimitPerUser = 0;
        }
        emit NewPoolLimit(poolLimitPerUser);
    }

    /*
     * @notice Update pool cap
     * @dev Only callable by owner.
     * @param _hasPoolLimit: whether the cap remains forced
     * @param _poolCap: new pool limit per user
     */
    function updatePoolCap(bool _hasPoolLimit, uint256 _poolCap)
        external
        onlyOwner
    {
        require(hasPoolLimit, "Must be set");
        if (_hasPoolLimit) {
            // require(_poolCap > poolCap, "New cap must be higher");
            poolCap = _poolCap;
        } else {
            hasPoolLimit = _hasPoolLimit;
            poolCap = 0;
        }
        emit NewPoolCap(poolCap);
    }

    /*
     * @notice Update reward per block
     * @dev Only callable by owner.
     * @param _rewardPerBlock: the reward per block
     */
    function updateRewardPerBlock(uint256 _rewardPerBlock, ERC20 _token)
        external
        onlyOwner
    {
        // require(block.number < startBlock, "Pool has started");
        
        (bool foundToken, uint256 tokenIndex) = findElementPosition(
            _token,
            rewardTokens
        );
        require(foundToken, "Cannot find token");
        rewardPerBlock[_token] = _rewardPerBlock;
        emit NewRewardPerBlock(_rewardPerBlock, _token);
    }

    /**
     * @notice It allows the admin to update start and end blocks
     * @dev This function is only callable by owner.
     * @param _startBlock: the new start block
     * @param _bonusEndBlock: the new end block
     */
    function updateStartAndEndBlocks(
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) external onlyOwner {
        require(block.number < startBlock, "Pool has started");
        require(
            _startBlock < _bonusEndBlock,
            "New startBlock must be lower than new endBlock"
        );
        require(
            block.number < _startBlock,
            "New startBlock must be higher than current block"
        );

        require(
            stakingBlock <= _startBlock,
            "Staking block exceeds start block"
        );
        require(
            stakingEndBlock <= _bonusEndBlock,
            "End staking block exceeds bonus end block"
        );
        //require(unStakingBlock >= _bonusEndBlock, "Unstaking block precedes end block");

        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        // Set the lastRewardBlock as the startBlock
        lastRewardBlock = startBlock;

        emit NewStartAndEndBlocks(_startBlock, _bonusEndBlock);
    }

    /**
     * @notice It allows the admin to update staking block
     * @dev This function is only callable by owner.
     * @param _startStakingBlock: the new staking block
     */
    function updateStakingBlocks(
        uint256 _startStakingBlock,
        uint256 _endStakingBlock
    ) external onlyOwner {
        //require(block.number < stakingBlock, "Staking has started");
        require(
            _startStakingBlock <= startBlock,
            "Staking block exceeds start block"
        );
        require(
            _startStakingBlock <= unStakingBlock,
            "Staking block exceeds unstaking block"
        );
        require(
            block.number < _startStakingBlock,
            "New stakingBlock must be higher than current block"
        );

        require(
            _startStakingBlock < _endStakingBlock,
            "Staking block exceeds end staking block"
        );
        require(
            _endStakingBlock <= bonusEndBlock,
            "End staking block exceeds bonus end block"
        );
        //require(block.number < _startStakingBlock, "New stakingBlock must be higher than current block");

        stakingBlock = _startStakingBlock;
        stakingEndBlock = _endStakingBlock;

        emit NewStakingBlocks(_startStakingBlock, _endStakingBlock);
    }

    /**
     * @notice It allows the admin to update unstaking block
     * @dev This function is only callable by owner.
     * @param _startUnStakingBlock: the new staking block
     */
    function updateUnStakingBlock(uint256 _startUnStakingBlock)
        external
        onlyOwner
    {
        require(block.number < unStakingBlock, "Unstaking has started");
        //require(_startUnStakingBlock >= bonusEndBlock, "Unstaking block precedes end block");
        require(
            stakingBlock <= _startUnStakingBlock,
            "Staking block exceeds unstaking block"
        );
        require(
            block.number < _startUnStakingBlock,
            "New UnStakingBlock must be higher than current block"
        );

        unStakingBlock = _startUnStakingBlock;

        emit NewUnStakingBlock(_startUnStakingBlock);
    }

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user)
        external
        view
        returns (uint256[] memory, ERC20[] memory)
    {
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));
        uint256[] memory userPendingRewards = new uint256[](
            rewardTokens.length
        );
        if (block.number > lastRewardBlock && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 bscsReward;
            uint256 adjustedTokenPerShare;
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                bscsReward = multiplier.mul(rewardPerBlock[rewardTokens[i]]);
                adjustedTokenPerShare = accTokenPerShare[rewardTokens[i]].add(
                    bscsReward.mul(PRECISION_FACTOR[rewardTokens[i]]).div(
                        stakedTokenSupply
                    )
                );
                userPendingRewards[i] = user
                .amount
                .mul(adjustedTokenPerShare)
                .div(PRECISION_FACTOR[rewardTokens[i]])
                .sub(user.rewardDebt[rewardTokens[i]]);
            }
            return (userPendingRewards, rewardTokens);
        } else {
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                userPendingRewards[i] = user
                .amount
                .mul(accTokenPerShare[rewardTokens[i]])
                .div(PRECISION_FACTOR[rewardTokens[i]])
                .sub(user.rewardDebt[rewardTokens[i]]);
            }
            return (userPendingRewards, rewardTokens);
        }
    }

    /*
     * @notice View function to see pending reward on frontend (categorized by rewardToken)
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingRewardByToken(address _user, ERC20 _token)
        external
        view
        returns (uint256)
    {
        (bool foundToken, uint256 tokenIndex) = findElementPosition(
            _token,
            rewardTokens
        );
        if (!foundToken) {
            return 0;
        }
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));
        uint256 userPendingReward;
        if (block.number > lastRewardBlock && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 bscsReward = multiplier.mul(rewardPerBlock[_token]);
            uint256 adjustedTokenPerShare = accTokenPerShare[_token].add(
                bscsReward.mul(PRECISION_FACTOR[_token]).div(
                    stakedTokenSupply
                )
            );
            userPendingReward = user
            .amount
            .mul(adjustedTokenPerShare)
            .div(PRECISION_FACTOR[_token])
            .sub(user.rewardDebt[_token]);
            return userPendingReward;
        } else {
            return
                user
                    .amount
                    .mul(accTokenPerShare[_token])
                    .div(PRECISION_FACTOR[_token])
                    .sub(user.rewardDebt[_token]);
        }
    }

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }

        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));

        if (stakedTokenSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        uint256 bscsReward;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            bscsReward = multiplier.mul(rewardPerBlock[rewardTokens[i]]);
            accTokenPerShare[rewardTokens[i]] = accTokenPerShare[
                rewardTokens[i]
            ]
            .add(
                bscsReward.mul(PRECISION_FACTOR[rewardTokens[i]]).div(
                    stakedTokenSupply
                )
            );
        }
        lastRewardBlock = block.number;
    }

    /*
     * @notice Return reward multiplier over the given _from to _to block.
     * @param _from: block to start
     * @param _to: block to finish
     */
    function _getMultiplier(uint256 _from, uint256 _to)
        internal
        view
        returns (uint256)
    {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }

    /*
     * @notice Add new reward token.
     * @param _token: new rewardToken to add
     * @param _rewardPerBlock: _token's rewardPerBlock
     */
    function addRewardToken(ERC20 _token, uint256 _rewardPerBlock)
        external
        onlyOwner
    {
        require(address(_token) != address(0), "Must be a real token");
        require(address(_token) != address(this), "Must be a real token");
        (bool foundToken, uint256 tokenIndex) = findElementPosition(
            _token,
            rewardTokens
        );
        require(!foundToken, "Token exists");
        rewardTokens.push(_token);

        uint256 decimalsRewardToken = uint256(_token.decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");
        PRECISION_FACTOR[_token] = uint256(
            10**(uint256(30).sub(decimalsRewardToken))
        );
        rewardPerBlock[_token] = _rewardPerBlock;
        accTokenPerShare[_token] = 0;

        emit NewRewardToken(_token, _rewardPerBlock, PRECISION_FACTOR[_token]);
    }

    /*
     * @notice Remove a reward token.
     * @param _token: rewardToken to remove
     */
    function removeRewardToken(ERC20 _token) external onlyOwner {
        require(address(_token) != address(0), "Must be a real token");
        require(address(_token) != address(this), "Must be a real token");
        require(rewardTokens.length > 0, "List of token is empty");

        (bool foundToken, uint256 tokenIndex) = findElementPosition(
            _token,
            rewardTokens
        );
        require(foundToken, "Cannot find token");
        (bool success, ERC20[] memory newRewards) = removeElement(
            tokenIndex,
            rewardTokens
        );
        rewardTokens = newRewards;
        require(success, "Remove token unsuccessfully");
        PRECISION_FACTOR[_token] = 0;
        rewardPerBlock[_token] = 0;
        accTokenPerShare[_token] = 0;

        emit RemoveRewardToken(_token);
    }

    /*
     * @notice Remove element at index.
     * @param _index: index of the element to remove
     * @param _array: array of which to remove element at _index
     */
    function removeElement(uint256 _index, ERC20[] storage _array)
        internal
        returns (bool, ERC20[] memory)
    {
        if (_index >= _array.length) {
            return (false, _array);
        }

        for (uint256 i = _index; i < _array.length - 1; i++) {
            _array[i] = _array[i + 1];
        }

        _array.pop();
        return (true, _array);
    }
    
    /*
     * @notice Find element position in array.
     * @param _token: token of which to find position
     * @param _array: array that contains _token
     */
    function findElementPosition(ERC20 _token, ERC20[] storage _array)
        internal
        view
        returns (bool, uint256)
    {
        for (uint256 i = 0; i < _array.length; i++) {
            if (_array[i] == _token) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    //**Additional get methods for frontend use */

    function getUserDebt(address _usr)
        external
        view
        returns (ERC20[] memory, uint256[] memory)
    {
        uint256[] memory userDebt = new uint256[](rewardTokens.length);
        UserInfo storage user = userInfo[_usr];
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            userDebt[i] = user.rewardDebt[rewardTokens[i]];
        }
        return (rewardTokens, userDebt);
    }

    function getUserDebtByToken(address _usr, ERC20 _token)
        external
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[_usr];
        return (user.rewardDebt[_token]);
    }

    function getAllRewardPerBlock(ERC20[] memory _tokens)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory RPBlist = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            RPBlist[i] = rewardPerBlock[_tokens[i]];
        }
        return (RPBlist);
    }

    function getAllAccTokenPerShared(ERC20[] memory _tokens)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory ATPSlist = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            ATPSlist[i] = accTokenPerShare[_tokens[i]];
        }
        return (ATPSlist);
    }

    function getAllPreFactor(ERC20[] memory _tokens)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory PFlist = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            PFlist[i] = PRECISION_FACTOR[_tokens[i]];
        }
        return (PFlist);
    }

    //*Override transfer functions, allowing receipts to be transferable */
    function getStakingEndBlock() external view returns (uint256) {
        return stakingEndBlock;
    }

    function getUnStakingFee() external view returns (uint256) {
        return unStakingFee;
    }

    function getFeePeriod() external view returns (uint256) {
        return feePeriod;
    }

    function getFeeCollector() external view returns (address) {
        return feeCollector;
    }

    function getLastStakingBlock(address _user)
        external
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[_user];
        return user.lastStakingBlock;
    }
}
