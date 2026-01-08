module coindrip::coindrip;

use std::string;
use std::type_name::get;
use std::u256;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;
use sui::package;
use sui::sui::SUI;

// === Errors ===
const EInsufficientBalance: u64 = 0;
const EInvalidSegments: u64 = 1;
const EInvalidStartTime: u64 = 2;
const EInvalidEndTime: u64 = 3;
const EZeroClaim: u64 = 4;
const EBalanceNotZero: u64 = 5;
const ECliffTooBig: u64 = 6;
const ESegmentValueOverflow: u64 = 7;
const EInvalidExponent: u64 = 8;
const EInvalidVersion: u64 = 11;
const EInvalidFeeAmount: u64 = 12;
const ETruncationDataTooShort: u64 = 13;
const ETooManySegments: u64 = 14;
const EInvalidSegmentDuration: u64 = 15;
const EFeeTooHigh: u64 = 16;

// === Constants ===

const STREAM_IMAGE_BASE_URL: vector<u8> = b"https://devnet.coindrip.finance/api/stream";
const VERSION: u64 = 1;
const MAX_EXPONENT: u8 = 10;
const ONE_SUI: u64 = 1_000_000_000;
const MAX_DURATION_TICKS: u64 = 525_600; // Max ticks to prevent overflow at exp=10
const MAX_SEGMENT_DURATION: u64 = 189_345_600_000; // ~6 years in milliseconds
const MAX_SEGMENTS: u64 = 500;
const MAX_CLAIM_FEE: u64 = 50_000_000_000; // 50 SUI max

// === Structs ===

/// A segment defines a portion of a stream with its own streaming curve.
/// The streaming curve follows the formula: streamed = amount * (elapsed / duration)^exponent
/// - exponent = 1: linear streaming
/// - exponent > 1: exponential streaming (slow start, fast end)
public struct Segment has copy, drop, store {
    amount: u64,     // Total tokens to stream in this segment
    exponent: u8,    // Curve exponent (1-10), controls streaming speed distribution
    duration: u64,   // Duration of this segment in milliseconds
}

/// A token stream that vests tokens over time according to defined segments.
/// The stream is represented as an NFT that can be transferred to change the recipient.
public struct Stream<phantom T> has key, store {
    id: UID,
    name: string::String,
    image_url: string::String,
    sender: address,              // Original creator of the stream
    token: std::ascii::String,    // Token type identifier
    balance: Balance<T>,          // Remaining tokens in the stream
    initial_deposit: u64,         // Original amount deposited
    start_time: u64,              // Stream start timestamp (ms)
    end_time: u64,                // Stream end timestamp (ms)
    segments: vector<Segment>,    // Streaming curve segments
    cliff: u64,                   // Cliff duration (ms) - no tokens claimable until cliff passes
    tick_size: u64,               // Pre-computed tick size for segment calculations
}

/// Capability granting full admin privileges (treasury withdrawal, version migration)
public struct AdminCap has key, store {
    id: UID,
}

/// Capability granting permission to update the claim fee
public struct UpdateFeeCap has key, store {
    id: UID,
}

/// Global controller managing protocol configuration and fee collection
public struct Controller has key, store {
    id: UID,
    version: u64,            // Protocol version for upgrade compatibility
    claim_fee: u64,          // Fee charged per claim (in MIST)
    treasury: Balance<SUI>,  // Accumulated fees
}

public struct COINDRIP has drop {}

// === Events ===

public struct StreamCreated has copy, drop {
    stream_id: ID,
    sender: address,
    amount: u64,
    start_time: u64,
    end_time: u64,
    token: std::ascii::String,
    cliff: u64,
    segments: vector<Segment>,
}

public struct StreamClaimed has copy, drop {
    stream_id: ID,
    claimed_by: address,
    amount: u64,
    remaining_balance: u64,
}

public struct StreamDestroyed has copy, drop {
    stream_id: ID,
    destroyed_by: address,
}

// === Public Functions ===

