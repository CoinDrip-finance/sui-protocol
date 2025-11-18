#[test_only]
module coindrip::coindrip_tests_fees;

use coindrip::coindrip::{Self, AdminCap, Controller, Stream, UpdateFeeCap};
use coindrip::coindrip_tests_create_stream::create_stream_hc1;
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario as ts;

const SENDER: address = @0xAAA;
const RECIPIENT: address = @0xBBB;
const ADMIN: address = @0xAD;
const ONE_SUI: u64 = 1_000_000_000;

const EInvalidFeeAmount: u64 = 12;

// Test that the controller is initialized with correct claim fee
#[test]
public fun test_initial_claim_fee() {
    let mut scenario = create_stream_hc1();

    scenario.next_tx(SENDER);
    {
        let controller = ts::take_shared<Controller>(&scenario);

        // Verify initial fee is ONE_SUI / 4 (0.25 SUI)
        assert!(coindrip::get_claim_fee(&controller) == ONE_SUI / 4);

        // Verify treasury starts empty
        assert!(coindrip::get_treasury_balance(&controller) == 0);

        ts::return_shared(controller);
    };

    scenario.end();
}

// Test updating the claim fee with UpdateFeeCap
#[test]
public fun test_update_fee_with_cap() {
    let mut scenario = create_stream_hc1();

    // Switch to ADMIN to access UpdateFeeCap
    scenario.next_tx(ADMIN);
    {
        let update_fee_cap = ts::take_from_address<UpdateFeeCap>(&scenario, ADMIN);
        let mut controller = ts::take_shared<Controller>(&scenario);

        // Update fee to ONE_SUI / 2 (0.5 SUI)
        coindrip::update_fee(&update_fee_cap, &mut controller, ONE_SUI / 2);

        // Verify fee is updated
        assert!(coindrip::get_claim_fee(&controller) == ONE_SUI / 2);

        transfer::public_transfer(update_fee_cap, ADMIN);
        ts::return_shared(controller);
    };

    // Now claim with the new fee amount
    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(500);

        let mut stream = ts::take_from_sender<Stream<SUI>>(&scenario);

        // Pay the NEW fee amount
        let fee_coin = coin::mint_for_testing<SUI>(ONE_SUI / 2, scenario.ctx());
        let coin = coindrip::claim_from_stream(
            &mut controller,
            &mut stream,
            fee_coin,
            &clock,
            scenario.ctx(),
        );

        assert!(coin.value() == ONE_SUI * 1000 / 2); // Half of stream claimed
        transfer::public_transfer(coin, RECIPIENT);

        // Verify treasury accumulated the new fee
        assert!(coindrip::get_treasury_balance(&controller) == ONE_SUI / 2);

        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test that claiming with incorrect fee amount fails
#[test]
#[expected_failure(abort_code = EInvalidFeeAmount, location = coindrip)]
public fun test_claim_with_incorrect_fee_fails() {
    let mut scenario = create_stream_hc1();

    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(500);

        let mut stream = ts::take_from_sender<Stream<SUI>>(&scenario);

        // Fee is ONE_SUI / 4, but we pay ONE_SUI / 2 (wrong amount)
        let fee_coin = coin::mint_for_testing<SUI>(ONE_SUI / 2, scenario.ctx());
        let coin = coindrip::claim_from_stream(
            &mut controller,
            &mut stream,
            fee_coin,
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(coin, RECIPIENT);
        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test that treasury accumulates fees from multiple claims
#[test]
public fun test_treasury_accumulation() {
    let mut scenario = create_stream_hc1();

    // First claim
    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(250);

        let mut stream = ts::take_from_sender<Stream<SUI>>(&scenario);

        let fee_coin = coin::mint_for_testing<SUI>(ONE_SUI / 4, scenario.ctx());
        let coin = coindrip::claim_from_stream(
            &mut controller,
            &mut stream,
            fee_coin,
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(coin, RECIPIENT);

        // Verify treasury has 1 fee
        assert!(coindrip::get_treasury_balance(&controller) == ONE_SUI / 4);

        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    // Second claim
    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(250);

        let mut stream = ts::take_from_sender<Stream<SUI>>(&scenario);

        let fee_coin = coin::mint_for_testing<SUI>(ONE_SUI / 4, scenario.ctx());
        let coin = coindrip::claim_from_stream(
            &mut controller,
            &mut stream,
            fee_coin,
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(coin, RECIPIENT);

        // Verify treasury has 2 fees
        assert!(coindrip::get_treasury_balance(&controller) == 2 * (ONE_SUI / 4));

        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    // Third claim
    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(500);

        let mut stream = ts::take_from_sender<Stream<SUI>>(&scenario);

        let fee_coin = coin::mint_for_testing<SUI>(ONE_SUI / 4, scenario.ctx());
        let coin = coindrip::claim_from_stream(
            &mut controller,
            &mut stream,
            fee_coin,
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(coin, RECIPIENT);

        // Verify treasury has 3 fees
        assert!(coindrip::get_treasury_balance(&controller) == 3 * (ONE_SUI / 4));

        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test withdrawing treasury with AdminCap
#[test]
public fun test_withdraw_treasury_with_admin_cap() {
    let mut scenario = create_stream_hc1();

    // Perform 2 claims to accumulate fees
    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(250);

        let mut stream = ts::take_from_sender<Stream<SUI>>(&scenario);

        let fee_coin = coin::mint_for_testing<SUI>(ONE_SUI / 4, scenario.ctx());
        let coin = coindrip::claim_from_stream(
            &mut controller,
            &mut stream,
            fee_coin,
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(coin, RECIPIENT);
        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(250);

        let mut stream = ts::take_from_sender<Stream<SUI>>(&scenario);

        let fee_coin = coin::mint_for_testing<SUI>(ONE_SUI / 4, scenario.ctx());
        let coin = coindrip::claim_from_stream(
            &mut controller,
            &mut stream,
            fee_coin,
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(coin, RECIPIENT);
        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    // Now withdraw treasury
    scenario.next_tx(ADMIN);
    {
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
        let mut controller = ts::take_shared<Controller>(&scenario);

        // Verify treasury has 2 fees before withdrawal
        assert!(coindrip::get_treasury_balance(&controller) == 2 * (ONE_SUI / 4));

        let withdrawn_coin = coindrip::withdraw_treasury(
            &admin_cap,
            &mut controller,
            scenario.ctx(),
        );

        // Verify withdrawn amount
        assert!(withdrawn_coin.value() == 2 * (ONE_SUI / 4));

        // Verify treasury is now empty
        assert!(coindrip::get_treasury_balance(&controller) == 0);

        transfer::public_transfer(withdrawn_coin, ADMIN);
        transfer::public_transfer(admin_cap, ADMIN);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test multiple claims with different fee amounts
#[test]
public fun test_multiple_claims_different_fees() {
    let mut scenario = create_stream_hc1();

    // First claim with default fee (ONE_SUI / 4)
    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(250);

        let mut stream = ts::take_from_sender<Stream<SUI>>(&scenario);

        let fee_coin = coin::mint_for_testing<SUI>(ONE_SUI / 4, scenario.ctx());
        let coin = coindrip::claim_from_stream(
            &mut controller,
            &mut stream,
            fee_coin,
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(coin, RECIPIENT);
        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    // Update fee to ONE_SUI / 2
    scenario.next_tx(ADMIN);
    {
        let update_fee_cap = ts::take_from_address<UpdateFeeCap>(&scenario, ADMIN);
        let mut controller = ts::take_shared<Controller>(&scenario);

        coindrip::update_fee(&update_fee_cap, &mut controller, ONE_SUI / 2);

        transfer::public_transfer(update_fee_cap, ADMIN);
        ts::return_shared(controller);
    };

    // Second claim with new fee (ONE_SUI / 2)
    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(250);

        let mut stream = ts::take_from_sender<Stream<SUI>>(&scenario);

        let fee_coin = coin::mint_for_testing<SUI>(ONE_SUI / 2, scenario.ctx());
        let coin = coindrip::claim_from_stream(
            &mut controller,
            &mut stream,
            fee_coin,
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(coin, RECIPIENT);

        // Verify treasury = (ONE_SUI / 4) + (ONE_SUI / 2) = 3/4 SUI
        let expected_treasury = (ONE_SUI / 4) + (ONE_SUI / 2);
        assert!(coindrip::get_treasury_balance(&controller) == expected_treasury);

        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test claiming with zero fee
#[test]
public fun test_claim_with_zero_fee() {
    let mut scenario = create_stream_hc1();

    // Update fee to 0
    scenario.next_tx(ADMIN);
    {
        let update_fee_cap = ts::take_from_address<UpdateFeeCap>(&scenario, ADMIN);
        let mut controller = ts::take_shared<Controller>(&scenario);

        coindrip::update_fee(&update_fee_cap, &mut controller, 0);
        assert!(coindrip::get_claim_fee(&controller) == 0);

        transfer::public_transfer(update_fee_cap, ADMIN);
        ts::return_shared(controller);
    };

    // Claim without paying any fee
    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(500);

        let mut stream = ts::take_from_sender<Stream<SUI>>(&scenario);

        // Pay zero fee
        let fee_coin = coin::mint_for_testing<SUI>(0, scenario.ctx());
        let coin = coindrip::claim_from_stream(
            &mut controller,
            &mut stream,
            fee_coin,
            &clock,
            scenario.ctx(),
        );

        assert!(coin.value() == ONE_SUI * 1000 / 2); // Half of stream claimed
        transfer::public_transfer(coin, RECIPIENT);

        // Verify treasury is still 0
        assert!(coindrip::get_treasury_balance(&controller) == 0);

        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    scenario.end();
}
