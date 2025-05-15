#[test_only]
module coindrip::coindrip_tests_create_stream;

use coindrip::coindrip::{Self, Controller, Segment, Stream};
use coindrip::coindrip_tests_setup::setup;
use std::type_name;
use sui::clock::Clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{Self as ts, Scenario};

const SENDER: address = @0xAAA;
const RECIPIENT: address = @0xBBB;
const ONE_SUI: u64 = 1_000_000_000;

const EInsufficientBalance: u64 = 0;
const EInvalidSegments: u64 = 1;
const EInvalidStartTime: u64 = 2;
const ECliffTooBig: u64 = 6;

// Create a stream with a valid coin, recipient, start time, and one segment.
#[test]
public fun create_stream_hc1(): Scenario {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);

        let stream_coin = coin::mint_for_testing<SUI>(ONE_SUI * 1000, scenario.ctx());
        clock.set_for_testing(1000);
        let segment = coindrip::new_segment(&controller, stream_coin.value(), 1, 1000);

        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment],
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.next_tx(RECIPIENT);
    {
        let stream = ts::take_from_sender<Stream<SUI>>(&scenario);
        assert!(stream.get_sender() == SENDER);
        assert!(stream.get_token() == type_name::get<SUI>().into_string());
        assert!(stream.get_balance() == ONE_SUI * 1000);
        assert!(stream.get_initial_deposit() == ONE_SUI * 1000);
        assert!(stream.get_start_time() == 1000);
        assert!(stream.get_end_time() == 2000);
        assert!(stream.get_cliff() == 0);
        assert!(stream.get_segments().length() == 1);
        assert!(stream.get_segments()[0].get_segment_amount() == ONE_SUI * 1000);
        assert!(stream.get_segments()[0].get_segment_exponent() == 1);
        assert!(stream.get_segments()[0].get_segment_duration() == 1000);

        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
    };

    scenario
}

// Create a stream with three segments summing to the coin value.
#[test]
public fun create_stream_hc2() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);

        let stream_coin = coin::mint_for_testing<SUI>(ONE_SUI * 3000, scenario.ctx());
        clock.set_for_testing(1000);
        let segment1 = coindrip::new_segment(&controller, stream_coin.value() / 3, 1, 1000);
        let segment2 = coindrip::new_segment(&controller, stream_coin.value() / 3, 1, 2000);
        let segment3 = coindrip::new_segment(&controller, stream_coin.value() / 3, 1, 3000);

        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            500,
            vector<Segment>[segment1, segment2, segment3],
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.next_tx(RECIPIENT);
    {
        let stream = ts::take_from_sender<Stream<SUI>>(&scenario);
        assert!(stream.get_sender() == SENDER);
        assert!(stream.get_token() == type_name::get<SUI>().into_string());
        assert!(stream.get_balance() == ONE_SUI * 3000);
        assert!(stream.get_initial_deposit() == ONE_SUI * 3000);
        assert!(stream.get_start_time() == 1000);
        assert!(stream.get_end_time() == 7000);
        assert!(stream.get_cliff() == 500);
        assert!(stream.get_segments().length() == 3);
        assert!(stream.get_segments()[0].get_segment_amount() == ONE_SUI * 1000);
        assert!(stream.get_segments()[0].get_segment_exponent() == 1);
        assert!(stream.get_segments()[0].get_segment_duration() == 1000);
        assert!(stream.get_segments()[1].get_segment_amount() == ONE_SUI * 1000);
        assert!(stream.get_segments()[1].get_segment_exponent() == 1);
        assert!(stream.get_segments()[1].get_segment_duration() == 2000);
        assert!(stream.get_segments()[2].get_segment_amount() == ONE_SUI * 1000);
        assert!(stream.get_segments()[2].get_segment_exponent() == 1);
        assert!(stream.get_segments()[2].get_segment_duration() == 3000);

        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
    };

    scenario.end();
}

// Attempt to create a stream with a coin of value 0.
#[test]
#[expected_failure(abort_code = EInsufficientBalance, location = coindrip)]
public fun create_stream_fc1() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);
        let stream_coin = coin::mint_for_testing<SUI>(0, scenario.ctx());
        clock.set_for_testing(1000);
        let segment = coindrip::new_segment(&controller, stream_coin.value(), 1, 1000);

        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment],
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Attempt to create a stream with a start time in the past.
#[test]
#[expected_failure(abort_code = EInvalidStartTime, location = coindrip)]
public fun create_stream_fc3() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);
        let stream_coin = coin::mint_for_testing<SUI>(ONE_SUI * 1000, scenario.ctx());
        clock.set_for_testing(2000);
        let segment = coindrip::new_segment(&controller, stream_coin.value(), 1, 1000);

        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment],
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// #[test]
// #[expected_failure(abort_code = EInvalidEndTime, location = coindrip)]
// public fun create_stream_fc4() {
//     let mut scenario = setup();

