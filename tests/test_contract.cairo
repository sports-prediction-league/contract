use starknet::ContractAddress;
use core::option::OptionTrait;
use core::{starknet::SyscallResultTrait, integer::{u8, u64}};
use starknet::testing::set_block_timestamp;
use core::result::ResultTrait;
use core::traits::{TryInto, Into};
use core::byte_array::{ByteArray, ByteArrayTrait};

use openzeppelin_token::{
    erc20::interface::{ERC20ABISafeDispatcher, ERC20ABISafeDispatcherTrait},
    erc721::interface::{ERC721ABIDispatcher, ERC721ABI, IERC721}
};

use snforge_std::{
    declare, start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait,
    DeclareResultTrait, spy_events, EventSpyAssertionsTrait, get_class_hash,
    start_cheat_block_timestamp, stop_cheat_block_timestamp
};

use starknet::{ClassHash, get_block_timestamp, get_caller_address};

use spl::mods::interfaces::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use spl::mods::interfaces::ispl::{ISPLDispatcher, ISPLDispatcherTrait};
use spl::mods::{types, constants::{Errors}, events, tokens};
use spl::mods::types::{
    Score, Reward, PredictionDetails, Leaderboard, Match, RoundDetails, MatchType, User, Prediction,
    PredictionType, RawPrediction, RawPredictionType, PredictionVariants, RawMatch, Odd
};

const ADMIN: felt252 = 'ADMIN';
const ONE_E18: u256 = 1000000000000000000_u256;

fn OWNER() -> ContractAddress {
    'owner'.try_into().unwrap()
}

fn _setup_() -> ContractAddress {
    let spl = declare("SPL").unwrap().contract_class();
    let erc20_address = __deploy_spl_erc20__(OWNER());
    let mut calldata = array![];
    OWNER().serialize(ref calldata);
    erc20_address.serialize(ref calldata);

    let (spl_contract_address, _) = spl.deploy(@calldata).unwrap();

    start_cheat_caller_address(erc20_address, OWNER());
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.mint(OWNER(), 50000000000000000000000);
    stop_cheat_caller_address(erc20_address);

    return spl_contract_address;
}

fn __deploy_spl_erc20__(admin: ContractAddress) -> ContractAddress {
    let spl_erc20_class_hash = declare("spl_token").unwrap().contract_class();
    let mut calldata = array![];
    admin.serialize(ref calldata);
    // let mut events_constructor_calldata: Array<felt252> = array![ADMIN];
    let (spl_erc20_contract_address, _) = spl_erc20_class_hash.deploy(@calldata).unwrap();

    return spl_erc20_contract_address;
}

fn USER() -> ContractAddress {
    return 'user'.try_into().unwrap();
}

fn OTHER(key: felt252) -> ContractAddress {
    return key.try_into().unwrap();
}

#[test]
fn test_register_user() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let user: ContractAddress = USER();
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1011, username: 'javis', address: user };
    spl.register_user(user_construct);
    let registered_user = spl.get_user_by_address(user);
    assert!(registered_user.username == user_construct.username);
    assert!(registered_user.id == user_construct.id);
    stop_cheat_caller_address(spl_contract_address);
}
#[test]
#[should_panic(expected: 'ALREADY_EXIST')]
fn test_register_user_twice() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let user: ContractAddress = USER();
    start_cheat_caller_address(spl_contract_address, user);
    let user1_construct = User { id: 1011, username: 'javis', address: user };
    let user2_construct = User {
        id: 1012, username: 'owen', address: 'another'.try_into().unwrap()
    };

    spl.register_user(user1_construct);
    spl.register_user(user2_construct);
    stop_cheat_caller_address(spl_contract_address);
}

