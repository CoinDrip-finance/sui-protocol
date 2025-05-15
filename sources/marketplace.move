module coindrip::marketplace;

use coindrip::coindrip::Stream;
use std::string;
use std::type_name::{TypeName, get};
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::display;
use sui::event;
use sui::package::{Self, Publisher};
use sui::sui::SUI;
use sui::table::{Self, Table};
use sui::url::{Self, Url};

/*
* This is work in progress and not be taken into consideration.
*/

// === Error codes ===

public struct MarketplaceController has key, store {
    id: UID,
    streams: Bag,
    listings: Table<ID, Listing>,
}

public struct Listing has key, store {
    id: UID,
    stream: ID,
    price: u64,
    owner: address,
}

public struct MARKETPLACE has drop {}

fun init(otw: MARKETPLACE, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    transfer::public_transfer(publisher, ctx.sender());

    let controller = MarketplaceController {
        id: object::new(ctx),
        listings: table::new(ctx),
        streams: bag::new(ctx),
    };

    transfer::public_share_object(controller);
}

public fun list<T>(
    controller: &mut MarketplaceController,
    stream: Stream<T>,
    price: u64,
    ctx: &mut TxContext,
) {
    let listing = Listing {
        id: object::new(ctx),
        stream: stream.get_stream_id(),
        price,
        owner: ctx.sender(),
    };

    table::add(&mut controller.listings, stream.get_stream_id(), listing);
    bag::add(&mut controller.streams, stream.get_stream_id(), stream);
}

public fun cancel<T>(
    controller: &mut MarketplaceController,
    stream_id: ID,
    ctx: &mut TxContext,
): Stream<T> {
    let listing = table::remove(&mut controller.listings, stream_id);
    assert!(listing.owner == ctx.sender(), 1);

    let stream: Stream<T> = bag::remove(&mut controller.streams, stream_id);

    let Listing {
        id,
        stream: _,
        price: _,
        owner: _,
    } = listing;
    object::delete(id);

    stream
}

public fun buy<T>(
    controller: &mut MarketplaceController,
    stream_id: ID,
    coin: Coin<SUI>,
    ctx: &mut TxContext,
): Stream<T> {
    let listing = table::remove(&mut controller.listings, stream_id);
    assert!(listing.price == coin.value(), 0);

    let stream: Stream<T> = bag::remove(&mut controller.streams, stream_id);
    transfer::public_transfer(coin, listing.owner);

    let Listing {
        id,
        stream: _,
        price: _,
        owner: _,
    } = listing;
    object::delete(id);

    stream
}

public struct StreamListed has copy, drop {
    stream_id: ID,
    listing_id: ID,
    owner: address,
    price: u64,
}

public struct ListingCanceled has copy, drop {
    stream_id: ID,
    listing_id: ID,
}

public struct StreamBought has copy, drop {
    stream_id: ID,
    listing_id: ID,
}
