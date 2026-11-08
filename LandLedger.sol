// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title LandLedger
 * @notice Blockchain-based Land Registry & Property Marketplace
 *         DHA Phase 1, Rawalpindi — Sepolia Testnet
 * @dev Supports full plot registration, ownership transfer,
 *      marketplace listings, partial plot splitting, and admin controls.
 */
contract LandLedger {

    // ─────────────────────────────────────────────
    //  STRUCTS
    // ─────────────────────────────────────────────

    struct Plot {
        string  plotId;          // e.g. "A-101"
        string  block_;          // "A" | "B" | "C" | "D" | "E" | "F"
        string  size;            // "5 Marla" | "10 Marla" | "1 Kanal" | "2 Kanal"
        uint16  marla;           // numeric marla value
        string  plotType;        // "Residential" | "Commercial"
        address owner;           // current owner wallet
        PlotStatus status;       // Available | ForSale | Partial | Sold
        uint256 askingPriceWei;  // 0 if not listed
        uint8   partialPct;      // % being sold (0 = full, else 25/50/75)
        string  notes;           // seller notes
        bool    exists;          // guard flag
    }

    struct TransferRecord {
        address from;
        address to;
        uint256 priceWei;
        uint256 timestamp;
        string  transferType;   // "First Allotment" | "Sale" | "Partial Sale" | "Inheritance"
    }

    struct Listing {
        string  plotId;
        address seller;
        uint256 priceWei;
        uint8   partialPct;     // 100 = full plot
        bool    active;
    }

    enum PlotStatus { Available, ForSale, Partial, Sold }

    // ─────────────────────────────────────────────
    //  STATE
    // ─────────────────────────────────────────────

    address public admin;

    // plotId => Plot
    mapping(string => Plot) public plots;

    // plotId => history array
    mapping(string => TransferRecord[]) public ownershipHistory;

    // plotId => active Listing
    mapping(string => Listing) public listings;

    // owner address => list of plotIds they own
    mapping(address => string[]) public ownerPlots;

    // all registered plot IDs (for enumeration)
    string[] public allPlotIds;

    // platform fee in basis points (e.g. 200 = 2%)
    uint16 public feeBps = 200;

    // accumulated platform fees
    uint256 public platformFees;

    // ─────────────────────────────────────────────
    //  EVENTS
    // ─────────────────────────────────────────────

    event PlotRegistered(
        string indexed plotId,
        address indexed owner,
        string size,
        string block_
    );

    event PlotListed(
        string indexed plotId,
        address indexed seller,
        uint256 priceWei,
        uint8   partialPct
    );

    event PlotDelisted(string indexed plotId, address indexed seller);

    event PlotSold(
        string indexed plotId,
        address indexed from,
        address indexed to,
        uint256 priceWei,
        uint8   partialPct,
        uint256 timestamp
    );

    event PlotSplit(
        string indexed originalPlotId,
        string  newPlotId,
        uint16  soldMarla,
        uint16  retainedMarla,
        address indexed buyer
    );

    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);

    // ─────────────────────────────────────────────
    //  MODIFIERS
    // ─────────────────────────────────────────────

    modifier onlyAdmin() {
        require(msg.sender == admin, "LandLedger: caller is not admin");
        _;
    }

    modifier plotMustExist(string memory plotId) {
        require(plots[plotId].exists, "LandLedger: plot does not exist");
        _;
    }

    modifier onlyOwner(string memory plotId) {
        require(plots[plotId].owner == msg.sender, "LandLedger: caller is not plot owner");
        _;
    }

    // ─────────────────────────────────────────────
    //  CONSTRUCTOR
    // ─────────────────────────────────────────────

    constructor() {
        admin = msg.sender;
    }

    // ─────────────────────────────────────────────
    //  ADMIN: REGISTER PLOT
    //  Called once per plot during society setup
    // ─────────────────────────────────────────────

    /**
     * @notice Register a new plot in the registry (admin only)
     * @param plotId    Unique plot identifier, e.g. "A-101"
     * @param block_    Society block, e.g. "A"
     * @param size      Human-readable size, e.g. "10 Marla"
     * @param marla     Numeric marla value, e.g. 10
     * @param plotType  "Residential" or "Commercial"
     * @param owner     Initial owner wallet address
     * @param notes     Any notes about the plot
     */
    function registerPlot(
        string  memory plotId,
        string  memory block_,
        string  memory size,
        uint16         marla,
        string  memory plotType,
        address        owner,
        string  memory notes
    ) external onlyAdmin {
        require(!plots[plotId].exists, "LandLedger: plot already registered");
        require(owner != address(0), "LandLedger: invalid owner address");

        plots[plotId] = Plot({
            plotId:         plotId,
            block_:         block_,
            size:           size,
            marla:          marla,
            plotType:       plotType,
            owner:          owner,
            status:         PlotStatus.Available,
            askingPriceWei: 0,
            partialPct:     0,
            notes:          notes,
            exists:         true
        });

        allPlotIds.push(plotId);
        ownerPlots[owner].push(plotId);

        ownershipHistory[plotId].push(TransferRecord({
            from:         address(0),
            to:           owner,
            priceWei:     0,
            timestamp:    block.timestamp,
            transferType: "First Allotment"
        }));

        emit PlotRegistered(plotId, owner, size, block_);
    }

    // ─────────────────────────────────────────────
    //  LIST PLOT FOR SALE
    // ─────────────────────────────────────────────

    /**
     * @notice List your plot (or a portion) for sale on the marketplace
     * @param plotId      Plot to list
     * @param priceWei    Asking price in wei
     * @param partialPct  Percentage to sell: 25, 50, 75, or 100
     *                    Must be 100 if plot is < 8 marla (can't split tiny plots)
     */
    function listForSale(
        string memory plotId,
        uint256       priceWei,
        uint8         partialPct
    ) external plotMustExist(plotId) onlyOwner(plotId) {
        Plot storage p = plots[plotId];

        require(p.status == PlotStatus.Available, "LandLedger: plot is not available");
        require(priceWei > 0, "LandLedger: price must be > 0");
        require(
            partialPct == 25 || partialPct == 50 || partialPct == 75 || partialPct == 100,
            "LandLedger: partialPct must be 25, 50, 75, or 100"
        );
        if (partialPct < 100) {
            require(p.marla >= 8, "LandLedger: plot too small to split");
        }

        p.status         = (partialPct == 100) ? PlotStatus.ForSale : PlotStatus.Partial;
        p.askingPriceWei = priceWei;
        p.partialPct     = partialPct;

        listings[plotId] = Listing({
            plotId:     plotId,
            seller:     msg.sender,
            priceWei:   priceWei,
            partialPct: partialPct,
            active:     true
        });

        emit PlotListed(plotId, msg.sender, priceWei, partialPct);
    }

    // ─────────────────────────────────────────────
    //  DELIST PLOT
    // ─────────────────────────────────────────────

    /**
     * @notice Remove your plot listing from the marketplace
     */
    function delistPlot(string memory plotId)
        external
        plotMustExist(plotId)
        onlyOwner(plotId)
    {
        Plot storage p = plots[plotId];
        require(
            p.status == PlotStatus.ForSale || p.status == PlotStatus.Partial,
            "LandLedger: plot is not listed"
        );

        p.status         = PlotStatus.Available;
        p.askingPriceWei = 0;
        p.partialPct     = 0;
        listings[plotId].active = false;

        emit PlotDelisted(plotId, msg.sender);
    }

    // ─────────────────────────────────────────────
    //  BUY PLOT
    // ─────────────────────────────────────────────

    /**
     * @notice Purchase a listed plot (full or partial)
     *
     * Full purchase (partialPct == 100):
     *   - Ownership transfers entirely to buyer
     *
     * Partial purchase (partialPct < 100):
     *   - A new plot entry is created for the sold portion
     *   - Original plot is updated with reduced marla
     *   - New plot ID = originalId + "-S" (e.g. "B-203-S")
     *
     * Platform fee (feeBps / 10000) is deducted before paying seller.
     */
    function buyPlot(string memory plotId)
        external
        payable
        plotMustExist(plotId)
    {
        Plot storage p = plots[plotId];
        require(
            p.status == PlotStatus.ForSale || p.status == PlotStatus.Partial,
            "LandLedger: plot is not for sale"
        );
        require(msg.sender != p.owner, "LandLedger: cannot buy your own plot");
        require(msg.value >= p.askingPriceWei, "LandLedger: insufficient payment");

        address seller      = p.owner;
        uint256 salePrice   = p.askingPriceWei;
        uint8   pct         = p.partialPct;
        uint256 fee         = (salePrice * feeBps) / 10_000;
        uint256 sellerShare = salePrice - fee;
        platformFees       += fee;

        // Refund overpayment
        if (msg.value > salePrice) {
            payable(msg.sender).transfer(msg.value - salePrice);
        }

        if (pct == 100) {
            // ── Full transfer ──────────────────────────
            _removeFromOwnerList(seller, plotId);
            p.owner          = msg.sender;
            p.status         = PlotStatus.Available;
            p.askingPriceWei = 0;
            p.partialPct     = 0;
            ownerPlots[msg.sender].push(plotId);
            listings[plotId].active = false;

            ownershipHistory[plotId].push(TransferRecord({
                from:         seller,
                to:           msg.sender,
                priceWei:     salePrice,
                timestamp:    block.timestamp,
                transferType: "Sale"
            }));

            emit PlotSold(plotId, seller, msg.sender, salePrice, 100, block.timestamp);

        } else {
            // ── Partial split ──────────────────────────
            uint16 soldMarla     = uint16((uint256(p.marla) * pct) / 100);
            uint16 retainedMarla = p.marla - soldMarla;

            // Create new plot for sold portion
            string memory newId = string(abi.encodePacked(plotId, "-S"));
            require(!plots[newId].exists, "LandLedger: split plot ID collision, rename manually");

            plots[newId] = Plot({
                plotId:         newId,
                block_:         p.block_,
                size:           _marlaToSize(soldMarla),
                marla:          soldMarla,
                plotType:       p.plotType,
                owner:          msg.sender,
                status:         PlotStatus.Available,
                askingPriceWei: 0,
                partialPct:     0,
                notes:          string(abi.encodePacked("Split from ", plotId)),
                exists:         true
            });
            allPlotIds.push(newId);
            ownerPlots[msg.sender].push(newId);

            ownershipHistory[newId].push(TransferRecord({
                from:         seller,
                to:           msg.sender,
                priceWei:     salePrice,
                timestamp:    block.timestamp,
                transferType: "Partial Sale"
            }));

            // Update original plot
            p.marla          = retainedMarla;
            p.size           = _marlaToSize(retainedMarla);
            p.status         = PlotStatus.Available;
            p.askingPriceWei = 0;
            p.partialPct     = 0;
            listings[plotId].active = false;

            ownershipHistory[plotId].push(TransferRecord({
                from:         seller,
                to:           seller,
                priceWei:     0,
                timestamp:    block.timestamp,
                transferType: "Partial Split (retained)"
            }));

            emit PlotSold(plotId, seller, msg.sender, salePrice, pct, block.timestamp);
            emit PlotSplit(plotId, newId, soldMarla, retainedMarla, msg.sender);
        }

        // Pay seller
        payable(seller).transfer(sellerShare);
    }

    // ─────────────────────────────────────────────
    //  ADMIN: INHERITANCE / AUTHORITY TRANSFER
    // ─────────────────────────────────────────────

    /**
     * @notice Transfer ownership without payment (inheritance, court order, etc.)
     *         Only callable by admin (DHA Authority)
     */
    function authorityTransfer(
        string  memory plotId,
        address        newOwner,
        string  memory reason
    ) external onlyAdmin plotMustExist(plotId) {
        require(newOwner != address(0), "LandLedger: invalid address");
        Plot storage p = plots[plotId];
        address prevOwner = p.owner;

        _removeFromOwnerList(prevOwner, plotId);
        p.owner          = newOwner;
        p.status         = PlotStatus.Available;
        p.askingPriceWei = 0;
        listings[plotId].active = false;
        ownerPlots[newOwner].push(plotId);

        ownershipHistory[plotId].push(TransferRecord({
            from:         prevOwner,
            to:           newOwner,
            priceWei:     0,
            timestamp:    block.timestamp,
            transferType: reason
        }));

        emit PlotSold(plotId, prevOwner, newOwner, 0, 100, block.timestamp);
    }

    // ─────────────────────────────────────────────
    //  UPDATE NOTES
    // ─────────────────────────────────────────────

    function updateNotes(string memory plotId, string memory notes)
        external
        plotMustExist(plotId)
        onlyOwner(plotId)
    {
        plots[plotId].notes = notes;
    }

    // ─────────────────────────────────────────────
    //  ADMIN: WITHDRAW FEES
    // ─────────────────────────────────────────────

    function withdrawFees() external onlyAdmin {
        uint256 amount = platformFees;
        platformFees   = 0;
        payable(admin).transfer(amount);
    }

    function setFeeBps(uint16 _feeBps) external onlyAdmin {
        require(_feeBps <= 1000, "LandLedger: fee cannot exceed 10%");
        feeBps = _feeBps;
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "LandLedger: zero address");
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    // ─────────────────────────────────────────────
    //  READ FUNCTIONS
    // ─────────────────────────────────────────────

    /// @notice Get full plot details
    function getPlot(string memory plotId)
        external
        view
        plotMustExist(plotId)
        returns (Plot memory)
    {
        return plots[plotId];
    }

    /// @notice Get ownership history for a plot
    function getHistory(string memory plotId)
        external
        view
        plotMustExist(plotId)
        returns (TransferRecord[] memory)
    {
        return ownershipHistory[plotId];
    }

    /// @notice Get all plot IDs owned by an address
    function getOwnerPlots(address owner)
        external
        view
        returns (string[] memory)
    {
        return ownerPlots[owner];
    }

    /// @notice Total number of registered plots
    function totalPlots() external view returns (uint256) {
        return allPlotIds.length;
    }

    /// @notice Get all plot IDs (use with pagination for large registries)
    function getAllPlotIds() external view returns (string[] memory) {
        return allPlotIds;
    }

    /// @notice Get active listing for a plot
    function getListing(string memory plotId)
        external
        view
        returns (Listing memory)
    {
        return listings[plotId];
    }

    // ─────────────────────────────────────────────
    //  INTERNAL HELPERS
    // ─────────────────────────────────────────────

    function _removeFromOwnerList(address owner, string memory plotId) internal {
        string[] storage arr = ownerPlots[owner];
        for (uint256 i = 0; i < arr.length; i++) {
            if (keccak256(bytes(arr[i])) == keccak256(bytes(plotId))) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                break;
            }
        }
    }

    function _marlaToSize(uint16 marla) internal pure returns (string memory) {
        if (marla >= 40) return "2 Kanal";
        if (marla >= 20) return "1 Kanal";
        if (marla >= 10) return "10 Marla";
        return "5 Marla";
    }
}