#[test]
#[should_panic(expected: 'INVALID_ADDRESS')]
fn test_register_user_with_invalid_address() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let user: ContractAddress = USER();
    let user_construct = User { id: 1011, username: 'jane', address: get_caller_address() };
    start_cheat_caller_address(spl_contract_address, user);

    spl.register_user(user_construct);
    stop_cheat_caller_address(spl_contract_address);
}

#[test]
#[should_panic(expected: 'INVALID_PARAMS')]
fn test_register_user_with_invalid_params() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let user: ContractAddress = USER();
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 0, username: 'jane', address: user };

    spl.register_user(user_construct);
    stop_cheat_caller_address(spl_contract_address);
}

#[test]
fn test_register_user_indexes() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let user: ContractAddress = USER();
    let user1_construct = User { id: 1011, username: 'javis', address: user };
    let user2_construct = User {
        id: 1012, username: 'owen', address: 'another'.try_into().unwrap()
    };

    start_cheat_caller_address(spl_contract_address, user);
    spl.register_user(user1_construct);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, 'another'.try_into().unwrap());
    spl.register_user(user2_construct);
    stop_cheat_caller_address(spl_contract_address);

    let user1 = spl.get_user_by_index(1);
    let user2 = spl.get_user_by_index(2);

    assert_eq!(user1.username, user1_construct.username);
    assert_eq!(user2.username, user2_construct.username);
}


#[test]
fn test_register_matches() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id, value: (123 + i).try_into().unwrap() }]
                    }
                )
        };

    assert_eq!(spl.get_current_round(), 0);
    let timestamp = *matches[0].timestamp;
    spl.register_matches(matches);
    for i in min
        ..max {
            let odd = spl.get_match_odd(i.try_into().unwrap(), i.try_into().unwrap());
            assert_eq!(odd, (123 + i).try_into().unwrap());
        };
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
#[should_panic(expected: 'UNAUTHORIZED')]
fn test_register_matches_not_owner() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let someone: ContractAddress = 'someone'.try_into().unwrap();
    start_cheat_caller_address(spl_contract_address, someone);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id, value: (123 + 1).try_into().unwrap() }]
                    }
                )
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches);
    for i in min
        ..max {
            let odd = spl.get_match_odd(i.try_into().unwrap(), i.try_into().unwrap());
            assert_eq!(odd, (123 + i).try_into().unwrap());
        };
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
#[should_panic(expected: 'UNAUTHORIZED')]
fn test_set_score_unauthorized() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let mut scores: Array<Score> = array![];

    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id: '1', value: 123 }]
                    }
                );

            scores.append(Score { winner_odd: '1', inputed: true, match_id: id });
        };

    assert_eq!(spl.get_current_round(), 0);
    let timestamp = *matches[0].timestamp;
    spl.register_matches(matches);
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    stop_cheat_caller_address(spl_contract_address);
    start_cheat_caller_address(spl_contract_address, USER());

    spl.set_scores(scores);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
#[should_panic(expected: 'INVALID_PARAMS')]
fn test_set_score_invalid_param() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let mut scores: Array<Score> = array![];

    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id, value: 123 }]
                    }
                );
            scores.append(Score { winner_odd: id, inputed: true, match_id: id + 1 })
        };

    assert_eq!(spl.get_current_round(), 0);
    let timestamp = *matches[0].timestamp;
    let last_timestamp = *matches[matches.len() - 1].timestamp;
    spl.register_matches(matches);
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    start_cheat_block_timestamp(spl_contract_address, last_timestamp + 120);
    spl.set_scores(scores);
    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
