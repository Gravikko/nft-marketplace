# Complete Testing Guide for Foundry Project

## Table of Contents
1. [Understanding .t.sol and .s.sol Files](#understanding-files)
2. [Testing Strategy & Order](#testing-strategy)
3. [Step-by-Step Testing Process](#step-by-step)
4. [File Organization](#file-organization)
5. [Combining Scripts and Tests](#combining-scripts-tests)
6. [Best Practices](#best-practices)

---

## Understanding .t.sol and .s.sol Files {#understanding-files}

### `.t.sol` Files (Test Files)
- **Purpose**: Test your contracts' functionality
- **Location**: `test/` directory
- **Naming**: `ContractName.t.sol` (e.g., `Factory.t.sol`)
- **What they do**: 
  - Test contract behavior
  - Verify functions work correctly
  - Check edge cases and error conditions
  - Run unit, fuzz, and invariant tests

### `.s.sol` Files (Script Files)
- **Purpose**: Deployment and interaction scripts
- **Location**: `script/` directory
- **Naming**: `DeployContractName.s.sol` (e.g., `DeployFactory.s.sol`)
- **What they do**:
  - Deploy contracts to networks
  - Configure contracts after deployment
  - Perform one-time setup operations
  - Can be used in tests for integration testing

---

## Testing Strategy & Order {#testing-strategy}

### Recommended Testing Order:

1. **Unit Tests** (Start Here) ⭐
   - Test individual functions in isolation
   - Fastest to write and run
   - Foundation for all other tests
   - **When**: Always start here

2. **Integration Tests**
   - Test how contracts work together
   - Test complete workflows
   - **When**: After unit tests pass

3. **Fuzz Tests**
   - Automatically test with random inputs
   - Find edge cases you might miss
   - **When**: After unit tests are solid

4. **Invariant Tests**
   - Test properties that should always be true
   - **When**: For complex state machines

5. **Forked Tests**
   - Test against mainnet/testnet state
   - Test with real external contracts
   - **When**: When integrating with external protocols

---

## Step-by-Step Testing Process {#step-by-step}

### Phase 1: Setup (Do This First)

#### Step 1.1: Create Helper Contracts
Create a `test/helpers/` directory with:
- `TestHelpers.sol` - Common utilities
- `DeployHelpers.s.sol` - Deployment helpers
- Mocks for external dependencies

#### Step 1.2: Create Base Test Contract
Create `test/Base.t.sol` with common setup:
```solidity
// test/Base.t.sol
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

abstract contract BaseTest is Test {
    // Common addresses
    address public constant MULTISIG = address(0x1);
    address public constant USER1 = address(0x1001);
    address public constant USER2 = address(0x1002);
    
    // Common setup
    function setUp() public virtual {
        // Initialize common state
    }
}
```

### Phase 2: Unit Tests (Start Here!)

#### Step 2.1: Test Core Contracts First
Start with contracts that have no dependencies:
1. **MultisigTimelock** (if it has minimal dependencies)
2. **VRFAdapter** (if standalone)
3. **Factory** (core contract)
4. **ERC721Collection** (depends on Factory)
5. **Marketplace** (depends on Factory)
6. **Auction** (depends on Marketplace/Factory)
7. **Staking** (depends on ERC721Collection)

#### Step 2.2: Write Tests for Each Contract
For each contract, create `ContractName.t.sol`:

**Example Structure:**
```solidity
// test/Factory.t.sol
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "./Base.t.sol";
import {Factory} from "../src/Factory.sol";

contract FactoryTest is BaseTest {
    Factory public factory;
    
    function setUp() public override {
        super.setUp();
        // Deploy and initialize Factory
        factory = new Factory();
        // ... setup code
    }
    
    // Test categories:
    // 1. Initialization tests
    // 2. Access control tests
    // 3. Core functionality tests
    // 4. Edge cases
    // 5. Error conditions
}
```

### Phase 3: Integration Tests

#### Step 3.1: Test Contract Interactions
Create integration tests that test workflows:
- Factory → ERC721Collection creation
- Marketplace → Factory → ERC721Collection interactions
- Complete user journeys

### Phase 4: Fuzz Tests

#### Step 4.1: Add Fuzz Testing
Add `fuzz_` prefix to test functions:
```solidity
function testFuzz_CreateCollection(
    string memory name,
    string memory symbol,
    uint256 maxSupply
) public {
    // Fuzz test with random inputs
    // Add bounds checking
    maxSupply = bound(maxSupply, 1, 20000);
    // ... test logic
}
```

### Phase 5: Forked Tests (If Needed)

#### Step 5.1: Test on Forked Networks
```solidity
// test/forked/FactoryForked.t.sol
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

contract FactoryForkedTest is Test {
    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }
    
    // Test with real mainnet state
}
```

---

## File Organization {#file-organization}

### Recommended Structure:

```
contracts/
├── src/
│   ├── Factory.sol
│   ├── ERC721Collection.sol
│   ├── Marketplace.sol
│   └── ...
├── test/
│   ├── Base.t.sol                    # Base test contract
│   ├── helpers/
│   │   ├── TestHelpers.sol          # Utility functions
│   │   ├── Mocks.sol                # Mock contracts
│   │   └── DeployHelpers.s.sol      # Deployment helpers
│   ├── unit/
│   │   ├── Factory.t.sol            # Unit tests for Factory
│   │   ├── ERC721Collection.t.sol   # Unit tests for ERC721Collection
│   │   ├── Marketplace.t.sol        # Unit tests for Marketplace
│   │   └── ...
│   ├── integration/
│   │   ├── FactoryCollection.t.sol  # Factory + Collection integration
│   │   ├── MarketplaceFlow.t.sol    # Complete marketplace flow
│   │   └── ...
│   ├── fuzz/
│   │   ├── FactoryFuzz.t.sol        # Fuzz tests for Factory
│   │   └── ...
│   └── forked/                       # Forked tests (optional)
│       └── ...
└── script/
    ├── DeployFactory.s.sol          # Deploy Factory
    ├── DeployMarketplace.s.sol      # Deploy Marketplace
    └── ...
```

### Should You Create One File Per Contract?

**Yes, for unit tests!** Recommended approach:
- ✅ **One `.t.sol` file per contract** for unit tests
- ✅ **Separate integration test files** for testing interactions
- ✅ **Separate fuzz test files** if they're extensive
- ✅ **One `.s.sol` file per deployment** for scripts

**Example:**
- `test/unit/Factory.t.sol` - All Factory unit tests
- `test/integration/FactoryCollection.t.sol` - Factory + Collection integration
- `test/fuzz/FactoryFuzz.t.sol` - Factory fuzz tests

---

## Combining Scripts and Tests {#combining-scripts-tests}

### Method 1: Use Scripts in Tests (Recommended)

You can import and use deployment scripts in your tests:

```solidity
// test/Factory.t.sol
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployFactory} from "../script/DeployFactory.s.sol";
import {Factory} from "../src/Factory.sol";

contract FactoryTest is Test {
    Factory public factory;
    DeployFactory public deployScript;
    
    function setUp() public {
        // Use deployment script in test
        deployScript = new DeployFactory();
        factory = deployScript.deploy();
    }
    
    function test_CreateCollection() public {
        // Your test logic
    }
}
```

### Method 2: Shared Deployment Logic

Create a helper that both scripts and tests can use:

```solidity
// script/DeployHelpers.s.sol
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Factory} from "../src/Factory.sol";

library DeployHelpers {
    function deployFactory(address multisig) public returns (Factory) {
        Factory factory = new Factory();
        factory.initialize(multisig);
        return factory;
    }
}
```

Use in both script and test:
```solidity
// script/DeployFactory.s.sol
import {DeployHelpers} from "./DeployHelpers.s.sol";

// test/Factory.t.sol
import {DeployHelpers} from "../script/DeployHelpers.s.sol";
```

### Method 3: Test Scripts Directly

You can also test your deployment scripts:

```solidity
// test/DeployFactory.t.sol
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployFactory} from "../script/DeployFactory.s.sol";

contract DeployFactoryTest is Test {
    function test_DeployFactory() public {
        DeployFactory deploy = new DeployFactory();
        deploy.run();
        // Verify deployment
    }
}
```

---

## Best Practices {#best-practices}

### 1. Test Organization
- ✅ Group related tests together
- ✅ Use descriptive test names: `test_CreateCollection_Success()`
- ✅ Test happy paths first, then edge cases
- ✅ Test all error conditions

### 2. Test Coverage
- ✅ Aim for >80% code coverage
- ✅ Test all public/external functions
- ✅ Test all error conditions
- ✅ Test access control (onlyMultisig, etc.)

### 3. Test Data
- ✅ Use constants for addresses
- ✅ Create helper functions for common setups
- ✅ Use fixtures for complex setups

### 4. Upgradeable Contracts
For your UUPS upgradeable contracts:
- ✅ Test initialization
- ✅ Test upgrades
- ✅ Test upgrade authorization
- ✅ Test state preservation after upgrades

### 5. Access Control
Test all access control modifiers:
```solidity
function test_RevertWhen_NotMultisig() public {
    vm.expectRevert(Factory.NotAMultisigTimelock.selector);
    factory.activateFactory();
}
```

### 6. Events
Always test events are emitted:
```solidity
vm.expectEmit(true, true, false, true);
emit CollectionCreated(collectionId, creator, address, name, symbol);
factory.createCollection(...);
```

### 7. Gas Optimization
- Use `forge snapshot` to track gas usage
- Compare gas before/after optimizations

### 8. Running Tests
```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/Factory.t.sol

# Run with gas reporting
forge test --gas-report

# Run with coverage
forge coverage

# Run fuzz tests with more runs
forge test --fuzz-runs 10000

# Run forked tests
forge test --fork-url $MAINNET_RPC_URL
```

---

## Quick Start Checklist

- [ ] Create `test/Base.t.sol` with common setup
- [ ] Create `test/helpers/` directory with utilities
- [ ] Write unit tests for `MultisigTimelock` (if applicable)
- [ ] Write unit tests for `Factory`
- [ ] Write unit tests for `ERC721Collection`
- [ ] Write unit tests for `Marketplace`
- [ ] Write unit tests for `Auction` and `Staking`
- [ ] Write integration tests for workflows
- [ ] Add fuzz tests for critical functions
- [ ] Create deployment scripts in `script/`
- [ ] Test deployment scripts
- [ ] Run coverage report and aim for >80%
- [ ] Document any test assumptions

---

## Example Test File Template

```solidity
// test/unit/Factory.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../Base.t.sol";
import {Factory} from "../../src/Factory.sol";

contract FactoryTest is BaseTest {
    Factory public factory;
    
    // Events
    event CollectionCreated(uint256 indexed collectionId, ...);
    
    function setUp() public override {
        super.setUp();
        // Deploy and setup
    }
    
    // ============ Initialization Tests ============
    function test_Initialize() public {
        // Test initialization
    }
    
    // ============ Access Control Tests ============
    function test_RevertWhen_NotMultisig() public {
        // Test access control
    }
    
    // ============ Core Functionality Tests ============
    function test_CreateCollection_Success() public {
        // Test happy path
    }
    
    // ============ Edge Cases ============
    function test_CreateCollection_MaxSupply() public {
        // Test edge cases
    }
    
    // ============ Fuzz Tests ============
    function testFuzz_CreateCollection(uint256 maxSupply) public {
        maxSupply = bound(maxSupply, 1, 20000);
        // Fuzz test
    }
}
```

---

## Next Steps

1. Start with `test/Base.t.sol` and `test/helpers/`
2. Write unit tests for `Factory.t.sol` first
3. Gradually add tests for other contracts
4. Add integration tests once unit tests pass
5. Add fuzz tests for critical functions
6. Create deployment scripts
7. Run coverage and improve test coverage

Good luck with your testing! 🚀

