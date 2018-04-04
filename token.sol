pragma solidity 0.4.18;

library SafeMath
{
  function mul(uint256 a, uint256 b) internal pure returns (uint256) 
  {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) 
  {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) 
  {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256) 
  {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}

contract Ownable 
{
    address public owner;
    
    //  @dev The Ownable constructor sets the original `owner` of the contract to the sender
    //  account.
    function Ownable() public 
    {
        owner = msg.sender;
    }

    //  @dev Throws if called by any account other than the owner. 
    modifier onlyOwner() 
    {
        require(msg.sender == owner);
        _;
    }
    
    //  @dev Allows the current owner to transfer control of the contract to a newOwner.
    //  @param newOwner The address to transfer ownership to. 
    function transferOwnership(address newOwner) public onlyOwner
    {
        if (newOwner != address(0)) 
        {
            owner = newOwner;
        }
    }
}

contract ERC223ReceivingContract 
{
    function tokenFallback(address _from, uint _value, bytes _data) public;
}

contract BasicToken is ERC223ReceivingContract
{
    using SafeMath for uint256;
    
     //  Total number of Tokens
    uint totalCoinSupply;
    
    //  allowance map
    //  ( owner => (spender => amount ) ) 
    mapping (address => mapping (address => uint256)) public AllowanceLedger;
    
    //  ownership map
    //  ( owner => value )
    mapping (address => uint256) public balanceOf;

    function tokenFallback(address _from, uint _value, bytes _data) public
    {
        Received(_from,_value,_data);
    }

    function transfer(address to, uint value, bytes data) public returns(bool)
    {
        // Standard function transfer similar to ERC20 transfer with no _data .
        // Added due to backwards compatibility reasons .
        uint codeLength;

        assembly {
            // Retrieve the size of the code on target address, this needs assembly .
            codeLength := extcodesize(to)
        }

        balanceOf[msg.sender] = balanceOf[msg.sender].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        
        if(codeLength>0)
        {
            ERC223ReceivingContract receiver = ERC223ReceivingContract(to);
            receiver.tokenFallback(msg.sender, value, data);
        }
        Transfer(msg.sender, to, value);
    }

    // Standard function transfer similar to ERC20 transfer with no _data .
    // Added due to backwards compatibility reasons .
    function transfer(address to, uint value) public returns(bool)
    {
        uint codeLength;
        bytes memory empty;

        assembly {
            // Retrieve the size of the code on target address, this needs assembly .
            codeLength := extcodesize(to)
        }

        balanceOf[msg.sender] = balanceOf[msg.sender].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        
        if(codeLength>0) 
        {
            ERC223ReceivingContract receiver = ERC223ReceivingContract(to);
            receiver.tokenFallback(msg.sender, value, empty);
        }
        Transfer(msg.sender, to, value);
    }
    
    function transferFrom( address _owner, address _recipient, uint256 _value ) 
        public returns( bool success )
    {
        var _allowance = AllowanceLedger[_owner][msg.sender];
        // Check is not needed because sub(_allowance, _value) will already 
        //  throw if this condition is not met
        // require (_value <= _allowance);

        balanceOf[_recipient] = balanceOf[_recipient].add(_value);
        balanceOf[_owner] = balanceOf[_owner].sub(_value);
        AllowanceLedger[_owner][msg.sender] = _allowance.sub(_value);
        Transfer(_owner, _recipient, _value);
        return true;
    }
    
    function approve( address _spender, uint256 _value ) 
        public returns( bool success )
    {
        //  _owner is the address of the owner who is giving approval to
        //  _spender, who can then transact coins on the behalf of _owner
        address _owner = msg.sender;
        AllowanceLedger[_owner][_spender] = _value;
        
        //  Fire off Approval event
        Approval( _owner, _spender, _value);
        return true;
    }
    
    function allowance( address _owner, address _spender ) public constant 
        returns ( uint256 remaining )
    {
        //  returns the amount _spender can transact on behalf of _owner
        return AllowanceLedger[_owner][_spender];
    }
    
    function totalSupply() public constant returns( uint256 total )
    {  
        return totalCoinSupply;
    }

    //  @dev Gets the balance of the specified address.
    //  @param _owner The address to query the the balance of. 
    //  @return An uint256 representing the amount owned by the passed address.
    function balanceOf(address _owner) public constant returns (uint256 balance)
    {
        return balanceOf[_owner];
    }
    
    event Transfer( address indexed _owner, address indexed _recipient, uint256 _value );
    event Approval( address _owner, address _spender, uint256 _value );
    event Received( address _from, uint256 _value, bytes data );

}

contract RentIDToken is BasicToken, Ownable
{
    using SafeMath for uint256;
    
    // Token Cap for each rounds
    uint256 public saleCap;

    // Address where funds are collected.
    address public wallet;
    
    // Sale period.
    uint256 public startDate;
    uint256 public endDate;

    // Amount of raised money in wei.
    uint256 public weiRaised;
    
    //  Tokens sold (denominated in ether)
    uint256 public tokensSold = 0;
    
    //  Token bonus rate
    uint256 public bonusRatePerEther = 0;
    
    bool public finalized = false;
    
    //  This is the 'Ticker' symbol and name for our Token.
    string public constant symbol = "TESTID13";
    string public constant name = "TESTNUMBER13";
    
    //  This is for how your token can be fracionalized. 
    uint8 public decimals = 18;
    
    //  Lockout mapping
    mapping (address => uint256) public lockoutMap;
    
    // Events
    event TokenPurchase(address indexed purchaser, uint256 value, 
        uint256 tokenAmount);
    event CompanyTokenPushed(address indexed beneficiary, uint256 amount);
    event Burn( address burnAddress, uint256 amount);
    
    function RentIDToken() public 
    {
    }
    
    //  @dev set lockout period for specified address
    //  @param target - The address to specifiy lockout time
    //  @param time - amount of time to lockout
    function setLockout(address target, uint256 time) public onlyOwner
    {
        lockoutMap[target] = time;
    }
    
    //  @dev gets the sale pool balance
    //  @return tokens in the pool
    function supply() internal constant returns (uint256) 
    {
        return balanceOf[0xb1];
    }

    modifier uninitialized() 
    {
        require(wallet == 0x0);
        _;
    }

    //  @dev gets the current time
    //  @return current time
    function getCurrentTimestamp() public constant returns (uint256) 
    {
        return now;
    }
	
	//  @dev gets the current rate of tokens per ether contributed
    //  @return number of tokens per ether
    function setBonusRate(uint256 _newRate) public onlyOwner
    {
		bonusRatePerEther = _newRate;
    }
    
    //  @dev gets the current rate of tokens per ether contributed
    //  @return number of tokens per ether
    function getRate() public constant returns (uint256)
    {
        uint256 rate;
        
        if(tokensSold < 10000)
        {
            //  First tier - 500 tokens per ether
		    rate = 500;
        }
		else if(tokensSold < 20000)
		{
		    //  Second tier - 400 tokens per ether
		    rate = 400;
		}
		else if(tokensSold < 30000)
		{
		    //  third tier - 300 tokens per ether
		    rate = 300;
		}
		else if(tokensSold < 40000)
		{
		     //  fourth tier - 200 tokens per ether
		    rate = 200;
		}
		else
		{
		    //  final tier - 100 tokens per ether
		    rate = 100;
		}	
		
		//  bonusRate adds an additional amount of tokens per ether
		//  initially 0 but can be set by the owner
		rate = rate.add(bonusRatePerEther);
		
		return rate;
    }
    
    //  @dev Initialize wallet parms, can only be called once
    //  @param _wallet - address of multisig wallet which receives contributions
    //  @param _start - start date of sale
    //  @param _end - end date of sale
    //  @param _saleCap - amount of coins for sale
    //  @param _totalSupply - total supply of coins
    function initialize(address _wallet, uint256 _start, uint256 _end,
                        uint256 _saleCap, uint256 _totalSupply)
                        public onlyOwner uninitialized
    {
        require(_start >= getCurrentTimestamp());
        require(_start < _end);
        require(_wallet != 0x0);
        require(_totalSupply > _saleCap);

        finalized = false;
        startDate = _start;
        endDate = _end;
        saleCap = _saleCap;
        wallet = _wallet;
        totalCoinSupply = _totalSupply;

        //  Set balance of company stock
        balanceOf[wallet] = _totalSupply.sub(saleCap);
        
        //  Log transfer of tokens to company wallet
        Transfer(0x0, wallet, balanceOf[wallet]);
        
        //  Set balance of sale pool
        balanceOf[0xb1] = saleCap;
        
        //  Log transfer of tokens to ICO sale pool
        Transfer(0x0, 0xb1, saleCap);
    }
    
    //  Fallback function is entry point to buy tokens
    function () public payable
    {
        buyTokens(msg.sender, msg.value);
    }

    //  @dev Internal token purchase function
    //  @param beneficiary - The address of the purchaser 
    //  @param value - Value of contribution, in ether
    function buyTokens(address beneficiary, uint256 value) internal
    {
        require(beneficiary != 0x0);
        require(value >= 0.1 ether);
        
        // Calculate token amount to be purchased
        uint256 weiAmount = value;
        uint256 actualRate = getRate();
        uint256 tokenAmount = weiAmount.mul(actualRate);

        //  Check our supply
        //  Potentially redundant as balanceOf[0xb1].sub(tokenAmount) will
        //  throw with insufficient supply
        require(supply() >= tokenAmount);

        //  Check conditions for sale
        require(saleActive());
        
        // Transfer
        balanceOf[0xb1] = balanceOf[0xb1].sub(tokenAmount);
        balanceOf[beneficiary] = balanceOf[beneficiary].add(tokenAmount);
        TokenPurchase(msg.sender, weiAmount, tokenAmount);
        
        //  Log the transfer of tokens
        Transfer(0xb1, beneficiary, tokenAmount);
        
        // Update state.
        uint256 updatedWeiRaised = weiRaised.add(weiAmount);
        
        //  Get the base value of tokens
        uint256 base = tokenAmount.div(1 ether);
        uint256 updatedTokensSold = tokensSold.add(base);
        weiRaised = updatedWeiRaised;
        tokensSold = updatedTokensSold;

        // Forward the funds to fund collection wallet.
        wallet.transfer(msg.value);
    }
    
    //  @dev Time remaining until official sale begins
    //  @returns time remaining, in seconds
    function getTimeUntilStart() public constant returns (uint256)
    {
        if(getCurrentTimestamp() >= startDate)
            return 0;
            
        return startDate.sub(getCurrentTimestamp());
    }
    
    //  @dev transfer tokens from one address to another
    //  @param _recipient - The address to receive tokens
    //  @param _value - number of coins to send
    //  @return true if no requires thrown
    function transfer( address _recipient, uint256 _value, bytes _data ) public returns(bool)
    {
        //  Check to see if the sale has ended
        require(finalized);
        
        //  Check to see if the sender is locked out from transferring tokens
        require(endDate + lockoutMap[msg.sender] < getCurrentTimestamp());
        
        //  transfer
        super.transfer(_recipient, _value, _data);
        
        return true;
    }
    
    
    //  @dev transfer tokens from one address to another
    //  @param _recipient - The address to receive tokens
    //  @param _value - number of coins to send
    //  @return true if no requires thrown
    function transfer( address _recipient, uint256 _value ) public returns(bool)
    {
        //  Check to see if the sale has ended
        require(finalized);
        
        //  Check to see if the sender is locked out from transferring tokens
        require(endDate + lockoutMap[msg.sender] < getCurrentTimestamp());
        
        //  transfer
        super.transfer(_recipient, _value);
        
        return true;
    }
    
    //  @dev push tokens from treasury stock to specified address
    //  @param beneficiary - The address to receive tokens
    //  @param amount - number of coins to push
    //  @param lockout - lockout time 
    function push(address beneficiary, uint256 amount, uint256 lockout) public 
        onlyOwner 
    {
        require(balanceOf[wallet] >= amount);

        // Transfer
        balanceOf[wallet] = balanceOf[wallet].sub(amount);
        balanceOf[beneficiary] = balanceOf[beneficiary].add(amount);
        
        //  Log transfer of tokens
        CompanyTokenPushed(beneficiary, amount);
        Transfer(wallet, beneficiary, amount);
        
        //  Set lockout if there's a lockout time
        if(lockout > 0)
            setLockout(beneficiary, lockout);
    }
    
    //  @dev Burns tokens from sale pool remaining after the sale
    function finalize() public onlyOwner 
    {
        //  Can only finalize after after sale is completed
        require(getCurrentTimestamp() > endDate);

        //  Set finalized
        finalized = true;

        //  Transfer unsold tokens from the sale pool back to 
        //  treasury wallet
        balanceOf[wallet] = balanceOf[wallet].add(balanceOf[0xb1]);
        
        //  Log transfer of tokens
        Transfer(0xb1, wallet, balanceOf[0xb1]);
        
        //  Set sale pool tokens to 0
        balanceOf[0xb1] = 0;
    }

    //  @dev check to see if the sale period is active
    //  @return true if sale active, false otherwise
    function saleActive() public constant returns (bool) 
    {
        //  Ability to purchase has begun for this purchaser with either 2 
        //  conditions: Sale has started 
        bool checkSaleBegun = getCurrentTimestamp() >= startDate;
        
        //  Sale of tokens can not happen after the ico date or with no
        //  supply in any case
        bool canPurchase = checkSaleBegun && 
            getCurrentTimestamp() < endDate &&
            supply() > 0;
            
        return(canPurchase);
    }
}