fn test_set_score() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let mut scores: Array<Score> = array![];
    // let mut rewards: Array<Reward> = array![];
    let prediction1 = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: 1.try_into().unwrap() }
        ),
        stake: 0,
        pair: Option::None
    };
    let prediction2 = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: '23' }
        ),
        stake: 0,
        pair: Option::None
    };

    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id, value: 123 }]
                    }
                );

            scores.append(Score { winner_odd: id, inputed: true, match_id: id });
        };

    assert_eq!(spl.get_current_round(), 0);
    let last_timestamp = *matches[matches.len() - 1].timestamp;
    let timestamp = *matches[0].timestamp;
    spl.register_matches(matches);
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, USER());
    let user_construct = User { id: 1, username: 'jane', address: USER() };
    spl.register_user(user_construct);
    spl.make_prediction(prediction1);
    stop_cheat_caller_address(spl_contract_address);
    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 1);
    assert_eq!(*match_predictions[0].user.address, USER());

    start_cheat_caller_address(spl_contract_address, OTHER('other'));
    let user_construct = User { id: 2, username: 'jane', address: OTHER('other') };
    spl.register_user(user_construct);
    spl.make_prediction(prediction2);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, owner);
    start_cheat_block_timestamp(spl_contract_address, last_timestamp + 120);
    spl.set_scores(scores.clone());
    let user_score = spl.get_user_total_scores(USER());
    let reward = spl.get_user_reward(USER());

    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 2);
    assert_eq!(*match_predictions[match_predictions.len() - 1].user.address, OTHER('other'));
    for i in min
        ..max {
            let _match = spl.get_match_by_id(i.try_into().unwrap());
            assert_eq!(_match.winner_odd.is_some(), true);
            assert_eq!(_match.winner_odd.unwrap(), *scores[(i - 1).try_into().unwrap()].winner_odd);
        };
    assert_eq!(reward, 0);
    assert_eq!(user_score, 123);
    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
#[should_panic(expected: 'MATCH_NOT_ENDED')]
fn test_set_score_unended_match() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let mut scores: Array<Score> = array![];

    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id: '1', value: 123 }]
                    }
                );

            scores.append(Score { winner_odd: '1', inputed: true, match_id: id })
        };

    assert_eq!(spl.get_current_round(), 0);
    let last_timestamp = *matches[matches.len() - 1].timestamp;
    let timestamp = *matches[0].timestamp;
    spl.register_matches(matches);
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);

    spl.set_scores(scores);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
#[should_panic(expected: 'NOT_REGISTERED')]
fn test_make_prediction_unregistered_user() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id: '1', value: 123 }]
                    }
                );
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, USER());
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: '1' }
        ),
        stake: 0,
        pair: Option::None
    };

    spl.make_prediction(prediction);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
#[should_panic(expected: 'INVALID_MATCH_ID')]
fn test_make_prediction_invalid_match_id() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id: '1', value: 123 }]
                    }
                );
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches);
    stop_cheat_caller_address(spl_contract_address);
    let user: ContractAddress = USER();
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 100.try_into().unwrap(), odd: '1' }
        ),
        stake: 0,
        pair: Option::None
    };

    spl.make_prediction(prediction);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
#[should_panic(expected: 'MATCH_SCORED')]
fn test_make_prediction_scored_match() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let mut scores: Array<Score> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id: '1', value: 123 }]
                    }
                );

            scores.append(Score { winner_odd: '1', inputed: true, match_id: id })
        };

    assert_eq!(spl.get_current_round(), 0);

    let timestamp = *matches[0].timestamp;
    spl.register_matches(matches);
    let max_time = 120;
    start_cheat_block_timestamp(spl_contract_address, (timestamp) + max_time.try_into().unwrap());
    spl.set_scores(array![*scores[0]]);
    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
    let user: ContractAddress = USER();
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: '1' }
        ),
        stake: 0,
        pair: Option::None
    };

    spl.make_prediction(prediction);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
#[should_panic(expected: 'PREDICTION_CLOSED')]
fn test_make_prediction_prediction_closed() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id: '1', value: 123 }]
                    }
                );
        };

    assert_eq!(spl.get_current_round(), 0);

    let timestamp = *matches[0].timestamp;
    spl.register_matches(matches);

    stop_cheat_caller_address(spl_contract_address);
    let user: ContractAddress = USER();
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: '1' }
        ),
        stake: 0,
        pair: Option::None
    };
    start_cheat_block_timestamp(spl_contract_address, (timestamp));
    spl.make_prediction(prediction);
    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
