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
    Score, Reward, PredictionDetails, Leaderboard, Match, RoundDetails, MatchType, User, Prediction
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
    erc20.mint(OWNER(), 100000000000000000000);
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
    let mut matches: Array<Match> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                )
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, *matches[0].timestamp);
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
    let mut matches: Array<Match> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                )
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
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
    let mut matches: Array<Match> = array![];
    let mut scores: Array<Score> = array![];

    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );

            scores.append(Score { home: 1, away: 0, inputed: true, match_id: id })
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, *matches[0].timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    stop_cheat_caller_address(spl_contract_address);
    start_cheat_caller_address(spl_contract_address, USER());

    spl.set_scores(scores, array![]);
    stop_cheat_caller_address(spl_contract_address);
}

#[test]
#[should_panic(expected: 'INVALID_MATCH_ID')]
fn test_set_score_invalid_match_id() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<Match> = array![];
    let mut scores: Array<Score> = array![];

    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );

            scores.append(Score { home: 1, away: 0, inputed: true, match_id: id + 1 })
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, *matches[0].timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    start_cheat_block_timestamp(spl_contract_address, *matches[matches.len() - 1].timestamp + 120);
    spl.set_scores(scores, array![]);
    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
}

// #[test]
// #[should_panic(expected: 'SCORED')]
// fn test_set_score_already_scored() {
//     let spl_contract_address = _setup_();
//     let spl = ISPLDispatcher { contract_address: spl_contract_address };
//     let owner: ContractAddress = OWNER();
//     start_cheat_caller_address(spl_contract_address, owner);
//     let _timestamp = get_block_timestamp();
//     let mut matches: Array<Match> = array![];
//     let mut scores: Array<Score> = array![];

//     let min: u8 = 1_u8;
//     let max: u8 = 11_u8;
//     for i in min
//         ..max {
//             let id: felt252 = i.try_into().unwrap();
//             let timestamp: u64 = ((i.try_into().unwrap() * 100) +
//             _timestamp).try_into().unwrap();
//             matches
//                 .append(
//                     Match {
//                         inputed: true,
//                         id,
//                         timestamp,
//                         round: Option::None,
//                         match_type: MatchType::Virtual
//                     }
//                 );

//             scores.append(Score { home: 1, away: 0, inputed: true, match_id: id })
//         };

//     assert_eq!(spl.get_current_round(), 0);
//     spl.register_matches(matches.clone());
//     assert_eq!(spl.get_current_round(), 1);
//     let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
//     assert_eq!(match_by_id.timestamp, *matches[0].timestamp);
//     let match_index = spl.get_match_index(10.try_into().unwrap());
//     assert_eq!(match_index, 10);
//     start_cheat_block_timestamp(spl_contract_address, *matches[matches.len() - 1].timestamp +
//     120);
//     spl.set_scores(scores.clone(), array![]);
//     spl.set_scores(scores, array![]);
//     stop_cheat_block_timestamp(spl_contract_address);
//     stop_cheat_caller_address(spl_contract_address);
// }

#[test]
#[should_panic(expected: 'USER_NOT_PREDICTED')]
fn test_set_score_not_predicted() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<Match> = array![];
    let mut scores: Array<Score> = array![];
    let mut rewards: Array<Reward> = array![];

    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );

            scores.append(Score { home: 1, away: 0, inputed: true, match_id: id });
            if i % 2 != 0 {
                rewards
                    .append(
                        Reward {
                            point: i.try_into().unwrap(),
                            user: USER(),
                            reward: i.try_into().unwrap() * 10,
                            match_id: id
                        }
                    );
            }
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, *matches[0].timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    start_cheat_block_timestamp(spl_contract_address, *matches[matches.len() - 1].timestamp + 120);
    spl.set_scores(scores, rewards);
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
    let mut matches: Array<Match> = array![];
    let mut scores: Array<Score> = array![];
    let mut rewards: Array<Reward> = array![];
    let mut predictions: Array<Prediction> = array![];

    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );

            scores.append(Score { home: 1, away: 0, inputed: true, match_id: id });
            predictions
                .append(
                    Prediction {
                        match_id: id, id: '1', stake: 0, inputed: true, pair: Option::None
                    }
                );
            if i % 2 != 0 {
                rewards
                    .append(
                        Reward {
                            point: i.try_into().unwrap(),
                            user: USER(),
                            reward: i.try_into().unwrap() * 10,
                            match_id: id
                        }
                    );
            }
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, *matches[0].timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, USER());
    let user_construct = User { id: 1, username: 'jane', address: USER() };
    spl.register_user(user_construct);
    spl.make_bulk_prediction(predictions.clone());
    stop_cheat_caller_address(spl_contract_address);
    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 1);
    assert_eq!(*match_predictions[0].user.address, USER());

    start_cheat_caller_address(spl_contract_address, OTHER('other'));
    let user_construct = User { id: 2, username: 'jane', address: OTHER('other') };
    spl.register_user(user_construct);
    spl.make_bulk_prediction(predictions);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, owner);
    start_cheat_block_timestamp(spl_contract_address, *matches[matches.len() - 1].timestamp + 120);
    spl.set_scores(scores.clone(), rewards);
    let user_score = spl.get_user_total_scores(USER());
    let reward = spl.get_user_reward(USER());
    let match_scores = spl.get_match_scores(1);
    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 2);
    assert_eq!(*match_predictions[match_predictions.len() - 1].user.address, OTHER('other'));
    assert_eq!(match_scores.len(), 10);
    let mut match_score_index = 0;
    for match_score in match_scores {
        assert_eq!(match_score, *scores[match_score_index]);
        match_score_index += 1;
    };
    assert_eq!(reward, 250);
    assert_eq!(user_score, 25);
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
    let mut matches: Array<Match> = array![];
    let mut scores: Array<Score> = array![];

    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );

            scores.append(Score { home: 1, away: 0, inputed: true, match_id: id })
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, *matches[0].timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);

    spl.set_scores(scores, array![]);
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
    let mut matches: Array<Match> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                )
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, USER());
    let prediction = Prediction {
        inputed: true, match_id: 1, id: '1', stake: 0, pair: Option::None
    };

    spl.make_prediction(prediction);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
