/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.0;

import "ds-test/test.sol";
import "dss.git/vat.sol";
import "../common/math.sol";
import "../gate1.sol";
import "./Vm.sol";

contract TestVat is Vat {
    uint256 constant ONE = 10 ** 27;
    function mint(address usr, uint wad) public {
        dai[usr] += wad * ONE;
        debt += wad * ONE;
    }
}

contract MockVow {
    constructor() {}
}

contract Integration {
    Gate1 public gate;

    constructor(Gate1 gate_) {
        gate = gate_;
    }

    function draw(uint256 amount_) public {
        gate.draw(amount_);
    }

    function suck(address u, address v, uint256 rad) public {
        gate.suck(u, v, rad);
    }
}

// when gate is deployed
contract DeployGate1Test is DSTest {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    Vat vat;
    MockVow vow;
    Gate1 gate;
    address me;

    function setUp() public {
        vm.warp(1641400537);

        me = address(this);
        vat = new Vat();
        vow = new MockVow();
        gate = new Gate1(me, address(vat), address(vow));
        vat.rely(address(gate));
    }

    // should set gov vat and vow addresses
    function testAddresses() public {
        assertTrue(gate.gov() == me);
        assertTrue(gate.vat() != address(0));
        assertTrue(gate.vow() != address(0));
    }

    // should set withdrawafter to non-zero value
    function testWithdrawAfterNotZero() public {
        assertTrue(gate.withdrawAfter() != 0);
    }
}

// when integration is denied approval
contract IntegrationAuthDeniedGate1Test is DSTest {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    Vat vat;
    MockVow vow;
    Gate1 gate;
    address me;

    address user1;
    address user2;

    function setUp() public {
        vm.warp(1641400537);

        me = address(this);
        vat = new Vat();
        vow = new MockVow();
        gate = new Gate1(me, address(vat), address(vow));
        vat.rely(address(gate));

        user1 = address(new Integration(gate));
        gate.relyIntegration(user1); // approve integration user1
        
        user2 = address(new Integration(gate));
    }

    // todo test expect emit event

    // should fail if integration is not already approved
    function testIntegrationNotApproved() public {
        vm.expectRevert("integration/not-approved");
        gate.denyIntegration(user2);
    }

    // should pass if integration is approved
    function testIntegrationApproved() public {
        gate.denyIntegration(user1);
        assertTrue(!gate.integrations(user1));
    }

    // should fail if caller is not gov
    function testCallerNotGov() public {
        vm.prank(address(1337)); // impersonate random address
        
        vm.expectRevert("gov/not-authorized");
        gate.denyIntegration(user1);
    }

    // should pass if caller is gov
    function testCallerGov() public {
        gate.denyIntegration(user1);
        assertTrue(!gate.integrations(user1));
    }
}

// when integration is approved
contract IntegrationAuthApprovedGate1Test is DSTest {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    Vat vat;
    MockVow vow;
    Gate1 gate;
    address me;

    address user1;
    address user2;

    function setUp() public {
        vm.warp(1641400537);

        me = address(this);
        vat = new Vat();
        vow = new MockVow();
        gate = new Gate1(me, address(vat), address(vow));
        vat.rely(address(gate));

        user1 = address(new Integration(gate));
        user2 = address(new Integration(gate));
    }

    // todo test expect emit event

    // should fail if integration was already approved
    function testIntegrationNotApproved() public {
        gate.relyIntegration(user1);

        vm.expectRevert("integration/approved");
        gate.relyIntegration(user1);
    }

    // should pass if integration is not approved
    function testIntegrationApproved() public {
        gate.relyIntegration(user1);
        assertTrue(gate.integrations(user1));
    }

    // should fail if caller is not gov
    function testCallerNotGov() public {
        vm.prank(address(1337)); // impersonate random address
        
        vm.expectRevert("gov/not-authorized");
        gate.relyIntegration(user1);
    }

    // should pass if caller is gov
    function testCallerGov() public {
        gate.relyIntegration(user1);
        assertTrue(gate.integrations(user1));
    }
}

// when dai balance is called
contract DaiBalanceGate1Test is DSTest {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    TestVat vat;
    MockVow vow;
    Gate1 gate;
    address me;

    address user1;
    address user2;

    function setUp() public {
        vm.warp(1641400537);

        me = address(this);
        vat = new TestVat();
        vow = new MockVow();
        gate = new Gate1(me, address(vat), address(vow));
        vat.rely(address(gate));

        user1 = address(new Integration(gate));
        user2 = address(new Integration(gate));

        vat.mint(address(this), 123 ether);
    }

    // should return dai balance of gate in vat
    function testDaiBalance() public {
        // transfer dai to gate
        vat.move(address(this), address(gate), 100 ether);

        // check if balance matches
        assertEq(gate.daiBalance(), 100 ether);
    }
}