fn test_make_prediction_with_stake() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let erc20 = ERC20ABISafeDispatcher { contract_address: spl.get_erc20() };
    let owner: ContractAddress = OWNER();
    let user: ContractAddress = USER();
    let stake: u256 = 1000000000000000000_u256;
    start_cheat_caller_address(spl_contract_address, owner);
    start_cheat_caller_address(spl.get_erc20(), owner);
    erc20.transfer(user, stake).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    assert_eq!(erc20.balance_of(user).unwrap(), stake);

    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let min: u8 = 1_u8;

    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id: '1', value: 123 }]
                    }
                );
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches);

    stop_cheat_caller_address(spl_contract_address);
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: '1' }
        ),
        stake,
        pair: Option::None
    };
    start_cheat_caller_address(spl.get_erc20(), user);
    erc20.approve(spl_contract_address, stake).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    spl.make_prediction(prediction);
    let user_predictions = spl.get_user_matches_predictions(array![1], user);

    assert_eq!(user_predictions.len(), 1);
    assert_eq!(
        *user_predictions[0].prediction_type,
        PredictionType::Single(PredictionVariants { match_id: 1.try_into().unwrap(), odd: '1' })
    );
    assert_eq!(erc20.balance_of(user).unwrap(), 0);
    assert_eq!(erc20.balance_of(spl_contract_address).unwrap(), stake);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
fn test_make_prediction_without_stake() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let erc20 = ERC20ABISafeDispatcher { contract_address: spl.get_erc20() };
    let owner: ContractAddress = OWNER();
    let user: ContractAddress = USER();
    let stake: u256 = 1000000000000000000_u256;
    start_cheat_caller_address(spl_contract_address, owner);
    start_cheat_caller_address(spl.get_erc20(), owner);
    erc20.transfer(user, stake).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    assert_eq!(erc20.balance_of(user).unwrap(), stake);

    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let min: u8 = 1_u8;

    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id: '1', value: 123 }]
                    }
                )
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches);

    stop_cheat_caller_address(spl_contract_address);
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: '1' }
        ),
        stake: 0,
        pair: Option::None
    };

    spl.make_prediction(prediction);
    let user_predictions = spl.get_user_matches_predictions(array![1], user);

    assert_eq!(user_predictions.len(), 1);
    assert_eq!(
        *user_predictions[0].prediction_type,
        PredictionType::Single(PredictionVariants { match_id: 1.try_into().unwrap(), odd: '1' })
    );
    assert_eq!(erc20.balance_of(user).unwrap(), stake);
    assert_eq!(erc20.balance_of(spl_contract_address).unwrap(), 0);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
fn test_get_leaderboard() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let mut scores: Array<Score> = array![];

    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: '1' }
        ),
        stake: 0,
        pair: Option::None
    };

    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id: '1', value: 125 }]
                    }
                );

            scores.append(Score { winner_odd: '1', inputed: true, match_id: id });
        };

    assert_eq!(spl.get_current_round(), 0);
    let last_timestamp = *matches[matches.len() - 1].timestamp;
    let timestamp = *matches[0].timestamp;
    spl.register_matches(matches);
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, USER());
    let user_construct = User { id: 1, username: 'jane', address: USER() };
    spl.register_user(user_construct);
    spl.make_prediction(prediction);
    stop_cheat_caller_address(spl_contract_address);
    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 1);
    assert_eq!(*match_predictions[0].user.address, USER());

    start_cheat_caller_address(spl_contract_address, OTHER('other'));
    let user_construct = User { id: 2, username: 'jane', address: OTHER('other') };
    spl.register_user(user_construct);
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: '125' }
        ),
        stake: 0,
        pair: Option::None
    };
    spl.make_prediction(prediction);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, owner);
    start_cheat_block_timestamp(spl_contract_address, last_timestamp + 120);
    spl.set_scores(scores);
    let leaderboard = spl.get_leaderboard(1, 100);
    assert_eq!(leaderboard.len(), 2);
    assert_eq!(*leaderboard[0].total_score, 125);
    assert_eq!(*leaderboard[1].total_score, 0);
    let user_score = spl.get_user_total_scores(USER());
    let reward = spl.get_user_reward(USER());
    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 2);
    assert_eq!(*match_predictions[match_predictions.len() - 1].user.address, OTHER('other'));
    assert_eq!(reward, 0);
    assert_eq!(user_score, 125);
    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
