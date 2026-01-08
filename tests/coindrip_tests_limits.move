#[test_only]
module coindrip::coindrip_tests_limits;

use coindrip::coindrip::{Self, AdminCap, Controller, Segment, UpdateFeeCap};
use coindrip::coindrip_tests_setup::setup;
use sui::clock::Clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario as ts;

const ADMIN: address = @0xAD;
const SENDER: address = @0xAAA;
const RECIPIENT: address = @0xBBB;
const ONE_SUI: u64 = 1_000_000_000;

const EInvalidSegments: u64 = 1;
const EInvalidSegmentDuration: u64 = 15;
const EFeeTooHigh: u64 = 16;
const ETooManySegments: u64 = 14;

// ============== Segment Duration Limit Tests ==============

// Test that creating a segment with maximum allowed duration (6 years) succeeds
#[test]
public fun test_segment_duration_at_max_succeeds() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let controller = ts::take_shared<Controller>(&scenario);

        // MAX_SEGMENT_DURATION = 189_345_600_000 (~6 years in ms)
        let max_duration = coindrip::get_max_segment_duration();
        let segment = coindrip::new_segment(&controller, ONE_SUI * 1000, 1, max_duration);

        // Verify segment was created with correct duration
        assert!(coindrip::get_segment_duration(&segment) == max_duration);
        assert!(coindrip::get_segment_amount(&segment) == ONE_SUI * 1000);

        ts::return_shared(controller);
    };

    scenario.end();
}

// Test that creating a segment with duration exceeding max fails
#[test]
#[expected_failure(abort_code = EInvalidSegmentDuration, location = coindrip)]
public fun test_segment_duration_exceeds_max_fails() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let controller = ts::take_shared<Controller>(&scenario);

        // Try to create segment with duration > MAX_SEGMENT_DURATION
        let max_duration = coindrip::get_max_segment_duration();
        let _segment = coindrip::new_segment(&controller, ONE_SUI * 1000, 1, max_duration + 1);

        ts::return_shared(controller);
    };

    scenario.end();
}

// Test that creating a segment with zero duration fails
#[test]
#[expected_failure(abort_code = EInvalidSegments, location = coindrip)]
public fun test_segment_duration_zero_fails() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let controller = ts::take_shared<Controller>(&scenario);

        // Try to create segment with 0 duration
        let _segment = coindrip::new_segment(&controller, ONE_SUI * 1000, 1, 0);

        ts::return_shared(controller);
    };

    scenario.end();
}

// ============== Segment Count Limit Tests ==============

// Test that creating a stream with maximum allowed segments (500) succeeds
#[test]
public fun test_segments_count_at_max_succeeds() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);

        let max_segments = coindrip::get_max_segments();
        let amount_per_segment = ONE_SUI; // 1 SUI per segment
        let total_amount = amount_per_segment * max_segments;
        let duration_per_segment = 1000; // 1 second per segment

        let stream_coin = coin::mint_for_testing<SUI>(total_amount, scenario.ctx());
        clock.set_for_testing(1000);

        // Create 500 segments
        let mut segments = vector::empty<Segment>();
        let mut i = 0;
        while (i < max_segments) {
            let segment = coindrip::new_segment(&controller, amount_per_segment, 1, duration_per_segment);
            vector::push_back(&mut segments, segment);
            i = i + 1;
        };

        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            segments,
            &clock,
            scenario.ctx(),
        );

        // Verify stream was created
        assert!(coindrip::get_balance(&stream) == total_amount);
        assert!(coindrip::get_segments(&stream).length() == max_segments);

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test that creating a stream with segments exceeding max fails
#[test]
#[expected_failure(abort_code = ETooManySegments, location = coindrip)]
public fun test_segments_count_exceeds_max_fails() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);

        let max_segments = coindrip::get_max_segments();
        let segments_count = max_segments + 1; // 501 segments
        let amount_per_segment = ONE_SUI;
        let total_amount = amount_per_segment * segments_count;
        let duration_per_segment = 1000;

        let stream_coin = coin::mint_for_testing<SUI>(total_amount, scenario.ctx());
        clock.set_for_testing(1000);

        // Try to create 501 segments
        let mut segments = vector::empty<Segment>();
        let mut i = 0;
        while (i < segments_count) {
            let segment = coindrip::new_segment(&controller, amount_per_segment, 1, duration_per_segment);
            vector::push_back(&mut segments, segment);
            i = i + 1;
        };

        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            segments,
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// ============== Fee Limit Tests ==============

// Test that updating fee to maximum allowed (50 SUI) succeeds
#[test]
public fun test_fee_at_max_succeeds() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let update_fee_cap = ts::take_from_address<UpdateFeeCap>(&scenario, ADMIN);
        let mut controller = ts::take_shared<Controller>(&scenario);

        let max_fee = coindrip::get_max_claim_fee();

        // Update fee to MAX_CLAIM_FEE (50 SUI)
        coindrip::update_fee(&update_fee_cap, &mut controller, max_fee);

        // Verify fee was updated
        assert!(coindrip::get_claim_fee(&controller) == max_fee);

        transfer::public_transfer(update_fee_cap, ADMIN);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test that updating fee exceeding max fails
#[test]
#[expected_failure(abort_code = EFeeTooHigh, location = coindrip)]
public fun test_fee_exceeds_max_fails() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let update_fee_cap = ts::take_from_address<UpdateFeeCap>(&scenario, ADMIN);
        let mut controller = ts::take_shared<Controller>(&scenario);

        let max_fee = coindrip::get_max_claim_fee();

        // Try to update fee to more than MAX_CLAIM_FEE
        coindrip::update_fee(&update_fee_cap, &mut controller, max_fee + 1);

        transfer::public_transfer(update_fee_cap, ADMIN);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test that fee can be set to zero
#[test]
public fun test_fee_zero_succeeds() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let update_fee_cap = ts::take_from_address<UpdateFeeCap>(&scenario, ADMIN);
        let mut controller = ts::take_shared<Controller>(&scenario);

        // Update fee to 0
        coindrip::update_fee(&update_fee_cap, &mut controller, 0);

        // Verify fee was updated
        assert!(coindrip::get_claim_fee(&controller) == 0);

        transfer::public_transfer(update_fee_cap, ADMIN);
        ts::return_shared(controller);
    };

    scenario.end();
}