// when max draw amount is called
contract MaxDrawGate1Test is DSTest, DSMath {
Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    TestVat vat;
    MockVow vow;
    Gate1 gate;
    address me;

    address user1;
    address user2;

    function rad(uint256 amt_) public pure returns (uint256) {
        return mulu(amt_, RAD);
    }

    function setUp() public {
        vm.warp(1641400537);

        me = address(this);
        vat = new TestVat();
        vow = new MockVow();
        gate = new Gate1(me, address(vat), address(vow));
        vat.rely(address(gate));

        user1 = address(new Integration(gate));
        user2 = address(new Integration(gate));

        vat.mint(address(this), rad(123)); // mint dai
    }

    // should return approved total when it is higher
    function testReturnApprovedTotal() public {
        vat.move(address(this), address(gate), rad(100)); // add some backup balance
        gate.updateApprovedTotal(rad(150));// add a draw limit

        assertEq(gate.maxDrawAmount(), rad(150));
    }

    // should return backup balance when it is higher
    function testReturnBackupBalance() public {
        vat.move(address(this), address(gate), rad(100)); // add some backup balance
        gate.updateApprovedTotal(rad(75));// add a draw limit

        assertEq(gate.maxDrawAmount(), rad(100));
    }

    // should work even when gate is not authorized in vat
    function testUnauthorizedVat() public {
        vat.move(address(this), address(gate), rad(100)); // add some backup balance
        gate.updateApprovedTotal(rad(75));// add a draw limit

        vat.deny(address(gate));
        assertEq(gate.maxDrawAmount(), rad(100)); // works
    }

}

// when approved total is updated
contract ApprovedTotalUpdateGate1Test is DSTest, DSMath {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    TestVat vat;
    MockVow vow;
    Gate1 gate;
    address me;

    address user1;
    address user2;

    function rad(uint256 amt_) public pure returns (uint256) {
        return mulu(amt_, RAD);
    }

    function setUp() public {
        vm.warp(1641400537);

        me = address(this);
        vat = new TestVat();
        vow = new MockVow();
        gate = new Gate1(me, address(vat), address(vow));
        vat.rely(address(gate));

        user1 = address(new Integration(gate));
        user2 = address(new Integration(gate));

        vat.mint(address(this), rad(123)); // mint dai

        gate.updateApprovedTotal(rad(750)); // setup approved total
    }

    // should fail if address is not gov
    function testUpdateNewApprovedTotalNotGov() public {
        vm.prank(address(1337)); // impersonate random address
        
        vm.expectRevert("gov/not-authorized");
        gate.updateApprovedTotal(rad(999));
    }

    // should succeed if address is gov
    function testUpdateNewApprovedTotalGov() public {
        gate.updateApprovedTotal(rad(999));
        assertEq(gate.approvedTotal(), rad(999));
    }

    // todo should emit a new approved total event

    // should update new total when it is lower
    function testUpdateNewApprovedTotalLower() public {
        gate.updateApprovedTotal(rad(500)); // change 750 to 500
        assertEq(gate.approvedTotal(), rad(500));
    }

    // should update new total when it is higher
    function testUpdateNewApprovedTotalHigher() public {
        gate.updateApprovedTotal(rad(1234)); // change 750 to 1234
        assertEq(gate.approvedTotal(), rad(1234));
    }
}

