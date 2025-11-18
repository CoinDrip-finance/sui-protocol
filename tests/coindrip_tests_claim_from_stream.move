#[test_only]
module coindrip::coindrip_tests_claim_from_stream;

use coindrip::coindrip::{Self, Controller, Segment, Stream};
use coindrip::coindrip_tests_create_stream::create_stream_hc1;
use coindrip::coindrip_tests_setup::setup;
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario as ts;

const SENDER: address = @0xAAA;
const RECIPIENT: address = @0xBBB;
const ONE_SUI: u64 = 1_000_000_000;

const EZeroClaim: u64 = 4;

// Claim tokens halfway through a single-segment stream with exponent: 1
#[test]
public fun claim_from_stream_hc3() {
    let mut scenario = create_stream_hc1();
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
        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    scenario.next_tx(RECIPIENT);
    {
        let stream = ts::take_from_sender<Stream<SUI>>(&scenario);
        assert!(stream.get_balance() == ONE_SUI * 1000 / 2);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);

        let coin = ts::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin.value() == ONE_SUI * 1000 / 2);
        ts::return_to_sender<Coin<SUI>>(&scenario, coin);
    };

    scenario.end();
}

// Claim all tokens after the stream’s end time.
#[test]
public fun claim_from_stream_hc4() {
    let mut scenario = create_stream_hc1();
    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(1001);

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
        let stream = ts::take_from_sender<Stream<SUI>>(&scenario);
        assert!(stream.get_balance() == 0);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);

        let coin = ts::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin.value() == ONE_SUI * 1000);
        ts::return_to_sender<Coin<SUI>>(&scenario, coin);
    };

    scenario.end();
}

// Claim tokens at multiple points during a stream.
#[test]
public fun claim_from_stream_hc5() {
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
        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    scenario.next_tx(RECIPIENT);
    {
        let stream = ts::take_from_sender<Stream<SUI>>(&scenario);
        assert!(stream.get_balance() == ONE_SUI * 1000 / 4 * 3);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);

        let coin = ts::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin.value() == ONE_SUI * 1000 / 4);
        ts::return_to_sender<Coin<SUI>>(&scenario, coin);
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
        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    scenario.next_tx(RECIPIENT);
    {
        let stream = ts::take_from_sender<Stream<SUI>>(&scenario);
        assert!(stream.get_balance() == ONE_SUI * 1000 / 2);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);

        let coin1 = ts::take_from_sender<Coin<SUI>>(&scenario);
        let coin2 = ts::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin1.value() + coin2.value() == ONE_SUI * 1000 / 2);
        ts::return_to_sender<Coin<SUI>>(&scenario, coin1);
        ts::return_to_sender<Coin<SUI>>(&scenario, coin2);
    };

    scenario.end();
}

// Attempt to claim before the stream's start time.
#[test]
#[expected_failure(abort_code = EZeroClaim, location = coindrip)]
public fun claim_from_stream_fc7() {
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
            2000,
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
        let clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);

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

    scenario.end();
}

// Attempt to claim during the cliff period.
#[test]
#[expected_failure(abort_code = EZeroClaim, location = coindrip)]
public fun claim_from_stream_fc8() {
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
            500,
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
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(200);

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

    scenario.end();
}

// Attempt to claim after the entire balance has been claimed.
#[test]
#[expected_failure(abort_code = EZeroClaim, location = coindrip)]
public fun claim_from_stream_fc9() {
    let mut scenario = create_stream_hc1();

    // First claim
    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(2000);

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
        let stream = ts::take_from_sender<Stream<SUI>>(&scenario);
        assert!(stream.get_balance() == 0);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);

        let coin = ts::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin.value() == ONE_SUI * 1000);
        ts::return_to_sender<Coin<SUI>>(&scenario, coin);
    };

    // Second claim
    scenario.next_tx(RECIPIENT);
    {
        let mut clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
        clock.increment_for_testing(200);

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

    scenario.end();
}

// Claim at the exact start time with no cliff.
#[test]
#[expected_failure(abort_code = EZeroClaim, location = coindrip)]
public fun claim_from_stream_ec5() {
    let mut scenario = create_stream_hc1();

    scenario.next_tx(RECIPIENT);
    {
        let clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);

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

    scenario.end();
}

// Claim immediately after the cliff period ends.
#[test]
#[expected_failure(abort_code = EZeroClaim, location = coindrip)]
public fun claim_from_stream_ec6() {
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
            500,
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
        let clock = scenario.take_shared<Clock>();
        let mut controller = ts::take_shared<Controller>(&scenario);
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

    scenario.end();
}

// Claim from a stream with exponent: 2 to test non-linear vesting.
#[test]
public fun claim_from_stream_ec7() {
    let mut scenario = setup();

    scenario.next_tx(SENDER);
    {
        let mut clock = scenario.take_shared<Clock>();
        let controller = ts::take_shared<Controller>(&scenario);
        let stream_coin = coin::mint_for_testing<SUI>(ONE_SUI * 1000, scenario.ctx());
        clock.set_for_testing(1000);
        let segment = coindrip::new_segment(&controller, stream_coin.value(), 2, 1000);

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
        ts::return_shared(clock);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);
        ts::return_shared(controller);
    };

    scenario.next_tx(RECIPIENT);
    {
        let stream = ts::take_from_sender<Stream<SUI>>(&scenario);
        assert!(stream.get_balance() == ONE_SUI *1000 / 4 * 3);
        ts::return_to_sender<Stream<SUI>>(&scenario, stream);

        let coin = ts::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin.value() == ONE_SUI * 1000 / 4);
        ts::return_to_sender<Coin<SUI>>(&scenario, coin);
    };

    scenario.end();
}
