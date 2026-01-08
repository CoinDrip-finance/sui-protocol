#[test_only]
module coindrip::coindrip_tests_overflow;

use coindrip::coindrip::{Self, Controller, Segment};
use coindrip::coindrip_tests_setup::setup;
use sui::clock::Clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario as ts;

const SENDER: address = @0xAAA;
const RECIPIENT: address = @0xBBB;
const ONE_SUI: u64 = 1_000_000_000;

// ============== Variable Tick Calculation Tests ==============

// Test that compute_tick_size returns 1 for small durations (millisecond precision)
#[test]
public fun test_compute_tick_size_small_duration() {
    let max_duration_ticks = coindrip::get_max_duration_ticks();

    // For durations <= MAX_DURATION_TICKS, tick_size should be 1
    let tick_size_1 = coindrip::compute_tick_size_for_test(1000); // 1 second
    assert!(tick_size_1 == 1);

    let tick_size_2 = coindrip::compute_tick_size_for_test(max_duration_ticks);
    assert!(tick_size_2 == 1);

    let tick_size_3 = coindrip::compute_tick_size_for_test(100_000); // 100 seconds
    assert!(tick_size_3 == 1);
}

// Test that compute_tick_size returns larger values for large durations
#[test]
public fun test_compute_tick_size_large_duration() {
    let max_duration_ticks = coindrip::get_max_duration_ticks(); // 525_600

    // For durations > MAX_DURATION_TICKS, tick_size should be > 1
    // tick_size = ceil(duration / MAX_DURATION_TICKS)

    // 1 year in ms = 31_536_000_000
    let one_year_ms: u64 = 31_536_000_000;
    let tick_size_1_year = coindrip::compute_tick_size_for_test(one_year_ms);
    // Expected: ceil(31_536_000_000 / 525_600) = ceil(60000) = 60000
    assert!(tick_size_1_year > 1);

    // 6 years (max duration)
    let max_segment_duration = coindrip::get_max_segment_duration(); // 189_345_600_000
    let tick_size_6_years = coindrip::compute_tick_size_for_test(max_segment_duration);
    // Expected: ceil(189_345_600_000 / 525_600) = ~360000
    assert!(tick_size_6_years > 1);

    // Verify that duration_ticks would be within limits
    // duration_ticks = duration / tick_size <= MAX_DURATION_TICKS
    let duration_ticks_6_years = max_segment_duration / tick_size_6_years;
    assert!(duration_ticks_6_years <= max_duration_ticks);
}

// ============== Overflow Prevention Tests ==============

// Test that segment value calculation doesn't overflow with max duration + max exponent + large amount
#[test]
public fun test_segment_value_max_duration_max_exponent_no_overflow() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);

        let max_segment_duration = coindrip::get_max_segment_duration();
        // Use large amount (1 billion SUI = u64 in the billions range)
        let large_amount: u64 = ONE_SUI * 1_000_000_000; // 1 billion SUI

        clock.set_for_testing(1000);

        // Create segment with max duration, max exponent (10), and large amount
        let segment = coindrip::new_segment(&controller, large_amount, 10, max_segment_duration);

        let stream_coin = coin::mint_for_testing<SUI>(large_amount, scenario.ctx());
        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment],
            &clock,
            scenario.ctx(),
        );

        // Move to 50% through the stream
        clock.increment_for_testing(max_segment_duration / 2);

        // This should not overflow - the variable tick strategy handles it
        let claimable = coindrip::recipient_balance(&stream, &clock);
        // With exponent 10 and 50% elapsed, the value should be small (0.5^10 * amount)
        // ~0.001 * amount, but due to tick granularity may vary
        assert!(claimable <= large_amount);

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test 6-year duration with exponent 10 (edge case from audit)
#[test]
public fun test_segment_value_6_year_duration_exponent_10() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);

        let six_years_ms = coindrip::get_max_segment_duration();
        let amount = ONE_SUI * 1000; // 1000 SUI

        clock.set_for_testing(1000);

        let segment = coindrip::new_segment(&controller, amount, 10, six_years_ms);

        let stream_coin = coin::mint_for_testing<SUI>(amount, scenario.ctx());
        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment],
            &clock,
            scenario.ctx(),
        );

        // Test at various points to ensure no overflow
        // At 10%
        clock.set_for_testing(1000 + six_years_ms / 10);
        let claimable_10pct = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable_10pct <= amount);

        // At 50%
        clock.set_for_testing(1000 + six_years_ms / 2);
        let claimable_50pct = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable_50pct <= amount);
        assert!(claimable_50pct >= claimable_10pct); // Should be monotonically increasing

        // At 90%
        clock.set_for_testing(1000 + (six_years_ms * 9) / 10);
        let claimable_90pct = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable_90pct <= amount);
        assert!(claimable_90pct >= claimable_50pct);

        // At 100% (end)
        clock.set_for_testing(1000 + six_years_ms);
        let claimable_100pct = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable_100pct == amount); // Should be full amount

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test precision with coarse ticks on large duration
#[test]
public fun test_segment_value_precision_with_coarse_ticks() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);

        // 1 year duration
        let one_year_ms: u64 = 31_536_000_000;
        let amount = ONE_SUI * 100; // 100 SUI

        clock.set_for_testing(1000);

        // With exponent 1, the calculation is linear
        let segment = coindrip::new_segment(&controller, amount, 1, one_year_ms);

        let stream_coin = coin::mint_for_testing<SUI>(amount, scenario.ctx());
        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment],
            &clock,
            scenario.ctx(),
        );

        // At 50% with linear exponent
        clock.set_for_testing(1000 + one_year_ms / 2);
        let claimable = coindrip::recipient_balance(&stream, &clock);

        // For linear stream, should be approximately 50% of amount
        // Allow small precision loss due to tick rounding
        let expected = amount / 2;
        let tolerance = amount / 100; // 1% tolerance
        assert!(claimable >= expected - tolerance && claimable <= expected + tolerance);

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// ============== Edge Case Tests ==============