#[should_panic(expected: 'NOT_REGISTERED')]
fn test_make_bulk_prediction_unregistered_user() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<Match> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                )
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, USER());
    let prediction = Prediction {
        inputed: true, match_id: 1, id: '1', stake: 0, pair: Option::None
    };

    spl.make_bulk_prediction(array![prediction]);
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
    let mut matches: Array<Match> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                )
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    stop_cheat_caller_address(spl_contract_address);
    let user: ContractAddress = USER();
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = Prediction {
        inputed: true, match_id: 100, id: '1', stake: 0, pair: Option::None
    };

    spl.make_prediction(prediction);
    stop_cheat_caller_address(spl_contract_address);
}

#[test]
#[should_panic(expected: 'INVALID_MATCH_ID')]
fn test_make_bulk_prediction_invalid_match_id() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<Match> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                )
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    stop_cheat_caller_address(spl_contract_address);
    let user: ContractAddress = USER();
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = Prediction {
        inputed: true, match_id: 100, id: '1', stake: 0, pair: Option::None
    };

    spl.make_bulk_prediction(array![prediction]);
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
    let mut matches: Array<Match> = array![];
    let mut scores: Array<Score> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );

            scores.append(Score { home: 1, away: 0, inputed: true, match_id: id })
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    let max_time = 120;
    start_cheat_block_timestamp(
        spl_contract_address, (*matches[0].timestamp) + max_time.try_into().unwrap()
    );
    spl.set_scores(array![*scores[0]], array![]);
    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
    let user: ContractAddress = USER();
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = Prediction {
        inputed: true, match_id: 1, id: '1', stake: 0, pair: Option::None
    };

    spl.make_prediction(prediction);
    stop_cheat_caller_address(spl_contract_address);
}

#[test]
#[should_panic(expected: 'MATCH_SCORED')]
fn test_make_bulk_prediction_scored_match() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<Match> = array![];
    let mut scores: Array<Score> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );

            scores.append(Score { home: 1, away: 0, inputed: true, match_id: id })
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    let max_time = 120;
    start_cheat_block_timestamp(
        spl_contract_address, (*matches[0].timestamp) + max_time.try_into().unwrap()
    );
    spl.set_scores(array![*scores[0]], array![]);
    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
    let user: ContractAddress = USER();
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = Prediction {
        inputed: true, match_id: 1, id: '1', stake: 0, pair: Option::None
    };

    spl.make_bulk_prediction(array![prediction]);
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
    let mut matches: Array<Match> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());

    stop_cheat_caller_address(spl_contract_address);
    let user: ContractAddress = USER();
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = Prediction {
        inputed: true, match_id: 1, id: '1', stake: 0, pair: Option::None
    };
    start_cheat_block_timestamp(spl_contract_address, (*matches[0].timestamp));
    spl.make_prediction(prediction);
    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
}