fn test_claim_reward() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let erc20 = ERC20ABISafeDispatcher { contract_address: spl.get_erc20() };
    let owner: ContractAddress = OWNER();
    let user: ContractAddress = USER();
    let stake: u256 = 1000000000000000000_u256;
    // erc20.transfer(spl_contract_address, stake * 5).unwrap();
    start_cheat_caller_address(spl.get_erc20(), owner);
    erc20.transfer(user, stake).unwrap();
    erc20.transfer(OTHER('other'), stake).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let mut scores: Array<Score> = array![];
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: '1' }
        ),
        stake,
        pair: Option::None
    };
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id: '1', value: 123 }]
                    }
                );

            scores.append(Score { winner_odd: '1', inputed: true, match_id: id });
        };

    assert_eq!(spl.get_current_round(), 0);
    let last_timestamp = *matches[matches.len() - 1].timestamp;
    let timestamp = *matches[0].timestamp;
    spl.register_matches(matches);
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, USER());
    let user_construct = User { id: 1, username: 'jane', address: USER() };
    spl.register_user(user_construct);
    start_cheat_caller_address(spl.get_erc20(), user);
    erc20.approve(spl_contract_address, stake).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    spl.make_prediction(prediction);
    stop_cheat_caller_address(spl_contract_address);
    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 1);
    assert_eq!(*match_predictions[0].user.address, USER());

    start_cheat_caller_address(spl_contract_address, OTHER('other'));
    let user_construct = User { id: 2, username: 'jane', address: OTHER('other') };
    spl.register_user(user_construct);
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: '123' }
        ),
        stake,
        pair: Option::None
    };
    start_cheat_caller_address(spl.get_erc20(), OTHER('other'));
    erc20.approve(spl_contract_address, stake).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    erc20.approve(spl_contract_address, stake).unwrap();
    spl.make_prediction(prediction);
    stop_cheat_caller_address(spl_contract_address);
    assert_eq!(erc20.balance_of(spl_contract_address).unwrap(), stake * 2);

    start_cheat_caller_address(spl_contract_address, owner);
    start_cheat_block_timestamp(spl_contract_address, last_timestamp + 120);
    spl.set_scores(scores);
    let leaderboard = spl.get_leaderboard(1, 100);
    assert_eq!(leaderboard.len(), 2);
    assert_eq!(*leaderboard[0].total_score, 123);
    assert_eq!(*leaderboard[1].total_score, 0);
    let user_score = spl.get_user_total_scores(USER());
    let reward = spl.get_user_reward(USER());
    assert_eq!(reward, ((123 * stake) / 100));
    assert_eq!(user_score, 123);
    start_cheat_caller_address(spl_contract_address, user);
    spl.claim_reward();
    assert_eq!(spl.get_user_reward(USER()), 0);
    assert_eq!(
        erc20.balance_of(spl_contract_address).unwrap(), ((stake * 2) - ((123 * stake) / 100))
    );
    assert_eq!(erc20.balance_of(user).unwrap(), ((123 * stake) / 100));
    stop_cheat_caller_address(spl_contract_address);

    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