//     scenario.next_tx(SENDER);
//     {
//         let mut clock = scenario.take_shared<Clock>();
//         let controller = ts::take_shared<Controller>(&scenario);
//         let stream_coin = coin::mint_for_testing<SUI>(ONE_SUI * 1000, scenario.ctx());
//         clock.set_for_testing(1000);
//         let segment = coindrip::new_segment(&controller, stream_coin.value(), 1, 0);

//         let stream = coindrip::create_stream(
//             &controller,
//             stream_coin,
//             1000,
//             0,
//             vector<Segment>[segment],
//             &clock,
//             scenario.ctx(),
//         );

//         transfer::public_transfer(stream, RECIPIENT);
//         ts::return_shared(clock);
//         ts::return_shared(controller);
//     };

//     scenario.end();
// }

// Attempt to create a stream where the cliff period extends beyond or equals the end time.
#[test]
#[expected_failure(abort_code = ECliffTooBig, location = coindrip)]
public fun create_stream_fc5() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);
        let stream_coin = coin::mint_for_testing<SUI>(ONE_SUI * 1000, scenario.ctx());
        clock.set_for_testing(1000);
        let segment = coindrip::new_segment(&controller, stream_coin.value(), 1, 1000);

        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            1000,
            vector<Segment>[segment],
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Attempt to create a stream where segments’ total amount does not match the coin value.
#[test]
#[expected_failure(abort_code = EInvalidSegments, location = coindrip)]
public fun create_stream_fc61() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);
        let stream_coin = coin::mint_for_testing<SUI>(ONE_SUI * 1000, scenario.ctx());
        clock.set_for_testing(1000);
        let segment = coindrip::new_segment(&controller, stream_coin.value() / 2, 1, 1000);

        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment],
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Attempt to create a stream where one segment's duration is zero
#[test]
#[expected_failure(abort_code = EInvalidSegments, location = coindrip)]
public fun create_stream_fc62() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);
        let stream_coin = coin::mint_for_testing<SUI>(ONE_SUI * 1000, scenario.ctx());
        clock.set_for_testing(1000);
        let segment1 = coindrip::new_segment(&controller, stream_coin.value() / 2, 1, 1000);
        let segment2 = coindrip::new_segment(&controller, stream_coin.value() / 2, 1, 0);

        let stream = coindrip::create_stream(
            &controller,
            stream_coin,
            1000,
            0,
            vector<Segment>[segment1, segment2],
            &clock,
            scenario.ctx(),
        );

        transfer::public_transfer(stream, RECIPIENT);
        ts::return_shared(clock);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Create a stream with a large number of segments (e.g., 100) summing to the coin value.
#[test]
public fun create_stream_ec3() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);
        let stream_coin = coin::mint_for_testing<SUI>(ONE_SUI * 10_000, scenario.ctx());
        clock.set_for_testing(1000);

        let mut segments = vector::empty<Segment>();
        let mut i = 0;
        while (i < 100) {
            let segment = coindrip::new_segment(&controller, stream_coin.value() / 100, 1, 100);
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

    scenario.next_tx(RECIPIENT);
    {
        let stream = ts::take_from_sender<Stream<SUI>>(&scenario);
        assert!(stream.get_sender() == SENDER);
        assert!(stream.get_token() == type_name::get<SUI>().into_string());
        assert!(stream.get_balance() == ONE_SUI * 10_000);
        assert!(stream.get_initial_deposit() == ONE_SUI * 10_000);
        assert!(stream.get_start_time() == 1000);
        assert!(stream.get_end_time() == 11_000);
        assert!(stream.get_cliff() == 0);
        assert!(stream.get_segments().length() == 100);
        assert!(stream.get_segments()[0].get_segment_amount() == ONE_SUI * 100);
        assert!(stream.get_segments()[0].get_segment_exponent() == 1);
        assert!(stream.get_segments()[0].get_segment_duration() == 100);

        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
    };

    scenario.end();
}
