// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenClaim is Ownable{
    using SafeERC20 for IERC20;
    
    address public admin;
    
    //user => claim round => claim status
    mapping(address => mapping(uint256 => bool)) public userClaim;
    mapping(address => bool) public isClaimed;
    //user => refund status
    mapping(address => bool) public userRefund;
    mapping(address => uint256) public totalClaimed;
    mapping(address => uint256) public totalRefunded;
  
    // token => claim round 
    uint256 public currentClaimRound;
    
    address public idoToken;
    address public refundToken;
  
    uint256 public refundBlockNumber;
    uint256 public claimStartAt;
 
    bool public initialized; 
  
    event EventClaimed(
        address indexed recipient,
        uint amount,
        uint date
    );

    event EventRefunded(
        address indexed recipient,
        uint amount,
        uint date
    );
  
    event EventSetConfig(
        address _refundTk,
        address _idoToken,
        uint256 _refundBlock,
        uint256 _claimTime,
        uint256 _claimRound
    );

    event EventEmergencyWithdraw(
        address _token, 
        address _to, 
        uint256 _amount
    );
    constructor(
        address _idoToken, 
        address _refundToken,
        uint256 _startClaimAt,
        uint256 _refundBlockNumber
    ) 
    {
        admin = msg.sender; 
        refundToken = _refundToken;
        idoToken = _idoToken;
        refundBlockNumber = _refundBlockNumber;
        claimStartAt = _startClaimAt;
    }
  
    function setAdm( address _newAdmin) external {
        require(msg.sender == admin, 'only admin');
        require(_newAdmin != address(0), '_newAdmin is zero address');
        admin = _newAdmin;
    }

    function setConfig(
        address _refundTk,
        address _idoToken,
        uint256 _refundBlock,
        uint256 _claimTime,
        uint256 _claimRound
    ) 
        external 
    {
        require(msg.sender == admin, 'only admin');
    
        if (initialized == false) {
            initialized = true;
        }
    
        if (_refundTk != address(0)) {
            refundToken = _refundTk;    
        }
    
        if (_idoToken != address(0)) {
            idoToken = _idoToken;    
        }
    
        if (_refundBlock > 0) {
            refundBlockNumber = _refundBlock;        
        }
    
        if (_claimTime > 0) {
            claimStartAt = _claimTime;        
        }
    
        if (_claimRound > 0 ){
            currentClaimRound = _claimRound;
        }
    
        emit EventSetConfig(
            _refundTk,
            _idoToken,
            _refundBlock,
            _claimTime,
            _claimRound
            );
        }

    function emergencyWithdraw(
        address _token, 
        address _to, 
        uint256 _amount
        ) 
        external 
        {
        require(msg.sender == admin,'Not allowed');
        IERC20(_token).safeTransfer(_to, _amount);
        emit EventEmergencyWithdraw(
            _token, 
            _to, 
            _amount
            );
        }

    function verifyAmt(
        uint256 _amount,
        uint256 _claimRound,
        bytes calldata sig
    ) 
        external 
        view
        returns(uint256)
    {
        address recipient = msg.sender;
        uint256 thisBal = IERC20(idoToken).balanceOf(address(this));
        require(thisBal >= _amount,'Not enough balance');
        require(initialized == true, 'Not yet initialized');
        require(claimStartAt > 0,'Claim has not started yet');
        require(block.timestamp > claimStartAt,'Claim has not started yet');
        // already refunded
        require(userRefund[recipient] == false,'Refunded');
    
        bytes32 message = prefixed(keccak256(abi.encodePacked(
            recipient, 
             _amount,
            _claimRound,
            address(this)
        )));
         // must be in whitelist 
            require(recoverSigner(message, sig) == admin , 'wrong signature');
            require(currentClaimRound > 0 && _claimRound <= currentClaimRound,'Invalid claim round');
            require(userClaim[recipient][_claimRound] == false,'Already claimed');
    
        if (thisBal > 0) {
            return _amount;
        } else {
            return 0;
        }
    }
  
  
    function claimTokens(
        uint256 _amount,
        uint256 _claimRound,
        bytes calldata sig
        ) 
        external 
    {
        address recipient = msg.sender;
   
        bytes32 message = prefixed(keccak256(abi.encodePacked(
            recipient, 
            _amount,
            _claimRound,
            address(this)
            )));
        // must be in whitelist 
        require(recoverSigner(message, sig) == admin , 'wrong signature');
    
        require(claimStartAt > 0,'Claim has not started yet');
        require(block.timestamp > claimStartAt,'Claim has not started yet');
        // already refunded
        require(userRefund[recipient] == false,'Refunded');
        uint256 thisBal = IERC20(idoToken).balanceOf(address(this));
        require(thisBal >= _amount,'Not enough balance');
        require(initialized == true, 'Not yet initialized');
        require(currentClaimRound > 0 && _claimRound <= currentClaimRound,'Invalid claim round');
        require(userClaim[recipient][_claimRound] == false,'Already claimed');
    
        if (thisBal > 0) {
            userClaim[recipient][_claimRound] = true;
            isClaimed[recipient] = true;
            totalClaimed[recipient] = totalClaimed[recipient] + _amount;
            IERC20(idoToken).safeTransfer(recipient, _amount);
        
        emit EventClaimed(
            recipient,
            _amount,
            block.timestamp
        );
        } 
    }
  
    function checkRefund() external view returns(bool){
        if(block.number < refundBlockNumber) {
            return true;
        }
      
        return false;
    }
  
    function refund(
        uint256 _amount,
        bytes calldata sig
        ) 
        external 
    {
        address recipient = msg.sender;
        bytes32 message = prefixed(keccak256(abi.encodePacked(
        recipient, 
        _amount,
        address(this)
        )));
        // must be in whitelist 
        require(recoverSigner(message, sig) == admin , 'wrong signature');
        uint256 thisBal = IERC20(refundToken).balanceOf(address(this));
        require(thisBal >= _amount,'Not enough balance');
        require(initialized == true, 'Not yet initialized');
        require(claimStartAt > 0,'Not yet started');
        require(block.number < refundBlockNumber, 'Refund is no longer allowed');
        require(refundBlockNumber > 0, 'Not refundable');
        require(userRefund[recipient] == false,'Refunded');
        require(isClaimed[recipient] == false, 'Already claimed');
    
        if (thisBal > 0) {
            userRefund[recipient] = true;
            totalRefunded[recipient] = totalRefunded[recipient] + _amount;
            IERC20(refundToken).safeTransfer(recipient, _amount);
            emit EventRefunded(
                recipient,
                _amount,
                block.timestamp
        );   
        }
    }
  
  
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
        '\x19Ethereum Signed Message:\n32', 
        hash
    ));
    }

    function recoverSigner(bytes32 message, bytes memory sig)
        internal
        pure
        returns (address)
    {
        uint8 v;
        bytes32 r;
        bytes32 s;
  
        (v, r, s) = splitSignature(sig);
  
        return ecrecover(message, v, r, s);
    }

    function splitSignature(bytes memory sig)
        internal
        pure
        returns (uint8, bytes32, bytes32)
    {
        require(sig.length == 65);
  
        bytes32 r;
        bytes32 s;
        uint8 v;
  
        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }
  
        return (v, r, s);
    }
}
