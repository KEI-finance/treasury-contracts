// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "./interfaces/ITreasury.sol";
import "./libraries/TreasuryLibrary.sol";

contract Treasury is ITreasury, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant override SKIM_ROLE = keccak256("SKIM_ROLE");

    mapping(address => uint256) private $reserves;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ITreasury).interfaceId || super.supportsInterface(interfaceId);
    }

    function balanceOf(address asset) external view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function reserves(address asset) external view override returns (uint256) {
        return $reserves[asset];
    }

    function roleOf(address asset) public pure override returns (bytes32) {
        return TreasuryLibrary.roleOf(asset);
    }

    function withdraw(address asset, address recipient, uint256 amount)
        external
        override
        whenNotPaused
        onlyRole(roleOf(asset))
        returns (uint256 reserves_)
    {
        reserves_ = _relinquish($reserves[asset], asset, amount);

        _withdraw(asset, recipient, amount);
    }

    function relinquish(address asset, uint256 amount)
        external
        override
        whenNotPaused
        onlyRole(roleOf(asset))
        returns (uint256 reserves_)
    {
        reserves_ = _relinquish($reserves[asset], asset, amount);
    }

    function sync(address asset, uint256 maxToSync) external override whenNotPaused returns (uint256 received) {
        ($reserves[asset], received) = _sync($reserves[asset], asset, maxToSync);
    }

    function syncAndWithdraw(address asset, address recipient, uint256 amount, uint256 maxToSync)
        external
        override
        whenNotPaused
        onlyRole(roleOf(asset))
        returns (uint256 reserves_, uint256 received)
    {
        (reserves_, received) = _sync($reserves[asset], asset, maxToSync);

        reserves_ = _relinquish(reserves_, asset, amount);

        _withdraw(asset, recipient, amount);
    }

    function skim(address asset, address recipient)
        external
        override
        whenNotPaused
        onlyRole(SKIM_ROLE)
        returns (uint256 sent)
    {
        uint256 _balance = IERC20(asset).balanceOf(address(this));
        uint256 _reserves = $reserves[asset];

        if (_balance > _reserves) {
            unchecked {
                sent = _balance - _reserves;
            }

            IERC20(asset).safeTransfer(recipient, sent);

            emit Skim(asset, sent, recipient, _msgSender());
        }
    }

    function _relinquish(uint256 reserves_, address asset, uint256 amount) private returns (uint256 newReserves) {
        require(amount > 0, "Treasury: ZERO_AMOUNT");
        require(reserves_ >= amount, "Treasury: INSUFFICIENT_RESERVES");

        unchecked {
            newReserves = reserves_ - amount;
        }

        $reserves[asset] = newReserves;

        emit Relinquish(asset, amount, _msgSender());
    }

    function _sync(uint256 prevReserves, address asset, uint256 maxToSync)
        private
        returns (uint256 newReserves, uint256 received)
    {
        newReserves = IERC20(asset).balanceOf(address(this));

        if (newReserves > prevReserves) {
            unchecked {
                received = newReserves - prevReserves;

                if (maxToSync > 0 && received > maxToSync) {
                    newReserves = prevReserves + maxToSync;
                    received = maxToSync;
                }
            }

            emit Deposit(asset, received, _msgSender());
        } else if (newReserves < prevReserves) {
            // this should hopefully never be emitted
            emit Loss(asset, prevReserves - newReserves, _msgSender());
        }
    }

    function _withdraw(address asset, address recipient, uint256 amount) private {
        require(recipient != address(0), "Treasury: ZERO_ADDRESS");

        IERC20(asset).safeTransfer(recipient, amount);

        emit Withdraw(asset, recipient, amount, _msgSender());
    }
}
