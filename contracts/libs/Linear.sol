// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

library Linear {
    using SafeMath for uint256;

    struct Account {
        uint256 total;
        uint256 released;
        uint256 relay;
        uint256 lastRelease;
        uint256 duration;
    }

    function add(
        Account storage a,
        uint256 value,
        uint256 startTimestamp,
        uint256 duration
    ) internal {
        if (a.duration == 0) {
            a.duration = duration;
        }
        if (a.lastRelease == 0) {
            a.lastRelease = startTimestamp;
        }

        uint256 _pending = pending(a);

        if (_pending > 0) {
            a.lastRelease = block.timestamp;
            a.relay = a.relay.add(_pending);
        }

        a.total = a.total.add(value);
    }

    function release(Account storage a) internal returns (uint256) {
        if (a.total == 0) {
            return 0;
        }

        uint256 _pending = pending(a);
        uint256 paid = a.relay.add(_pending);

        if (paid > 0) {
            a.relay = 0;
            a.lastRelease = block.timestamp;
            a.released = a.released.add(paid);
        }

        return paid;
    }

    function locked(Account storage a) internal view returns (uint256) {
        uint256 _pending = pending(a);
        return a.total.sub(a.released).sub(a.relay).sub(_pending);
    }

    function pendingRelease(Account storage a) internal view returns (uint256) {
        uint256 _pending = pending(a);
        return a.relay.add(_pending);
    }

    function pending(Account storage a) internal view returns (uint256) {
        if (a.lastRelease > block.timestamp || a.duration == 0) {
            return 0;
        }

        uint256 totalSec = block.timestamp.sub(a.lastRelease);
        uint256 paid = a.total.div(a.duration).mul(totalSec);

        if (a.released.add(a.relay) > 0) {
            paid = paid.sub(
                a.released.add(a.relay).div(a.duration).mul(totalSec)
            );
        }

        uint256 amount = a.released.add(a.relay).add(paid);

        if (amount > a.total) {
            return paid.sub(amount.sub(a.total));
        }

        return paid;
    }
}