/// Creates a new token stream with the specified parameters.
/// Returns a Stream NFT that represents the vesting schedule.
public fun create_stream<T>(
    controller: &Controller,
    coin: Coin<T>,
    start_time: u64,
    cliff: u64,
    segments: vector<Segment>,
    clock: &Clock,
    ctx: &mut TxContext,
): Stream<T> {
    assert!(controller.version == VERSION, EInvalidVersion);
    assert!(coin.value() > 0, EInsufficientBalance);

    let sender = ctx.sender();

    let current_time = clock.timestamp_ms();
    assert!(start_time >= current_time, EInvalidStartTime);
    let stream_duration = validate_stream_segments(coin.value(), &segments);
    let end_time = start_time + stream_duration;
    assert!(end_time > start_time, EInvalidEndTime);
    assert!(start_time + cliff < end_time, ECliffTooBig);

    // Compute tick_size based on max segment duration (computed once at creation)
    let mut max_duration: u64 = 0;
    let mut j = 0;
    while (j < segments.length()) {
        let seg = segments.borrow(j);
        if (seg.duration > max_duration) {
            max_duration = seg.duration;
        };
        j = j + 1;
    };
    let tick_size = compute_tick_size(max_duration);

    let nftId = object::new(ctx);
    let objectIdString = nftId.to_address().to_string().as_bytes();

    let mut stream_name = b"Stream ";
    stream_name.append(truncate_with_ellipsis(objectIdString));

    let mut stream_image_url = STREAM_IMAGE_BASE_URL;
    stream_image_url.append(b"/0x");
    stream_image_url.append(*objectIdString);
    stream_image_url.append(b"/nft");

    let coin_value = coin.value();
    let coin_balance = coin.into_balance();

    let stream = Stream<T> {
        id: nftId,
        name: string::utf8(stream_name),
        image_url: string::utf8(stream_image_url),
        sender,
        token: get<T>().into_string(),
        balance: coin_balance,
        initial_deposit: coin_value,
        start_time,
        end_time,
        cliff,
        segments,
        tick_size,
    };

    event::emit(StreamCreated {
        stream_id: object::id(&stream),
        sender,
        amount: coin_value,
        start_time,
        end_time,
        token: get<T>().into_string(),
        cliff,
        segments,
    });

    stream
}

