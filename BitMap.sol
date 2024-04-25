pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/BitMaps.sol";

contract Test {
  using BitMaps for BitMaps.BitMap;

    BitMaps.BitMap private bitmap;


    constructor() {
    }

  function get(address user) public view returns (bool) {
    return bitmap.get(uint256(uint160(user)));
  }

  function setTo(address user, bool value) public {
    bitmap.setTo(uint256(uint160(user)),value);
  }

  function set(uint index) public {
    bitmap.set(index);
  }

  function unset(uint index) public {
    bitmap.unset(index);
  }
}