// Test segment value at exact segment start boundary
#[test]
public fun test_segment_value_at_start_boundary() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);

        let duration = 1000;
        let amount = ONE_SUI * 100;

        clock.set_for_testing(1000);

        let segment = coindrip::new_segment(&controller, amount, 1, duration);

        let stream_coin = coin::mint_for_testing<SUI>(amount, scenario.ctx());
        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment],
            &clock,
            scenario.ctx(),
        );

        // At exact start time, claimable should be 0
        let claimable = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable == 0);

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test segment value at exact segment end boundary
#[test]
public fun test_segment_value_at_end_boundary() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);

        let duration = 1000;
        let amount = ONE_SUI * 100;

        clock.set_for_testing(1000);

        let segment = coindrip::new_segment(&controller, amount, 1, duration);

        let stream_coin = coin::mint_for_testing<SUI>(amount, scenario.ctx());
        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment],
            &clock,
            scenario.ctx(),
        );

        // At exact end time, claimable should be full amount
        clock.set_for_testing(1000 + duration);
        let claimable = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable == amount);

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test multiple segments with varying durations and exponents
#[test]
public fun test_multiple_segments_varying_params_no_overflow() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);

        // Create 3 segments with different characteristics
        let duration1: u64 = 1000; // 1 second, small
        let duration2: u64 = 31_536_000_000; // 1 year, large
        let duration3: u64 = 100_000_000_000; // ~3 years, large

        let amount1 = ONE_SUI * 100;
        let amount2 = ONE_SUI * 500;
        let amount3 = ONE_SUI * 400;
        let total_amount = amount1 + amount2 + amount3;

        clock.set_for_testing(1000);

        let segment1 = coindrip::new_segment(&controller, amount1, 1, duration1);
        let segment2 = coindrip::new_segment(&controller, amount2, 5, duration2);
        let segment3 = coindrip::new_segment(&controller, amount3, 10, duration3);

        let stream_coin = coin::mint_for_testing<SUI>(total_amount, scenario.ctx());
        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment1, segment2, segment3],
            &clock,
            scenario.ctx(),
        );

        // After first segment completes
        clock.set_for_testing(1000 + duration1);
        let claimable_after_seg1 = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable_after_seg1 >= amount1); // At least first segment

        // At the very end
        clock.set_for_testing(1000 + duration1 + duration2 + duration3 + 1);
        let claimable_end = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable_end == total_amount);

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test with maximum u64 amount to verify no overflow in multiplication
#[test]
public fun test_segment_value_with_max_u64_amount() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);

        // Use a very large amount (not quite max u64 to avoid other issues)
        let large_amount: u64 = 18_000_000_000_000_000_000; // ~18 quintillion
        let duration = coindrip::get_max_segment_duration();

        clock.set_for_testing(1000);

        let segment = coindrip::new_segment(&controller, large_amount, 5, duration);

        let stream_coin = coin::mint_for_testing<SUI>(large_amount, scenario.ctx());
        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment],
            &clock,
            scenario.ctx(),
        );

        // Test at 50% - should not overflow
        clock.set_for_testing(1000 + duration / 2);
        let claimable = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable <= large_amount);

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test absolute worst case: MAX duration + MAX exponent + near-MAX u64 amount
#[test]
public fun test_absolute_max_values_no_overflow() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);

        // Absolute worst case parameters
        let max_amount: u64 = 18_000_000_000_000_000_000; // ~18 quintillion (near max u64)
        let max_duration = coindrip::get_max_segment_duration(); // 6 years
        let max_exponent: u8 = 10; // Maximum allowed exponent

        clock.set_for_testing(1000);

        let segment = coindrip::new_segment(&controller, max_amount, max_exponent, max_duration);

        let stream_coin = coin::mint_for_testing<SUI>(max_amount, scenario.ctx());
        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment],
            &clock,
            scenario.ctx(),
        );

        // Test at various points to ensure no overflow with all max values
        // At 10%
        clock.set_for_testing(1000 + max_duration / 10);
        let claimable_10pct = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable_10pct <= max_amount);

        // At 50%
        clock.set_for_testing(1000 + max_duration / 2);
        let claimable_50pct = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable_50pct <= max_amount);
        assert!(claimable_50pct >= claimable_10pct); // Monotonically increasing

        // At 90%
        clock.set_for_testing(1000 + (max_duration * 9) / 10);
        let claimable_90pct = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable_90pct <= max_amount);
        assert!(claimable_90pct >= claimable_50pct);

        // At 100% (end)
        clock.set_for_testing(1000 + max_duration);
        let claimable_100pct = coindrip::recipient_balance(&stream, &clock);
        assert!(claimable_100pct == max_amount); // Should be full amount at end

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}
