#[test_only]
module coindrip::coindrip_tests_destroy_zero;

use coindrip::coindrip::{Self, Controller, Stream};
use coindrip::coindrip_tests_create_stream::create_stream_hc1;
use sui::clock::Clock;
use sui::sui::SUI;
use sui::test_scenario as ts;

const RECIPIENT: address = @0xBBB;

const EBalanceNotZero: u64 = 5;

// Destroy a stream after claiming all tokens.
#[test]
public fun claim_from_stream_hc6() {
    let mut scenario = create_stream_hc1();

    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(1000);

        let mut stream = ts::take_from_sender<Stream<SUI>>(&scenario);

        let coin = coindrip::claim_from_stream(
            &controller,
            &mut stream,
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
        let stream = ts::take_from_sender<Stream<SUI>>(&scenario);
        let controller = ts::take_shared<Controller>(&scenario);

        coindrip::destroy_zero(
            &controller,
            stream,
            scenario.ctx(),
        );

        ts::return_shared(controller);
    };

    scenario.end();
}

// Attempt to destroy a stream with remaining balance.
#[test]
#[expected_failure(abort_code = EBalanceNotZero, location = coindrip)]
public fun claim_from_stream_fc10() {
    let mut scenario = create_stream_hc1();

    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(500);

        let mut stream = ts::take_from_sender<Stream<SUI>>(&scenario);

        let coin = coindrip::claim_from_stream(
            &controller,
            &mut stream,
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
        let stream = ts::take_from_sender<Stream<SUI>>(&scenario);
        let controller = ts::take_shared<Controller>(&scenario);

        coindrip::destroy_zero(
            &controller,
            stream,
            scenario.ctx(),
        );

        ts::return_shared(controller);
    };

    scenario.end();
}
