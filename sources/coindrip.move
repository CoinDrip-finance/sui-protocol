module coindrip::coindrip;

use std::string;
use std::type_name::TypeName;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::display;
use sui::event;
use sui::package::{Self, Publisher};
use sui::table::{Self, Table};
use sui::url::{Self, Url};

// === Error codes ===
const EInsufficientBalance: u64 = 0;
const EStreamToSender: u64 = 1;
const EInvalidStartTime: u64 = 2;
const EInvalidEndTime: u64 = 3;
const EZeroClaim: u64 = 4;
const EBalanceNotZero: u64 = 5;
const ECliffTooBig: u64 = 6;

public struct Segment has drop, store {
    amount: u64,
    exponent: u64,
    duration: u64,
}

public struct Stream<phantom T> has key, store {
    id: UID,
    name: string::String,
    image_url: Url,
    sender: address,
    balance: Balance<T>,
    initial_deposit: u64,
    start_time: u64,
    end_time: u64,
    segments: vector<Segment>,
    cliff: u64,
}

public struct AdminCap has key, store {
    id: UID,
}

public struct Controller has key, store {
    id: UID,
    protocol_fee: Table<TypeName, u64>,
}

public struct COINDRIP has drop {}

fun init(otw: COINDRIP, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    transfer::public_transfer(publisher, ctx.sender());

    let admin_cap = AdminCap {
        id: object::new(ctx),
    };

    transfer::public_transfer(admin_cap, ctx.sender());

    let controller = Controller {
        id: object::new(ctx),
        protocol_fee: table::new<TypeName, u64>(ctx),
    };

    transfer::public_share_object(controller);
}

#[allow(lint(self_transfer))]
public fun init_display<T>(_: &AdminCap, publisher: &Publisher, ctx: &mut TxContext) {
    let keys = vector[
        b"name".to_string(),
        b"image_url".to_string(),
        b"project_url".to_string(),
        b"creator".to_string(),
    ];

    let values = vector[
        b"{name}".to_string(),
        b"{image_url}".to_string(),
        b"https://coindrip.finance".to_string(),
        b"CoinDrip".to_string(),
    ];

    let mut display = display::new_with_fields<Stream<T>>(
        publisher,
        keys,
        values,
        ctx,
    );

    display.update_version();

    transfer::public_transfer(display, ctx.sender());
}

public fun create_stream<T>(
    coin: Coin<T>,
    recipient: address,
    start_time: u64,
    cliff: u64,
    segments: vector<Segment>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(coin.value() > 0, EInsufficientBalance);

    let sender = ctx.sender();
    assert!(sender != recipient, EStreamToSender);

    let current_time = clock.timestamp_ms();
    assert!(start_time >= current_time, EInvalidStartTime);
    let stream_duration = validate_stream_segments(coin.value(), &segments);
    let end_time = start_time + stream_duration;
    assert!(end_time > start_time, EInvalidEndTime);
    assert!(start_time + cliff < end_time, ECliffTooBig);

    let nftId = object::new(ctx);
    let objectIdString = nftId.to_address().to_string().as_bytes();

    let mut stream_name = b"Stream ";
    stream_name.append(*objectIdString);

    let mut stream_image_url = b"https://example.com"; // TODO: Change this
    stream_image_url.append(*objectIdString);

    let coin_value = coin.value();
    let coin_balance = coin.into_balance();

    let stream = Stream<T> {
        id: nftId,
        name: string::utf8(stream_name),
        image_url: url::new_unsafe_from_bytes(stream_image_url),
        sender,
        balance: coin_balance,
        initial_deposit: coin_value,
        start_time,
        end_time,
        cliff,
        segments,
    };

    event::emit(StreamCreated {
        stream_id: object::id(&stream),
        sender,
        amount: coin_value,
        start_time,
        end_time,
    });

    transfer::public_transfer(stream, recipient);
}

fun validate_stream_segments(deposit_amount: u64, segments: &vector<Segment>): u64 {
    let mut total_duration = 0;
    let mut total_amount = 0;

    let mut i = 0;
    while (i < segments.length()) {
        let segment = segments.borrow(i);
        total_duration = segment.duration + total_duration;
        total_amount = segment.amount + total_amount;
        i = i + 1;
    };

    assert!(total_amount == deposit_amount, 5);

    total_duration
}

fun min(a: u64, b: u64): u64 {
    if (a < b) {
        a
    } else {
        b
    }
}

fun recipient_balance<T>(stream: &Stream<T>, clock: &Clock): u64 {
    let current_time = clock.timestamp_ms();

    if (current_time < stream.start_time) {
        return 0
    };

    let streamed_so_far =
        stream.initial_deposit * (current_time - stream.start_time) / (stream.end_time - stream.start_time);
    let claimed_amount = stream.initial_deposit - stream.balance.value();
    let recipient_balance = min(streamed_so_far, stream.initial_deposit) - claimed_amount;

    recipient_balance
}

#[allow(lint(self_transfer))]
public fun claim_from_stream<T>(stream: &mut Stream<T>, clock: &Clock, ctx: &mut TxContext) {
    let amount = recipient_balance(stream, clock);

    assert!(amount > 0, EZeroClaim);

    let sender = ctx.sender();

    event::emit(StreamClaimed {
        stream_id: object::id(stream),
        claimed_by: sender,
        amount: amount,
    });

    let coin = coin::take(&mut stream.balance, amount, ctx);
    transfer::public_transfer(coin, sender);
}

fun destroy_zero<T>(self: Stream<T>, ctx: TxContext) {
    let Stream {
        id,
        name: _,
        image_url: _,
        sender: _,
        balance,
        initial_deposit: _,
        start_time: _,
        end_time: _,
        cliff: _,
        segments: _,
    } = self;

    assert!(balance.value() == 0, EBalanceNotZero);

    let sender = ctx.sender();

    event::emit(StreamDestroyed {
        stream_id: id.to_inner(),
        destroyed_by: sender,
    });

    object::delete(id);
    balance::destroy_zero(balance);
}

// === Events ===
public struct StreamCreated has copy, drop {
    stream_id: ID,
    sender: address,
    amount: u64,
    start_time: u64,
    end_time: u64,
}

public struct StreamClaimed has copy, drop {
    stream_id: ID,
    claimed_by: address,
    amount: u64,
}

public struct StreamDestroyed has copy, drop {
    stream_id: ID,
    destroyed_by: address,
}
