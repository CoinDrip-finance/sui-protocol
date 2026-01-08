#[test_only]
module coindrip::coindrip_tests_helper_functions;

use coindrip::coindrip::{
    Self,
    Controller,
    Segment,
    validate_stream_segments_for_test,
    compute_segment_value_for_test,
    compute_tick_size_for_test
};
use coindrip::coindrip_tests_setup::setup;
use sui::clock::Clock;
use sui::test_scenario as ts;

const RECIPIENT: address = @0xBBB;

// Test validate_stream_segments with valid segments.
#[test]
public fun claim_from_stream_hc7() {
    let scenario = setup();
    let controller = ts::take_shared<Controller>(&scenario);

    let segment1 = coindrip::new_segment(&controller, 1000, 1, 1000);
    let segment2 = coindrip::new_segment(&controller, 1000, 1, 2000);
    let segments_vector = vector<Segment>[segment1, segment2];

    let duration = validate_stream_segments_for_test(2000, &segments_vector);

    assert!(duration == 3000);

    ts::return_shared(controller);
    scenario.end();
}

// Test compute_segment_value for a segment.
#[test]
public fun claim_from_stream_hc8() {
    let mut scenario = setup();

    scenario.next_tx(RECIPIENT);
    {
        let controller = ts::take_shared<Controller>(&scenario);
        let mut clock = scenario.take_shared<Clock>();
        clock.set_for_testing(1500);

        let segment = coindrip::new_segment(&controller, 1000, 1, 1000);

        // Compute tick_size based on segment duration (1000 ms -> tick_size = 1)
        let tick_size = compute_tick_size_for_test(1000);
        let duration = compute_segment_value_for_test(1000, &segment, tick_size, &clock);

        assert!(duration == 500);

        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}
