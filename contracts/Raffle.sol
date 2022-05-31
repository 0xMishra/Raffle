//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";

error Raffle_NotEnoughTokensToEnter();
error Raffle_TransferFailed();
error Raffle_NotOpen();
error Raffle_UpkeepNotNeeded(
  uint256 currentBalance,
  uint256 NumberOfPlayers,
  uint256 raffleState
);

/**@title A sample Raffle Contract
 * @notice This contract is for creating a sample raffle contract
 * @dev This implements the Chainlink VRF Version 2
 */
contract Raffle is VRFConsumerBaseV2, KeeperCompatibleInterface {
  enum RaffleState {
    OPEN,
    CALCULATING
  }

  address payable[] private s_players;
  VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
  uint256 private immutable i_entranceFee;
  uint64 private immutable i_subscriptionId;
  bytes32 private immutable i_gasLane;
  uint32 private immutable i_callbackGasLimit;
  uint16 private constant REQUEST_CONFIRMATIONS = 3;
  uint32 private constant NUM_WORDS = 1;

  event LotteryEnter(address indexed player);
  event RequestedRaffleWinner(uint256 indexed requestID);
  event ChosenWinner(address indexed winner);

  address private s_currentWinner;
  RaffleState private s_raffleState;
  uint256 private s_lastTimestamp;
  uint256 private immutable i_interval;

  constructor(
    address vrfCoordinator,
    uint256 _entranceFee,
    bytes32 gasLane,
    uint64 subscriptionId,
    uint32 callbackGasLimit,
    uint256 interval
  ) VRFConsumerBaseV2(vrfCoordinator) {
    i_entranceFee = _entranceFee;
    i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
    i_subscriptionId = subscriptionId;
    i_gasLane = gasLane;
    i_callbackGasLimit = callbackGasLimit;
    s_raffleState = RaffleState.OPEN;
    s_lastTimestamp = block.timestamp;
    i_interval = interval;
  }

  function enterLottery() public payable {
    if (msg.value < i_entranceFee) {
      revert Raffle_NotEnoughTokensToEnter();
    }
    if (s_raffleState != RaffleState.OPEN) {
      revert Raffle_NotOpen();
    }
    s_players.push(payable(msg.sender));
    emit LotteryEnter(msg.sender);
  }

  /*
   *@dev This function is called be chainlink keepers node
   * They look for 'upkeepNeeded' to return true
   * Following should be true in order to return true:
   *1 Our time interval should have passed
   *2 The lottery should have at least 1 player and should have some eth
   *3 Our subscription is funded with ETH
   *4 Our lottery should be in OPEN state
   */

  function checkUpkeep(
    bytes memory /* checkData */
  )
    public
    view
    override
    returns (
      bool upkeepNeeded,
      bytes memory /* performData */
    )
  {
    bool isOpen = RaffleState.OPEN == s_raffleState;
    bool timePassed = ((block.timestamp - s_lastTimestamp) > i_interval);
    bool hasPlayers = s_players.length > 0;
    bool hasBalance = address(this).balance > 0;
    upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);
    return (upkeepNeeded, "0x0");
  }

  function performUpkeep(
    bytes calldata /* performData */
  ) external override {
    (bool upkeepNeeded, ) = checkUpkeep("");

    if (!upkeepNeeded) {
      revert Raffle_UpkeepNotNeeded(
        address(this).balance,
        s_players.length,
        uint256(s_raffleState)
      );
    }
    s_raffleState = RaffleState.CALCULATING;
    uint256 requestId = i_vrfCoordinator.requestRandomWords(
      i_gasLane,
      i_subscriptionId,
      REQUEST_CONFIRMATIONS,
      i_callbackGasLimit,
      NUM_WORDS
    );

    emit RequestedRaffleWinner(requestId);
  }

  function fulfillRandomWords(
    uint256, /*requestId*/
    uint256[] memory randomWords
  ) internal override {
    uint256 indexOfWinner = randomWords[0] % s_players.length;
    address payable currentWinner = s_players[indexOfWinner];
    s_currentWinner = currentWinner;
    s_raffleState = RaffleState.OPEN;
    s_players = new address payable[](0);
    s_lastTimestamp = 0;
    (bool success, ) = currentWinner.call{ value: address(this).balance }("");

    if (!success) {
      revert Raffle_TransferFailed();
    }

    emit ChosenWinner(currentWinner);
  }

  function getEntranceFee() public view returns (uint256) {
    return i_entranceFee;
  }

  function getPlayer(uint256 index) public view returns (address) {
    return s_players[index];
  }

  function getCurrentWinner() public view returns (address) {
    return s_currentWinner;
  }

  function getRaffleState() public view returns (RaffleState) {
    return s_raffleState;
  }

  function getNumWords() public pure returns (uint256) {
    return NUM_WORDS;
  }

  function getNumberOfPlayers() public view returns (uint256) {
    return s_players.length;
  }

  function getLatestTimestamp() public view returns (uint256) {
    return s_lastTimestamp;
  }

  function getRequestConfirmations() public pure returns (uint256) {
    return REQUEST_CONFIRMATIONS;
  }
}