// when dai is drawn by integration
contract DaiDrawnGate1Test is DSTest, DSMath {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    TestVat vat;
    MockVow vow;
    Gate1 gate;
    address me;

    Integration user1;
    Integration user2;

    function rad(uint256 amt_) public pure returns (uint256) {
        return mulu(amt_, RAD);
    }

    function setUp() public {
        vm.warp(1641400537);

        me = address(this);
        vat = new TestVat();
        vow = new MockVow();
        gate = new Gate1(me, address(vat), address(vow));
        vat.rely(address(gate));

        user1 = new Integration(gate);
        gate.relyIntegration(address(user1)); // authorize user1
        user2 = new Integration(gate);

        vat.mint(address(this), rad(123)); // mint dai
    }

    // draw fails if integration is not approved
    function testIntegrationNotApproved() public {
        vm.expectRevert("integration/not-authorized");
        user2.draw(rad(1)); // user2 not authorized
    }

    // draw succeeds if integration is approved
    function testIntegrationApproved() public {
        vat.move(me, address(gate), rad(50)); // backup balance: 50
        user1.draw(rad(10)); // draw: 10
    }

    // draw succeeds without suck when backup balance is present
    function testBackupBalance() public {
        vat.deny(address(gate)); // no auth, force backup balance usage
        vat.move(me, address(gate), rad(50)); // backup balance: 50

        user1.draw(rad(10)); // draw: 10
        assertEq(vat.dai(address(gate)), rad(40));
    }

    // draw succeeds with suck when backup balance is zero
    function testBackupBalanceZero() public {
        gate.updateApprovedTotal(rad(25)); // draw limit approved total: 25
        vat.move(me, address(gate), rad(50)); // backup balance: 50

        user1.draw(rad(10)); // draw from vat: 10
        assertEq(vat.dai(address(gate)), rad(50));  // draw from backup balance: 0
    }

    // draw fails when approved limit is lower than amount
    function testFailApprovedLimitLowerThanDraw() public {
        gate.updateApprovedTotal(rad(25)); // draw limit approved total: 25
        // backup balance: 0

        user1.draw(rad(50)); // draw from vat: 50
    }

    // draw fails when vat does not authorize gate
    function testFailVatNotAuthorized() public {
        vat.deny(address(gate)); // no vat auth
        gate.updateApprovedTotal(rad(25)); // draw limit approved total: 25
        // backup balance: 0

        user1.draw(rad(10)); // draw from vat: 10
    }

    // draw fails when backup balance is not sufficient
    function testFailInsufficientBackupBalance() public {
        vat.deny(address(gate)); // no vat auth
        vat.move(me, address(gate), rad(50)); // backup balance: 50

        user1.draw(rad(75)); // draw from vat: 75 
    }

    // draw updates balance of integration and gate when backup balance is used
    function testBalancesUpdated() public {
        vat.deny(address(gate)); // no auth, force backup balance usage
        vat.move(me, address(gate), rad(50)); // backup balance: 50

        user1.draw(rad(10)); // draw: 10
        assertEq(vat.dai(address(gate)), rad(40)); // backup balance: 40
        assertEq(vat.dai(address(user1)), rad(10)); // integration : 10
    }

    // draw increases sin when suck is used
    function testIncreaseSinAfterSuck() public {
        // backup balance: 0
        gate.updateApprovedTotal(rad(50)); // draw limit approved total: 50

        user1.draw(rad(10)); // draw: 10
        assertEq(vat.sin(address(vow)), rad(10));
    }

    // todo draw emits the draw event

    // draw decreases the approved total when suck is used
    function testDecreaseApprovedTotalAfterSuck() public {
        // backup balance: 0
        gate.updateApprovedTotal(rad(50)); // draw limit approved total: 50

        user1.draw(rad(10)); // draw: 10
        assertEq(gate.approvedTotal(), rad(40));
    }

    // draw leaves approved total unchanged when backup balance is used
    function testApprovedTotalUnchanged() public {
        gate.updateApprovedTotal(rad(10)); // draw limit approved total: 10
        vat.move(me, address(gate), rad(50)); // backup balance: 50

        user1.draw(rad(25)); // draw: 25
        assertEq(gate.approvedTotal(), rad(10));  // approved total unchanged
        assertEq(vat.dai(address(gate)), rad(25)); // backup balance: 25
    }

    // gate suck interface works
    function testGateSuckInterface() public {
        // backup balance: 0
        gate.updateApprovedTotal(rad(50)); // draw limit approved total: 50

        user1.suck(address(0), address(user2), rad(10)); // draw: 10
        assertEq(vat.dai(address(user2)), rad(10)); // user2: 10
    }

    // should test priority of sources
    function testSourcePriority() public {
        gate.updateApprovedTotal(rad(75)); // draw limit approved total: 75
        vat.move(me, address(gate), rad(50)); // backup balance: 50

        user1.draw(rad(25)); // draw: 25
        assertEq(gate.approvedTotal(), rad(50));  // approved total: 50
        assertEq(vat.dai(address(gate)), rad(50)); // backup balance: 50
    }

    // should draw from backup balance when amount is beyond draw limit
    function testDrawBackupBalanceExceedsApprovedTotal() public {
        gate.updateApprovedTotal(rad(10)); // draw limit approved total: 10
        vat.move(me, address(gate), rad(50)); // backup balance: 50

        user1.draw(rad(25)); // draw: 25
        assertEq(gate.approvedTotal(), rad(10));  // approved total unchanged
        assertEq(vat.dai(address(gate)), rad(25)); // backup balance: 25
    }
}
