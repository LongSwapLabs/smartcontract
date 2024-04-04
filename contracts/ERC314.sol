// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";

interface IEERC314 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event AddLiquidity(uint32 _blockToUnlockLiquidity, uint256 value);
    event RemoveLiquidity(uint256 value);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out
    );
}

abstract contract ERC314 is Context, Ownable, IEERC314 {
    mapping(address account => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    uint256 public _maxWallet;
    uint32 public blockToUnlockLiquidity;
    uint32 public coolingBlock;
    uint32 public sellTax;
    uint32 public buyTax;

    mapping(address => bool) public excludeCoolingOf;

    string private _name;
    string private _symbol;

    address public liquidityProvider;

    bool public liquidityAdded;

    uint256 public constant _rebaseDuration = 1 hours;
    uint256 public _rebaseRate = 25;
    uint256 public _lastRebaseTime;

    mapping(address account => uint32) private lastTransaction;

    uint256 presaleAmount;
    bool public presaleEnable = false;

    modifier onlyLiquidityProvider() {
        require(
            _msgSender() == liquidityProvider,
            "You are not the liquidity provider"
        );
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        uint32 _coolingBlock,
        uint32 _sellTax,
        uint32 _buyTax
    ) {
        _name = name_;
        _symbol = symbol_;
        _totalSupply = totalSupply_;

        _maxWallet = totalSupply_ / 200;

        coolingBlock = _coolingBlock;
        sellTax = _sellTax;
        buyTax = _buyTax;

        _lastRebaseTime = block.timestamp + 1 days;

        presaleAmount = (totalSupply_ * 2) / 10;

        uint256 liquidityAmount = totalSupply_ - presaleAmount;
        _balances[address(this)] = liquidityAmount;
    }

    function presale(address[] memory _investors) public onlyOwner {
        require(presaleEnable == false, "Presale already enabled");
        uint256 _amount = presaleAmount / _investors.length;
        for (uint256 i = 0; i < _investors.length; i++) {
            _balances[_investors[i]] += _amount;
        }
        presaleEnable = true;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    function allowance(
        address owner,
        address spender
    ) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);

        if (to == address(this)) {
            sell(from, amount);
        } else {
            _transfer(from, to, amount);
        }

        return true;
    }

    function transfer(address to, uint256 value) public virtual returns (bool) {
        // sell or transfer
        if (to == address(this)) {
            sell(_msgSender(), value);
        } else {
            _transfer(_msgSender(), to, value);
        }
        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC20: insufficient allowance"
            );
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(to != address(0), "ERC20: transfer to the zero address");

        if (!excludeCoolingOf[_msgSender()]) {
            require(
                lastTransaction[_msgSender()] + coolingBlock < block.number,
                "You can't make two transactions in the cooling block"
            );
            lastTransaction[_msgSender()] = uint32(block.number);
        }

        uint256 fromBalance = _balances[from];
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function _basicTransfer(address from, address to, uint256 amount) internal {
        require(
            _balances[from] >= amount,
            "ERC20: transfer amount exceeds balance"
        );

        unchecked {
            _balances[from] -= amount;
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function getReserves() public view returns (uint256, uint256) {
        return (address(this).balance, _balances[address(this)]);
    }

    function setMaxWallet(uint256 _maxWallet_) external onlyOwner {
        _maxWallet = _maxWallet_;
    }

    function setLastTransaction(
        address[] memory accounts,
        uint32 _block
    ) external onlyOwner {
        for (uint i = 0; i < accounts.length; i++) {
            lastTransaction[accounts[i]] = _block;
        }
    }

    function setExcludeCoolingOf(
        address[] memory accounts,
        bool _ok
    ) external onlyOwner {
        for (uint i = 0; i < accounts.length; i++) {
            excludeCoolingOf[accounts[i]] = _ok;
        }
    }

    function setBuyTax(uint32 _buyTax) external onlyOwner {
        require(_buyTax <= 50, "Tax is too big");
        buyTax = _buyTax;
    }

    function setSellTax(uint32 _sellTax) external onlyOwner {
        require(_sellTax <= 50, "Tax is too big");
        sellTax = _sellTax;
    }

    function setCooling(uint32 _coolingBlock) external onlyOwner {
        require(_coolingBlock <= 100, "Cooling is too big");
        coolingBlock = _coolingBlock;
    }

    function addLiquidity(
        uint32 _blockToUnlockLiquidity
    ) public payable onlyOwner {
        require(liquidityAdded == false, "Liquidity already added");

        liquidityAdded = true;

        require(msg.value > 0, "No ETH sent");
        require(block.number < _blockToUnlockLiquidity, "Block number too low");

        blockToUnlockLiquidity = _blockToUnlockLiquidity;
        liquidityProvider = _msgSender();

        emit AddLiquidity(_blockToUnlockLiquidity, msg.value);
    }

    function removeLiquidity() public onlyLiquidityProvider {
        require(block.number > blockToUnlockLiquidity, "Liquidity locked");

        liquidityAdded = false;

        payable(liquidityProvider).transfer(address(this).balance);

        emit RemoveLiquidity(address(this).balance);
    }

    function extendLiquidityLock(
        uint32 _blockToUnlockLiquidity
    ) public onlyLiquidityProvider {
        require(
            blockToUnlockLiquidity < _blockToUnlockLiquidity,
            "You can't shorten duration"
        );

        blockToUnlockLiquidity = _blockToUnlockLiquidity;
    }

    function getAmountOut(
        uint256 value,
        bool _buy
    ) public view returns (uint256) {
        (uint256 reserveETH, uint256 reserveToken) = getReserves();

        if (_buy) {
            return (value * reserveToken) / (reserveETH + value);
        } else {
            return (value * reserveETH) / (reserveToken + value);
        }
    }

    function buy() internal {
        require(liquidityAdded, "Trading not enable");
        require(msg.sender == tx.origin, "Only external calls allowed");

        address owner = _msgSender();

        uint256 tokenAmount = (msg.value * _balances[address(this)]) /
            (address(this).balance);

        require(
            tokenAmount + _balances[owner] <= _maxWallet,
            "Max wallet exceeded"
        );

        uint256 fee = (tokenAmount * buyTax) / 100;
        _transfer(address(this), owner, tokenAmount - fee);
        _basicTransfer(address(this), address(0xdead), fee);

        emit Swap(owner, msg.value, 0, 0, tokenAmount);
    }

    function sell(address owner, uint256 amount) internal {
        require(liquidityAdded, "Trading not enable");
        require(msg.sender == tx.origin, "Only external calls allowed");

        uint256 fee = (amount * sellTax) / 100;
        uint256 sellAmount = amount - fee;

        uint256 ethAmount = (sellAmount * address(this).balance) /
            (_balances[address(this)] + sellAmount);

        require(ethAmount > 0, "Sell amount too low");
        require(
            address(this).balance >= ethAmount,
            "Insufficient ETH in reserves"
        );

        _transfer(owner, address(this), amount);
        _basicTransfer(address(this), address(0xdead), fee);

        payable(owner).transfer(ethAmount);

        emit Swap(owner, 0, amount, ethAmount, 0);
    }

    function rebase() external {
        uint256 lastRebaseTime = _lastRebaseTime;
        if (0 == lastRebaseTime) {
            return;
        }

        uint256 nowTime = block.timestamp;
        if (nowTime < lastRebaseTime + _rebaseDuration) {
            return;
        }

        _lastRebaseTime = nowTime;

        uint256 poolBalance = _balances[address(this)];
        uint256 rebaseAmount = (((poolBalance * _rebaseRate) / 10000) *
            (nowTime - lastRebaseTime)) / _rebaseDuration;

        if (rebaseAmount > poolBalance / 2) {
            rebaseAmount = poolBalance / 2;
        }

        if (rebaseAmount > 0) {
            _basicTransfer(address(this), address(0xdead), rebaseAmount);
        }
    }

    receive() external payable {
        buy();
    }
}
