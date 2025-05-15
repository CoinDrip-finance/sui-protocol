#[test_only]
module coindrip::coindrip_tests_setup;

use coindrip::coindrip::{Self, Controller, Segment, Stream};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self as ts, Scenario};

const ADMIN: address = @0xAD;

#[test_only]
public fun setup(): Scenario {
    let mut scenario = ts::begin(ADMIN);
    {
        coindrip::init_for_test(scenario.ctx());
    };
    scenario.next_tx(@0x0);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        clock::share_for_testing(clock);
    };

    scenario
}
