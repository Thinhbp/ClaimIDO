// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ClaimIDO is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint public totalToken;
    uint public maxTotalToken;
    uint public startTime;
    uint public cliff;
    uint public timeReleaseCycle;
    uint public firstReleasePercent;
    uint public releaseEachCyclePercent;
    address public token;

    EnumerableSet.AddressSet private whiteList;

    struct User {
        uint allocation;
        uint claimedToken;
    }

    mapping(address => User) public users;


    constructor (
        uint _maxTotalToken,
        uint _startTime,
        uint _cliff,
        uint _timeReleaseCycle,
        uint _firstReleasePercent,
        uint _releaseEachCyclePercent,
        address _token) {
            require(_maxTotalToken > 0 && _startTime > block.timestamp && _cliff > 0 && _timeReleaseCycle >0 && _firstReleasePercent > 0 && _releaseEachCyclePercent > 0 , "INALID INPUT");
            maxTotalToken = _maxTotalToken;
            startTime = _startTime;
            cliff = _cliff;
            timeReleaseCycle = _timeReleaseCycle;
            firstReleasePercent = _firstReleasePercent;
            releaseEachCyclePercent = _releaseEachCyclePercent;
            token = _token;
        }

    function setStartTime(uint _time) public onlyOwner {
        require(_time > block.timestamp && startTime > block.timestamp , "INVALID");
        startTime = _time;
    }

    function setMaxTotalToken(uint _amount) public onlyOwner {
        require(_amount > 0 && _amount > totalToken, "INVALID");
        maxTotalToken = _amount;
    }

    function fundVesting(uint _amount) public onlyOwner {
        require(_amount > 0, "INALID");
        IERC20(token).transferFrom(msg.sender, address(this), _amount);
    }

    function setWhiteList(address[] memory _users, uint[] memory _amount) public onlyOwner {
        require(_users.length == _amount.length, "INVALID");
        for (uint i = 0 ; i < _users.length; i++) {
            whiteList.add(_users[i]);
            users[_users[i]].allocation = _amount[i];
        }
    }

    function removeWhiteList(address[] memory _users) public onlyOwner {
        for (uint i=0; i< _users.length; i++){
            whiteList.remove(_users[i]);
            delete users[_users[i]];
        }
    }


    function claimToken() public {
        require(block.timestamp > startTime, "You can not claim token now");
        require(whiteList.contains(msg.sender), "You not in whitelist");
        uint passedTime = block.timestamp - startTime;
        uint ableClaim;
        uint amount = users[msg.sender].allocation;
        uint firstClaim = amount * firstReleasePercent / 10_000;
        if (passedTime < cliff) {
            require(users[msg.sender].claimedToken == 0, "You claimed");
            ableClaim = firstClaim;
        } else {
            uint timeClaimCycle = passedTime - cliff;
            uint time  = timeClaimCycle / timeReleaseCycle + 1;
            uint current = time * amount * releaseEachCyclePercent / 10_000 + firstClaim;
            if (current >= amount){
                current = amount;
            }
            ableClaim = current - users[msg.sender].claimedToken;
        }
        require(ableClaim > 0 , "You can't claim");
        users[msg.sender].claimedToken = users[msg.sender].claimedToken + ableClaim;
        require(IERC20(token).transfer(msg.sender, ableClaim), "transfer fail");

    }

    function withdrawEmergency(address _token) public onlyOwner {
        require(_token != address(0), "INVALID TOKEN");
        uint balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender,balance);
    }

    receive() external payable {
        payable(owner()).transfer(address(this).balance);
    }
}