fn test_claim_reward_on_multiple_correct_prediction() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let erc20 = ERC20ABISafeDispatcher { contract_address: spl.get_erc20() };
    let owner: ContractAddress = OWNER();
    let user: ContractAddress = USER();
    let stake: u256 = 1000000000000000000_u256;
    // erc20.transfer(spl_contract_address, stake * 5).unwrap();
    start_cheat_caller_address(spl.get_erc20(), owner);
    erc20.transfer(user, stake).unwrap();
    erc20.transfer(OTHER('other'), stake * 3).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let mut scores: Array<Score> = array![];
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Multiple(
            array![
                PredictionVariants { match_id: 1.try_into().unwrap(), odd: 1.try_into().unwrap() },
                PredictionVariants { match_id: 2.try_into().unwrap(), odd: 2.try_into().unwrap() },
                PredictionVariants { match_id: 3.try_into().unwrap(), odd: 3.try_into().unwrap() }
            ]
        ),
        stake,
        pair: Option::Some('124')
    };
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id, value: 123 }]
                    }
                );

            scores.append(Score { winner_odd: id, inputed: true, match_id: id });
        };

    assert_eq!(spl.get_current_round(), 0);
    let last_timestamp = *matches[matches.len() - 1].timestamp;
    let timestamp = *matches[0].timestamp;
    spl.register_matches(matches);
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, USER());
    let user_construct = User { id: 1, username: 'jane', address: USER() };
    spl.register_user(user_construct);
    start_cheat_caller_address(spl.get_erc20(), user);
    erc20.approve(spl_contract_address, stake).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    spl.make_prediction(prediction);

    let pair_count = spl.get_pair_count('124');
    assert_eq!(pair_count, 3);
    stop_cheat_caller_address(spl_contract_address);
    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 1);
    assert_eq!(*match_predictions[0].user.address, USER());
    let user_matches_predictions = spl.get_user_matches_predictions(array![1, 2, 3], user);
    start_cheat_caller_address(spl_contract_address, OTHER('other'));
    let user_construct = User { id: 2, username: 'jane', address: OTHER('other') };
    spl.register_user(user_construct);
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: '123' }
        ),
        stake: stake * 3,
        pair: Option::None
    };
    start_cheat_caller_address(spl.get_erc20(), OTHER('other'));
    erc20.approve(spl_contract_address, stake * 3).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    erc20.approve(spl_contract_address, stake).unwrap();
    spl.make_prediction(prediction);
    stop_cheat_caller_address(spl_contract_address);
    assert_eq!(erc20.balance_of(spl_contract_address).unwrap(), stake * 4);

    start_cheat_caller_address(spl_contract_address, owner);
    start_cheat_block_timestamp(spl_contract_address, last_timestamp + 120);
    let reward = spl.get_user_reward(USER());
    assert_eq!(reward, 0);
    spl.set_scores(scores);
    let leaderboard = spl.get_leaderboard(1, 100);
    assert_eq!(leaderboard.len(), 2);
    assert_eq!(*leaderboard[0].total_score, 123 * 3);
    assert_eq!(*leaderboard[1].total_score, 0);
    let user_score = spl.get_user_total_scores(USER());
    let reward = spl.get_user_reward(USER());
    assert_eq!(reward, ((369 * stake) / 100));
    assert_eq!(user_score, 369);
    start_cheat_caller_address(spl_contract_address, user);
    spl.claim_reward();
    assert_eq!(spl.get_user_reward(USER()), 0);
    assert_eq!(
        erc20.balance_of(spl_contract_address).unwrap(), ((stake * 4) - (((123 * 3) * stake) / 100))
    );
    assert_eq!(erc20.balance_of(user).unwrap(), (((123 * 3) * stake) / 100));
    stop_cheat_caller_address(spl_contract_address);

    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
