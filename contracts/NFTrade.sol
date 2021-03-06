// SPDX-License-Identifier: MIT
pragma solidity ^0.8;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NFTrade {
  address[][] public participants; // participants[tradeId] == array of each owner participating in a trade
  address[][] public tokenContracts; // tokenContracts[tradeId] == array of each NFT involved in a trade
  uint[][] public tokenIds; // tokenIds[tradeId] == array of token IDs involved in a trade
  uint[] public expirations; // expirations[tradeId] == expiration time for swap (0 for no expiration)

  /** @dev Emitted when a swap is created.
   *  @param _id ID of swap.
   *  @param _creator Creator of swap.
   *  @param _recipient Recipient of swap. 
   */
  event SwapCreated(uint _id, address indexed _creator, address indexed _recipient);

  /** @dev Requires that caller is the creator of a certain swap.
   *  @param _id ID of the swap.
   */
  modifier onlySwapCreator(uint _id) {
    address[] memory arr = participants[_id];
    require(arr[0] == msg.sender, "Caller must be swap creator.");
    _;
  }

  /** @dev Requires that caller is the recipient of a certain swap.
   *  @param _id ID of the swap.
   */
  modifier onlySwapRecipient(uint _id) {
    address[] memory arr = participants[_id];
    require(arr[arr.length - 1] == msg.sender, "Caller must be swap recipient.");
    _;
  }

  /** @dev Creates a swap for a recipient to approve.
   *  @param _recipient Recipient of the swap.
   *  @param _recipientIndex The index in the _tokenContracts and _tokenIds arrays
   *    at which the creator's tokens for trade are separated 
   *    by the recipient's tokens for trade.
   *  @param _tokenContracts The contracts for the tokens that will be swapped.
   *    The array begins with the contracts of the creator's tokens for trade
   *    and ends with the contracts of the recipient's tokens for trade, 
   *    with _recipientIndex indicating where they are separated.
   *  @param _tokenIds The IDs for the tokens that will be swapped.
   *    The array begins with the IDs of the creator's tokens for trade
   *    and ends with the IDs of the recipient's tokens for trade, 
   *    with _recipientIndex indicating where they are separated.
   *  @param _expiresIn Time in seconds until expiration. Pass 0 for no expiration.
   */
  function createSwap(
    address _recipient,
    uint _recipientIndex,
    address[] memory _tokenContracts, 
    uint[] memory _tokenIds,
    uint _expiresIn
  ) public {
    uint id = participants.length;
    require(
      _tokenContracts.length == _tokenIds.length,
      "Input array lengths do not match."
    );
    require(_tokenContracts.length >= 2, "Arrays not long enough.");
    require(_recipient != address(0), "Swap recipient cannot be 0x0.");
    require(
      _recipientIndex > 0 && _recipientIndex < _tokenContracts.length,
      "Invalid recipient index."
    );
    address[] memory _participants = new address[](_tokenContracts.length);
    for (uint i = 0; i < _tokenContracts.length; i++) {
      for (uint j = 0; j < i; j++) {
        if (_tokenContracts[i] == _tokenContracts[j] && _tokenIds[i] == _tokenIds[j])
          revert("Duplicate tokens.");
      }
      IERC721 tokenContract = IERC721(_tokenContracts[i]);
      address owner = (i < _recipientIndex) ? msg.sender : _recipient;
      require(
        tokenContract.ownerOf(_tokenIds[i]) == owner, 
        "Invalid token owner."
      );
      _participants[i] = owner;
    }
    participants.push(_participants);
    tokenContracts.push(_tokenContracts);
    tokenIds.push(_tokenIds);
    expirations.push(_expiresIn == 0 ? 0 : block.timestamp + _expiresIn);
    emit SwapCreated(id, msg.sender, _recipient);
  }

  /** @dev Executes a swap. Called by the recipient.
   *  @param _id ID of the swap.
   */
  function executeSwap(uint _id) onlySwapRecipient(_id) public {
    require(
      expirations[_id] == 0 || expirations[_id] >= block.timestamp,
      "Swap has expired."
    );
    address[] memory swapParticipants = participants[_id];
    address[] memory swapContractAddresses = tokenContracts[_id];
    for (uint i = 0; i < swapContractAddresses.length; i++) {
      IERC721 tokenContract = IERC721(swapContractAddresses[i]);
      bool tokenApproved = tokenContract.isApprovedForAll(swapParticipants[i], address(this)) 
        || tokenContract.getApproved(tokenIds[_id][i]) == address(this);
      require(tokenApproved, "Token not approved.");
    }
    for (uint i = 0; i < swapParticipants.length; i++) {
      IERC721 tokenContract = IERC721(swapContractAddresses[i]);
      address to = swapParticipants[(swapParticipants[i] == msg.sender) ? 0 : swapParticipants.length - 1]; 
      tokenContract.safeTransferFrom(swapParticipants[i], to, tokenIds[_id][i]);
    }
    _invalidateSwap(_id);
  }

  /** @dev Called by creator of swap to unapprove it for execution.
   *  @param _id ID of the swap.
   */
  function unapproveSwap(uint _id) onlySwapCreator(_id) public {
    _invalidateSwap(_id);
  }

  /** @dev Invalidates a swap from future execution.
   *  @param _id ID of the swap.
   */
  function _invalidateSwap(uint _id) private {
    expirations[_id] = block.timestamp;
  }
}
