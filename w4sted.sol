// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract w4sted is Ownable, ERC20, ReentrancyGuard {
    // keep song serial number
    uint256 private serial;

    // user details
    struct User {
        uint256 tokensPurchased;
        string[] songsListened;
    }

    // track details
    struct Song {
        string name;
        string text;
        uint256 length;
        uint256 rates;
        uint256 rateCount;
        uint256 timesListened;
        uint256 baseValue;
        bool active;
    }

    // mapping to keep track of all songs
    mapping(uint256 => Song) private songs;
    // mapping to keep track of all users
    mapping(address => User) private users;
    // mapping to keep track of songs a user has already rated to ensure user rate only once per song
    mapping(uint256 => mapping(address => bool)) private rated;

    // mapping to keep track of songs a user has listened too
    mapping(uint256 => mapping(address => bool)) private listened;

    constructor(uint256 _quantity) ERC20("W4sted Productions", "SMS") {
        _mint(address(this), _quantity * (10**18));
    }

    /**
     * @dev function to get the value of token SMS in ethers
     * @dev Token SMS has 18 decimals
     * @notice 1 token = 1 ether
     * */
    function getValue(uint256 _quantity) internal pure returns (uint256) {
        return _quantity * (10**18);
    }

    /// @dev function to get the calculated value of song
    /// @notice song value is increment by 5% for every listen
    function calculateValue(uint256 _songSerial) public view returns (uint256) {
        Song memory song = songs[_songSerial];
        // this prevents zero incrementation except if timesListened is zero
        // divided to represent 1%
        uint256 increment = (song.baseValue * song.timesListened) / 100;
        // baseValue is added to increment after it has been multiplied by 5 to equal incrementation of 5%
        uint256 calculatedValue = song.baseValue + (increment * 5);
        return calculatedValue;
    }

    /// @dev Add new song into the library
    /// @param _length in seconds
    function AddSong(
        string calldata _name,
        string calldata _text,
        uint256 _length,
        uint256 _value
    ) external onlyOwner {
        require(_length > 1 minutes, "Song length too short");
        require(bytes(_name).length > 0, "Empty name");
        require(bytes(_text).length > 0, "Empty text");
        // to ensure that increment works properly as below 100 wei, zero would be return in increment(zero will still be returned for the first time listened)
        require(_value >= 100, "Value has to be greater or equal to 100 wei");
        songs[serial] = Song(_name, _text, _length, 5, 1, 0, _value, true);
        serial += 1;
    }

    /// @dev function to remove a song from the library
    function removeSong(uint256 _songSerial) public onlyOwner {
        songs[_songSerial] = songs[serial - 1];
        delete songs[serial - 1];
        serial--;
    }

    /// @dev function to swap customer token SMS for eth from contract
    function swapTokens(uint256 _quantity) external payable nonReentrant {
        require(_quantity > 0, "Invalid quantity of tokens entered");
        // token SMS follows the standard decimal value for erc20 tokens
        uint totalAmount = _quantity * (10**18);
        require(
            totalAmount <= balanceOf(msg.sender),
            "Quantity requested higher that your balance"
        );
        uint amountEthers = getValue(_quantity);
        require(
            address(this).balance >= amountEthers,
            "Not enough ethers available for swap"
        );
        // first send token to contract
        _transfer(msg.sender, address(this), totalAmount);
        // then get value of token in user wallet in return
        (bool success, ) = payable(msg.sender).call{value: amountEthers}("");
        require(success, "Swapping failed");
    }

    /// @dev function to buy token SMS from contract
    function buyToken(uint256 _quantity) external payable nonReentrant {
        uint256 cost = getValue(_quantity);
        require(msg.value == cost, "Quantity is not enough to buy");
        uint256 contractTokenBalance = balanceOf(address(this));
        // user cannot buy more than the token balance in the contract
        uint totalAmount = _quantity * (10**18);
        require(
            totalAmount <= contractTokenBalance,
            "Insufficient tokens in contract"
        );
        // transfer token to user
        _transfer(address(this), msg.sender, totalAmount);
        // keep track of number of tokens purchased
        users[msg.sender].tokensPurchased += totalAmount;
    }

    /// @dev function to listen song and pay tokens for it
    function listenSong(uint256 _serial) public {
        // first confirm if song is available now
        require(songs[_serial].active, "Song deleted/does not exist");
        // get calculated value of song
        uint256 calculatedValue = calculateValue(_serial);
        // confirm if user has enough tokens to listen song
        require(
            calculatedValue <= balanceOf(msg.sender),
            "You don't have enough tokens to listen song"
        );
        _transfer(msg.sender, address(this), calculatedValue);
        if(!listened[_serial][msg.sender]){
            listened[_serial][msg.sender] = true;
            songs[_serial].timesListened++;
        }
        // Storage in the client's history of listened songs
        users[msg.sender].songsListened.push(songs[_serial].name);
    }

    // function to rate a song, 1 and 10 inclusive
    function rateSong(uint256 _serial, uint256 _rate) public {
        require((_rate > 0) && (_rate <= 10), "Invalid rate entered");
        require(
            !rated[_serial][msg.sender],
            "You can't rate song more than once"
        );
        uint totalRates = songs[_serial].rates + _rate;
        songs[_serial].rates = totalRates;
        songs[_serial].rateCount++;
        rated[_serial][msg.sender] = true;
    }

    /// @dev get details of songs user has listened
    function getSongsListened() public view returns (string[] memory) {
        return users[msg.sender].songsListened;
    }

    /// @dev function to get song details
    function getSongDetails(uint256 _serial)
        public
        view
        returns (
            string memory name,
            string memory text,
            uint256 length,
            uint256 timesListened,
            uint256 rating,
            uint256 value
        )
    {
        require(songs[_serial].active, "Song not active / song deleted");
        Song memory song = songs[_serial];
        name = song.name;
        text = song.text;
        length = song.length;
        timesListened = song.timesListened;
        rating = song.rates / song.rateCount;
        value = calculateValue(_serial);
    }

    /// @dev function to withdraw funds from contract without "rug pulling" users funds
    function withdraw() public onlyOwner nonReentrant {
        // get total number of token users are holding
        uint256 tokensOut = totalSupply() - balanceOf(address(this));
        // amount in eth to pay token holders
        uint256 secureHodlers = address(this).balance - getValue(tokensOut);
        // balance owner will be able to withdraw such that there will be enough
        // ethers in the contract for token holders
        uint256 organicBal = address(this).balance - secureHodlers;
        (bool success,) = payable(owner()).call{value: organicBal}("");
        require(success, "Withdrawal failed");
    }
}