#[test]
#[should_panic(expected: 'PREDICTION_CLOSED')]
fn test_make_bulk_prediction_prediction_closed() {
    let spl_contract_address = _setup_();
    let spl = ISPLDispatcher { contract_address: spl_contract_address };
    let owner: ContractAddress = OWNER();
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<Match> = array![];
    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());

    stop_cheat_caller_address(spl_contract_address);
    let user: ContractAddress = USER();
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = Prediction {
        inputed: true, match_id: 1, id: '1', stake: 0, pair: Option::None
    };
    start_cheat_block_timestamp(spl_contract_address, (*matches[0].timestamp));
    spl.make_bulk_prediction(array![prediction]);
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
    let mut matches: Array<Match> = array![];
    let min: u8 = 1_u8;

    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());

    stop_cheat_caller_address(spl_contract_address);
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = Prediction {
        inputed: true, match_id: 1, id: '1', stake: stake, pair: Option::None
    };
    start_cheat_caller_address(spl.get_erc20(), user);
    erc20.approve(spl_contract_address, stake).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    spl.make_prediction(prediction);
    let user_predictions = spl.get_user_predictions(1, user);

    assert_eq!(user_predictions.len(), 1);
    assert_eq!(*user_predictions[0], prediction);
    assert_eq!(erc20.balance_of(user).unwrap(), 0);
    assert_eq!(erc20.balance_of(spl_contract_address).unwrap(), stake);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
fn test_make_bulk_prediction_with_stake() {
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
    let mut matches: Array<Match> = array![];
    let min: u8 = 1_u8;

    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());

    stop_cheat_caller_address(spl_contract_address);
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = Prediction { inputed: true, match_id: 1, id: '1', stake, pair: Option::None };
    start_cheat_caller_address(spl.get_erc20(), user);
    erc20.approve(spl_contract_address, stake).unwrap();
    stop_cheat_caller_address(spl.get_erc20());
    spl.make_bulk_prediction(array![prediction]);
    let user_predictions = spl.get_user_predictions(1, user);

    assert_eq!(user_predictions.len(), 1);
    assert_eq!(*user_predictions[0], prediction);
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
    let mut matches: Array<Match> = array![];
    let min: u8 = 1_u8;

    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());

    stop_cheat_caller_address(spl_contract_address);
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = Prediction {
        inputed: true, match_id: 1, id: '1', stake: 0, pair: Option::None
    };

    spl.make_prediction(prediction);
    let user_predictions = spl.get_user_predictions(1, user);

    assert_eq!(user_predictions.len(), 1);
    assert_eq!(*user_predictions[0].id, prediction.id);
    assert_eq!(erc20.balance_of(user).unwrap(), stake);
    assert_eq!(erc20.balance_of(spl_contract_address).unwrap(), 0);
    stop_cheat_caller_address(spl_contract_address);
}