fn test_claim_reward_on_multiple_one_icorrect_prediction() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let erc20 = ERC20ABISafeDispatcher { contract_address: spl.get_erc20() };
    let owner: ContractAddress = OWNER();
    let user: ContractAddress = USER();
    let stake: u256 = 1000000000000000000_u256;
    // erc20.transfer(spl_contract_address, stake * 5).unwrap();
    start_cheat_caller_address(spl.get_erc20(), owner);
    erc20.transfer(user, stake).unwrap();
    erc20.transfer(OTHER('other'), stake * 3).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<RawMatch> = array![];
    let mut scores: Array<Score> = array![];
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Multiple(
            array![
                PredictionVariants { match_id: 1.try_into().unwrap(), odd: 1.try_into().unwrap() },
                PredictionVariants { match_id: 2.try_into().unwrap(), odd: 1.try_into().unwrap() },
                PredictionVariants { match_id: 3.try_into().unwrap(), odd: 3.try_into().unwrap() }
            ]
        ),
        stake,
        pair: Option::Some('124')
    };
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    RawMatch {
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual,
                        odds: array![Odd { id, value: 123 }]
                    }
                );

            scores.append(Score { winner_odd: id, inputed: true, match_id: id });
        };

    assert_eq!(spl.get_current_round(), 0);
    let last_timestamp = *matches[matches.len() - 1].timestamp;
    let timestamp = *matches[0].timestamp;
    spl.register_matches(matches);
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, USER());
    let user_construct = User { id: 1, username: 'jane', address: USER() };
    spl.register_user(user_construct);
    start_cheat_caller_address(spl.get_erc20(), user);
    erc20.approve(spl_contract_address, stake).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    spl.make_prediction(prediction);

    let pair_count = spl.get_pair_count('124');
    assert_eq!(pair_count, 3);
    stop_cheat_caller_address(spl_contract_address);
    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 1);
    assert_eq!(*match_predictions[0].user.address, USER());
    let user_matches_predictions = spl.get_user_matches_predictions(array![1, 2, 3], user);
    start_cheat_caller_address(spl_contract_address, OTHER('other'));
    let user_construct = User { id: 2, username: 'jane', address: OTHER('other') };
    spl.register_user(user_construct);
    let prediction = RawPrediction {
        prediction_type: RawPredictionType::Single(
            PredictionVariants { match_id: 1.try_into().unwrap(), odd: '123' }
        ),
        stake: stake * 3,
        pair: Option::None
    };
    start_cheat_caller_address(spl.get_erc20(), OTHER('other'));
    erc20.approve(spl_contract_address, stake * 3).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    erc20.approve(spl_contract_address, stake).unwrap();
    spl.make_prediction(prediction);
    stop_cheat_caller_address(spl_contract_address);
    assert_eq!(erc20.balance_of(spl_contract_address).unwrap(), stake * 4);

    start_cheat_caller_address(spl_contract_address, owner);
    start_cheat_block_timestamp(spl_contract_address, last_timestamp + 120);
    let reward = spl.get_user_reward(USER());
    assert_eq!(reward, 0);
    spl.set_scores(scores);
    let leaderboard = spl.get_leaderboard(1, 100);
    assert_eq!(leaderboard.len(), 2);
    assert_eq!(*leaderboard[0].total_score, 123 * 2);
    assert_eq!(*leaderboard[1].total_score, 0);
    let user_score = spl.get_user_total_scores(USER());
    let reward = spl.get_user_reward(USER());
    assert_eq!(reward, 0);
    assert_eq!(user_score, 123 * 2);
    start_cheat_caller_address(spl_contract_address, user);
    // spl.claim_reward();
    assert_eq!(spl.get_user_reward(USER()), 0);
    assert_eq!(erc20.balance_of(spl_contract_address).unwrap(), stake * 4);
    assert_eq!(erc20.balance_of(user).unwrap(), 0);
    assert_eq!(erc20.balance_of(OTHER('other')).unwrap(), 0);
    stop_cheat_caller_address(spl_contract_address);

    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
}
