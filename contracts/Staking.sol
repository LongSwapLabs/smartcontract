// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./libs/Linear.sol";
import "./interfaces/IERC314.sol";

contract Staking is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using Linear for Linear.Account;

    IERC20 public x314;

    uint256 public duration;
    mapping(address => Linear.Account) public accountOf;

    IERC20 public usdt;
    bool public lotteryEnable;
    mapping(address => mapping(uint256 => bool)) public lotteryOf;

    function initialize(IERC20 _x314) public initializer {
        x314 = _x314;
        duration = 30 days;

        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function deposit(uint256 amount) public {
        require(amount > 0, "Amount error");
        _deposit(msg.sender, amount);
    }

    function depositByReferrer(uint256 amount, address referrer) public {
        require(amount > 0, "Amount error");
        _deposit(msg.sender, amount);

        if (referrer != address(0) && referrer != msg.sender) {
            accountOf[referrer].add(
                (amount * 10) / 100,
                block.timestamp,
                duration
            );
        }
    }

    function _deposit(address user, uint256 amount) internal {
        _unlock();
        x314.safeTransferFrom(user, address(this), amount);
        accountOf[user].add(amount * 2, block.timestamp, duration);
    }

    function claim() public {
        uint256 amount = accountOf[msg.sender].release();
        if (amount > 0) {
            _unlock();
            _safeTransfer(msg.sender, amount);
        }
    }

    function tryLottery() public {
        require(lotteryEnable, "Not open");

        uint256 today = block.timestamp / 86400;
        require(!lotteryOf[msg.sender][today], "Has Lottery");

        lotteryOf[msg.sender][today] = true;

        uint256 randomness = _generateRandomNumber();
        uint256 rewardChance = randomness % 100;

        if (rewardChance < 5) {
            if (accountOf[msg.sender].total >= 100000 * 1e18) {
                usdt.safeTransfer(msg.sender, 100 * 1e18);
            } else if (accountOf[msg.sender].total >= 10000 * 1e18) {
                usdt.safeTransfer(msg.sender, 20 * 1e18);
            }
        }
    }

    function pending(address user) public view returns (uint256) {
        return accountOf[user].pendingRelease();
    }

    function hasLotteryToday(address user) public view returns (bool) {
        uint256 today = block.timestamp / 86400;
        return lotteryOf[user][today];
    }

    function _generateRandomNumber() public view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        msg.sender,
                        block.coinbase,
                        x314.balanceOf(address(this)),
                        block.number
                    )
                )
            );
    }

    function _safeTransfer(address to, uint256 amount) internal {
        x314.safeTransfer(to, amount);
    }

    function setUsdt(IERC20 _usdt) public onlyOwner {
        usdt = _usdt;
    }

    function setLotteryEnable(bool _lotteryEnable) public onlyOwner {
        lotteryEnable = _lotteryEnable;
    }

    function _unlock() internal {
        address[] memory accounts = new address[](1);
        accounts[0] = address(this);
        IERC314(address(x314)).setLastTransaction(accounts, 0);
    }
}