#[test]
fn test_make_bulk_prediction_without_stake() {
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
    let mut matches: Array<Match> = array![];
    let min: u8 = 1_u8;

    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());

    stop_cheat_caller_address(spl_contract_address);
    start_cheat_caller_address(spl_contract_address, user);
    let user_construct = User { id: 1, username: 'jane', address: user };

    spl.register_user(user_construct);
    let prediction = Prediction {
        inputed: true, match_id: 1, id: '1', stake: 0, pair: Option::None
    };

    spl.make_bulk_prediction(array![prediction]);
    let user_predictions = spl.get_user_predictions(1, user);

    assert_eq!(user_predictions.len(), 1);
    assert_eq!(*user_predictions[0].id, prediction.id);
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
    let mut matches: Array<Match> = array![];
    let mut scores: Array<Score> = array![];
    let mut rewards: Array<Reward> = array![];
    let mut predictions: Array<Prediction> = array![];

    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );

            scores.append(Score { home: 1, away: 0, inputed: true, match_id: id });
            predictions
                .append(
                    Prediction {
                        match_id: id, id: '1', stake: 0, inputed: true, pair: Option::None
                    }
                );
            if i % 2 != 0 {
                rewards
                    .append(
                        Reward {
                            point: i.try_into().unwrap(),
                            user: USER(),
                            reward: i.try_into().unwrap() * 10,
                            match_id: id
                        }
                    );
            }
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, *matches[0].timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, USER());
    let user_construct = User { id: 1, username: 'jane', address: USER() };
    spl.register_user(user_construct);
    spl.make_bulk_prediction(predictions.clone());
    stop_cheat_caller_address(spl_contract_address);
    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 1);
    assert_eq!(*match_predictions[0].user.address, USER());

    start_cheat_caller_address(spl_contract_address, OTHER('other'));
    let user_construct = User { id: 2, username: 'jane', address: OTHER('other') };
    spl.register_user(user_construct);
    spl.make_bulk_prediction(predictions);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, owner);
    start_cheat_block_timestamp(spl_contract_address, *matches[matches.len() - 1].timestamp + 120);
    spl.set_scores(scores.clone(), rewards);
    let leaderboard = spl.get_leaderboard(1, 100);
    assert_eq!(leaderboard.len(), 2);
    assert_eq!(*leaderboard[0].total_score, 25);
    assert_eq!(*leaderboard[1].total_score, 0);
    let user_score = spl.get_user_total_scores(USER());
    let reward = spl.get_user_reward(USER());
    let match_scores = spl.get_match_scores(1);
    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 2);
    assert_eq!(*match_predictions[match_predictions.len() - 1].user.address, OTHER('other'));
    assert_eq!(match_scores.len(), 10);
    let mut match_score_index = 0;
    for match_score in match_scores {
        assert_eq!(match_score, *scores[match_score_index]);
        match_score_index += 1;
    };
    assert_eq!(reward, 250);
    assert_eq!(user_score, 25);
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
    start_cheat_caller_address(spl.get_erc20(), owner);
    erc20.transfer(spl_contract_address, stake).unwrap();
    assert_eq!(erc20.balance_of(spl_contract_address).unwrap(), stake);
    stop_cheat_caller_address(spl.get_erc20());
    start_cheat_caller_address(spl_contract_address, owner);
    let _timestamp = get_block_timestamp();
    let mut matches: Array<Match> = array![];
    let mut scores: Array<Score> = array![];
    let mut rewards: Array<Reward> = array![];
    let mut predictions: Array<Prediction> = array![];

    let min: u8 = 1_u8;
    let max: u8 = 11_u8;
    for i in min
        ..max {
            let id: felt252 = i.try_into().unwrap();
            let timestamp: u64 = ((i.try_into().unwrap() * 100) + _timestamp).try_into().unwrap();
            matches
                .append(
                    Match {
                        inputed: true,
                        id,
                        timestamp,
                        round: Option::None,
                        match_type: MatchType::Virtual
                    }
                );

            scores.append(Score { home: 1, away: 0, inputed: true, match_id: id });
            predictions
                .append(
                    Prediction {
                        match_id: id, id: '1', stake: 0, inputed: true, pair: Option::None
                    }
                );
            if i % 2 != 0 {
                rewards
                    .append(
                        Reward {
                            point: i.try_into().unwrap(),
                            user: USER(),
                            reward: i.try_into().unwrap() * 10,
                            match_id: id
                        }
                    );
            }
        };

    assert_eq!(spl.get_current_round(), 0);
    spl.register_matches(matches.clone());
    assert_eq!(spl.get_current_round(), 1);
    let match_by_id = spl.get_match_by_id(1.try_into().unwrap());
    assert_eq!(match_by_id.timestamp, *matches[0].timestamp);
    let match_index = spl.get_match_index(10.try_into().unwrap());
    assert_eq!(match_index, 10);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, USER());
    let user_construct = User { id: 1, username: 'jane', address: USER() };
    spl.register_user(user_construct);
    spl.make_bulk_prediction(predictions.clone());
    stop_cheat_caller_address(spl_contract_address);
    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 1);
    assert_eq!(*match_predictions[0].user.address, USER());

    start_cheat_caller_address(spl_contract_address, OTHER('other'));
    let user_construct = User { id: 2, username: 'jane', address: OTHER('other') };
    spl.register_user(user_construct);
    spl.make_bulk_prediction(predictions);
    stop_cheat_caller_address(spl_contract_address);

    start_cheat_caller_address(spl_contract_address, owner);
    start_cheat_block_timestamp(spl_contract_address, *matches[matches.len() - 1].timestamp + 120);
    spl.set_scores(scores.clone(), rewards);
    let leaderboard = spl.get_leaderboard(1, 100);
    assert_eq!(leaderboard.len(), 2);
    assert_eq!(*leaderboard[0].total_score, 25);
    assert_eq!(*leaderboard[1].total_score, 0);
    let user_score = spl.get_user_total_scores(USER());
    let reward = spl.get_user_reward(USER());
    let match_scores = spl.get_match_scores(1);
    let match_predictions = spl.get_match_predictions(1.try_into().unwrap());
    assert_eq!(match_predictions.len(), 2);
    assert_eq!(*match_predictions[match_predictions.len() - 1].user.address, OTHER('other'));
    assert_eq!(match_scores.len(), 10);
    let mut match_score_index = 0;
    for match_score in match_scores {
        assert_eq!(match_score, *scores[match_score_index]);
        match_score_index += 1;
    };
    assert_eq!(reward, 250);
    assert_eq!(user_score, 25);
    start_cheat_caller_address(spl_contract_address, user);
    spl.claim_reward();
    assert_eq!(spl.get_user_reward(USER()), 0);
    assert_eq!(erc20.balance_of(spl_contract_address).unwrap(), stake - 250);
    assert_eq!(erc20.balance_of(user).unwrap(), 250);
    stop_cheat_caller_address(spl_contract_address);

    stop_cheat_block_timestamp(spl_contract_address);
    stop_cheat_caller_address(spl_contract_address);
}
