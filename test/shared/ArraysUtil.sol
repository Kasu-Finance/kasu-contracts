// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library ArraysUtil {
    function test_lib() external pure {}

    function toArray(uint256 x1) public pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](1);
        result[0] = x1;
        return result;
    }

    function toArray(uint256 x1, uint256 x2) public pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](2);
        result[0] = x1;
        result[1] = x2;
        return result;
    }

    function toArray(uint256 x1, uint256 x2, uint256 x3) public pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](3);
        result[0] = x1;
        result[1] = x2;
        result[2] = x3;
        return result;
    }

    function toArray(uint256 x1, uint256 x2, uint256 x3, uint256 x4) public pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](4);
        result[0] = x1;
        result[1] = x2;
        result[2] = x3;
        result[3] = x4;
        return result;
    }

    function toArray(address x1) public pure returns (address[] memory) {
        address[] memory result = new address[](1);
        result[0] = x1;
        return result;
    }

    function toArray(address x1, address x2) public pure returns (address[] memory) {
        address[] memory result = new address[](2);
        result[0] = x1;
        result[1] = x2;
        return result;
    }

    function toArray(address x1, address x2, address x3) public pure returns (address[] memory) {
        address[] memory result = new address[](3);
        result[0] = x1;
        result[1] = x2;
        result[2] = x3;
        return result;
    }

    function toArray(address x1, address x2, address x3, address x4) public pure returns (address[] memory) {
        address[] memory result = new address[](4);
        result[0] = x1;
        result[1] = x2;
        result[2] = x3;
        result[3] = x4;
        return result;
    }

    function toArray(address x1, address x2, address x3, address x4, address x5)
        public
        pure
        returns (address[] memory)
    {
        address[] memory result = new address[](5);
        result[0] = x1;
        result[1] = x2;
        result[2] = x3;
        result[3] = x4;
        result[4] = x5;
        return result;
    }

    function toArray(bool x1) public pure returns (bool[] memory) {
        bool[] memory result = new bool[](1);
        result[0] = x1;
        return result;
    }

    function toArray(bool x1, bool x2) public pure returns (bool[] memory) {
        bool[] memory result = new bool[](2);
        result[0] = x1;
        result[1] = x2;
        return result;
    }

    function toArray(bool x1, bool x2, bool x3) public pure returns (bool[] memory) {
        bool[] memory result = new bool[](3);
        result[0] = x1;
        result[1] = x2;
        result[2] = x3;
        return result;
    }

    /// @dev based on https://gist.github.com/subhodi/b3b86cc13ad2636420963e692a4d896f
    function _quickSort(address[] memory arr, int256 left, int256 right) private pure {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        address pivot = arr[uint256(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint256(i)] < pivot) i++;
            while (pivot < arr[uint256(j)]) j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
                i++;
                j--;
            }
        }
        if (left < j) {
            _quickSort(arr, left, j);
        }
        if (i < right) {
            _quickSort(arr, i, right);
        }
    }

    function sort(address[] memory arr) public pure returns (address[] memory) {
        _quickSort(arr, int256(0), int256(arr.length - 1));

        return arr;
    }
}
