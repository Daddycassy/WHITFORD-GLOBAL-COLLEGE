// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Whitford Merit Points (ERC-20, non-transferable)
// Students earn points for attendance, on-time work and achievements, and spend them on
// campus perks. Points have no cash value and cannot be sent to other wallets.
// Built on OpenZeppelin Contracts v5. In Remix the imports below resolve automatically.

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract WhitfordPoints is ERC20, Ownable, Pausable {
    // Loophole fix: cap on any single award, so a misused college key cannot print unlimited points.
    uint256 public constant MAX_AWARD_PER_CALL = 500;

    // Loophole fix: only currently enrolled students (verified by the college) can hold points.
    mapping(address => bool) public enrolled;

    struct Perk {
        string name;
        uint256 cost; // in points
        bool active;
    }
    mapping(uint256 => Perk) public perks;

    event StudentEnrolled(address indexed wallet, bool status);
    event PointsAwarded(address indexed student, uint256 amount, string reason);
    event PerkSet(uint256 indexed perkId, string name, uint256 cost, bool active);
    event PerkRedeemed(address indexed student, uint256 indexed perkId, uint256 cost);

    // 'college' is the issuing address. In production this should be a multisig wallet.
    constructor(address college)
        ERC20("Whitford Merit Points", "WGCP")
        Ownable(college)
    {}

    // Whole points only.
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    // The college marks a wallet as belonging to an enrolled student. One wallet per student is
    // enforced off-chain in the college's student records system.
    function setEnrolled(address wallet, bool status) external onlyOwner {
        enrolled[wallet] = status;
        emit StudentEnrolled(wallet, status);
    }

    // Award points for an achievement. The reason is recorded in the event for audit.
    function awardPoints(address student, uint256 amount, string calldata reason) external onlyOwner {
        require(amount > 0 && amount <= MAX_AWARD_PER_CALL, "Amount exceeds cap");
        _mint(student, amount);
        emit PointsAwarded(student, amount, reason);
    }

    // The college defines or changes a perk, e.g. (1, "Printing credit EUR 5", 50, true).
    function setPerk(uint256 perkId, string calldata name, uint256 cost, bool active) external onlyOwner {
        require(cost > 0, "Cost must be above zero");
        perks[perkId] = Perk(name, cost, active);
        emit PerkSet(perkId, name, cost, active);
    }

    // An enrolled student spends their own points. The points are burned; the college then
    // delivers the perk through its normal systems (canteen, print service, library).
    function redeem(uint256 perkId) external whenNotPaused {
        require(enrolled[msg.sender], "Student not enrolled");
        Perk memory p = perks[perkId];
        require(p.active, "Perk not available");
        _burn(msg.sender, p.cost); // reverts if the balance is too low
        emit PerkRedeemed(msg.sender, perkId, p.cost);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Every mint, transfer and burn passes through here (OpenZeppelin v5).
    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        // Non-transferable: only minting (from == 0) and burning (to == 0) are allowed.
        require(from == address(0) || to == address(0), "Points are non-transferable");
        // Minting: the receiver must be an enrolled student.
        if (from == address(0)) {
            require(enrolled[to], "Student not enrolled");
        }
        super._update(from, to, value);
    }
}