/// Claims available tokens from a stream. The caller must be the stream owner.
/// Requires exact fee payment matching controller.claim_fee.
public fun claim_from_stream<T>(
    controller: &mut Controller,
    stream: &mut Stream<T>,
    fee_payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T> {
    assert!(controller.version == VERSION, EInvalidVersion);

    // Validate and process claim fee
    assert!(fee_payment.value() == controller.claim_fee, EInvalidFeeAmount);
    coin::put(&mut controller.treasury, fee_payment);

    let balance_before_claim = stream.balance.value();
    let amount = recipient_balance(stream, clock);

    assert!(amount > 0, EZeroClaim);

    let sender = ctx.sender();

    event::emit(StreamClaimed {
        stream_id: object::id(stream),
        claimed_by: sender,
        amount: amount,
        remaining_balance: balance_before_claim - amount,
    });

    coin::take(&mut stream.balance, amount, ctx)
}

/// Destroys a fully claimed stream (balance must be zero).
/// Cleans up the Stream object after all tokens have been claimed.
public fun destroy_zero<T>(controller: &Controller, self: Stream<T>, ctx: &mut TxContext) {
    assert!(controller.version == VERSION, EInvalidVersion);
    let Stream {
        id,
        name: _,
        image_url: _,
        sender: _,
        token: _,
        balance,
        initial_deposit: _,
        start_time: _,
        end_time: _,
        cliff: _,
        segments: _,
        tick_size: _,
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

/// Creates a new segment with the specified parameters.
/// Validates: exponent <= 10, 0 < duration <= ~6 years
public fun new_segment(controller: &Controller, amount: u64, exponent: u8, duration: u64): Segment {
    assert!(controller.version == VERSION, EInvalidVersion);
    assert!(exponent <= MAX_EXPONENT, EInvalidExponent);
    assert!(duration > 0, EInvalidSegments);
    assert!(duration <= MAX_SEGMENT_DURATION, EInvalidSegmentDuration);
    Segment {
        amount,
        exponent,
        duration,
    }
}

// === View Functions ===

public fun get_stream_id<T>(stream: &Stream<T>): ID {
    stream.id.to_inner()
}

public fun get_name<T>(stream: &Stream<T>): string::String {
    stream.name
}

public fun get_image_url<T>(stream: &Stream<T>): string::String {
    stream.image_url
}

public fun get_sender<T>(stream: &Stream<T>): address {
    stream.sender
}

public fun get_token<T>(stream: &Stream<T>): std::ascii::String {
    stream.token
}

public fun get_balance<T>(stream: &Stream<T>): u64 {
    stream.balance.value()
}

public fun get_initial_deposit<T>(stream: &Stream<T>): u64 {
    stream.initial_deposit
}

public fun get_start_time<T>(stream: &Stream<T>): u64 {
    stream.start_time
}

public fun get_end_time<T>(stream: &Stream<T>): u64 {
    stream.end_time
}

public fun get_cliff<T>(stream: &Stream<T>): u64 {
    stream.cliff
}

public fun get_segments<T>(stream: &Stream<T>): vector<Segment> {
    stream.segments
}

public fun get_segment_duration(segment: &Segment): u64 {
    segment.duration
}

public fun get_segment_amount(segment: &Segment): u64 {
    segment.amount
}

public fun get_segment_exponent(segment: &Segment): u8 {
    segment.exponent
}

public fun get_claim_fee(controller: &Controller): u64 {
    controller.claim_fee
}

public fun get_treasury_balance(controller: &Controller): u64 {
    controller.treasury.value()
}

/// Returns the amount of tokens currently claimable by the stream recipient.
/// This is calculated as: total_streamed - already_claimed
public fun recipient_balance<T>(stream: &Stream<T>, clock: &Clock): u64 {
    let current_time = clock.timestamp_ms();

    // Stream hasn't started yet
    if (current_time < stream.start_time) {
        return 0
    };

    // Still within cliff period
    if (stream.start_time + stream.cliff > current_time) {
        return 0
    };

    // Stream has ended - return all remaining balance
    if (current_time > stream.end_time) {
        return stream.balance.value()
    };

    let claimed_amount = stream.initial_deposit - stream.balance.value();
    let streamed_amount = streamed_amount(stream, clock);

    streamed_amount - claimed_amount
}

// === Admin Functions ===

/// Updates the claim fee. Requires UpdateFeeCap capability.
public fun update_fee(_: &UpdateFeeCap, controller: &mut Controller, new_fee: u64) {
    assert!(new_fee <= MAX_CLAIM_FEE, EFeeTooHigh);
    controller.claim_fee = new_fee;
}

/// Withdraws all accumulated fees from the treasury. Requires AdminCap capability.
public fun withdraw_treasury(
    _: &AdminCap,
    controller: &mut Controller,
    ctx: &mut TxContext,
): Coin<SUI> {
    let amount = controller.treasury.value();
    coin::take(&mut controller.treasury, amount, ctx)
}

/// Updates the controller version after a package upgrade. Requires AdminCap capability.
/// This is necessary to re-enable protocol functions after upgrading the package.
public fun migrate_controller_version(_: &AdminCap, controller: &mut Controller, new_version: u64) {
    controller.version = new_version;
}

// === Private Functions ===

fun init(otw: COINDRIP, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    transfer::public_transfer(publisher, ctx.sender());

    let admin_cap = AdminCap {
        id: object::new(ctx),
    };

    transfer::public_transfer(admin_cap, ctx.sender());

    let update_fee_cap = UpdateFeeCap {
        id: object::new(ctx),
    };

    transfer::public_transfer(update_fee_cap, ctx.sender());

    let controller = Controller {
        id: object::new(ctx),
        version: VERSION,
        claim_fee: ONE_SUI / 4,
        treasury: balance::zero<SUI>(),
    };

    transfer::public_share_object(controller);
}

fun truncate_with_ellipsis(data: &vector<u8>): vector<u8> {
    let len = vector::length(data);

    // Ensure the vector has at least 8 bytes to avoid out-of-bounds access
    assert!(len >= 8, ETruncationDataTooShort);

    // Extract the first 4 bytes
    let mut first_four = vector::empty<u8>();
    let mut i = 0;
    while (i < 4) {
        vector::push_back(&mut first_four, *vector::borrow(data, i));
        i = i + 1;
    };

    // Define the ellipsis ("...")
    let ellipsis = b"..."; // This is a vector<u8> literal

    // Extract the last 4 bytes
    let mut last_four = vector::empty<u8>();
    let mut j = len - 4;
    while (j < len) {
        vector::push_back(&mut last_four, *vector::borrow(data, j));
        j = j + 1;
    };

    // Concatenate: first_four + ellipsis + last_four
    let mut result = vector::empty<u8>();
    vector::append(&mut result, first_four);
    vector::append(&mut result, ellipsis);
    vector::append(&mut result, last_four);

    result
}

/// Validates that segments are properly configured and returns the total stream duration.
/// Ensures: segment count <= MAX_SEGMENTS, all durations > 0, total amount == deposit
fun validate_stream_segments(deposit_amount: u64, segments: &vector<Segment>): u64 {
    assert!(segments.length() <= MAX_SEGMENTS, ETooManySegments);

    let mut total_duration = 0;
    let mut total_amount = 0;

    let mut i = 0;
    while (i < segments.length()) {
        let segment = segments.borrow(i);
        assert!(segment.duration > 0, EInvalidSegments);
        total_duration = segment.duration + total_duration;
        total_amount = segment.amount + total_amount;
        i = i + 1;
    };

    assert!(total_amount == deposit_amount, EInvalidSegments);

    total_duration
}

fun min(a: u64, b: u64): u64 {
    if (a < b) {
        a
    } else {
        b
    }
}

/// Computes the tick size for duration-based calculations.
/// For short durations, uses millisecond precision (tick_size = 1).
/// For long durations, uses coarser ticks to prevent overflow in exponentiation.
fun compute_tick_size(duration: u64): u64 {
    if (duration <= MAX_DURATION_TICKS) {
        return 1
    };
    // tick_size = ceil(duration / MAX_DURATION_TICKS)
    (duration + MAX_DURATION_TICKS - 1) / MAX_DURATION_TICKS
}

/// Computes the streamed amount for a single segment at the current time.
/// Formula: amount * (elapsed_ticks / duration_ticks)^exponent
/// Uses tick-based calculation to prevent overflow with large durations.
fun compute_segment_value(segment_start_time: u64, segment: &Segment, tick_size: u64, clock: &Clock): u64 {
    let segment_end_time = segment_start_time + segment.duration;
    let current_time = clock.timestamp_ms();

    // Segment hasn't started
    if (current_time <= segment_start_time) {
        return 0
    };

    // Segment has completed
    if (current_time >= segment_end_time) {
        return segment.amount
    };

    let elapsed_time = current_time - segment_start_time;

    // Convert to ticks to prevent overflow in exponentiation
    let elapsed_ticks = elapsed_time / tick_size;
    let duration_ticks = segment.duration / tick_size;

    // Calculate: (elapsed/duration)^exponent * amount using u256 for precision
    let elapsed_ticks_u256 = elapsed_ticks as u256;
    let amount_u256 = segment.amount as u256;
    let duration_ticks_u256 = duration_ticks as u256;

    let numerator = elapsed_ticks_u256.pow(segment.exponent) * amount_u256;
    let denominator = duration_ticks_u256.pow(segment.exponent);

    let result_option_u64 = u256::try_as_u64(numerator / denominator);
    assert!(option::is_some(&result_option_u64), ESegmentValueOverflow);
    option::destroy_some(result_option_u64)
}

/// Calculates the total amount streamed across all segments at the current time.
/// Uses the pre-computed tick_size stored in the stream for efficient calculation.
fun streamed_amount<T>(stream: &Stream<T>, clock: &Clock): u64 {
    let current_time = clock.timestamp_ms();

    if (current_time < stream.start_time) {
        return 0
    };

    if (stream.start_time + stream.cliff > current_time) {
        return 0
    };

    if (current_time > stream.end_time) {
        return stream.initial_deposit
    };

    // Sum up streamed amounts from each segment using pre-computed tick_size
    let mut i = 0;
    let mut total = 0;
    let mut segment_start_time = stream.start_time;

    while (i < stream.segments.length()) {
        // Early exit if segment hasn't started yet (all subsequent segments are in the future)
        if (segment_start_time > current_time) {
            break
        };

        let segment = stream.segments.borrow(i);
        let segment_value = compute_segment_value(segment_start_time, segment, stream.tick_size, clock);
        total = total + segment_value;

        segment_start_time = segment_start_time + segment.duration;
        i = i + 1;
    };

    // Cap at initial deposit to handle any rounding edge cases
    min(total, stream.initial_deposit)
}

// === Test Functions ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    let otw = COINDRIP {};
    init(otw, ctx);
}

#[test_only]
public fun validate_stream_segments_for_test(deposit_amount: u64, segments: &vector<Segment>): u64 {
    validate_stream_segments(deposit_amount, segments)
}

#[test_only]
public fun compute_segment_value_for_test(
    segment_start_time: u64,
    segment: &Segment,
    tick_size: u64,
    clock: &Clock,
): u64 {
    compute_segment_value(segment_start_time, segment, tick_size, clock)
}

#[test_only]
public fun compute_tick_size_for_test(duration: u64): u64 {
    compute_tick_size(duration)
}

#[test_only]
public fun get_max_duration_ticks(): u64 {
    MAX_DURATION_TICKS
}

#[test_only]
public fun get_max_segment_duration(): u64 {
    MAX_SEGMENT_DURATION
}

#[test_only]
public fun get_max_segments(): u64 {
    MAX_SEGMENTS
}

#[test_only]
public fun get_max_claim_fee(): u64 {
    MAX_CLAIM_FEE
}
