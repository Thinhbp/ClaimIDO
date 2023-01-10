// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


contract claimIDO is Ownable {
    address public icoToken;
    address public refundToken;
    uint public totalToken;
    uint public startJoin;
    uint public startClaim;
    uint public startRefund;
    uint public totalRaised;
    uint public rate;
    uint public minInvest;
    uint public maxInvest;
    uint public timeToRefund;

    uint public roundID;
    mapping(address => mapping(uint => uint)) public userInfo;
    mapping(address => mapping(uint => bool)) public isJoined;
    mapping(address => mapping(uint => bool)) public isClaimed;
    mapping(address => mapping(uint => bool)) public isRefunded;




    constructor(
        address _icoToken,
        address _refundToken,
        uint _totalToken,
        uint _startClaim,
        uint _startRefund,
        uint _roundID,
        uint _rate, 
        uint _startJoin,
        uint _minInvest,
        uint _maxInvest,
        uint _timeToRefund
    ){
        require(_icoToken != address(0) && _refundToken != address(0) && _totalToken >0 , "INVALID INPUT");
        require(_startClaim > block.timestamp && _startRefund >= _startClaim, "INVALID TIME");
        require(_startJoin < _startClaim, "INVALID");
        require(_minInvest < _maxInvest, "INVALID");
        icoToken = _icoToken;
        refundToken = _refundToken;
        totalToken = _totalToken;
        startClaim = _startClaim;
        startRefund = _startRefund; 
        roundID = _roundID;
        rate = _rate;
        startJoin = _startJoin;
        minInvest = _minInvest;
        maxInvest = _maxInvest;
        timeToRefund = _timeToRefund;
    }

    function setRoundID(uint _roundID) public onlyOwner {
        require(block.timestamp < startClaim, "INVALID");
        roundID = _roundID;
    }

    function joinIDO(uint _amount) public {
        require(totalRaised + _amount <= totalToken, "LIMIT");
        require(block.timestamp >= startJoin, "Not yet time");
        require(block.timestamp <= startClaim, "time-expired");
        require(!isJoined[msg.sender][roundID], "You joined");
        require(_amount >= minInvest && _amount <= maxInvest, "INVALID AMOUNT");
        isJoined[msg.sender][roundID] = true;
        userInfo[msg.sender][roundID] = _amount;
        require(IERC20(refundToken).transferFrom(msg.sender, address(this), _amount), "Transfer fail");
        totalRaised = totalRaised + _amount;

    }

    function claimToken() public {
        require(block.timestamp >= startClaim , "Not yet time to claim ");
        require(!isRefunded[msg.sender][roundID], "You refunded");
        require(isJoined[msg.sender][roundID], "You have to join");
        require(!isClaimed[msg.sender][roundID], "You claimed");
        uint amountToClaim = userInfo[msg.sender][roundID] * rate;
        isClaimed[msg.sender][roundID] = true;
        require(IERC20(icoToken).transfer(msg.sender, amountToClaim), "Transfer fail");
        userInfo[msg.sender][roundID] = 0;
    }

    function reFund() public {
        require(block.timestamp >= startRefund, "Not yet time to refund");
        require(block.timestamp <= startRefund + timeToRefund, "You can not refund");
        require(!isRefunded[msg.sender][roundID], "You refunded");
        require(isJoined[msg.sender][roundID], "You have to join");
        require(!isClaimed[msg.sender][roundID], "You claimed");
        isRefunded[msg.sender][roundID] = true;
        uint amountToRefund = userInfo[msg.sender][roundID];
        require(IERC20(refundToken).transfer(msg.sender, amountToRefund), "Transfer fail");
        userInfo[msg.sender][roundID] = 0;


    }

    function checkRestOfAllocation() public view returns(uint) {
        return (totalToken - totalRaised) ;
    }

    function withdrawEmergency(address _token) public onlyOwner {
        require(_token != address(0), "INVALID TOKEN");
        uint balance = IERC20(_token).balanceOf(address(this));
        require(IERC20(_token).transfer(msg.sender, balance), "transfer fail");

    }

    receive() external payable {
        payable(owner()).transfer(address(this).balance);
    }




}
