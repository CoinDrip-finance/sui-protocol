#[test_only]
module coindrip::coindrip_tests_migration;

use coindrip::coindrip::{Self, AdminCap, Controller, Segment, Stream};
use coindrip::coindrip_tests_setup::setup;
use sui::clock::Clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario as ts;

const ADMIN: address = @0xAD;
const SENDER: address = @0xAAA;
const RECIPIENT: address = @0xBBB;
const ONE_SUI: u64 = 1_000_000_000;

// Test successful migration of controller version with AdminCap
#[test]
public fun test_migrate_controller_version_success() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
        let mut controller = ts::take_shared<Controller>(&scenario);

        // Migrate to version 2
        coindrip::migrate_controller_version(&admin_cap, &mut controller, 2);

        transfer::public_transfer(admin_cap, ADMIN);
        ts::return_shared(controller);
    };

    scenario.end();
}

// Test that functions work after migration (simulated by keeping version at 1)
#[test]
public fun test_functions_work_with_current_version() {
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

    // Claim from the stream to verify it works
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

    scenario.end();
}
